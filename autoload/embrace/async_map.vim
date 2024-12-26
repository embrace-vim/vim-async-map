" vim:tw=0:ts=2:sw=2:et:norl:
" Author: Landon Bouma <https://tallybark.com/>
" Project: https://github.com/embrace-vim/vim-async-map#જ⁀➴
" License: MIT | Copyright © 2024 Landon Bouma, © 2017 Yichao Zhou
" Summary: vim-easyescape fork avoids edits, supports arbitrary commands

" -------------------------------------------------------------------

" ABOUT:
" - Support different sequences with arbitrary commands (vs.
"   vim-easyescape that only runs escape command).
" - Avoid leaving unedited buffer edited after sequence detected
"   (by using undo, if possible, to clear typed sequence; vs.
"    vim-easyescape that uses backspace and leaves buffer edited).

" -------------------------------------------------------------------

" REFER: Default args support:
"   :help optional-function-argument
" https://github.com/vim/vim/commit/42ae78cfff171fbd7412306083fe200245d7a7a6
if ! has("patch-8.1.1310")
  echom "ALERT: Please upgrade to Vim 8.1.1310 or better to use embrace-vim/vim-async-map"

  finish
endif

" -------------------------------------------------------------------

" Python necessary to set timeout < 2s, though not required.
let s:haspy3 = has("python3")

" List of imap definitions user has specified.
" - Each object is a Dictionary:
"     map_mode: To which mode the def'n applies, either 'i' or 'n'.
"     key_list: List of keys user must press to invoke command_seq.
"     map_command: Command to run when sequence completed.
let s:map_objs = {"i": [], "n": []}

" List of imap characters registered with Vim.
" - This plugin basically snifs keyboard traffic, but only on characters
"   the user has registered as part of a key sequence.
let s:map_chars_registered = {"i": [], "n": []}

" Arrays of active map_objs with additional key for each object:
"   reduction: Reduced key_list used to track input as sequence is typed.
let s:active_maps = {"i": [], "n": []}

" Booleans track whether user has started typing (possible) sequence,
" or if s:active_maps[mode] needs to be reset.
let s:is_reducing = {"i": 1, "n": 1}

" Max. time between keypresses for sequence to be detected. If two characters
" are typed more than g:vim_async_map_timeout msec. apart, the
" command_seq will not be run.
" - See below:
"   s:InitializeTimeout()
"
" Latest keypress time if Python not available, used to detect timeout.
" - We'll maintain either `py3 last_keypress_time_py3` or this value.
let s:last_keypress_time_vim = 0

" -------------------------------------------------------------------

" Args:
" - key_sequence: String of characters user can press in a sequence
"   within the timeout time between keypresses to run map_command.
" - map_command: Command to run when the key sequence is detected.

function! s:RegisterMapping(map_mode, key_sequence, map_command, timeout) abort
  if !s:MustVerifyMapMode(a:map_mode) | return | endif

  " Convert string into single-character List.
  let key_list = split(a:key_sequence, '.\{1}\zs')

  " Add to list of all imap or nmap sequences the plugin manages.
  let map_objs = s:map_objs[a:map_mode]

  let map_obj = {
  \   "map_mode": a:map_mode,
  \   "key_list": key_list,
  \   "map_command": a:map_command,
  \   "timeout": a:timeout,
  \ }

  call add(map_objs, map_obj)

  " Register an imap for each unique character. (We're basically sniffing
  " keyboard traffic, but only on keys that are part of a key sequence.)
  let map_chars_registered = s:map_chars_registered[a:map_mode]
  for key in key_list
    if index(map_chars_registered, key) < 0
      " SAVVY: Note that s:ProcessKeypress doesn't work; use <SID> instead.
      exec a:map_mode .. "noremap <expr> " .. key .. " <SID>ProcessKeypress("
        \ .. "\"" .. a:map_mode .. "\", \"" .. key .. "\")"

      call add(map_chars_registered, key)
    endif
  endfor

  " Reset list of active sequences, so next character typed is checked
  " against all sequences.
  let force_reset = 1
  call s:ResetActiveMaps("i", force_reset)
