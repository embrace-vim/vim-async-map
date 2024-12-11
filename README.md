# Asynchronous, non-blocking insert mode maps

Use `vim-async-map` to add non-blocking insert mode maps
using "regular" characters.

- Instead of using a `<Leader>` combination or modifiers (e.g., `<Ctrl>`)
  to wire insert mode maps, you can wire normal character sequences
  (such as `gf`) without disrupting the normal user experience.

## This `vim-easyescape` fork adds arbitrary command support, and more

This project forks [`vim-easyescape`](https://github.com/zhou13/vim-easyescape)
and makes the following changes:

- Supports multiple sequences for arbitrary commands.

  - [`vim-easyescape`](https://github.com/zhou13/vim-easyescape) only
    supports one key sequence — and it adds all permutations of it,
    e.g., if you map `kj`, then `jk` will also work.

  - [`vim-easyescape`](https://github.com/zhou13/vim-easyescape) only
    supports one map command, `<ESC>`.

  - This fork, in contrast, supports more than one key sequence, and it
    does not wire any any permutations unless you want them.

  - This fork supports any map command you want to run, e.g., `gf`.

  - This forks supports both insert mode and normal mode maps.

- Avoids editing the buffer.

  - After typing the key sequence,
    [`vim-easyescape`](https://github.com/zhou13/vim-easyescape)
    uses `<Backspace>` to remove what you typed, but this leaves
    the buffer edited.

    - And then you have to `:undo` or save, or you'll be prompted
      when you try to close the file.

  - This plugin uses `:undo` when possible to clear the typed
    sequence, so that the file buffer remains unchanged.

## Details

`vim-async-map` lets you add nondisruptive insert mode maps.

- A normal, naïve insert map pauses input between keypresses, e.g.,
  if you wanted to be able to use `gf` to open file paths from
  insert mode, you could add a basic `imap`, e.g.,

  ```
  inoremap gf <C-O>gf
  ```

  But this will degrade your user experience — now when you type
  a `g`, instead of inserting the character, Vim will show a `g`
  over the next character, and it won't insert the `g` until a
  timeout, or until you hit a character other than `f`.

  - E.g., assume the cursor is before 's' on the following line:

  ```
  this is some text
          ↑ cursor
  ```

  When you press `g`, you'll see this:

  ```
  this is gome text
          ↑ cursor
  ```

  And not until a timeout occurs, or until you press another key
  (other than `f`) will the insert happen.

  And you'll finally see, e.g.,

  ```
  this is gsome text
           ↑ cursor
  ```

- So instead of adding multiple-character mappings, `vim-async-map`
  adds single-character mappings and then monitors input to see if it
  matches any sequence that you've registered with it.

  - Considering the previous example, if you wanted to add a `gf`
    mapping, this plugin will monitor `g` and `f` separately
    (by creating two maps, `inoremap g` and `inoremap f`).

    Then, when it sees a `g`, it'll remember this, and if the next
    keypress is an `f`, it sees that you've typed a sequence, and it
    will run the command you've registered for that sequence.

## Common usage — map insert mode `jk` and `kj` to `<ESC>`

The most common use case is to replace `vim-easyescape`:

  ```
  let timeout_msec = 100

  call g:embrace#async_map#register_insert_mode_map("kj", "\<ESC>", timeout_msec)
  call g:embrace#async_map#register_insert_mode_map("jk", "\<ESC>", timeout_msec)
  ```

If you also wanted `kj` and `jk` to work from command mode,
you could add two simple maps:

  ```
  cnoremap kj <ESC>
  cnoremap jk <ESC>
  ```

Taking it even further, you could also add the same maps to normal
mode to toggle *back* to insert mode, and it won't interfere with
the built-in `j` or `k` commands, e.g.,

  ```
  let timeout_msec = 100

  call g:embrace#async_map#register_normal_mode_map("kj", "ji", timeout_msec)
  call g:embrace#async_map#register_normal_mode_map("jk", "ki", timeout_msec)
  ```

- So if you type `kj`, the `k` moves the cursor up one row, and
  the `j` triggers the map command. And then the map command
  runs `j` to move the cursor back down one row (to restore its
  position), and then `i` to enter insert mode.

- Beware that the plugin cannot detect when the user "breaks" a
  normal mode sequence. E.g., if the user registers `jk` but
  then types `juk`, if less than timeout msecs. pass between
  the `j` and the `k`, this plugin will assume that `jk` was
  pressed.

  - This does not affect insert mode maps because the plugin
    monitors the `InsertCharPre` event and can detect when a
    non-sequence character is pressed. But there is no equivalent
    event for normal mode (and the plugin does not set a map
    for every possible character — only those included in a
    sequence).

  - However, if you use a short, 100 msec. timeout, you should
    not have an issue. (E.g., it takes the author 115 msec. to
    type `juk` as fast as they can.)

[easyescape_kj_jk]: https://github.com/landonb/vim-ovm-easyescape-kj-jk/blob/2.0.0/plugin/vim_ovm_easyescape_kj_jk.vim

(You can see a real-world implementation in
[https://github.com/landonb/vim-ovm-easyescape-kj-jk/blob/2.0.0/plugin/vim_ovm_easyescape_kj_jk.vim][easyescape_kj_jk].)

## Common usage — map insert mode `gf` to normal mode `gf` ("goto file")

The `gf` command is very useful, especially if you bop around source code
and note files a lot and leave yourself file path references in comments
or in your notes.

But after a while, you might grow tired of needing to leave insert
mode to run `gf`! One idea is to map insert mode `gf` to running
the normal mode command of the same name, e.g.,

  ```
  let timeout_msec = 100

  " Wire the `gf` key sequence to the `gf` command.
  call g:embrace#async_map#register_insert_mode_map("gf", "gf", timeout_msec)
  ```

You could similarly add a visual mode mapping:

  ```
  " [y]ank selected text to `"` register, then paste `"` contents as arg to :edit.
  vnoremap gf y:edit <C-r>"<CR>
  ```

[includeexpr-for-gf]: https://github.com/embrace-vim/vim-goto-file-sh/blob/1.3.0/plugin/includeexpr-for-gf.vim

(You can see a real-world implementation in
[https://github.com/embrace-vim/vim-goto-file-sh/blob/1.3.0/plugin/includeexpr-for-gf.vim][includeexpr-for-gf].)

## Timeout values

You can set a different timeout for each sequence, as shown in the
examples above.

If you omit the timeout, it defaults to the value of a global variable,
`g:vim_async_map_timeout`, which defaults to 100 unless you change it,
e.g.,

  ```
  let g:vim_async_map_timeout = 100
  ```

Such a short timeout works well for the examples shown above, but you
may need a longer timeout for other maps.

- For instance, if you mix case, you might find that you need a longer
  timeout, e.g.,

  ```
  let timeout_msec = 200

  call g:embrace#async_map#register_insert_mode_map("gW", "gW", timeout_msec)
  ```

## Disable plugin for specific file types

You can disable `vim-async-map` for specific file types (or for any
buffer) by setting `b:vim_async_map_disable = 1`, e.g.:

  ```
  autocmd FileType text,markdown call setbufvar(bufnr("%"), 'vim_async_map_disable', 1)
  ```

- This applies to all registered mappings, however. (Feel free to PR if
  you want to make it more discerning, i.e., to disable individual key
  sequences instead of it being all-or-nothing.)

## Requirements — Python 3 (Optional)

Python3 is required to set a timeout less than 2000 msec., e.g.,

  ```
  let g:vim_async_map_timeout = 100
  ```

Otherwise the shortest usable timeout will be 2 secs.

- If more than *timeout* time passes between keypresses, the current
  key sequence is ignored.

  - E.g., if you `g` and then briefly pause before typing `f`, you
    can avoid running the `gf` command.

    - Though not that `gf` is a very common substring in English — there
      are only about 19 words that contain it, including "dogface" (older
      slang for a WW II infantryman), "eggfruit", "pigfish", "songful",
      "slugfest", and probably the most commonly used match, "meaningful".
      (Thanks to https://www.visca.com/regexdict/ for help with research.)

Hints:

- On macOS, ensure MacVim installed and its `vim`/`vi` are on `PATH` before Apple's.

- On Linux, build Vim with Python3 support.

  - Here's how DepoXy project builds Vim:

    https://github.com/DepoXy/depoxy/blob/1.4.0/home/.vim/_mrconfig#L53-L108

## Installation

Installation is easy using the packages feature (see
[`:help packages`](https://vimhelp.org/repeat.txt.html#packages)).

To install the package so that it will automatically load on Vim startup,
use a `start` directory, e.g.,

  ```
  mkdir -p ~/.vim/pack/embrace-vim/start
  cd ~/.vim/pack/embrace-vim/start
  ```

If you want to test the package first, make it optional instead
(see [`:help pack-add`](https://vimhelp.org/repeat.txt.html#pack-add)):

  ```
  mkdir -p ~/.vim/pack/embrace-vim/opt
  cd ~/.vim/pack/embrace-vim/opt
  ```

Clone the project to the desired path:

  ```
  git clone https://github.com/embrace-vim/vim-async-map.git
  ```

If you installed to the optional path, tell Vim to load the package:

  ```
  :packadd! vim-async-map
  ```

Just once, tell Vim to build the online help:

  ```
  :Helptags
  ```

Then whenever you want to reference the help from Vim, run:

  ```
  :help vim-async-map
  ```

[vim-plug]: https://github.com/junegunn/vim-plug
[Vundle]: https://github.com/VundleVim/Vundle.vim
[myrepos]: https://myrepos.branchable.com/
[ohmyrepos]: https://github.com/landonb/ohmyrepos

Note that you'll need to update the repo manually (e.g., `git pull`
occasionally).

- If you'd like to be able to update from within Vim, you could use
  [`vim-plug`][vim-plug].

  - You could then skip the steps above and register
    the plugin like this, e.g.:

  ```
  call plug#begin()

  " List your plugins here
  Plug 'embrace-vim/vim-async-map'

  call plug#end()
  ```

- And to update, call:

  ```
  :PlugUpdate
  ```

- Similarly, there's also [`Vundle`][Vundle].

  - You'd configure it something like this:

  ```
  set nocompatible              " be iMproved, required
  filetype off                  " required

  " set the runtime path to include Vundle and initialize
  set rtp+=~/.vim/bundle/Vundle.vim
  call vundle#begin()
  " alternatively, pass a path where Vundle should install plugins
  "call vundle#begin('~/some/path/here')

  " let Vundle manage Vundle, required
  Plugin 'VundleVim/Vundle.vim'

  Plugin 'embrace-vim/vim-async-map'

  " All of your Plugins must be added before the following line
  call vundle#end()            " required
  filetype plugin indent on    " required
  " To ignore plugin indent changes, instead use:
  "filetype plugin on
  ```

- And then to update, call one of these:

  ```
  :PluginInstall!
  :PluginUpdate
  ```

- Or, if you're like the author, you could use a multi-repo Git tool,
  such as [`myrepos`][myrepos] (along with the author's library, [`ohmyrepos`][ohmyrepos])).

  - With [`myrepos`][myrepos], you could update all your Git repos with
    the following command:

  ```
  mr -d / pull
  ```

- Alternatively, if you use [`ohmyrepos`][ohmyrepos], you could pull
  just Vim plugin changes with something like this:

  ```
  MR_INCLUDE=vim-plugins mr -d / pull
  ```

- After you identify your vim-plugins using the 'skip' action, e.g.:

  ```
  # Put this in ~/.mrconfig, or something loaded by it.
  [DEFAULT]
  skip = mr_exclusive "vim-plugins"

  [pack/embrace-vim/start/vim-async-map]
  lib = remote_set origin https://github.com/embrace-vim/vim-async-map.git

  [DEFAULT]
  skip = false
  ```

## Attribution

The [`embrace-vim`](https://github.com/embrace-vim) logo by
[`@landonb`](https://github.com/landonb) contains
[*coffee cup with straw by farra nugraha from Noun Project*](https://thenounproject.com/icon/coffee-cup-with-straw-6961731/)
(CC BY 3.0).

## Very Special Thanks

This project would not exist if not for
[`vim-easyescape`](https://github.com/zhou13/vim-easyescape)!

That plugin offered a novel approach to adding insert mode mappings,
one that I've used for many years, and it was only because I like it
so much that I hacked away hoping to improve upon it.

So with gratitude and admiration, thanks you,
```
_____                  _____                          
 | ____|__ _ ___ _   _  | ____|___  ___ __ _ _ __   ___ 
 |  _| / _` / __| | | | |  _| / __|/ __/ _` | '_ \ / _ \
 | |__| (_| \__ \ |_| | | |___\__ \ (_| (_| | |_) |  __/
 |_____\__,_|___/\__, | |_____|___/\___\__,_| .__/ \___|
                 |___/                      |_|
```

