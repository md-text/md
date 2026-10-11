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
md --help             # list the options (`--help --verbose` adds the settings and Crysterm's)
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

The shown panes share the width with a divider between each two: the editor
and the viewer equally, the table of contents as a 30-column list. Drag a
divider with the mouse to resize the panes beside it, or, without a mouse,
press `Alt-R`: the divider next to the pane you are in takes the keys,
`Left` and `Right` move it a column at a time, and `Enter`, `Escape` or
`Tab` go back to the panes. Uncheck View → Resizable Panes to lock the panes
as they are — the dividers then refuse the mouse and the keys, and `Alt-R`
says so — and check it again to resize them. A hidden pane gives its width
to the others and gets it back when shown. The sizes, and whether the panes
are resizable, are kept across runs with the other settings; a wider or
narrower terminal next time keeps the proportions of the editor and the
viewer, and the table of contents its columns.

| Key                | Action                                                                    |
| ------------------ | ------------------------------------------------------------------------- |
| `F1`, `F2`, `F3`   | Show and focus the editor, viewer or table of contents; hide it if it is already focused (the last pane stays) |
| `F4`               | Hide the menu bar and the status bar, or show them again (View → Menu and Status Bars); the entries' keys keep working meanwhile |
| `Tab`, `Shift-Tab` | Outside the editor, move focus to the next or previous shown pane (in the viewer, `Tab` first cycles links); in the editor, indent and outdent the caret's line or the selected lines (Format → Indent, Outdent) |
| `Enter`            | In the table of contents, jump the viewer to the selected heading; in the viewer, follow the focused link |
| `Space`, `Enter`   | In the viewer, read on by a page or by a line (arrows, `PageUp`/`PageDown`, `Home`/`End` as usual) |
| `Insert`           | Toggle the editor between inserting and overwriting (the `INS`/`OVR` field) |
| `F5`               | Cycle the mouse mode (the `🖱=` field)                                    |
| `F6`               | Cycle the theme: terminal, dark, light and the five Qt themes (View → Theme) |
| `Ctrl-Z`           | Outside the editor, suspend md to the shell (`fg` resumes); in the editor, undo |
| `Alt-F`, `Alt-E`, `Alt-M`, `Alt-V`, `Alt-O` | Open the File, Edit, Format, View and Options menus (`F10` too) |
| `Alt-W`            | Soft Wrap in the editor on and off (View → Soft Wrap)                     |
| `Shift` + `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown` | Select from the cursor, in the editor and in the viewer |
| `Ctrl-O`           | Open a file; asks for the name (File → Open…)                             |
| `Ctrl-R`           | Reload the file from disk (File → Reload)                                 |
| `Ctrl-S`           | Save; without a file name yet, asks for one (File → Save As… always asks) |
| `Ctrl-C`           | Copy the selection, or with nothing selected the current block (the line, in the editor) as plain text (Edit → Copy; Edit → Copy as Markdown copies the block's source) |
| `Ctrl-V`           | Paste the clipboard into the editor at the caret; from the viewer or the table of contents, at the source of the viewer's caret (Edit → Paste; Edit → Paste Special names the source) |
| `Ctrl-F`, `/`, `?` | Search; asks for the pattern (`/` and `?` outside the editor, `?` backward; Edit → Find…) |
| `Ctrl-G`, `Alt-G`, `n`, `N` | Next and previous match (`n` and `N` outside the editor; Edit → Find Next, Find Previous) |
| `Alt-H`            | Replace; asks for the pattern and the replacement, then about each match (Edit → Replace…) |
| `Ctrl-L`, `:`      | Go to a source line; asks for the number (`:` outside the editor; Edit → Go to Line…) |
| `Alt-Down`, `Alt-Up`, `]`, `[` | Jump to the next and previous heading (`]` and `[` outside the editor; Edit → Next Heading, Previous Heading) |
| `Alt-R`            | Resize the panes from the keyboard (when View → Resizable Panes is on): `Left`/`Right` move the divider next to the pane, `Enter`/`Escape` return |
| `Backspace`        | Outside the editor, go back to the file you were in before the last link or open, where you left it (File → Previous File) |
| `Alt-Left`, `Alt-Right` | Previous File and Next File (File → Previous File, Next File); in the editor and the viewer these move by word instead |
| `Enter`            | In the editor, on a list item: continue the list (an empty item ends it) |
| `Ctrl-B`, `Alt-I`, `Alt-C` | Bold, italic and code around the selection or the word at the caret, or off again (Format → Bold, Italic, Code) |
| `Alt-X`            | Tick or untick a list item's task box, or give it a ticked one (Format → Toggle Task Checkbox; Format → As a Task adds and removes the box) |
| `Ctrl-Up`, `Ctrl-Down` | Promote or demote the heading on the caret's line (Format → Promote Heading, Demote Heading) |
| `Alt-Q`            | Refill the paragraph at the caret, or the selected paragraphs, to the wrap column (Format → Rewrap → Paragraph; Rewrap → Document refills them all) |
| `Ctrl-Q`           | Quit (`q` too, anywhere but in the editor; File → Quit); asks first when changes are unsaved |

The File, Edit and Format menus show these keys next to their entries, spelled as
Qt does (`Ctrl+O`), and the right end of the menu bar names the keys that
open the menus. The keys work from any pane, after the pane had its turn —
the editor keeps the keys it uses — and wait while a prompt is open.

The editor has the usual editing keys: arrows and `Home`/`End`, `Shift` +
a movement key — the arrows, `Home`/`End`, `PageUp`/`PageDown` — to select
from the cursor, `Ctrl-Z`/`Alt-Z` to undo and redo, `Ctrl-K`/`Ctrl-Y` to kill
and yank, and the mouse to position the cursor, select and scroll. The
viewer has a cursor too, and the same `Shift` + movement keys select there,
for `Ctrl-C` to copy. (Some terminals keep `Shift-PageUp`/`PageDown` and
`Shift-Home`/`End` for their own scrollback and never send them on; the
arrows get through everywhere.)

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
as and quits, and lists the recently opened files; the Edit menu copies,
searches, replaces, goes to a line and jumps between headings; the Format menu marks
up the source (see Editing Markdown below); the View menu shows and hides
the panes.

### Copying

Edit → Copy (`Ctrl-C`) copies the selection in the focused pane. With
nothing selected, in the editor it copies the caret's line, and in the
viewer or the table of contents the block the viewer's caret is in — a
paragraph, a heading, a list item, or a fenced code block whole — as plain
text, the way it reads. Edit → Copy as Markdown copies the block's source
instead: the lines of the Markdown it was rendered from, fences included. A
notice says how much was copied. In a pane with a selection, `Ctrl-C` is
the pane's own copy, as `Ctrl-X` and `Ctrl-V` are its cut and paste.

Where a copy goes is the clipboard mode, under Options → Clipboard:

| Mode                  | The copy goes to…                                                       |
| --------------------- | ----------------------------------------------------------------------- |
| `Terminal (OSC 52)`   | the terminal, through the OSC 52 clipboard escape, which most terminals forward to the system clipboard (the default) |
| `Command (pbcopy)`    | a system command found on the PATH — `pbcopy` on macOS, `wl-copy` on Wayland, `xclip` or `xsel` on X11, or tmux's buffer inside tmux — for where the escape does not get through: tmux or screen without passthrough, SSH, a terminal that ignores it. The entry names the command found, and cannot be picked when there is none |
| `Internal (Within md)` | nowhere outside md: pasting within md still works, and nothing is written that a terminal might garble |

The mode applies to the editor's `Ctrl-C`, `Ctrl-X` and `Ctrl-V` too: in
Command mode a paste reads the paired command (`pbpaste`, `wl-paste`,
`xclip -o`, `xsel --output`, `tmux save-buffer`); otherwise it pastes what
md last copied. The terminal's own paste works in every mode (md takes
bracketed paste), and so do the terminal's own selection and copy with the
mouse while the mouse mode leaves the mouse to the terminal (above). The
mode is kept across runs with the other settings.

