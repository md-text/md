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
  the viewer; any combination of panes can be shown (`F1`/`F2`/`F3`), the
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
- View → Highlight Line: tints the cursor's row in each pane; with Sync
  Cursor on, the two tinted rows show the same place in the document.
- Search, as in a pager: `/` and `?` (`Ctrl-F` in the editor) ask for a
  pattern — a regular expression when it is one, literal text otherwise,
  case-insensitive unless it has an uppercase letter — and `n`/`N`
  (`Ctrl-G`/`Alt-G`) repeat it either way, wrapping around with a notice.
  Matches are underlined in both panes and the current one is selected;
  Edit → Clear Search Highlights takes the underlines off until the next
  search, `n` included. `:` (`Ctrl-L`) goes to a
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
  File → Previous File (`Alt-Left`; `Backspace` in the viewer and the table
  of contents) retraces the files left — through a link or an open — to the
  file and the position left; File → Next File (`Alt-Right`) undoes a
  Previous File. A jump within the document is not a step.
- Settings kept across runs: View → Sync Cursor and Highlight Line,
  Options → Ask Before Discarding Changes and the mouse mode are restored at
  start and written at exit to `$XDG_CONFIG_HOME/md/settings.json`
  (`~/.config/md/settings.json`), a store in the manner of Qt's `QSettings`
  that later settings (pane sizes, a theme) join as new keys.
- View → Theme (`F6` cycles): the themes built into Crysterm — terminal,
  dark and light, as `--colors-theme` names them — switched at runtime, the
  whole window restyled at once. The choice is kept in the settings;
  `--colors-theme` wins for its run without being kept, and a
  `--colors-stylesheet` of your own stays over whichever theme is on.
- View → Theme offers the five Qt themes embedded in Crysterm — Breeze
  Dark and Light, QDarkStyle Dark and Light and Qt Modern Dark — after
  Terminal, Dark and Light: a Qt stylesheet laid over Crysterm's rules, in
  a palette drawn from its window colors, so the whole window takes the
  look. `F6` cycles through all eight, `--colors-theme breeze-dark` names
  one for a run, and the choice is kept in the settings like the others.
- View → Media Backend: how Crysterm draws images, from the backends
  `--media-backend` names — Auto, the default, or one of the cell
  grid, the terminal's own graphics (Sixel, ReGIS, Kitty, iTerm2,
  Tektronix) and the external overlays (w3mimgdisplay, Überzug), those the
  terminal cannot drive disabled. A pick takes effect at once: Crysterm
  rebuilds the images it drew under the old backend (its CSS
  `background-image` layers, in every window) and the status bar says
  which is on. Change for 5s, a check entry above Auto, makes a pick
  a trial: five seconds of the backend, then back to the one before, the
  checks following; another pick restarts the time, picking the original
  ends the trial, and unchecking during one keeps the tried backend. The
  backend is kept with the other settings, as Crysterm's `media.backend`.
- View → Color Depth (Crysterm's `colors.depth`: Auto, Monochrome, 8,
  16, 256 Colors, True Color; the whole window is redrawn at the new depth;
  at Monochrome a light theme reads black on white, Crysterm drawing a cell
  whose polarity is the opposite of the terminal's in reverse video),
  View → Terminal Links (`render.hyperlinks`: whether the viewer's links are
  the terminal's own hyperlinks — Auto, with the detection's Yes or No
  beside it, Always,
  and Never, which turns the viewer's links off altogether: plain text,
  followed by neither a click nor `Enter`, skipped by `Tab`) and Options → Reduced
  Motion (`render.reduced_motion`): three more of Crysterm's options in the
  menus, kept with the other settings. Terminal Links → Double-click to
  Open (`link_double_click`) makes a double click follow a link where a
  single one does by default. (Crysterm's `TextEdit` learnt
  `links_enabled`, its `TextBrowser` `link_clicks`.)
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
  bare `+`: the end), ahead of the remembered position — on a stream once
  the line has arrived, or at the stream's end for a line never reached
  or counted from the end, as `less +N` on a pipe waits; `--view` and
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
  panes — or, with To Last Guide, at the rightmost guide pulled onto the
  editor while editing, the viewer otherwise — and View → Center Text puts the capped column in the middle of the
  pane. All three are kept across runs. (Crysterm: `line_wrap_column` and
  `line_wrap_column_alignment` on `AbstractScrollArea`, Qt's
  `lineWrapColumnOrWidth` and `QScrollArea::alignment`; the scroll bars
  stay at the frame outside the viewport margins, and `TextEdit` paints
  from the margins.)