endfunction

function! embrace#async_map#RegisterInsertModeMap(key_sequence, map_command, timeout = 0) abort
  call s:RegisterMapping("i", a:key_sequence, a:map_command, a:timeout)
endfunction

function! embrace#async_map#RegisterNormalModeMap(key_sequence, map_command, timeout = 0) abort
  call s:RegisterMapping("n", a:key_sequence, a:map_command, a:timeout)
endfunction

function! s:MustVerifyMapMode(map_mode) abort
  if index(["i", "n"], a:map_mode) < 0
    echomsg "GAFFE: embrace#async_map: Please specify map_mode 'i' or 'n'"

    return 0
  endif

  return 1
endfunction

" ***

function! s:ResetActiveMaps(map_mode, force_reset = 0) abort
  if !s:MustVerifyMapMode(a:map_mode) | return | endif

  if !s:is_reducing[a:map_mode] && !a:force_reset
    " Already reset.

    return
  endif

  let s:is_reducing[a:map_mode] = 0

  let s:active_maps[a:map_mode] = []

  for imap_obj in s:map_objs[a:map_mode]
    call add(s:active_maps[a:map_mode], {
      \   "map_mode": imap_obj["map_mode"],
      \   "key_list": imap_obj["key_list"],
      \   "map_command": imap_obj["map_command"],
      \   "timeout": imap_obj["timeout"],
      \   "reduction": imap_obj["key_list"],
      \ })
  endfor
endfunction

" ***