### Pasting

Edit → Paste (`Ctrl-V`) pastes the clipboard, as the mode reads it, into
the editor at the caret, replacing the selection, as one undo step. In the
editor `Ctrl-V` is the editor's own paste and does the same; from the
viewer or the table of contents the key reaches the entry, which shows the
editor if it is hidden, puts its caret on the source of the viewer's and
pastes there — the Format menu's way of acting on what you are reading.

Edit → Paste Special names the source instead of leaving it to the mode,
the way editors' "Paste from…" menus do:

| Entry                    | Pastes…                                                                 |
| ------------------------ | ----------------------------------------------------------------------- |
| From Terminal Clipboard  | what the terminal holds, asked for through the OSC 52 read; the paste happens when the terminal answers, and a notice gives up after two seconds, since many terminals (and tmux or screen without passthrough) never answer a read |
| From Command             | the paste command's output (`pbpaste`, `wl-paste`, …); the entry names the command found and cannot be picked when there is none |
| From Internal Buffer     | what md itself last copied, or last received from the terminal, without asking anything outside |
| From Kill Ring           | an entry of the editor's kill ring — what `Ctrl-K`, `Ctrl-U` and `Alt-D` killed — from a submenu remade each time the Edit menu opens, most recent first, numbered `1`–`9` and `0` for the tenth, each shown as its first forty columns with line breaks as `⏎`; `1` is what `Ctrl-Y` yanks, so an older kill is a pick away, emacs' `yank-pop` without the cycling |