- Edit → Copy (`Ctrl-C`) copies the selection or, with nothing selected, the
  current block — the caret's line in the editor; in the viewer and the table
  of contents the paragraph, heading, list item, whole fenced code block or
  whole table the viewer's caret is in — as plain text, with a notice of how
  much was copied; Edit → Copy as Markdown copies the block's source lines,
  fences included. Options → Clipboard picks where a copy goes, kept across
  runs: the terminal's OSC 52 escape (the default), a system command found on
  the PATH (`pbcopy`, `wl-copy`, `xclip`, `xsel` or tmux's buffer, named in
  the entry) for where the escape does not get through, or md alone. The mode
  is Crysterm's new `Application::Clipboard#mode`, so the editor's own
  `Ctrl-C`, `Ctrl-X` and `Ctrl-V` follow it, a paste in Command mode reading
  the paired command; and a selection-less `Ctrl-C` now passes from a text
  pane to the application.
- Resizable panes: the panes sit in a splitter (Crysterm's, after Qt's
  `QSplitter`) with a divider between each two shown, dragged with the mouse
  or moved with `Left`/`Right` after `Alt+R` focuses the divider next to the
  pane (`Enter`/`Escape` return). View → Resizable Panes, a check entry kept
  in the settings as `resizable_panes`, locks the panes as they are when
  unchecked: the dividers refuse the mouse and the keys, and `Alt+R` says
  so. A hidden pane takes no width and shows no divider, and gets its width
  back when shown. The sizes are kept in the settings as `pane_sizes` —
  columns per pane, hidden ones included — and restored at start; the editor
  and the viewer keep their proportion in a terminal of another width, the
  table of contents its columns. (Crysterm's splitter learnt to fold hidden
  panes away, to resize its panes in proportion and with stretch factors, to
  save and restore its state, to keep its dividers off the Tab chain, and to
  lock them, `Splitter#resizable`.)
