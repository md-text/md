# md manual

md is a Markdown viewer and editor for the terminal: the Markdown source,
the rendered document and a table of contents side by side, updating as
you type. This manual covers using it; Help → Manual opens it inside md.

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
file. On a stream the panes go there once the line has arrived and the
viewer shows it, as `less +N` on a pipe waits for it; a line the stream
never reaches, or one counted from the end, is taken when the stream ends. Show any combination you like; the viewer re-renders as you type, and the table of
contents follows the document's headings and keeps the heading you are
under highlighted as you move through either pane — or its nearest shown
parent while that branch is folded. A document arriving on standard
input is rendered as it comes in, and the viewer keeps scrolling to the end
until you scroll up.

The terminal's title is the document's file name, without its directory,
followed by `• MD` — `README.md • MD` for `docs/README.md`, `stdin • MD`
for a stream, `[No Name] • MD` for a new document — and changes as you open, save as or close a file. A terminal
without titles ignores it; one that keeps a stack of titles (xterm, kitty,
Ghostty, iTerm2, WezTerm, foot…) gets its own back when md exits or is
suspended.

The shown panes share the width with a divider between each two: the editor
and the viewer equally, the table of contents as a 30-column list. Drag a
divider with the mouse to resize the panes beside it, or, without a mouse,
press `Alt-R`: the divider next to the pane you are in takes the keys,
`Left` and `Right` move it a column at a time, and `Enter`, `Escape` or
`Tab` go back to the panes. Uncheck Options → Resizable Panes to lock the panes
as they are — the dividers then refuse the mouse and the keys, and `Alt-R`
says so — and check it again to resize them. A hidden pane gives its width
to the others and gets it back when shown. The sizes, and whether the panes
are resizable, are kept across runs with the other settings; a wider or
narrower terminal next time keeps the proportions of the editor and the
viewer, and the table of contents its columns. `F4`, or View → Menu and
Status Bars, hides the two bars and brings them back, so the panes take the
whole terminal; the entries' keys keep working meanwhile, and a question
asked in place of the status bar shows the bar while it is open. Kept across
runs too.

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
| `Alt-F`, `Alt-E`, `Alt-M`, `Alt-V`, `Alt-O`, `Alt-N`, `Alt-P` | Open the File, Edit, Format, View, Options, Window and Help menus (`F10` too) |
| `Alt-W`            | Soft Wrap in the editor on and off (Format → Soft Wrap)                     |
| `Shift` + `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `PageUp`, `PageDown` | Select from the cursor, in the editor and in the viewer |
| `Ctrl-Home`, `Ctrl-End` | Go to the start and the end of the document, in the editor and in the viewer |
| `Ctrl-O`           | Open a file; asks for the name (File → Open…)                             |
| `Ctrl-R`           | Reload the file from disk (File → Reload)                                 |
| `Ctrl-S`           | Save; without a file name yet, asks for one (File → Save As… always asks) |
| `Ctrl-C`           | Copy the selection, or with nothing selected the current block (the line, in the editor) as plain text (Edit → Copy; Edit → Copy as Markdown copies the block's source) |
| `Ctrl-V`           | Paste the clipboard into the editor at the caret; from the viewer or the table of contents, at the source of the viewer's caret (Edit → Paste; Edit → Paste Special names the source) |
| `Ctrl-F`, `/`, `?` | Search; asks for the pattern (`/` and `?` outside the editor, `?` backward; Edit → Find…) |
| `Ctrl-G`, `Alt-G`, `n`, `N` | Next and previous match (`n` and `N` outside the editor; Edit → Find Next, Find Previous) |
| `Alt-H`            | Replace; asks for the pattern and the replacement, then about each match (Edit → Replace…) |
| `Ctrl-L`           | Go to a source line; asks for the number (Edit → Go to Line…)             |
| `:`, `Alt-K`       | The command line: a command's name runs it, `Tab` completing it, and a number goes to that source line (`:` outside the editor; Edit → Run md Command…; see Commands) |
| `Alt-Down`, `Alt-Up`, `]`, `[` | Jump to the next and previous heading (`]` and `[` outside the editor; Edit → Next Heading, Previous Heading) |
| `Alt-R`            | Resize the panes from the keyboard (when Options → Resizable Panes is on): `Left`/`Right` move the divider next to the pane, `Enter`/`Escape` return |
| `Backspace`        | Outside the editor, go back to the file you were in before the last link or open, where you left it (File → Previous File) |
| `Alt-Left`, `Alt-Right` | Previous File and Next File (File → Previous File, Next File); in the editor and the viewer these move by word instead |
| `Enter`            | In the editor, on a list item: continue the list (an empty item ends it) |
| `Ctrl-B`, `Alt-I`, `Alt-C` | Bold, italic and code around the selection or the word at the caret, or off again (Format → Bold, Italic, Code) |
| `Alt-X`            | Tick or untick a list item's task box, or give it a ticked one, a line of text becoming an item (Format → Toggle Task Checkbox; Format → As a Task, a check entry, adds and removes the box) |
| `Ctrl-Up`, `Ctrl-Down` | Promote or demote the heading of the caret's section, from the heading or anywhere in its text (Format → Promote Heading, Demote Heading) |
| `Alt-Q`            | Refill the paragraph at the caret, or the selected paragraphs, to the wrap column (Format → Rewrap → Paragraph; Rewrap → Document refills them all) |
| `Ctrl-N`           | Open another window on this document (the same text, edited in either), in a new terminal window (Window → New) |
| `Ctrl-W`           | Outside the editor, close this window, asking first only when it is the last window on a document with unsaved changes; the last window's close quits (Window → Close Current) |
| `Ctrl-Q`           | Quit: closes every window (`q` too, anywhere but in the editor; File → Quit), once each document with unsaved changes was asked about; Cancel closes nothing |

The menus show these keys next to their entries, spelled as
Qt does (`Ctrl+O`), and the right end of the menu bar names the keys that
open the menus. The keys work from any pane, after the pane had its turn —
the editor keeps the keys it uses — and wait while a prompt is open.
The numeric keypad's `Enter` is `Enter` wherever this says `Enter`, and
its digits and operators type as the main keyboard's do.

The editor has the usual editing keys: arrows and `Home`/`End`,
`Ctrl-Home`/`Ctrl-End` for the start and the end of the document, `Shift` +
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
whether the document is modified.

A file is saved with the line endings it was opened with: `LF`, or `CRLF` for
a file from Windows, decided by its first line (a file mixing both is saved
with its first line's throughout, one without any line break as `LF`). The
status bar shows which; a new document is `LF`, a reload looks again, and a
document read from standard input takes its first line's. A lone carriage
return is a line break too, as in Qt, and is saved as the file's line ending. Two fields at the right are toggles you can
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
well, next to the overwrite mode. The File menu opens, reloads, closes, saves,
saves as and quits, lists the recently opened files and retraces the files
left (Previous File, Next File); the Edit menu copies, pastes, searches,
replaces, runs md's commands, goes to a line, jumps between headings and
turns Vi Mode on; the Format menu marks
up the source (see Editing Markdown below) — the markup around text first
(Bold, Italic, Code, Code Block), then what works on whole lines (Indent and
Outdent, the task entries, the heading level), then the wrapping (Soft Wrap,
Hard Wrap, Text Width and Rewrap); the View menu shows and hides the panes.

Every menu entry has a one-sentence description of what it does. While a
menu is open, the status bar shows the highlighted entry's in place of the
document's name — as desktop applications show a status tip, but as wide
as it needs, over the fields on the right when it does not fit beside them —
and gives the bar back when the highlight moves on or the menu closes; the entries' keys
are in the menus themselves. View → Tooltips moves the descriptions: *In
Status Bar* is that; *As a Popup* shows one in a small box beside the entry
instead, after a moment, gone as soon as the highlight leaves it, for a
terminal whose status bar is out of sight; *Never* shows none. Whatever the
choice, `F1` on a highlighted entry shows its description beside it until
the next key, and the status bar stays the document's. Kept across runs
(`md.tooltips`).

Options → Detachable Menus gives every menu a grab strip (`⠿⠿⠿`) in the
middle of its top border and another in the middle of its bottom border, after
GNOME 2's tear-off menus: drag either strip — or just click it — and a copy of
the menu is torn off and stays on screen where you drop it, the point you
grabbed staying under the pointer, with the same entries, kept in step with the
menu's own (a check made on either shows on both). Drag either of its strips to
move it, and click the `⊠` (`x` on an ASCII terminal) at the right end of its top border to close it; an outside click leaves it up, and
`Escape` only takes the keyboard back to the panes. Submenus tear off too,
and a torn-off menu's own submenus open as usual. The ordinary menus are
unchanged. Turning the option off hides the torn-off menus, and turning it
on again brings them back where they were (`--menu-tear-off`).

### Copying

Edit → Copy (`Ctrl-C`) copies the selection in the focused pane. With
nothing selected, in the editor it copies the caret's line, and in the
viewer or the table of contents the block the viewer's caret is in — a
paragraph, a heading, a list item, or a fenced code block or a table
whole — as plain text, the way it reads. Edit → Copy as Markdown copies the
block's source instead: the lines of the Markdown it was rendered from,
fences included. A notice says how much was copied. In a pane with a
selection, `Ctrl-C` is the pane's own copy, as `Ctrl-X` and `Ctrl-V` are
its cut and paste.

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
`--media-backend` option names. Auto, the default, leaves the choice
to Crysterm, which takes the best one your terminal drives (the entry names
it in parentheses) — Kitty graphics
on Kitty, Sixel on an xterm, sub-cell glyphs or one cell per pixel anywhere
else; the other entries name one and hold it: the cell grid (ANSI in true
color, 256, 16 or 8 colors; Unicode half blocks, quadrants, sextants,
octants, braille dots; ASCII contours), the terminal's own graphics (Sixel,
ReGIS, Kitty, iTerm2, Tektronix 4014) and the external overlays
(w3mimgdisplay, Überzug). The entries your terminal cannot drive are
disabled — ReGIS and Tektronix always, since nothing detects them, the
overlays without their helper program. None, below Auto, draws no images
and fetches none: an image with a title (`![alt](picture.png "title")`)
shows the picture glyph and the title where its picture would be, above
the row with the glyph and the alt text, and one without a title is that
row alone. A pick takes effect at once: Crysterm
drops the images it drew under the old backend and draws them again with the
new one, and the status bar says which is on. Check Change for 5s, above
Auto, to try a backend instead of keeping it: the pick switches for
five seconds and then goes back to the backend in force before, the check
marks following; another pick during the five seconds starts them over and
still returns to the original, picking the original ends the trial, and
unchecking Change for 5s during one keeps the tried backend and cancels the
return. The backend draws the document's pictures (see Images below) and
the background images a stylesheet sets (`background-image` in a
`--colors-stylesheet`). The backend is kept with the other settings; Change
for 5s is not, like Overwrite Mode.

Four more of Crysterm's options sit in the menus, for a reader who would
otherwise set them on the command line. View → Color Depth is how many
colors the window is drawn with — Auto, the default, takes the
terminal's word (the entry names the depth it found in parentheses, as in
Auto (256 Colors)), and Monochrome, 8, 16, 256 Colors or True Color force a
depth, for a terminal that reports fewer colors than it shows, or to see a
theme as a plainer terminal would; the whole window is redrawn at the new
depth at once (`--colors-depth`). Monochrome sends no colors at all, so a
cell can only be the terminal's own foreground on its background or the
two swapped: Crysterm draws a light-backed cell on a dark terminal (or a
dark one on a light terminal, by the background the terminal reports) in
reverse video, which is how a light theme comes out black on white rather
than in the terminal's defaults. Options → Links is whether the
links in the viewer are also the terminal's own hyperlinks, to click or
hover where the terminal does that: Auto, which says in parentheses
whether md found the terminal to support them (Yes or No), turns
them on where the terminal is known to support them, Always trusts the
terminal over the detection, and Never turns the viewer's links off
altogether — drawn as plain text, followed by neither a click nor `Enter`,
skipped by `Tab` (`--render-hyperlinks`). Below the three, Double-click to
Open makes a double click follow a link where a single one does by default,
the choice desktops offer; a single click then only places the caret
(`md.link_double_click`). Options → No Animations skips Crysterm's
animations and shows their end state at once (`--render-reduced-motion`):
so far the flash of a dialog button pressed from the keyboard and the
transitions of a stylesheet that declares them. Options → Detachable Menus is described with
the menus above (`--menu-tear-off`). All four are kept with the other
settings.

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
for `1. `, as CommonMark wants a child list, and no deeper (Markdown has no
deeper level without an item to hold it, and the first item of a list — or
a selection starting on one — has nothing to nest under, so those stay,
with a notice), and outdents back to
the indentation of the nearest shallower item — and any other line by
Markdown's unit of four spaces, `Shift-Tab` taking up to four spaces, or a
tab, off its front. `Tab` therefore never leaves the editor, as it does not
leave a text field in Qt; `F1`, `F2`, `F3` and the mouse do, and there is
no other focus key a terminal could tell from `Tab` (`Ctrl-Tab` arrives as
`Tab`). Outside the editor `Tab` cycles the panes as before.

Format → Bold, Italic and Code (`Ctrl-B`, `Alt-I`, `Alt-C`) put `**`, `*`
or backticks around the selection, or the word at the caret, or insert the
pair with the caret between when there is neither; on text that already has
them (`_` and `__` count too) they take them off, and the text stays
selected, so a second press undoes the first. Format → Code Block puts
the selected lines, or the paragraph at the caret, between ```` ``` ````
fences (inside a quote, the fences carry its `> `), drops an empty fenced
block on a blank line with the caret inside it, and takes the fences off
again when the caret is anywhere in a fenced block. Format → As a Task, a
check entry whose check shows whether the item at the caret is a task when
the menu opens, gives a list item a `[ ]` box and takes it off again;
Format → Toggle Task Checkbox (`Alt-X`) ticks the box `[x]` and unticks it,
and gives an item without a box a ticked one. A task box belongs on a list
item, so on a line of text that is no item both make it one first, `text`
becoming `- [ ] text` (a selection's lines of text each, when it holds no
item), and a line that starts with a box, `[ ] text` or `[x] text`, keeping
that box as the item's, which Toggle Task Checkbox ticks. An item that is a
heading, `- ## Title`, takes its box as a task heading, `- [ ] Title` over
`---` (`===` for `#`), since GFM boxes no ATX heading, and a level 3 to 6
one is left with a notice (see below); Format → Promote Heading and Demote Heading (`Ctrl-Up`, `Ctrl-Down`)
move the heading of the caret's section one level up or down, a paragraph
being the level above `#` — the caret's line when it is a heading, and from
anywhere in the section's text the nearest heading above it (one in a code
block does not count), the caret staying where it is. A setext heading
(`Title` over a line of `===` or `---`; a `---` after a blank line is a
rule) counts too, and becomes an ATX one as it moves: `---` is level 2, so
Demote makes it `### Title` and Promote `# Title`, while a promoted `===`
heading loses its underline. A heading in a list item, at any depth, counts
as CommonMark has it: `- ## Title`, or `- Title` over a `---` or `===`
indented to the item's text (a `---` at the margin under an item is a rule
after the list); it keeps its marker and indentation as it moves, `- Title`
over `---` demoted becoming `- ### Title`. A task item's heading follows
GFM as github.com renders it: the box counts only at the start of the
item's first paragraph, so `- [ ] Title` over `---` is a task whose text
is a level-2 heading, while `- [ ] ## Title` is a task whose text is
`## Title` and `- ## [ ] Title` a heading `[ ] Title` with no box. Such a
heading therefore stays setext as it moves, keeping the box: `===` for
level 1, `---` for level 2, and no underline for a paragraph. Demote stops
at level 2 with a notice, since a task item has no heading below that.
Before the first heading, Demote makes the caret's line a `#` heading, or
puts `===` under a task item's text. Each change is one undo step.