View → Theme picks the colors the whole window is drawn in, from the
themes built into Crysterm — the same ones its `--colors-theme` option
names: `terminal` derives a palette from your terminal's own colors, so md
blends in, `dark` and `light` are fixed palettes, and `breeze-dark`,
`breeze-light`, `qdarkstyle-dark`, `qdarkstyle-light` and `qtmodern-dark`
are the Qt themes of those names (Breeze, QDarkStyle and qtmodern), their
Qt stylesheets embedded in Crysterm and laid over its own rules, so the
whole window takes the Qt theme's look. The window switches at once, and
`F6` cycles through all of them from the keyboard. The choice is kept
with the other settings; `--colors-theme` given on the command line (or in
Crysterm's config file or environment) wins for that run and is not kept,
so the next plain run is back to the stored theme. A stylesheet of your own
(`--colors-stylesheet FILE`, CSS or Qt's QSS) layers over whichever theme
is on, so your rules stay in force when the theme changes under them.

View → Media Backend picks how Crysterm draws images, from the backends its
`--media-backend` option names. Auto-detect, the default, leaves the choice
to Crysterm, which takes the best one your terminal drives — Kitty graphics
on Kitty, Sixel on an xterm, sub-cell glyphs or one cell per pixel anywhere
else; the other entries name one and hold it: the cell grid (ANSI in true
color, 256, 16 or 8 colors; Unicode half blocks, quadrants, sextants,
octants, braille dots; ASCII contours), the terminal's own graphics (Sixel,
ReGIS, Kitty, iTerm2, Tektronix 4014) and the external overlays
(w3mimgdisplay, Überzug). The entries your terminal cannot drive are
disabled — ReGIS and Tektronix always, since nothing detects them, the
overlays without their helper program. A pick takes effect at once: Crysterm
drops the images it drew under the old backend and draws them again with the
new one, and the status bar says which is on. Check Change for 5s, above
Auto-detect, to try a backend instead of keeping it: the pick switches for
five seconds and then goes back to the backend in force before, the check
marks following; another pick during the five seconds starts them over and
still returns to the original, picking the original ends the trial, and
unchecking Change for 5s during one keeps the tried backend and cancels the
return. md's viewer draws no inline images yet (an image in the Markdown
shows as a placeholder), so for now the backend shows on background images a
stylesheet sets (`background-image` in a `--colors-stylesheet`) and on
whatever media Crysterm adds later. The backend is kept with the other
settings; Change for 5s is not, like Overwrite Mode.

Three more of Crysterm's options sit in the menus, for a reader who would
otherwise set them on the command line. View → Color Depth is how many
colors the window is drawn with — Auto-detect, the default, takes the
terminal's word, and Monochrome, 8, 16, 256 Colors or True Color force a
depth, for a terminal that reports fewer colors than it shows, or to see a
theme as a plainer terminal would; the whole window is redrawn at the new
depth at once (`--colors-depth`). View → Terminal Links is whether the
links in the viewer are also the terminal's own hyperlinks, to click or
hover where the terminal does that: Auto-detect turns them on where the
terminal is known to support them, On trusts the terminal over the
detection, Off is for a terminal that shows the escape sequence instead
(`--render-hyperlinks`). Options → Reduced Motion skips Crysterm's
animations — a pressed button, a fade — and shows their end state at once
(`--render-reduced-motion`). All three are kept with the other settings.

### Editing Markdown

