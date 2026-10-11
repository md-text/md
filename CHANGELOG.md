# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project infrastructure: build system, specs, linting, continuous integration
  and release builds for Linux (x86_64, aarch64) and macOS (Intel, Apple Silicon).
- Command line: `md [FILE | -]`, with `-` for standard input, `--help` and `--version`.
- The application: a main window (menu bar and status bar, empty for now) with
  three side-by-side panes — Markdown source editor, rendered viewer and a
  navigable table of contents. A new document opens in the editor, a file in
  the viewer; any combination of panes can be shown (`F2`/`F3`/`F4`), the
  viewer re-renders live as the source is edited, and `Ctrl-S` saves.
- Standard input is streamed into the viewer as it arrives, following the tail
  (`md -`, or `cmd | md`), with keyboard input taken from the terminal.
- Status bar: the document's name (or a passing notice), the caret position
  while editing or the reading position (`Top`, `Bot`, a percentage, `All`)
  while viewing, line and word counts, encoding and line endings, the modified
  flag, and two toggles: `INS`/`OVR` for the editor's overwrite mode (also the
  `Insert` key) and a mouse field — `🖱=` on terminals known to render the
  icon, `M=` elsewhere — cycling the mouse modes `a`, `n`, `i` and off, after
  vi's `set mouse=` (also `F5`).
- Menu bar: File (Save, Save As…, Quit), View (which panes are shown) and
  Options (overwrite mode, and the mouse mode as a radio submenu), with
  `Alt` + letter mnemonics.
- `Space` pages forward and `Enter` moves down a line in the viewer, as in a
  pager.
- Save As: a vi-style prompt in place of the status bar, the current name
  filled in, with file-name completion and history. `Ctrl-S` on a document
  without a name asks the same way.
- View → Follow cursor: the editor's and the viewer's cursors follow each
  other — a move in the pane you are in puts the other pane's cursor on the
  corresponding place, scrolled to the same row of its pane. Matched by
  source line, so inside formatted text the spot is approximate.
- View → Highlight line: tints the cursor's row in each pane; with Follow
  cursor on, the two tinted rows show the same place in the document.
- Search, as in a pager: `/` and `?` (`Ctrl-F` in the editor) ask for a
  pattern — a regular expression when it is one, literal text otherwise,
  case-insensitive unless it has an uppercase letter — and `n`/`N`
  (`Ctrl-G`/`Alt-G`) repeat it either way, wrapping around with a notice.
  Matches are underlined in both panes and the current one is selected;
  Edit → Clear Highlight takes the underlines off. `:` (`Ctrl-L`) goes to a
  source line in both panes, `]` and `[` (`Alt-Down`/`Alt-Up`) to the next
  and previous heading.
- File → Open… (`Ctrl-O`) opens another file, asked for in place of the
  status bar with completion like Save As; File → Reload (`Ctrl-R`) re-reads
  the file keeping the viewer's place; View → Watch file (and `--watch`)
  reloads it whenever it changes on disk, unless the editor holds unsaved
  changes, which are kept with a notice.
- A guard against losing unsaved changes: quitting, opening and reloading
  ask — Save, Don't save or Cancel — when the document is modified, through
  Crysterm's new close request, so the default `q`/`Ctrl-Q` keys ask too.
  Options → Ask before discarding changes turns it off.
- File → Open Recent lists the recently opened files, and the position in
  each is remembered and restored when it is opened again, in
  `$XDG_STATE_HOME/md/history.json` (`~/.local/state/md/history.json`).
- Links go somewhere: a relative or `file:` link to a Markdown file opens
  it in the same window (through the unsaved-changes guard, landing on the
  heading its `#fragment` names), a `#heading` link jumps to the heading,
  and `http:`, `mailto:` and other external links — and existing files that
  are not Markdown — open with the system's `open` (macOS) or `xdg-open`.
  Edit → Back (`Alt-Left`; `Backspace` in the viewer and the table of
  contents) retraces the links followed and the files opened, to the file
  and position left; Edit → Forward (`Alt-Right`) undoes a Back.