The keys are not all Qt's: `Ctrl-B` is, but a terminal sends the same byte
for `Ctrl-I` and `Tab`, and cannot tell `Ctrl-Shift-X` from `Ctrl-X`, so
Italic, Code and Toggle Task Checkbox use `Alt` chords the editor does not
(`Alt-B` and `Alt-F` are its readline word moves). Indent and Outdent show
`Tab` and `Shift+Tab`, keys that are theirs in the editor alone. The Format
menu works from any pane: chosen while reading, it edits the source of the
viewer's caret, showing the editor if it is hidden.

### Vi Mode

Edit → Vi Mode (Neovim) (`md.vi_mode`) edits the editor's text as in Neovim: an
`nvim` runs embedded, headless, and takes the editor's keys (turning it on
from the menu or by name shows and focuses the editor) — `i`, `dd`,
`ciw`, `.`, counts, registers, text objects, `/` and the rest are
Neovim's own — while the editor keeps the document, so the viewer, the
status bar, Find, Format and the other menus work on the text as before.
The function keys and the `Alt` chords are not Neovim's: they stay md's
(`F1`–`F6`, `F10` for the menus, `Alt-W`, `Alt-K`, the menus'
`Alt` letters), while the `Ctrl` keys are Neovim's in the editor
(`Ctrl-R` redoes, `Ctrl-B` pages up), so Bold is reached by the menu.