The editor knows the syntax it holds. `Enter` at the end of a list item —
`- `, `* `, `+ `, `1. ` or `1) `, a task `- [ ] `, indented or inside a
blockquote — starts the next item with the same marker (the number one
higher, the task box empty), taking along any text after the caret; on an
empty item, `Enter` ends the list instead — so two `Enter`s in a row end a
list, a task list or a numbered one alike, and a third is a plain newline;
on any other line `Enter` is a newline. `Tab` and `Shift-Tab` indent and outdent the caret's line, or
every line of the selection (Format → Indent and Outdent): a list item, or
a selection with one in it, moves by the list's rules — an item nests under
the item above by that item's content offset, two columns for `- `, three
for `1. `, as CommonMark wants a child list, and outdents back to the
indentation of the nearest shallower item — and any other line by
Markdown's unit of four spaces, `Shift-Tab` taking up to four spaces, or a
tab, off its front. `Tab` therefore never leaves the editor, as it does not
leave a text field in Qt; `F1`, `F2`, `F3` and the mouse do, and there is
no other focus key a terminal could tell from `Tab` (`Ctrl-Tab` arrives as
`Tab`). Outside the editor `Tab` cycles the panes as before.

Format → Bold, Italic and Code (`Ctrl-B`, `Alt-I`, `Alt-C`) put `**`, `*`
or backticks around the selection, or the word at the caret, or insert the
pair with the caret between when there is neither; on text that already has
them (`_` and `__` count too) they take them off, and the text stays
selected, so a second press undoes the first. Format → As a Task gives a
list item a `[ ]` box and takes it off again; Format → Toggle Task Checkbox (`Alt-X`)
ticks the box `[x]` and unticks it, and gives an item without a box a
ticked one; Format → Promote Heading and Demote Heading (`Ctrl-Up`, `Ctrl-Down`)
move the caret's line one heading level up or down, a paragraph being the
level above `#`. Each change is one undo step.

The keys are not all Qt's: `Ctrl-B` is, but a terminal sends the same byte
for `Ctrl-I` and `Tab`, and cannot tell `Ctrl-Shift-X` from `Ctrl-X`, so
Italic, Code and Toggle Task Checkbox use `Alt` chords the editor does not
(`Alt-B` and `Alt-F` are its readline word moves). Indent and Outdent show
`Tab` and `Shift+Tab`, keys that are theirs in the editor alone. The Format
menu works from any pane: chosen while reading, it edits the source of the
viewer's caret, showing the editor if it is hidden.

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
and the current one is selected; Edit → Clear Search Highlights takes the underlines
off, and `n` still knows the pattern.

Replacing (`Alt-H`, Edit → Replace…) works like vi's `:s///c`, at the same
prompt: it asks for the pattern — the last search's is filled in — and
then for the replacement, and steps through the matches from the cursor,
selecting each in the editor and asking `Replace? (y)es (n)o (a)ll (q)uit`.
A single key answers: `y` replaces the match and moves on, `n` leaves it,
`a` replaces it and every match after it (around the end of the document
and back to where you started), `q` and `Esc` stop. The pattern follows the
search's rules, and the replacement may refer to the pattern's groups,
`\1` to `\9`, and to the whole match, `\0`, as Crystal's `String#sub`
does (`\\` is a backslash). Replacing edits the Markdown source, so from
the viewer it shows and focuses the editor first; every replacement can be
undone with `Ctrl-Z`, the `a` as a single step. A notice reports how many
matches were replaced. (Qt's key, `Ctrl-H`, is Backspace in the terminal,
hence `Alt-H`.)

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
place. View → Watch File (or `--watch` on the command line) does that for
you: the file is polled once a second and reloaded when another program
changed it, so md beside an editor shows each save as it happens. While the
editor holds unsaved changes the reload is skipped and a notice says the
file changed on disk. The status bar shows `(watching)` after the name.

### Dropping a file

A file dragged from a file manager onto the window opens, as if by File →
Open…: a terminal has no drop of its own, so what arrives is the file's
path pasted as the shell would take it (spaces escaped, or quoted, or as a
`file:` URL, depending on the terminal), and md opens a paste that names
one existing file. In the editor a paste is text to insert, so drop on the
viewer or the table of contents; unsaved changes are asked about as with
any open.

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

Every file left is a step you can retrace: `Backspace` in the viewer or the
table of contents goes back to the file you came from, at the position you
left (File → Previous File, `Alt-Left`, works from the menu too), and File →
Next File (`Alt-Right`) undoes a Previous File. Opening a file from File →
Open… or Open Recent over the one shown is a step as well; a jump within the
document — a `#heading` link, the table of contents — is not, since the
entries lead to files. Going back to another file asks about unsaved changes
like any open. In the editor and the viewer `Alt-Left` and `Alt-Right` keep
moving the cursor by word, so the menu and `Backspace` are the way back from
there.

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
one, and the action goes ahead once the save is done. Options → Ask Before
Discarding Changes turns the question off.