- Settings kept across runs: View → Follow cursor and Highlight line,
  Options → Ask before discarding changes and the mouse mode are restored at
  start and written at exit to `$XDG_CONFIG_HOME/md/settings.json`
  (`~/.config/md/settings.json`), a store in the manner of Qt's `QSettings`
  that later settings (pane sizes, a theme) join as new keys.
- Options → Theme (`F6` cycles): the themes built into Crysterm — terminal,
  dark and light, as `--colors-theme` names them — switched at runtime, the
  whole window restyled at once. The choice is kept in the settings;
  `--colors-theme` wins for its run without being kept, and a
  `--colors-stylesheet` of your own stays over whichever theme is on.
- The menus show their entries' keys: File → Open…, Reload, Save and Quit
  and Edit → Find…, Find Next, Find Previous and Go to Line… carry their
  shortcuts (Crysterm's action shortcuts, spelled `Ctrl+O` as Qt does),
  and Edit → Next Heading and Previous Heading are new entries for
  `Alt-Down` and `Alt-Up`. The keys fire from any pane after the pane had
  its turn, so the editor keeps `Ctrl-Z`, `Ctrl-K` and the like, and wait
  while a prompt is open (a Crysterm fix: a prompt now owns the keyboard).
  The menu bar's hint spells its keys the same way (`Alt+F`).
- `Ctrl-Z` outside the editor suspends md to the shell, as it would in a
  program that left the key to the terminal; `fg` brings it back with the
  screen repainted (Crysterm's new `Crysterm.suspend`).
- View → Line numbers: a gutter with the source line numbers on the
  editor's left (Crysterm's new `PlainTextEdit#line_numbers`), kept across
  runs with the other View choices.
- Command line: `+N` or `--line N` (`-l N`) opens on source line `N` in
  both panes, as `less +N` and `vim +N` do (past the end: the last line; a
  bare `+`: the end), ahead of the remembered position; `--view` and
  `--edit` choose the pane whatever the file is, so `md --edit README.md`
  opens the editor on it and `md --view new.md` the viewer on an empty
  document. Giving both is a usage error.
- `md --export html FILE` and `--export text` (`--to FORMAT` as well, after
  pandoc) print the document rendered on standard output and exit without
  opening a window — md as a filter. With no FILE, standard input is read,
  terminal or not. The HTML is a body fragment from Crysterm's exporter, the
  text is the viewer's text without styling: block margins as blank lines,
  list markers, indented quotes, box-drawn tables.
- A man page and completions for bash, zsh and fish, printed by the binary
  itself (`md --generate man|bash|zsh|fish`) from the one table its option
  parser is built from, so they cannot drift from `--help`. `make man` and
  `make completions` write them under `share/`, `make install` installs
  them under `$(PREFIX)/share`, and the release archives carry them next to
  the binary.

[Unreleased]: https://github.com/crystallabs/md/commits/main

### Fixed

- Quitting with the viewer focused and the outline shown no longer crashes
  and wedges the process: tearing the panes down rewound focus from the
  viewer to the outline, whose focus-in refreshed the status bar, which asked
  the already-detached viewer for its geometry. The status bar now stops
  refreshing once a pane has left the widget tree. (Crysterm itself now
  survives such teardown errors, restoring the terminal and reporting them.)
- An error that escapes one of md's handlers no longer takes the app down
  with unsaved text: md shows "Internal error: …" in the status bar and goes
  on, with the backtrace in `$XDG_CACHE_HOME/md/md.log`
  (`~/.cache/md/md.log`, or `CRYSTERM_LOG_FILE`), where Crysterm's log now
  goes while md runs. An error md cannot continue from is printed with its
  backtrace on the restored terminal, and md exits with status 1.

- The viewer follows the CSS theme/stylesheet (`--colors-theme`,
  `--colors-stylesheet`) like the editor and the table of contents do: its
  background and text take the stylesheet's colors, and its headings, code,
  links, quote bars and rules take the theme's `TextEdit::heading`/`::code`/
  `::link`/`::quote`/`::rule` colors, which a stylesheet can override. (Fixed
  in Crysterm, which md builds against.)
