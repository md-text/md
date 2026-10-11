# md

md is a Markdown viewer and editor for the terminal. It renders a parsed
document for reading, edits the Markdown source, and shows editor and rendered
view side by side with live updates as you type. It can also follow a document
arriving on standard input, re-rendering and scrolling as new text comes in.

md is built on [Crysterm](https://github.com/crystallabs/crysterm) and ships as
a single self-contained binary for Linux and macOS: download it, put it on your
`PATH`, and run it in any terminal.

> **Status:** early development. Viewing, editing, the side-by-side layout
> and streaming from standard input work; the menu bar and status bar are
> still empty. See [PLAN.md](PLAN.md).

[![CI](https://github.com/crystallabs/md/actions/workflows/ci.yml/badge.svg)](https://github.com/crystallabs/md/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/crystallabs/md?sort=semver)](https://github.com/crystallabs/md/releases/latest)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/license-AGPL--3.0--or--later-blue.svg)](LICENSE)

## Installation

### Prebuilt binaries (recommended)

Every release on the [releases page](https://github.com/crystallabs/md/releases)
includes an archive per platform:

| Archive                              | Platform                                  |
| ------------------------------------ | ----------------------------------------- |
| `md-vX.Y.Z-linux-x86_64.tar.gz`      | Linux, 64-bit Intel/AMD (any distribution) |
| `md-vX.Y.Z-linux-aarch64.tar.gz`     | Linux, 64-bit ARM (any distribution)       |
| `md-vX.Y.Z-macos-aarch64.tar.gz`     | macOS, Apple Silicon                       |
| `md-vX.Y.Z-macos-x86_64.tar.gz`      | macOS, Intel                               |

The Linux binaries are fully static and run on any distribution without
installing anything else. The macOS binaries depend only on libraries that
ship with macOS.

To install, download the archive for your platform, verify it, unpack it and
move the binary somewhere on your `PATH`. For example, on Linux x86_64:

```sh
VERSION=vX.Y.Z   # see the releases page for the latest version
curl -LO https://github.com/crystallabs/md/releases/download/$VERSION/md-$VERSION-linux-x86_64.tar.gz
curl -LO https://github.com/crystallabs/md/releases/download/$VERSION/md-$VERSION-linux-x86_64.tar.gz.sha256
shasum -a 256 -c md-$VERSION-linux-x86_64.tar.gz.sha256
tar xzf md-$VERSION-linux-x86_64.tar.gz
sudo install -m 0755 md-$VERSION-linux-x86_64/md /usr/local/bin/md
sudo cp -r md-$VERSION-linux-x86_64/share /usr/local/   # man page and completions (optional)
md --version
```

The archive's `share/` directory holds the man page (`man md` once it is
installed) and completions for bash, zsh and fish, laid out as they are
installed under a prefix. The binary prints them itself — `md --generate
man`, `bash`, `zsh` or `fish` — so they can be put anywhere a shell looks
(`~/.zsh/completions/_md`, `~/.config/fish/completions/md.fish`).

On macOS, a binary downloaded with a web browser is quarantined by Gatekeeper
and refused on first start. Downloading with `curl` as above avoids that;
otherwise clear the flag with `xattr -d com.apple.quarantine md`.

Windows is not supported natively, since md needs a POSIX terminal. The Linux
binary runs under the [Windows Subsystem for Linux](https://learn.microsoft.com/windows/wsl/).

### From source

See [Building from source](#building-from-source) below.

## Usage

```sh
md                    # open an empty editor
md README.md          # open a file for viewing
md notes.md           # a file that does not exist yet opens in the editor
md --watch notes.md   # ...and reload it whenever it changes on disk
md +120 notes.md      # open on source line 120 (`--line 120` too)
md --edit README.md   # open the editor rather than the viewer on a file
md --view new.md      # or the viewer on a document that does not exist yet
md - < README.md      # read the document from standard input
some-command | md     # follow output as it arrives (`-` is optional here)
md --export html README.md > README.html   # render to standard output and exit
some-command | md --to text                # ...as plain text; `--to` is `--export`
md --help             # list the options (`--help --verbose` adds Crysterm's)
md --version          # print the version
man md                # the manual page, once installed
```

The window has three panes side by side: the Markdown source editor, the
rendered viewer and a table of contents. A new document starts with only the
editor shown; a file or a stream starts with only the viewer (`--edit` and
`--view` override that choice). `+N` or `--line N` puts both panes on source
line `N`, as `less +N` and `vim +N` do — past the end lands on the last line,
and a bare `+` is the end — instead of the position md remembers for the
file. Show any combination you like; the viewer re-renders as you type, and the table of
contents follows the document's headings. A document arriving on standard
input is rendered as it comes in, and the viewer keeps scrolling to the end
until you scroll up.

| Key                | Action                                                                    |
| ------------------ | ------------------------------------------------------------------------- |
| `F2`, `F3`, `F4`   | Show and focus the editor, viewer or table of contents; hide it if it is already focused (the last pane stays) |
| `Tab`, `Shift-Tab` | Move focus to the next or previous shown pane (in the viewer, `Tab` first cycles links) |
| `Enter`            | In the table of contents, jump the viewer to the selected heading; in the viewer, follow the focused link |
| `Space`, `Enter`   | In the viewer, read on by a page or by a line (arrows, `PageUp`/`PageDown`, `Home`/`End` as usual) |
| `Insert`           | Toggle the editor between inserting and overwriting (the `INS`/`OVR` field) |
| `F5`               | Cycle the mouse mode (the `🖱=` field)                                    |
| `F6`               | Cycle the theme: terminal, dark, light (Options → Theme)                  |
| `Ctrl-Z`           | Outside the editor, suspend md to the shell (`fg` resumes); in the editor, undo |
| `Alt-F`, `Alt-E`, `Alt-V`, `Alt-O` | Open the File, Edit, View and Options menus (`F10` too)   |
| `Ctrl-O`           | Open a file; asks for the name (File → Open…)                             |
| `Ctrl-R`           | Reload the file from disk (File → Reload)                                 |
| `Ctrl-S`           | Save; without a file name yet, asks for one (File → Save As… always asks) |
| `Ctrl-F`, `/`, `?` | Search; asks for the pattern (`/` and `?` outside the editor, `?` backward; Edit → Find…) |
| `Ctrl-G`, `Alt-G`, `n`, `N` | Next and previous match (`n` and `N` outside the editor; Edit → Find Next, Find Previous) |
| `Ctrl-L`, `:`      | Go to a source line; asks for the number (`:` outside the editor; Edit → Go to Line…) |
| `Alt-Down`, `Alt-Up`, `]`, `[` | Jump to the next and previous heading (`]` and `[` outside the editor; Edit → Next Heading, Previous Heading) |
| `Backspace`        | Outside the editor, go back to where you were before the last link or open (Edit → Back) |
| `Alt-Left`, `Alt-Right` | Back and Forward (Edit → Back, Forward); in the editor and the viewer these move by word instead |
| `Ctrl-Q`           | Quit (`q` too, anywhere but in the editor; File → Quit); asks first when changes are unsaved |

The File and Edit menus show these keys next to their entries, spelled as
Qt does (`Ctrl+O`), and the right end of the menu bar names the keys that
open the menus. The keys work from any pane, after the pane had its turn —
the editor keeps the keys it uses — and wait while a prompt is open.

The editor has the usual editing keys: arrows and `Home`/`End`, `Shift` +
arrows to select, `Ctrl-Z`/`Alt-Z` to undo and redo, `Ctrl-K`/`Ctrl-Y` to kill
and yank, and the mouse to position the cursor, select and scroll.

The status bar shows the document's name (a save result or warning takes its
place for a moment), the caret's line and column while editing or the reading
position while viewing (`Top`, `Bot`, a percentage, or `All` when the whole
document fits), the line and word counts, the encoding and line endings, and
whether the document is modified. Two fields at the right are toggles you can
click: `INS`/`OVR` switches the editor between inserting and overwriting, and
the mouse field — `🖱=` on terminals known to render the icon, `M=` elsewhere —
cycles the mouse modes, named after vi's `set mouse=` values:

| Mode      | The mouse works…                                                            |
| --------- | --------------------------------------------------------------------------- |
| `mouse=a` | always                                                                      |
| `mouse=n` | while reading, in the viewer or the table of contents (vi's Normal mode)   |
| `mouse=i` | while editing, in the editor (vi's Insert mode)                             |
| `mouse=`  | never                                                                       |

While the mouse does not work for md, the terminal's own text selection and
copy work instead. With the mouse off you cannot click the field, so `F5`
cycles the modes from the keyboard too, and the Options menu offers them as
well, next to the overwrite mode. The File menu opens, reloads, saves, saves
as and quits, and lists the recently opened files; the Edit menu searches,
goes to a line and jumps between headings; the View menu shows and hides
the panes.

Options → Theme picks the colors the whole window is drawn in, from the
themes built into Crysterm — the same ones its `--colors-theme` option
names: `terminal` derives a palette from your terminal's own colors, so md
blends in, and `dark` and `light` are fixed palettes. The window switches at
once, and `F6` cycles through them from the keyboard. The choice is kept
with the other settings; `--colors-theme` given on the command line (or in
Crysterm's config file or environment) wins for that run and is not kept,
so the next plain run is back to the stored theme. A stylesheet of your own
(`--colors-stylesheet FILE`, CSS or Qt's QSS) layers over whichever theme
is on, so your rules stay in force when the theme changes under them.

### Searching and jumping

Searching works like a pager's: `/` asks for a pattern and finds it forward
from the cursor, `?` backward, `n` repeats the search and `N` goes the other
way (in the editor, where those are letters to type, use `Ctrl-F`, `Ctrl-G`
and `Alt-G` instead; they work everywhere). The pane you are in is searched:
the Markdown source in the editor, the rendered text in the viewer (or from
the table of contents). The pattern is a regular expression when it is a
valid one and plain text otherwise, and it ignores case unless it contains
an uppercase letter, as vi's `smartcase` does. The search wraps around the
end of the document with a notice. Every match is underlined in both panes
and the current one is selected; Edit → Clear Highlight takes the underlines
off, and `n` still knows the pattern.

`:` (or `Ctrl-L`) asks for a source line number and puts both panes there;
`0` and negative numbers count from the end. `]` and `[` (or `Alt-Down` and
`Alt-Up`, Edit → Next Heading and Previous Heading) jump to the next and
previous heading, in both panes, with the heading on the viewer's top row
as a table of contents jump lands.

### Opening, reloading and watching

File → Open… (`Ctrl-O`) asks for a file name the way Save As does, with
`Tab` completion, and opens it: an existing file in the viewer, a new name as
an empty document in the editor. A document streaming in from standard input
is left behind. File → Open Recent lists the files you opened before, most
recent first; md also remembers where you were in each and lands there when
you open it again. The list lives in `$XDG_STATE_HOME/md/history.json`
(`~/.local/state/md/history.json`).

File → Reload (`Ctrl-R`) re-reads the file from disk, keeping the viewer's
place. View → Watch file (or `--watch` on the command line) does that for
you: the file is polled once a second and reloaded when another program
changed it, so md beside an editor shows each save as it happens. While the
editor holds unsaved changes the reload is skipped and a notice says the
file changed on disk. The status bar shows `(watching)` after the name.

### Following links

In the viewer, `Tab` moves between the document's links and `Enter` follows
the focused one (a mouse click does too). Where a link leads depends on what
it names. A `#heading` scrolls to that heading, as the table of contents
does. A relative path, or a `file:` URL, counts from the document's
directory (the working directory for a document without a file); when it
names a Markdown file — by extension: `.md`, `.markdown`, `.mdown`, `.mkd`,
`.mkdn`, `.mdwn` — the file opens in the same window, landing on the
heading a `#fragment` after the name points at. Any other link — `http:`,
`https:`, `mailto:`, or an existing file that is not Markdown, such as an
image or a PDF — is handed to the system to open with whatever handles it:
`open` on macOS, `xdg-open` elsewhere. A link to a file that does not exist
only gets a notice.

Every link followed is a step you can retrace: `Backspace` in the viewer or
the table of contents goes back to the file and position you came from
(Edit → Back, `Alt-Left`, works from the menu too), and Edit → Forward
(`Alt-Right`) undoes a Back. Opening a file from File → Open… or Open Recent
over the one shown is a step as well, and so is a jump from the table of
contents. Going back to another file asks about unsaved changes like any
open. In the editor and the viewer `Alt-Left` and `Alt-Right` keep moving
the cursor by word, so the menu and `Backspace` are the way back from there.

### Exporting

`md --export html FILE` (or `--to html`, pandoc's spelling) prints the
rendered document on standard output and exits without opening a window, so
md works as a filter in a pipeline: `md --export html notes.md > notes.html`,
`curl -s …/README.md | md --to text | less`. With no FILE, standard input is
read whether or not it is a terminal, as any filter does. The document goes
through the same rendering the viewer uses: `html` is an HTML body fragment
(no `<html>`/`<head>` wrapper, as pandoc without `--standalone`), `text` is
the viewer's text without its styling — paragraphs spaced as on screen, list
items with their markers, quotes and nested items indented, tables drawn
with box characters. Nothing else happens in this mode: no history, no log
file.

### Unsaved changes

Quitting, opening another file or reloading with unsaved changes asks first:
*Save*, *Don't save* or *Cancel*. Saving a document without a name asks for
one, and the action goes ahead once the save is done. Options → Ask before
discarding changes turns the question off.

The View menu also has *Follow cursor*: with it on, moving the cursor in the
editor puts the viewer's cursor on the same place in the rendered document,
scrolled to the same row of its pane, and moving it in the viewer does the
same in the editor.
The pane you are in leads. The match is by source line, so inside formatted
text the other cursor lands near rather than exactly on the spot, and a line
that renders nothing (a blank line, a code fence) maps to the rendered block
just above it. *Highlight line*, also in the View menu, tints the row the
cursor is on in each pane; together with *Follow cursor* the two tinted rows
are the same place in the document, which makes the pairing easy to see.
*Line numbers* puts a gutter with the source line numbers on the editor's
left, the way code editors do; the choice is kept across runs.

Save As asks for the name in place of the status bar, the way vi's command
line replaces its status line: the current name is filled in, `Tab` and
`Shift-Tab` complete file names, `Up` recalls earlier answers, `Enter` saves,
and `Escape` (or `Backspace` on an empty line) gives up.

### Auto-save and backups

Two nets catch what a crash, a kill or a slip would lose, both on by default
in the Options menu. *Keep a backup file* keeps the file as it was before
the first save of the session, as `FILE~` beside it (emacs' convention), so
one save too many is undone by copying the backup back; later saves in the
same session leave it alone. *Auto-save* writes your unsaved edits every 30
seconds to a recovery file — never to the file itself, which is written
only when you save, the way vim's swap file and emacs' `#file#` work. The
recovery files live in `$XDG_STATE_HOME/md/autosave/`
(`~/.local/state/md/autosave/`), named after the file's absolute path with
`/` escaped as `%2F` (`/home/u/notes.md` recovers from
`%2Fhome%2Fu%2Fnotes.md`); a document without a name, such as one piped in
on standard input and then edited, is kept as `unnamed-<date>-<time>-<pid>.md`.
Saving or quitting normally removes the recovery file, so whatever remains
in the directory is what some session lost. When you open a file whose
recovery file is newer than the file, a notice names the copy; open it
(File → Open… takes the path) or copy it over the file to get the edits
back. A new document is told of unnamed copies left behind.

### Settings

The choices made in the View and Options menus — Follow cursor, Highlight
line, Ask before discarding changes, Auto-save, Keep a backup file, the
mouse mode and the theme — are kept across runs
in `$XDG_CONFIG_HOME/md/settings.json` (`~/.config/md/settings.json`), written
when md quits. Watch file is not kept: like `--watch`, it is for the run at
hand. The file is plain JSON and can be edited by hand; a missing or broken
one simply means the defaults.

## Building from source

md is written in [Crystal](https://crystal-lang.org). You need:

- Crystal 1.21 or newer, with its `shards` dependency manager (included in all
  official packages);
- the [unibilium](https://github.com/neovim/unibilium) terminfo library with
  its development headers;
- `make` (optional, but the commands below assume it).

On Debian or Ubuntu:

```sh
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt-get install -y libunibilium-dev make
```

On macOS with [Homebrew](https://brew.sh):

```sh
brew install crystal unibilium make
```

Then, in a clone of this repository:

```sh
make release          # fetch dependencies and build an optimized bin/md
sudo make install     # copy it to /usr/local/bin (set PREFIX to change)
```

`make` alone builds a faster-compiling, unoptimized binary for development.
Both place the binary in `bin/md`. `make install` also installs the man
page and the shell completions under `$(PREFIX)/share`, generated by the
binary just built (`make man`, `make completions` produce them under
`share/` without installing).

> **Temporary:** `shard.override.yml` builds against Crysterm and Tput
> checkouts in `../crysterm2` and `../tput.cr`, which carry fixes md needs
> that are not yet released. Clone them there (or edit the paths), or delete
> the override once releases with those fixes are out and `shard.yml`
> requires them.

## Development

```sh
make                  # build bin/md
make test             # run the specs
make lint             # run ameba (static analysis) and the formatter check
make format           # reformat the sources
make check            # test + lint, the same as CI
```

Layout:

```
src/bin/md.cr         executable entry point
src/md.cr             library root
src/md/cli.cr         the command line: the option table, parsing, launching
src/md/source.cr      where the document comes from (file, stdin, nothing)
src/md/export.cr      --export: the document rendered to standard output
src/md/manual.cr      --generate: the man page and the shell completions
src/md/app.cr         the Crysterm application: window, panes, keys, streaming
src/md/app_status.cr  the status bar fields, the mouse modes
src/md/app_menu.cr    the menu bar
src/md/app_search.cr  search, go to line, heading jumps
src/md/app_file.cr    open, reload, watch; the unsaved-changes guard; recent files
src/md/app_links.cr   following links; Back and Forward
src/md/app_theme.cr   the theme: Crysterm's built-in themes, switched at runtime
src/md/app_autosave.cr auto-save to a recovery file; the backup file
src/md/app_settings.cr the View and Options choices kept across runs
src/md/settings.cr    the settings store (~/.config/md/settings.json)
src/md/history.cr     the recent files and positions (~/.local/state/md/history.json)
src/md/version.cr     Md::VERSION, read from shard.yml at compile time
spec/                 specs (crystal spec)
```

The man page and the completions are not kept in the repository: the
binary is their source (`md --generate`), the release workflow runs it, and
a spec checks that every option is in each of them.

CI runs the specs and lints every push and pull request on Linux (x86_64,
aarch64) and macOS (Intel, Apple Silicon), with the latest Crystal release
and, on one platform, Crystal nightly.

### Releasing

1. Set the new version in `shard.yml` and move the *Unreleased* entries in
   `CHANGELOG.md` under a heading for it.
2. Commit, then tag and push:

   ```sh
   git tag -a vX.Y.Z -m "md vX.Y.Z"
   git push origin main vX.Y.Z
   ```

The *Release* workflow creates the GitHub release for the tag and attaches an
archive per supported platform, with a SHA-256 checksum, holding the binary
and the man page and completions it generated. The
workflow can also be run by hand from the *Actions* tab against an existing
tag, or without a tag to produce the archives as workflow artifacts only.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

Copyright (C) 2026 Davor Ocelic

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU Affero General Public License as published by the Free
Software Foundation, either version 3 of the License, or (at your option) any
later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE. See the GNU Affero General Public License for more details.

See [LICENSE](LICENSE) for the full text.