The View menu also has *Sync Cursor*: with it on, moving the cursor in the
editor puts the viewer's cursor on the same place in the rendered document,
scrolled to the same row of its pane, and moving it in the viewer does the
same in the editor.
The pane you are in leads. The match is by source line, so inside formatted
text the other cursor lands near rather than exactly on the spot, and a line
that renders nothing (a blank line, a code fence) maps to the rendered block
just above it. *Highlight Line*, also in the View menu, tints the row the
cursor is on in each pane; together with *Sync Cursor* the two tinted rows
are the same place in the document, which makes the pairing easy to see.
*Line Numbers* puts a gutter with the source line numbers on the editor's
left, the way code editors do; the choice is kept across runs.

Four more View entries lay the text out. *Soft Wrap* (`Alt-W`) is the
editor's: on, a long line folds at the pane's edge; off, it runs past the
edge and the pane scrolls sideways. *Text Width* caps the width the text is
laid out in — 72, 80, 100 or 120 columns, or *Unlimited* — so a line does
not run the whole width of a wide terminal; it applies to both panes, which
keeps them reading side by side under Sync Cursor. *Center Text* puts the
capped column in the middle of a wider pane rather than at its left edge.

Two more measure it. *Rulers* puts a column ruler along the top row of each
pane (Horizontal) and a row ruler down its left (Vertical), each switched
on its own: a tape of `─` with a `┼` every fifth
column and a `│` on every tenth with its number right after it (`│20` marks
column 20), counted in the text's own columns — a
capped, centered column's tape starts where the text does, and both slide
with the text when it scrolls. In the editor the row ruler stands between
the line-number gutter and the text, and while the gutter numbers the source
lines it is a one-column tape of ticks (`┼` every fifth row, `╪` every
tenth); without the gutter it numbers the rows itself.
*Guides* draws a thin vertical line in the column just before the text and
the one just after it, in the blank cells only, so with a Text Width set in
a wider pane the capped column's edges are marked. With the rulers shown,
more guides are pulled off the column ruler with the mouse: press on the
ruler and drag down into the pane to make one where it is dropped, drag a
guide by its `┬` on the ruler to move it, and drop it on another guide, or
back on the ruler, to be rid of it. The two edge guides always stay. Both
choices are kept across runs.