" USAGE: Use b:vim_async_map_disable to disable based on filetype, e.g.,
"
"   autocmd FileType text,markdown call setbufvar(bufnr("%"), 'easyescape_disable', 1)
function! s:ProcessKeypress(map_mode, char) abort
  if exists("b:vim_async_map_disable") && b:vim_async_map_disable == 1

    return a:char
  endif

  " ***

  " We'll check if time between sequence keypresses is greater than timeout.
  let elapsed_time = s:ReadTimer()

  " Reset the timer.
  call s:ResetTimer()

  " ***

  let reduction = []
  let completed = {}

  for active_map in s:active_maps[a:map_mode]
    let timeout = active_map["timeout"]
    if timeout == 0 | let timeout = g:vim_async_map_timeout | endif

    " Check if char press matches next char of any sequence.
    " - If first char of sequence, ignore timeout. Otherwise
    "   check how long it's been since the keypress before it.
    if active_map["reduction"][0] == a:char
        \ && (len(active_map["reduction"]) == len(active_map["key_list"])
        \     || elapsed_time <= timeout)
      if len(active_map["reduction"]) > 1
        let reduced_map = {
          \   "map_mode": active_map["map_mode"],
          \   "key_list": active_map["key_list"],
          \   "map_command": active_map["map_command"],
          \   "timeout": active_map["timeout"],
          \   "reduction": active_map["key_list"][1:],
          \ }
        call add(reduction, reduced_map)
      else
        " There's no reason to support multiple commands mapped to the same
        " sequence, is there? We'll only complete one sequence.
        let completed = active_map
      endif
    endif
  endfor

  if !empty(completed)
    " After this character, next keypress could start a new sequence.
    call s:ResetActiveMaps(a:map_mode)

    if completed["map_mode"] == "n"
      let seq = completed["map_command"]
    else
      " Delete the key_list characters that user typed to invoke the command.
      " Then call the requested command.
      " - zhou13/vim-easyescape runs backspace, which will make unedited
      "   buffer appear edited — but then user must save, or undo, or be
      "   prompted to save on file close.
      "
      "     let seq = repeat("\<BS>", len(completed["key_list"]) - 1) .. completed["map_command"]
      "
      " - Ideal approach is to undo previous typing... unless it was more
      "   than the sequence.
      let s:prev_pos = getpos(".")
      let s:at_final_column = 0
      if s:prev_pos[2] >= col("$")
        let s:at_final_column = 1
      endif
      let s:before_lnum = len(".")
      let s:before_line = getline(".")
      let s:completed = completed
      let seq = "\<C-O>:u\<CR>"

      let do_callback = 1

      " 'Workaround for #3, might be less annoying but still not perfect'
      " - 'After pressing kj cursor goes to the beginning of line'
      "     https://github.com/zhou13/vim-easyescape/issues/3
      "   If user starts a newline and autoindent puts cursor after some
      "   initial whitespace, then they <Esc>, delete whitespace.
      " - Note in normal Vim, if user starts a newline and autoindent adds
      "   whitespace, then user uses a motion command, the whitespace will
      "   not be deleted on <ESC>. But the logic here will still delete it.
      "   And unless we want to intercept motion commands, too, I'm not sure
      "   there's a way to avoid this.
      if completed["map_command"] == "\<ESC>"
        let current_line = getline(".")
        let trimmed_line  = substitute(current_line, '^\s*\(.\{-}\)\s*$', '\1', '')
        let n_chars = len(completed["key_list"]) - 1

        if col(".") == len(current_line) + 1 && n_chars == len(trimmed_line)
          " SAVVY:
          "   0 goes to the start of the line.
          "   "_ is the *black hole register* (:h quote_).
          "   D deletes to the end of the line.
          let seq = "\<ESC>" .. '0"_D'

          let do_callback = 0
        endif

        let seq = seq .. "\<ESC>"
      endif

      " We cannot change text from this map command, otherwise we might
      " try to :undo and :redo to see if user typed more than the key
      " sequence.
      " - But if we :undo from this map function, Vim complains:
      "     'E565: Not allowed to change text or change window'
      "   Because such changes are prohibited.
      "   - REFER: :h textlock
      " So that's why we're returning `:u` as part of the result, so that
      " Vim runs undo *after* this map command returns. At the same time,
      " (here), we schedule an immediate callback (timer hack?) to decide
      " if we need to :redo, and to use <Backspace> instead to clean up
      " the user's typed key sequence.
      " - DUNNO: There's a 'command mapping' feature for :map, <Cmd>, that
      "   does not engage textlock and might obviate the timer callback —
      "   'Commands can be invoked directly in Command-line mode (which
      "   would otherwise require timer hacks).' But author failed to get
      "   it to work (and not sure this is an appropriate use case, either).
      if do_callback
        let timer_id = timer_start(0, "VimInsertModeMapVerifyUndoAndRunCommand")
      endif
    endif

    " Run the command associated with the completed sequence: first delete
    " key_list characters, then run the command; and if escape on new line,
    " delete from first column.
    return seq
  endif

  if empty(reduction)
    " Nothing matched. Do over, man.
    call s:ResetActiveMaps(a:map_mode)
  else
    " At least one character matched the start of a sequence, of the
    " next character in a sequence, but none of the sequences has
    " yet been completed.
    let s:active_maps[a:map_mode] = reduction
    let s:is_reducing[a:map_mode] = 1
  endif

  return a:char
endfunction

function! VimInsertModeMapVerifyUndoAndRunCommand(timer_id) abort
  let after_line = getline(".")
  if s:before_lnum != len(".")
      \ || len(s:before_line) != len(after_line) + len(s:completed["key_list"]) - 1
    " More than just the sequence was part of the undo, so restore the edit
    " and use backspace instead to remove the typed sequence characters.
    redo

    call setpos(".", s:prev_pos)

    " Be careful if cursor is at the end of the line.
    if !s:at_final_column
      exe "normal " .. (len(s:completed["key_list"]) - 1) .. "X"
    else
      exe "normal x" .. (len(s:completed["key_list"]) - 2) .. "X" .. "$"
    endif
  endif

  " Note calling <ESC> here doesn't work, i.e.:
  "   exe "normal! \e"
  " - So <Escape> was previously returned by s:ProcessKeypress().
  if s:completed["map_command"] != "\<ESC>"
    exe "normal " .. s:completed["map_command"]
  endif
endfunction

" ***

function! s:ResetTimer() abort
  if s:haspy3
    py3 last_keypress_time_py3 = default_timer()
  endif

  let s:last_keypress_time_vim = localtime()
