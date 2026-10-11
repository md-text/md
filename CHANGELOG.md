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
- View → Sync Cursor: the editor's and the viewer's cursors follow each
  other — a move in the pane you are in puts the other pane's cursor on the
  corresponding place, scrolled to the same row of its pane. Matched by
  source line, so inside formatted text the spot is approximate.
- View → Highlight Line: tints the cursor's row in each pane; with Follow
  Cursor on, the two tinted rows show the same place in the document.
- Search, as in a pager: `/` and `?` (`Ctrl-F` in the editor) ask for a
  pattern — a regular expression when it is one, literal text otherwise,
  case-insensitive unless it has an uppercase letter — and `n`/`N`
  (`Ctrl-G`/`Alt-G`) repeat it either way, wrapping around with a notice.
  Matches are underlined in both panes and the current one is selected;
  Edit → Clear Search Highlights takes the underlines off. `:` (`Ctrl-L`) goes to a
  source line in both panes, `]` and `[` (`Alt-Down`/`Alt-Up`) to the next
  and previous heading.
- File → Open… (`Ctrl-O`) opens another file, asked for in place of the
  status bar with completion like Save As; File → Reload (`Ctrl-R`) re-reads
  the file keeping the viewer's place; View → Watch File (and `--watch`)
  reloads it whenever it changes on disk, unless the editor holds unsaved
  changes, which are kept with a notice.
- A guard against losing unsaved changes: quitting, opening and reloading
  ask — Save, Don't save or Cancel — when the document is modified, through
  Crysterm's new close request, so the default `q`/`Ctrl-Q` keys ask too.
  Options → Ask Before Discarding Changes turns it off.
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
- Settings kept across runs: View → Sync Cursor and Highlight Line,
  Options → Ask Before Discarding Changes and the mouse mode are restored at
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
- View → Line Numbers: a gutter with the source line numbers on the
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
- Auto-Save and a backup file, both Options entries on by default and kept
  in the settings. Options → Keep a Backup File copies the file to `FILE~`
  beside it before the session's first save of it (emacs' `make-backup-files`).
  Options → Auto-Save writes unsaved edits every 30 seconds to a recovery
  file under `$XDG_STATE_HOME/md/autosave/` (`~/.local/state/md/autosave/`),
  never to the file itself — named after the file's absolute path with `/`
  escaped as `%2F`, or `unnamed-<date>-<time>-<pid>.md` for a document
  without a name, standard input included — and removes it on a save or a
  normal exit, so the directory holds only what a crash lost; opening a file
  whose copy is newer than it gets a notice naming the copy.
- View → Soft Wrap (`Alt-W`) folds long lines in the editor at the pane's
  edge or lets them run past it with sideways scrolling; View → Text Width
  caps the text at 72, 80, 100 or 120 columns for a wide terminal, in both
  panes, and View → Center Text puts the capped column in the middle of the
  pane. All three are kept across runs. (Crysterm: `line_wrap_column` and
  `line_wrap_column_alignment` on `AbstractScrollArea`, Qt's
  `lineWrapColumnOrWidth` and `QScrollArea::alignment`; the scroll bars
  stay at the frame outside the viewport margins, and `TextEdit` paints
  from the margins.)
- Edit → Copy (`Ctrl-C`) copies the selection or, with nothing selected,
  the current block — the caret's line in the editor; in the viewer and
  the table of contents the paragraph, heading, list item or whole fenced
  code block the viewer's caret is in — as plain text, with a notice of
  how much was copied; Edit → Copy as Markdown copies the block's source
  lines, fences included. Options → Clipboard picks where a copy goes, kept
  across runs: the terminal's OSC 52 escape (the default), a system command
  found on the PATH (`pbcopy`, `wl-copy`, `xclip`, `xsel` or tmux's buffer,
  named in the entry) for where the escape does not get through, or md
  alone. The mode is Crysterm's new `Application::Clipboard#mode`, so the
  editor's own `Ctrl-C`, `Ctrl-X` and `Ctrl-V` follow it, a paste in
  Command mode reading the paired command; and a selection-less `Ctrl-C`
  now passes from a text pane to the application.
- Resizable panes: the panes sit in a splitter (Crysterm's, after Qt's
  `QSplitter`) with a divider between each two shown, dragged with the mouse
  or moved with `Left`/`Right` after View → Resize Panes (`Alt+R`) focuses
  the divider next to the pane (`Enter`/`Escape` return). A hidden pane takes
  no width and shows no divider, and gets its width back when shown. The
  sizes are kept in the settings as `pane_sizes` — columns per pane, hidden
  ones included — and restored at start; the editor and the viewer keep
  their proportion in a terminal of another width, the table of contents its
  columns. (Crysterm's splitter learnt to fold hidden panes away, to resize
  its panes in proportion and with stretch factors, to save and restore its
  state, and to keep its dividers off the Tab chain.)
- A file dropped on the window opens: the terminal pastes its path, and a
  paste that names one existing file, outside the editor, opens it through
  the unsaved-changes guard.