*Hard Wrap*, off by default, is Kate's static word wrap: while you type, a
line that grows past the wrap column is broken at the last space before
the column and the rest carried to a new line, so the source itself stays
narrow — where Soft Wrap only folds the display. The column is the Text
Width when one is set, else 80. The carried line keeps its place in the
Markdown: in a list item it is indented to the item's text, in a blockquote
it gets the `> `, and a code block, a heading or a table row is never
broken. The keystroke and the wrap it caused undo as one step. Format →
Rewrap → Paragraph (`Alt-Q`, Emacs's fill) refills the paragraph at the
cursor, or every paragraph the selection touches, and Rewrap → Document
every paragraph in the file, to the same column — a list item keeping its
marker, a quote its markers, code blocks untouched — whether or not Hard
Wrap is on.

Save As asks for the name in place of the status bar, the way vi's command
line replaces its status line: the current name is filled in, `Tab` and
`Shift-Tab` complete file names, `Up` recalls earlier answers, `Enter` saves,
and `Escape` (or `Backspace` on an empty line) gives up.

### Dialogs

Every question md asks — Open, Save As, Find, Replace and its replacement,
Go to Line, and what to do with unsaved changes — is asked the way View →
Dialog Style says. *Line Prompts*, the default, asks in place of the status
bar as Save As does above; the unsaved-changes question becomes `Save
changes to NAME? (y)es, (n)o, (c)ancel:` and takes one key (`Enter` on an
empty line, like `Escape`, cancels). *Modal Dialogs* asks in a box in the
middle of the window, with a field and OK/Cancel, or a button per choice,
as desktop editors do. The Replace question at each match is asked at the
prompt in both styles, since a box at every match would be in the way of
the stepping. The choice is kept across runs.

### Auto-save and backups

Two nets catch what a crash, a kill or a slip would lose, both on by default
in the Options menu. *Keep a Backup File* keeps the file as it was before
the first save of the session, as `FILE~` beside it (emacs' convention), so
one save too many is undone by copying the backup back; later saves in the
same session leave it alone. *Auto-Save* writes your unsaved edits every 30
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

### Clearing the caches

Options → Clear Caches… forgets, after asking, everything md keeps for
itself between runs: the recent files and the positions remembered in them
(File → Open Recent goes empty), the auto-save recovery files — the
current document's too, which is written again at the next auto-save while
the document is modified — and the contents of `$XDG_CACHE_HOME/md`
(`~/.cache/md`), where Crysterm's log goes while md runs. A notice says
how many recent files and recovery files went. The settings are your
choices, not a cache, and stay.

### Settings

The choices made in the View and Options menus — Resizable Panes, Sync
Cursor, Highlight Line, Line Numbers, Soft Wrap, Hard Wrap, Text Width,
Center Text, Rulers, Guides, Dialog Style, Ask Before Discarding Changes,
Auto-Save, Keep a Backup File, the mouse mode, the clipboard mode and the
theme — and the pane sizes are kept across runs in
`$XDG_CONFIG_HOME/md/config.yml` (`~/.config/md/config.yml`), written when
md quits if anything changed. Watch File is not kept: like `--watch`, it is
for the run at hand.

Every one of those choices is a configuration option of Crysterm's registry,
beside the toolkit's own (the theme is Crysterm's `colors.theme`), so each
can be given four ways, the later winning: in the config file, as an
environment variable, on the command line, or in the menu while md runs.
`md --help --verbose` lists them all, with their defaults:

```sh
md --md-text-width 80 --md-vertical-ruler notes.md   # this run only
MD_MOUSE_MODE=off md notes.md                # likewise
cat ~/.config/md/config.yml
```

```yaml
md:
  text_width: 80
  vertical_ruler: true
  mouse_mode: Off
colors:
  theme: breeze-light
```

A choice given on the command line or in the environment is for that run:
it is not written to the file, and an entry the file already has for it stays
as it was (`--colors-theme dark` shows the document in the dark theme once,
and the next plain run is back to the stored theme). A pick in a menu is
recorded at once, whatever had set the option before. The file is YAML (JSON
reads too), as `--crysterm-dump-config` prints it, with one mapping per
option group — `md` for md's own choices, `colors`, `media` and the rest for
Crysterm's, which it can hold as well, so a theme or a media backend meant
for md alone goes here rather than in Crysterm's `~/.config/crysterm/config.yml`.
Entries md does not know are kept across a rewrite, so an older md does not
shed a newer one's settings; a broken file stops md with a message naming the
entry. One YAML caution: write a value that YAML reads as a boolean, such as
Terminal Links' `off`, in quotes (`hyperlinks: "off"`); md's own writes
quote every word.

The Options menu reaches the file directly: *Save Config* writes it now,
without waiting for the exit; *Save Config As…* asks for a file name, the
config file's filled in, and writes the settings there, for a copy or a
variant; *Load Config…* asks for a file name and applies that file at once —
the menu entries move, the panes follow, and its values count as picks, so
they replace whatever the environment or the command line set for the run
and are kept at exit. A file that cannot be read, or an entry that does not
fit, is a notice. The pane sizes are `md.pane_sizes`, the widths in columns of the
editor, the viewer and the table of contents, comma-separated, hidden ones
included (`0` for a pane never resized); the editor and the viewer are
fitted to the terminal in that proportion, the table of contents keeps its
columns.

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
src/md/app_panes.cr   the panes' splitter: resizing, the sizes kept
src/md/app_status.cr  the status bar fields, the mouse modes
src/md/app_menu.cr    the menu bar
src/md/app_search.cr  search, go to line, heading jumps
src/md/app_file.cr    open, reload, watch; the unsaved-changes guard; recent files
src/md/app_links.cr   following links; Previous File and Next File
src/md/app_theme.cr   the theme: Crysterm's built-in themes, switched at runtime
src/md/app_autosave.cr auto-save to a recovery file; the backup file
src/md/app_view.cr    soft wrap, text width and centering
src/md/app_clipboard.cr copying; the clipboard modes
src/md/app_config.cr  the View and Options choices linked to their options, the config file written
src/md/config.cr      the choices as Crysterm (Superconf) options; the config file (~/.config/md/config.yml)
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