- The table of contents follows the reading position: the entry of the
  heading the caret is under — the editor's caret while editing, the
  viewer's otherwise — is selected as you move, or its nearest shown parent
  while the branch is collapsed; a heading jump no longer selects its entry
  specially. (Crysterm's `TocView` learnt `track`.)
- The pane keys are `F1`, `F2` and `F3` (editor, viewer, table of contents),
  and `F4` hides the menu bar and the status bar together and brings them
  back (View → Menu and Status Bars, kept in the settings as `bars`): the
  panes take the whole terminal, the entries' keys (`Ctrl-O`, `Ctrl-S`…)
  keep working, and a question asked in place of the status bar shows the
  bar while it is open. (A hidden Crysterm menu bar no longer answers its
  `F10` and `Alt` letters.)
- A file dropped on the window opens: the terminal pastes its path, and a
  paste that names one existing file, outside the editor, opens it through
  the unsaved-changes guard.
- Markdown-aware editing, and a Format menu (`Alt-M`) between Edit and
  View. `Enter` on a list item — bullets, numbers, tasks, indented or in a
  blockquote — continues the list with the same marker (the number raised,
  the task box emptied) and ends it on an empty item; `Tab` and `Shift-Tab`
  indent and outdent the caret's line or the selected lines (Format →
  Indent, Outdent, whose shortcuts they are in the editor): a list item by
  the item above's content offset, any other line by four spaces. `Tab` no
  longer leaves the editor; `F1`–`F3` and the mouse do. Format → Bold, Italic and Code
  (`Ctrl-B`, `Alt-I`, `Alt-C`) wrap the selection or the word at the caret
  in `**`, `*` or backticks, the markers hugging the text (spaces at the
  selection's ends stay outside), or unwrap it, a selection taking in spaces beside the markers unwrapping too; Task, a check entry showing
  whether the caret's item is one, adds a `[ ]` box to a list item and
  takes it off, Toggle Task (`Alt-X`) ticks and unticks it (an
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
  Open Recent goes empty; the question counts the recent files, the
  positions remembered in them and the recovery files, `(0)` included), the auto-save recovery files (the current
  document's is written again at the next auto-save) and md's cache
  directory, `$XDG_CACHE_HOME/md` (the log file, emptied), with a notice
  of what went. The settings stay.
- View → Rulers → Horizontal and Vertical: a column ruler along the top row
  of the editor and the viewer and a row ruler down their left, each shown
  on its own, counted in the text's columns — a `│` on every tenth column
  with its number right after it, a capped, centered column's tape starting
  where the text does, and both sliding with the text when it scrolls — the
  row ruler between the editor's line-number gutter and the text, a tape of
  ticks while the gutter numbers the lines. Kept across runs as
  `horizontal_ruler` and `vertical_ruler`. (Crysterm's `AbstractScrollArea`
  learnt `column_ruler` and `row_ruler`, reserved as viewport margins and
  styled by `::ruler`.)
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
  item's content indentation, a blockquote's `> `; a code block (fenced or
  indented), a heading, a table row and a rule are never broken. The
  keystroke and its wrap are one undo step. (The wrapping is Crysterm's
  `hard_wrap_column`, with md supplying the Markdown continuation.)
  Format → Rewrap → Paragraph (`Alt-Q`) refills the paragraph at the cursor,
  or the selection's paragraphs, and Rewrap → Document every paragraph of
  the file, to the same column, with the same Markdown rules.
- Every View and Options choice is a configuration option as well, in
  Crysterm's registry beside the toolkit's own: `md.sync_cursor`,
  `md.text_width`, `md.mouse_mode` and the rest, each settable in the config
  file, as an `MD_*` environment variable (`MD_TEXT_WIDTH=80`) or on the
  command line (`--md-text-width 80`, `--no-md-soft-wrap`), the later
  winning, with a pick in a menu recorded in the option at once. `md --help
  --verbose` and the man page's SETTINGS section list them with their
  defaults; the shell completions know the flags.
- Options → Load Config…, Save Config and Save Config As…: a config file
  applied at once, with the menu entries and the panes following and its
  values counting as picks; the config file written now; the settings written
  to a file of your choosing.
- Every menu entry has a one-sentence description, shown while the entry is
  highlighted: in the status bar, in place of the document's name, by default
  (a desktop application's status tip); or, by Options → Tooltips, in a
  popup beside the entry after a moment, inert and gone as the highlight
  leaves; or nowhere. `F1` on a highlighted entry shows its description
  beside it either way. An entry bound to a setting describes itself with
  the setting's own description, so `--help --verbose` and the menu say the
  same. Kept across runs (`md.tooltips`).
- View → Images: the viewer draws the document's images — an `![alt](src)`
  on a line of its own, fitted to the text width and at most half the pane
  tall, drawn as View → Media Backend says — above the row holding the
  picture glyph and the alt text; a relative source counts from the
  document's directory, a remote one is fetched in the background. Off
  (`md.images`, `MD_IMAGES`, `--no-md-images`), that row is all there is.
- Window menu (`Alt-N`): New (`Ctrl-N`) opens another md window on the
  document as it stands — unsaved edits included and flagged as such, a stream
  as far as it has been read — in a new terminal window asked of the emulator md runs in
  (Terminal.app and iTerm2 on macOS; kitty, Alacritty, WezTerm, foot, xterm,
  Konsole and GNOME Terminal; a tmux or screen window inside one); Close
  Current (`Ctrl-W`) closes the one you are in after its unsaved-changes
  question, the last one quitting; the open windows are listed by title to
  switch between. Quit closes every window, each asking about its own
  changes. Where no window can be opened the entry is disabled and the key
  says why.
- Options → Detachable Menus (`menu.tear_off`, `--menu-tear-off`): every menu
  carries a grab strip (`⠿⠿⠿`) in the middle of its top border and another in
  the middle of its bottom border, after GNOME 2's tear-off menus; dragging
  either — or clicking it — tears off a copy of the menu that stays on screen
  where it is dropped, with the same entries kept in step with the menu's own,
  movable by either strip, closed by the `✕` at the right end of its top border, and left alone by outside clicks and `Escape`. Submenus tear off too.
  The ordinary menus are unchanged; the choice is kept with the other
  settings. (Crysterm's tear-off menus, which md builds against.)
- A menu entry's description in the status bar takes as much of the bar as it
  needs, covering the fields on the right while it shows when it does not fit
  beside them (Crysterm's `MainWindow#status_tips_full_width`); View → Media
  Backend's Auto names the backend it detects in parentheses.
- File → Close: closes the document after the unsaved-changes question, takes
  it off the trail Previous File and Next File retrace — every place in it, so
  neither the close nor a later step opens it again — and opens the file Next
  File would have gone to, or leaves a blank new document.
- Help menu (`Alt-P`), last on the bar: Manual opens md's manual — the
  README's opening and its Usage chapter, built into the binary — as the
  document; About names md's version, author and website in the status bar.
- Commands: everything md does has a name (`save`, `soft-wrap`,
  `theme-breeze-dark`, `toggle-editor`…), and the command line runs it by
  that name, as vi's `:` runs an ex command — `:` in the viewer, which still
  goes to a line given a number, or `Alt-K` (Edit → Run md Command…) anywhere,
  `Tab` completing the name. Every menu entry is a command, and the keys no
  entry has (`F1`–`F6`, `Ctrl-Z`, `Alt-R`) are now named actions too. The
  names are Crysterm's action names (`Action#name`, Qt's `objectName`),
  found with the new `find_action`; a prompt now completes with a completer
  of its own (`LinePrompt#prompt(completer:)`), and a shortcut stands down
  under a modal dialog in Crysterm itself (`Window#active_modal_widget`),
  where md held its keys back on its own.
- Every automatic choice in the menus is called Auto and names in
  parentheses what it detects on this terminal, brought up to date when View
  opens: Media Backend's (Auto (Sixel)), Terminal Links' (Auto (Yes)) and now
  Color Depth's (Auto (256 Colors)), through Crysterm's new
  `Window#detected_color_count`; Terminal Links' Always now answers to
  `W`, leaving `A` to Auto.
- Edit → Vi Mode (`vi-mode`, `md.vi_mode`): the editor is edited by an
  embedded Neovim (Crysterm's `Neovim::Handler`), its keys Neovim's but for
  the function keys and the `Alt` chords, which stay md's. The status bar
  shows the mode left of the position and the command line while one is
  typed, Neovim's messages come as notices, Visual mode is the editor's
  selection, `u`/`Ctrl-R` are Neovim's undo and redo, and `:w` saves (`:w
  FILE` saves as), `:q` closes the window as Window → Close Current does,
  `:q!` without asking, `:qa` quits, `:wq`, `:x` and `ZZ` save and close.
  Neovim starts with `--clean` unless Options → Vi Mode Uses Your Neovim
  Config (`vi-config`, `md.vi_config`) is on. Without `nvim` the entry is
  disabled and says why, and a Neovim that ends turns Vi Mode off. The
  viewer's `:` stays md's command line.

### Changed

- The settings live in `$XDG_CONFIG_HOME/md/config.yml`
  (`~/.config/md/config.yml`), YAML in the layout `--crysterm-dump-config`
  prints, one mapping per option group, instead of `settings.json`, which is
  no longer read. The file can hold Crysterm's options too, for md alone;
  Crysterm's own `~/.config/crysterm/config.yml` is read first, below it, and
  its values are never copied into md's file. It is written when md quits if
  anything changed, with what was picked during the run and what it already
  had; a value given on the command line or in the environment is for that
  run and leaves the file's own entry standing, and entries md does not know
  are kept. A broken file stops md with a message naming the entry, as does a
  value that fits no option in a file, a variable or a flag
  (`--colors-theme=bogus`), with exit status 1.

### Fixed

- Quitting with the viewer focused and the outline shown no longer crashes
  and wedges the process: tearing the panes down rewound focus from the
  viewer to the outline, whose focus-in refreshed the status bar, which asked
  the already-detached viewer for its geometry. Crysterm now releases the
  focus before tearing a window down, so no pane's focus-in runs against a
  half-gone tree, and it survives such teardown errors, restoring the
  terminal and reporting them.
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
- The editor no longer looks dimmed while the viewer or the table of contents
  has the focus: Crysterm's theme lightened a focused editor's background the
  way it lightens a focused one-line field, so the editor changed shade with
  the focus next to panes that keep theirs. The multi-line editor now keeps
  one background in either state, as Qt keeps a `QPlainTextEdit`'s base
  color. (Fixed in Crysterm, which md builds against.)
- Menus and submenus are readable under the Breeze Light theme (and the
  other Qt themes): their rows painted the terminal's default background,
  dark on a dark terminal, under the theme's dark text, since Qt's
  `QMenu::item { background: transparent }` was taken as "the terminal
  default" instead of "the menu's background shows through". Crysterm now
  resolves a transparent background to the parent's, as CSS and Qt do; only a
  widget with nothing behind it keeps the terminal default. (Fixed in
  Crysterm, which md builds against.)
- `Ctrl-Home` and `Ctrl-End` go to the start and the end of the document, in
  the editor and in the viewer, the other pane following with View → Sync
  Cursor; the keys arrived but Crysterm's text edits had no binding for them,
  now Qt's `MoveToStartOfDocument` and `MoveToEndOfDocument`. (Fixed in
  Crysterm, which md builds against.)
- The numeric keypad's `Enter` does what `Enter` does — a new line or a
  continued list in the editor, reading on or following a link in the viewer
  — and its digits and operators type, where they did nothing (on macOS
  terminals among others): the terminal sends them in application keypad
  mode (`\eOM`, `\eOp`…), which tput dropped, and under the kitty keyboard
  protocol as keypad codes that went unused. (Fixed in tput, which md builds
  against.)

[Unreleased]: https://github.com/crystallabs/md/commits/main
- Window → New no longer freezes md on macOS: once the new terminal window
  opened, the first window stopped answering the mouse and the keyboard, and
  the input it had not read was printed to the terminal when md quit. The new
  window's terminal was opened blocking (as Crystal opens every file on
  macOS), so its input reader, waiting for a key there, held up the whole
  process; it is now opened non-blocking, as the first window's terminal is.
  (Fixed in Crysterm, which md builds against.)
- Tables wider than the viewer read as tables: their columns narrow to fit
  and the cells wrap onto more lines within their row, as Qt lays a table
  out to the document's width, where each row ran on past the edge and the
  grid broke apart (the manual's tables, at a terminal's usual width). A
  table is laid out again as the window is resized. (Fixed in Crysterm,
  which md builds against.)
- Window → Close Current on the last window (and Quit, which closes each
  window) leaves the terminal with its cursor shown, as it was before md
  started: the window handed the terminal back first, and the editor, giving
  up the focus as the window was torn down afterwards, hid the cursor again.
  A terminal whose cursor is not white also keeps its own color, where md
  left it white. (Fixed in Crysterm and Tput, which md builds against.)
- A remote image the viewer could not fetch, because of a network blip, comes
  in with the next re-render (an edit, a reload) once the network is back,
  where it stayed missing until md was restarted; a broken link is still not
  fetched again more than about every 30 seconds. (Fixed in Crysterm, which
  md builds against.)