The status bar shows the mode left of the position — `NORMAL`, `INSERT`,
`VISUAL`, `V-LINE`, `REPLACE`, `COMMAND` — and the command line in
place of the document's name while one is typed; Neovim's messages come as
notices. Visual mode is the editor's selection, so Copy and Format act on
it. `u` and `Ctrl-R` are Neovim's undo and redo, an insert one step; an
edit made by md (Format, Replace, a paste with the mouse) reaches Neovim
and is undone by `u` too; a document opened, reloaded or closed starts
the undo history afresh, in Neovim as in the editor. `:w` saves, `:w
FILE` writes a copy to FILE and keeps the document's name, as Vim does
(a document without a name takes FILE's), `:saveas FILE` (or `:file
FILE` and `:w`) saves as FILE, `:q` closes the window as Window → Close
Current does, asking about unsaved changes when no other window shows
the document, `:q!` closes it without asking,
`:qa` (`:qa!`) quits, and `:wq`, `:x` and `ZZ` save, then close — a new
document once it is named in the Save As question, staying open when
that is cancelled.
Neovim writes no file itself.

Neovim starts with `--clean`, without your config, unless Options → Vi
Mode: Use Neovim Config (`md.vi_config`) is on: then your
`init.lua` or `init.vim` and plugins load, and a mapping of yours applies
in the editor. Without `nvim` in `PATH` the entry is disabled, its
description saying why; should Neovim end, not answer for 5 seconds
(`Ctrl-C` interrupts a loop or a `:!cmd` before that), or the editor's
buffer be closed in it (`:bw`), Vi Mode turns off with a notice and the editor goes on as
before. Neovim edits only the editor's buffer, in one window: `:enew`,
`:e FILE`, `:b N`, `:split` or `:new` is undone at once, with a notice;
the extra window is closed and a file it loaded dropped, unless modified.
The viewer's `:` stays md's command line
(the viewer is no text input), and the line prompts keep plain editing.

Windows on one document (see Windows) each run a Neovim of their own while
they are separate: each takes the others' edits as changes from outside, so
`u` in one undoes an edit made in another too, and marks, registers and the
jumplist are each window's. Linked windows share one Neovim and one buffer
for their document, as Vim's windows on one buffer do: keys typed in any of
them edit it, its cursor goes to the window you type in, `:w` saves from
there and `:q` closes that window alone. Switching Window → Linking
restarts Neovim, and its own undo history with it; the document's undo
(`Ctrl-Z` outside Vi Mode) stays.

### Searching and jumping

Searching works like a pager's: `/` asks for a pattern and finds it forward
from the cursor, `?` backward (to the start of a match the cursor is
in, as in vi), `n` repeats the search and `N` goes the other
way (in the editor, where those are letters to type, use `Ctrl-F`, `Ctrl-G`
and `Alt-G` instead; they work everywhere). The pane you are in is searched:
the Markdown source in the editor, the rendered text in the viewer (or from
the table of contents). The pattern is a regular expression when it is a
valid one and plain text otherwise (`^` and `$` match at the start and end
of every line, as in vi), and it ignores case unless it contains an
uppercase letter, as vi's `smartcase` does. The search wraps around the
end of the document with a notice. Every match is underlined in both panes
and the current one is selected; Edit → Clear Search Highlights takes the underlines
off until the next search — `n` is one, and still knows the pattern.

Replacing (`Alt-H`, Edit → Replace…) works like vi's `:s///c`, at the same
prompt: it asks for the pattern — the last search's is filled in — and
then for the replacement, and steps through the matches from the cursor,
selecting each in the editor and asking `Replace? (y)es (n)o (a)ll (q)uit (l)ast`.
A single key answers: `y` replaces the match and moves on, `n` leaves it,
`a` replaces it and every match after it (around the end of the document
and back to where you started), `l` replaces it and stops, `q` and `Esc`
stop. The pattern follows the
search's rules, and the replacement may refer to the pattern's groups,
`\1` to `\9`, and to the whole match, `\0`, as Crystal's `String#sub`
does (`\\` is a backslash). Replacing edits the Markdown source, so from
the viewer it shows and focuses the editor first; every replacement can be
undone with `Ctrl-Z`, the `a` as a single step. A notice reports how many
matches were replaced. (Qt's key, `Ctrl-H`, is Backspace in the terminal,
hence `Alt-H`.)

`Ctrl-L` (or `:`, the command line, given a number) asks for a source
line number and puts both panes there; `0` and negative numbers count from
the end. `]` and `[` (or `Alt-Down` and
`Alt-Up`, Edit → Next Heading and Previous Heading) jump to the next and
previous heading, in both panes, with the heading on the viewer's top row
as a table of contents jump lands.

### Opening, reloading and watching

File → Open… (`Ctrl-O`) asks for a file name the way Save As does, with
`Tab` completion, and opens it: an existing file in the viewer, a new name as
an empty document in the editor. A document streaming in from standard input
is left behind (it goes on streaming into any other window that keeps it
open). A file another md window has open — by whatever path, through a
symbolic link or a hard link — is not read again: the window shows that window's document,
unsaved edits included, and a notice says so. Opening the file the window
already shows goes nowhere; File → Reload reads it again. File → Open Recent lists the files you opened before, most
recent first; md also remembers where you were in each and lands there when
you open it again. A file is one entry however you reach it — through a
symbolic link, or by another case of its name on a case-insensitive volume
— shown by the path you last opened it by. The list lives in
`$XDG_STATE_HOME/md/history.json` (`~/.local/state/md/history.json`).

File → Reload (`Ctrl-R`) re-reads the file from disk, keeping the viewer's
place, in every window showing the document. A reload changes only what
differs from the file, as one edit: each window's cursor stays where it was
in the text unless the text under it changed, the document is then
unmodified, and Edit → Undo (`Ctrl-Z`) takes the reload back — unsaved
changes it dropped included, the document modified again — as in Qt
Creator. Unsaved changes are still asked about before a reload. Options →
Watch File (or
`--watch` on the command line) does that for
you: the file is polled once a second and reloaded when another program
changed it, so md beside an editor shows each save as it happens. While the
document holds unsaved changes (made in any window on it) the reload is skipped and a notice says the
file changed on disk; a file removed keeps its text in md, with a notice,
and is reloaded when it comes back. The status bar shows `(watching)` after
the name. Watch File is the document's: every window on it shows the same
check, and a file read in over a watched one is watched too (a file another
window has open already is watched as that window has it).

File → Close closes the document, asking first about unsaved changes (only
when no other window keeps it open; windows linked to this one close it
too, see Windows), and
takes it off the trail of files that Previous File and Next File retrace
(see Following links); its place is remembered, as for any file left. The
file Next File would have gone to opens in its place, where it was left;
with none, a blank new document is left, as `md` starts without a file, and
Previous File still leads back. A document being read from standard input
stops being read, unless another window keeps it open.

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

A link to a program on this computer is refused with a notice instead,
since the system would run it, not show it: a file with any execute
permission (a shell script, a binary), and by name an application bundle
or anything the system launches or installs — `.app`, `.command`, `.tool`,
`.terminal`, `.workflow`, `.action`, `.jar`, `.fileloc`, `.pkg` on macOS,
`.desktop`, `.AppImage`, `.run`, `.deb`, `.rpm`, `.flatpakref` and the
Windows `.exe`, `.msi`, `.bat`, `.cmd`, `.com` that Wine runs on Linux —
through a symbolic link too. A Markdown file is read whatever its
permissions. Options → Links → Open Local Programs lets such links through
(`md.open_local_programs`, `MD_OPEN_LOCAL_PROGRAMS`; off by default). Web
and mail links are not affected. On a volume that marks every file
executable (FAT, some network shares) every linked file counts as a
program.

Every file left is a step you can retrace: `Backspace` in the viewer or the
table of contents goes back to the file you came from, at the position you
left (File → Previous File, `Alt-Left`, works from the menu too), and File →
Next File (`Alt-Right`) undoes a Previous File. Opening a file from File →
Open… or Open Recent over the one shown is a step as well; a jump within the
document — a `#heading` link, the table of contents — is not, since the
entries lead to files. Going back to another file asks about unsaved changes
like any open. Each window retraces a trail of its own; linked windows
(Window → Linking) share one, and a step in any of them takes the whole
group (see Windows). In the editor and the viewer `Alt-Left` and `Alt-Right` keep
moving the cursor by word, so the menu and `Backspace` are the way back from
there.

### Images

An image on a line of its own — `![alt](picture.png)`, with or without a
link around it — is drawn in the viewer, above a row with a picture glyph
and the alt text, which is what stands for the image everywhere else: in
the editor, in a copy, in `--export`. The picture is as wide as the text
and as tall as its shape asks, up to half the pane, so a tall one never
fills the view; it scrolls with the text, and the cursor steps over it as
over a blank line. A relative name counts from the document's directory,
as a relative link does (the working directory for a new or streamed
document); an `http:` or `https:` one is fetched in the background and
takes its rows when it arrives. A picture that cannot be read leaves the
glyph and the alt text alone, and an image inside a sentence stays that
way too. How the picture is drawn is View → Media Backend's choice: the
terminal's own graphics where it has them (Kitty, Sixel, iTerm2), colored
cells or sub-cell glyphs anywhere else. View → Images turns the pictures
off and on (`md.images`, `MD_IMAGES`, `--no-md-images`), kept with the
other settings.

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
with box characters, a rule as a line 72 cells wide. Nothing else happens in
this mode: no history, no log file.

From inside md, File → Export as HTML… and Export as Text… write the same
output for the text as it is now, saved or not, to a file asked for by
name the way Save As asks — the document's name with `.html` or `.txt`
filled in, a leading `~/` being your home directory. The document keeps its
own name and file. An existing file is written over, as Save As writes,
except one open in md (the document's own source, say), which is refused
with a notice.

### Unsaved changes

Quitting, opening another file or reloading with unsaved changes asks first:
*Save*, *Don't save* or *Cancel*. Saving a document without a name asks for
one, and the action goes ahead once the save is done. Options → Ask Before
Discarding Changes turns the question off. Quitting asks about each
document with unsaved changes before any window closes, and Cancel keeps
them all open. A document shown in several windows (see Windows) is asked
about only in the last window on it otherwise: closing another window, or
opening another file in it, loses nothing —
except that opening another file in a linked window (Window → Linking)
takes every window of its group along, so it asks.
Reloading drops the changes in every window, so it asks whenever there are
some, and the question says how many windows show the document. Save As
onto a file another window has open with unsaved changes writes nothing and
says so; with none there, the file is written and that window shows this
document from then on, its cursor on the same line.

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
*Line Numbers* puts a gutter with line numbers down a pane's left, the
way code editors do: *Editor* numbers the editor's source lines, *Viewer*
the viewer's rendered rows. The viewer's numbers count the rows as shown,
from 1 at the top of the rendered document — a paragraph that wraps over
three rows takes three numbers, and the blank rows between blocks and a
picture's rows are counted too — so they are not the source line numbers,
and they change when the text re-wraps. Both choices are kept across runs.

Four more entries lay the text out, the first three in the Format menu,
beside Hard Wrap and Rewrap, and the last in View. *Soft Wrap* (`Alt-W`) is the
editor's: on, a long line folds at the pane's edge; off, it runs past the
edge and the pane scrolls sideways. *Text Width* caps the width the text is
laid out in — 72, 80, 100 or 120 columns, or *Unlimited* — so a line does
not run the whole width of a wide terminal; it applies to both panes, which
keeps them reading side by side under Sync Cursor. *To Last Guide*, below
the widths, sets it so the text ends just left of the rightmost guide you
pulled onto the editor while editing, the viewer otherwise (see Guides): a
guide dragged to a good place becomes the text's right edge. *Center Document* puts the
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
it gets the `> `, and a code block (fenced or indented), a heading, a table
row or a rule is never broken. The keystroke and the wrap it caused undo as
one step. Format → Rewrap → Paragraph (`Alt-Q`, Emacs's fill) refills the
paragraph at the cursor, or every paragraph the selection touches, and
Rewrap → Document every paragraph in the file, to the same column — a list
item keeping its marker, a quote its markers, code blocks untouched —
whether or not Hard Wrap is on. The Rewrap entry names that column, as
*Rewrap (to 80 Columns)*, and follows the Text Width as it changes.

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
same session leave it alone. A save itself writes the file whole: the text
goes to a temporary file beside it and replaces the file only once it is all
on disk, so a full disk or a crash mid-save leaves the previous contents
(the file's permissions are kept, and a symbolic link is followed; a file
with other hard links is written in place). *Auto-Save* writes your unsaved edits every 30
seconds to a recovery file — never to the file itself, which is written
only when you save, the way vim's swap file and emacs' `#file#` work. The
recovery files live in `$XDG_STATE_HOME/md/autosave/`
(`~/.local/state/md/autosave/`), named after the file's absolute path with
`/` escaped as `%2F` (`/home/u/notes.md` recovers from
`%2Fhome%2Fu%2Fnotes.md`; a path too long for a file name gives a digest
of it followed by its end, `…-%2Fnotes.md`); a document without a name, such as one piped in
on standard input and then edited, is kept as `unnamed-<date>-<time>-<pid>.md`
(with `-2`, `-3`… for another document's from the same second). A document
shown in several windows has one recovery file and one backup.
Saving or quitting normally removes the recovery file, so whatever remains
in the directory is what some session lost. When you open a file whose
recovery file is newer than the file, a notice names the copy; open it
(File → Open… takes the path) or copy it over the file to get the edits
back. A new document is told of unnamed copies left behind.

Two md processes on one file know of each other: each leaves a lock for
the files it has open in `$XDG_STATE_HOME/md/locks/`
(`~/.local/state/md/locks/`), named as the recovery files are and holding
its process id, host and the time. A second md opening a file the first
has open, or saving another file under its name, says so in a notice —
`README.md is open in another md (pid 1234); saving here overwrites its
changes` — and lets you go on: whichever saves last wins. A lock goes when
the last window on its file closes or md exits, moves with Save As, and one
whose process is gone (a crash) is replaced; one taken on another host
sharing the directory counts as held, since md cannot tell whether that
process lives. Options → Clear Caches leaves the locks alone.

### Clearing the caches

Options → Clear Caches… forgets, after asking, everything md keeps for
itself between runs: the recent files and the positions remembered in them
(File → Open Recent goes empty), the auto-save recovery files — those of
the documents open too, each written again at the next auto-save while it
is modified — the positions Window → Remember Positions keeps, and the
contents of `$XDG_CACHE_HOME/md`
(`~/.cache/md`), where Crysterm's log goes while md runs. A notice says
how many recent files and recovery files went. The settings are your
choices, not a cache, and stay.

### Windows

Window → New (`Ctrl-N`) opens another md window on the document you
are looking at, in a new terminal window, starting where this window is:
the same panes, the cursor and the scroll in the same places. md asks
the terminal emulator it is running in for one: kitty, Alacritty, WezTerm,
foot, xterm, Konsole and GNOME Terminal, Terminal.app, iTerm2 and Ghostty
on macOS (`$TERMINAL` names another), or a new tmux or screen window inside a
multiplexer, which works over SSH as well. A session that can open none —
a console, SSH without tmux, an emulator md cannot drive — has the entry
disabled, and `Ctrl-N` says why. The new window is the emulator's default
size, or this window's where the emulator takes a size. On macOS, Ghostty
opens each such window as a Ghostty of its own, with its own Dock icon,
which quits when the window closes: Ghostty takes no command for a new
window from outside, only at a start.

The two windows show one document, as two windows on one buffer do in Vim,
Emacs, Kate or Qt Creator: an edit in either is in both, editor and viewer,
as you type; Undo in either takes back the last edit, whichever window
made it, with the cursor on the change; the document is modified, saved,
reloaded and watched (Options → Watch File) for both at once, and it has one
recovery file. Each window keeps its own cursor, scroll, panes and search.
While two or more windows show a document they are named `README.md:1`,
`README.md:2` in their titles and in the Window menu; a single window is
plain `README.md` again. Opening a file another window has open (File →
Open…, a link, Open Recent, a dropped file, Previous File) shows the same
document as well. A document streaming in from standard input streams into
every window on it, a new one starting from what has arrived, and goes on
after the window that started it closes. A window in the background keeps
showing all of this as it happens: md turns off Crysterm's pause of
unfocused windows (`render.pause_when_unfocused`, which a config file can
turn back on).

Window → Linking says how the windows on one document behave towards each
other; the text, its undo and its modified state are one either way.
*Separate Views*, the default, is what is described above: each window
keeps its own cursor, scroll, search and trail of files (Previous File,
Next File), and opening another file in a window takes that window alone.
*Linked (Mirrored)* makes the windows on a document act as the panes of one
window: the cursor and selection, the scroll (the same first line, however
tall each window is), the viewer's place, the table of contents' entry, the
search and Sync Cursor follow whichever window you used last, and opening a
file, following a link, Previous File and File → Close take every window of
the group along. With Sync Cursor on, moving in one window's editor moves
another window's viewer, even one that shows no editor, as it would move
the viewer beside the editor. Each window keeps its own panes, sizes and
wrapping. The choice applies to every window at once: linking puts each
document's windows where the window you used last is; going back to
separate leaves each where it is, with its own copy of the trail. It is
kept across runs (`md.window_link`, `--md-window-link linked`).

The settings and the recent files are shared, written by the window that
ends last. Window → Close Current (`Ctrl-W`, outside the editor, where
`Ctrl-W` kills a word) closes the window you are in alone, asking about
unsaved changes only when no other window shows the document; in the last
window it is Quit. File → Quit (`Ctrl-Q`, `q`) first asks about each
document with unsaved changes, once — the one in the window you are in
first, then each other in a window showing it — and closes every window
only when all are answered; Cancel at any question closes nothing. The Window menu lists the open windows
by their names, the one you are in checked; picking another makes it the
active window (and, while windows are linked, the one the others follow),
raised when the two share a terminal; otherwise a notice says it is in
another terminal window, since one terminal cannot raise another.
Terminal.app keeps a closed window on screen with "[Process completed]"
when its profile says so.

Where a new window appears is the window manager's choice, as for any other
window, unless Window → Remember Positions is on (`md.remember_window_positions`,
off by default). Then each window Window → New opens is put where the
window with the same number was when it was last closed, at the size it had:
the window md was started in is the first and is never moved — it is your
own terminal — and the windows md opens are numbered from 2, each taking the
lowest number free while it is open, so the second window of this run opens
where the second window of the last one was. The places are kept per
emulator in `$XDG_STATE_HOME/md/windows.yml` (`~/.local/state/md/windows.yml`),
recorded as each window closes; a place on a display that is no longer
connected is not used, and the window manager places that window instead.
This works on macOS with Terminal.app and iTerm2, which md drives through
AppleScript, so the first use asks for the same Automation permission as
Window → New there, and with Ghostty, which asks for none and sizes a
window in whole cells, to the nearest; elsewhere — Linux and the BSDs, X11 or Wayland, tmux and
screen, the other macOS emulators — an emulator offers no way to place a
window and read where it is, and the entry is disabled, its description
saying why.

### Help

Help → Manual opens md's manual — this text, built into md — as the
document, so it reads, searches and navigates like any other; File → Previous File goes back to what was open
before. Help → About names md's version, its author and its website in the
status bar. `Alt-P` opens the menu, since `Alt-H` is Replace.

### Commands

Everything md does has a name, and the command line runs it by that name,
as vi's `:` runs an ex command: `:` in the viewer or the table of contents,
or `Alt-K` (Edit → Run md Command…) anywhere, asks for a command; `Tab`
completes the name and cycles through the names that start with what was
typed. A number instead goes to that source line. Every menu entry is a
command, and so is every key no entry has:

| Commands | |
| -------- | - |
| `open`, `reload`, `close`, `previous-file`, `next-file`, `save`, `save-as`, `export-html`, `export-text`, `quit` | The File menu |
| `copy`, `copy-as-markdown`, `paste`, `paste-from-terminal`, `paste-from-command`, `paste-from-internal`, `find`, `find-backward`, `find-next`, `find-previous`, `replace`, `clear-search-highlights`, `command`, `go-to-line`, `next-heading`, `previous-heading`, `vi-mode` | The Edit menu, and `?` |
| `bold`, `italic`, `code`, `code-block`, `indent`, `outdent`, `task`, `toggle-task`, `promote-heading`, `demote-heading`, `soft-wrap`, `hard-wrap`, `rewrap-paragraph`, `rewrap-document` | The Format menu (`soft-wrap` and `hard-wrap` turn their setting on or off) |
| `editor`, `viewer`, `toc`, `bars`, `sync-cursor`, `highlight-line`, `line-numbers`, `viewer-line-numbers`, `center-text`, `horizontal-ruler`, `vertical-ruler`, `guides`, `images`, `media-trial` | The View menu's check entries: each turns its setting on or off |
| `overwrite-mode`, `confirm-discard`, `autosave`, `backup-file`, `watch-file`, `link-double-click`, `open-local-programs`, `resizable-panes`, `reduced-motion`, `detachable-menus`, `vi-config`, `load-config`, `save-config`, `save-config-as`, `clear-caches` | The Options menu |
| `new-window`, `close-window`, `remember-window-positions`, `manual`, `about` | The Window and Help menus |
| `toggle-editor`, `toggle-viewer`, `toggle-toc`, `toggle-bars`, `cycle-mouse-mode`, `cycle-theme`, `suspend`, `resize-panes` | `F1`–`F6`, `Ctrl-Z` and `Alt-R` |

A choice among several is named after its submenu and the choice:
`theme-breeze-dark`, `text-width-80` (`text-width-off` for none,
`text-width-to-last-guide`), `color-depth-xterm256`, `hyperlinks-auto`,
`dialog-style-modal`, `mouse-all`, `clipboard-terminal`,
`tooltips-status-bar`, `media-backend-kitty`, `window-link-linked`. A command that cannot run
now — an entry the menu shows disabled — says so, as does a name md does
not know.

### Settings

The choices made in the Edit, Format, View, Options and Window menus — Vi Mode, Soft Wrap, Hard
Wrap, Text Width, Menu and
Status Bars, Sync Cursor, Highlight Line, Line Numbers (Editor and
Viewer), Center Document, Rulers (Horizontal and Vertical), Guides,
Images, Links → Double-click to Open and Open Local Programs, Dialog Style, Ask Before Discarding
Changes, Auto-Save, Keep a Backup File, the mouse mode, the clipboard mode,
Resizable Panes, Tooltips, the theme and Crysterm's own Color Depth, Links, Media
Backend, No Animations, Detachable Menus, Vi Mode: Use Neovim Config, Window → Linking and Window → Remember Positions — and the pane sizes are kept across runs in
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
  mouse_mode: "off"
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
for md alone goes here rather than in Crysterm's `~/.config/crysterm/config.yml`
(which md reads first, below its own, and never copies into it).
Entries md does not know are kept across a rewrite, so an older md does not
shed a newer one's settings; a broken file stops md with a message naming the
entry, as does a file that is not a mapping of option groups or a value that
fits no option, given anywhere. One YAML caution: write a value that YAML reads as a boolean, such as
the mouse mode's or Links' `off`, in quotes (`mouse_mode: "off"`,
`hyperlinks: "off"`), or md stops on it; md's own writes quote every word.

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