endfunction

function! s:ReadTimer() abort
  if s:haspy3
    py3 vim.command("let pyresult = %g" % (1000 * (default_timer() - last_keypress_time_py3)))

    return pyresult
  else
    let viresult = 1000 * (localtime() - s:last_keypress_time_vim)

    return viresult
  endif
endfunction

" On load, set initial timer value.
function! s:InitializeTimeout() abort
  if g:vim_async_map_timeout == 0
    if s:haspy3
      let g:vim_async_map_timeout = 100
    else
      let g:vim_async_map_timeout = 2000
    endif
  elseif !s:haspy3 && g:vim_async_map_timeout < 2000
    call s:PrintAlertPython3Missing()

    let g:vim_async_map_timeout = 2000
  endif
endfunction

function! s:PrintAlertPython3Missing() abort
  echomsg "ALERT: Python v3 required to set g:vim_async_map_timeout < 2000"

  if has('macunix')
    echomsg "- USAGE: On macOS, ensure MacVim installed and its vim/vi are on PATH before Apple's"
  else
    echomsg "- USAGE: On Linux, build Vim with Python3 support"
    echomsg "  - CXREF: Here's how DepoXy project builds Vim:"
    echomsg "    https://github.com/DepoXy/depoxy/blob/1.4.0/home/.vim/_mrconfig#L53-L108"
  endif
endfunction

if !exists("g:vim_async_map_timeout")
  let g:vim_async_map_timeout = 0
endif

call s:InitializeTimeout()

" Load Python modules, which stay loaded.
if s:haspy3
  py3 from timeit import default_timer
  py3 import vim
  " Initialize timer value, which is used to verify map sequences.
  " - This value is updated by s:ProcessKeypress().
  call s:ResetTimer()
else
  " MAYBE/2024-12-20: Try timer_start instead — that has better granularity,
  " and we could use it to set a flag (so when next keypress received, we
  " check if timer fired or not. If it fired, timeout happened and we reset
  " the sequences; otherwise cancel the timer and check next seq. char.).
  let s:last_keypress_time_vim = localtime()
endif

" ***

" In addition to the single-character maps, watch InsertCharPre. If the
" user presses any other key that's *not* registered, reset the watch.
" - This prevents, e.g., user typing `juke` and plugin matching `jk`.
" - Note that s:Process_InsertCharPre() runs *after* s:ProcessKeypress(),
"   and rather than look at v:char, we can check s:is_reducing to
"   see if s:ProcessKeypress() is in the middle of processing a
"   sequence or not (and if not, we'll reset the sequence trackers).
"
" BWARE: There's no equivalent for watching normal mode keypresses (as
" far as the author knows), so user could still see false-positives.
" - E.g., suppose user sets `jk` normal mode async sequence. If user
"   types `juk` (down, undo, up) and the time between the `j` and `k`
"   inputs is less than the timeout, this plugin will detect the `jk`
"   sequence.
"   - In practice, if the timeout is 100 msec., the author is unable
"     to type `juk` fast enough. But at 200 msec. I can. (The fastest
"     I can type `juk` is around ~115 msec. And `kuj` takes me 102
"     msec. between the `k` and the `j`. So it seems like 100 msec.
"     is sorta the ideal timeout, at least for normal mode `kj`/`jk`
"     sequence.)
function! s:Process_InsertCharPre() abort
  let map_mode = 'i'
  if s:is_reducing[map_mode]
    " The pressed key matched a sequence we're monitoring, and
    " s:ProcessKeypress() just handled it (and set is_reducing=1).

    return
  endif

  " User pressed some other key than what's part of any sequence,
  " so reset seq. tracking.
  call s:ResetActiveMaps(map_mode)
endfunction

" ***

augroup vim_async_map_augroup
  au!

  au InsertCharPre * call s:Process_InsertCharPre()

  " REFER: exists('##event') checks autocommand supported by user's Vim.
  if exists('##ModeChanged')
    autocmd ModeChanged *:[ni] call s:ResetActiveMaps(v:event["new_mode"])
  endif
augroup END