- Markdown-aware editing, and a Format menu (`Alt-M`) between Edit and
  View. `Enter` on a list item — bullets, numbers, tasks, indented or in a
  blockquote — continues the list with the same marker (the number raised,
  the task box emptied) and ends it on an empty item; `Tab` and `Shift-Tab`
  indent and outdent the item, or the selected lines, by the item above's
  content offset (Format → Indent, Outdent). Format → Bold, Italic and Code
  (`Ctrl-B`, `Alt-I`, `Alt-C`) wrap the selection or the word at the caret
  in `**`, `*` or backticks, or unwrap it; Task Box adds a `[ ]` box to a
  list item and takes it off, Check Task (`Alt-X`) ticks and unticks it (an
  item without a box gets a ticked one); Promote Heading and Demote Heading
  (`Ctrl-Up`, `Ctrl-Down`) change the line's heading level. Each change is
  one undo step.
- Edit → Replace… (`Alt-H`, since Qt's `Ctrl-H` is Backspace in a terminal): the
  prompt asks for the pattern (the last search's filled in) and the
  replacement, then steps through the matches from the cursor in the
  editor — shown and focused if need be, the source being what is replaced
  — asking `Replace? (y)es (n)o (a)ll (q)uit`, answered by a single key.
  The pattern follows the search's rules; the replacement may use `\1`–`\9`
  and `\0` for the pattern's groups and the whole match, as `String#sub`
  does. Every replacement is undoable, `a` as one step, and a notice gives
  the count.
- Edit → Paste (`Ctrl-V`) pastes the clipboard, as Options → Clipboard
  reads it, into the editor at the caret, replacing the selection, as one
  undo step; from the viewer or the table of contents the key reaches the
  entry, which shows the editor and pastes at the source of the viewer's
  caret. Edit → Paste Special names the source: From Terminal Clipboard
  asks the terminal through the OSC 52 read and pastes when it answers (a
  notice gives up after two seconds, since many terminals never answer),
  From Command pastes the paste command's output, From Internal Buffer what
  md itself last copied, and From Kill Ring an entry of the editor's kill
  ring — `Ctrl-K`'s, `Ctrl-U`'s and `Alt-D`'s kills — from a submenu
  remade as the Edit menu opens, most recent first, emacs' `yank-pop` as a
  menu. (Crysterm's clipboard exposes its in-process mirror as
  `internal_text`.)
- View → Dialog Style: every question md asks — Open, Save As, Find,
  Replace, Go to Line, the unsaved-changes question — is asked either in
  place of the status bar (Line Prompts, now the default for all of them;
  the unsaved-changes question becomes `Save changes to NAME? (y)es, (n)o,
  (c)ancel:` answered by one key) or in a modal dialog in the middle of
  the window (Modal Dialogs: Crysterm's `InputDialog` and `MessageBox`).
  The Replace question stays at the prompt in both styles. Kept in the
  settings as `dialog_style`.
- Options → Clear Caches… empties, after asking, what md keeps for itself
  between runs: the recent files and positions (`History#clear`, File →
  Open Recent goes empty), the auto-save recovery files (the current
  document's is written again at the next auto-save) and md's cache
  directory, `$XDG_CACHE_HOME/md` (the log file, emptied), with a notice
  of what went. The settings stay.
- View → Rulers: a column ruler along the top row of the editor and the
  viewer and a row ruler down their left, counted in the text's columns —
  a capped, centered column's tape starts where the text does, and both
  slide with the text when it scrolls — the row ruler outside the editor's
  line-number gutter. Kept across runs. (Crysterm's `AbstractScrollArea`
  learnt `rulers`, reserved as viewport margins and styled by `::ruler`.)
- View → Guides: a thin vertical line in the column just before the text
  and the one just after it, drawn in blank cells only, which with a Text
  Width set in a wider pane marks the capped column's edges. With the
  rulers shown, more guides are pulled off the column ruler with the mouse,
  moved by their ruler end, and dropped on another guide or back on the
  ruler to be removed; the two edge guides always stay. Kept across runs.
  (Crysterm's `AbstractScrollArea` learnt `guides_enabled`, `guides` and
  the `::guide` color, with the drag.)
- `Shift` + a movement key — the arrows, `Home`/`End`, `PageUp`/`PageDown`
  — selects from the cursor in the viewer as well as in the editor, for
  `Ctrl-C` to copy; a spec now holds both panes to it.
- View → Hard Wrap, off by default and kept with the settings: Kate's static
  word wrap. As a line is typed past the wrap column — the Text Width, or
  80 without one — it is broken at the last space before the column and the
  rest carried to a new line, which keeps its place in the Markdown: a list
  item's content indentation, a blockquote's `> `; a code block, a heading
  and a table row are never broken. The keystroke and its wrap are one undo
  step. (The wrapping is Crysterm's `hard_wrap_column`, with md supplying
  the Markdown continuation.) Format → Rewrap Paragraph (`Alt-Q`) refills
  the paragraph at the cursor, or the selection's paragraphs, to the same
  column, with the same Markdown rules.

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
