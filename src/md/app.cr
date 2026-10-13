require "crysterm"
require "./source"

module Md
  # The interactive terminal application: a `MainWindow` (menu bar and status
  # bar) whose central area holds three panes side by
  # side — the Markdown source editor, the rendered viewer and a navigable
  # table of contents — in a splitter whose dividers resize them
  # (`app_panes.cr`). Any combination of panes can be shown; by default only
  # one is, chosen by the `Source` (editor for a new document, viewer for a
  # file or a stream).
  #
  # The editor is the source of truth: the viewer is re-rendered from its text
  # on every edit (lazily, when the viewer or table of contents is hidden) and
  # the table of contents tracks the viewer's document. A streamed document
  # (`#stream`) goes to the viewer chunk by chunk, following the tail, and is
  # loaded into the editor only when the editor is first shown.
  #
  # The status bar (`app_status.cr`) shows the document's name, position,
  # size, encoding and modified state, and holds two toggles: the editor's
  # insert/overwrite mode and the mouse mode (`MouseMode`, after vi's
  # `set mouse=`). The menu bar (`app_menu.cr`) puts every command and
  # setting within the keyboard's reach, each entry naming its key.
  #
  # View → Sync Cursor (`#sync_cursor`) keeps the editor's and the
  # viewer's carets on the same place in the document. The focused pane
  # leads: a caret move there puts the other pane's caret on the
  # corresponding position and scrolls it to the same row of the viewport,
  # so the two panes read side by side. The correspondence is
  # by source line — the Markdown importer stamps every rendered block with
  # the line it came from (`TextBlock#source_line`) — with the caret's offset
  # within the line carried over as an approximation: the rendered text has
  # no markup, so a position inside a formatted span lands near, not on, its
  # source, and a line that renders nothing (a blank line, a fence, a table
  # delimiter row) maps to the nearest rendered block above it.
  #
  # View → Highlight Line (`#highlight_line`) tints the row the caret is on
  # in both panes (Crysterm's `highlight_current_line`) — with Sync
  # Cursor, the two tinted rows are the same place in the document.
  #
  # Format → Soft Wrap and Text Width and View → Center Document
  # (`app_view.cr`) lay the text out: the editor's wrap mode, a cap on the
  # text's width for a wide terminal, and whether the capped column is
  # centered in the pane. View →
  # Rulers and Guides (there too) measure it: a column and a row ruler on
  # each pane, and guide lines at the text's edges and wherever one is
  # pulled off the ruler.
  #
  # Searching, going to a line and jumping between headings are in
  # `app_search.cr`; opening, reloading and watching the file, the guard
  # against losing unsaved changes and the history of recent files in
  # `app_file.cr`; auto-save and the backup file in `app_autosave.cr`;
  # copying and pasting, and the clipboard mode (Options → Clipboard), in
  # `app_clipboard.cr`; following a link and the way back from it (File →
  # Previous File, Next File) in `app_links.cr`;
  # the editing that knows Markdown — lists continued on `Enter` and
  # indented with `Tab`, the Format menu — in `app_edit.cr`; the questions
  # md asks, in place of the status bar or in a dialog (View → Dialog
  # Style), in `app_dialogs.cr`; the theme in `app_theme.cr`, the viewer's
  # pictures and how they are drawn (View → Images, Media Backend) in
  # `app_media.cr`, Crysterm's other options in the menus in
  # `app_toolkit.cr`, the entries' descriptions (View → Tooltips) in
  # `app_tips.cr`, the settings' link to the config file in `app_config.cr`,
  # Options → Clear Caches… in `app_caches.cr` and the other windows of the
  # process in `app_windows.cr`.
  #
  # Keys: `F1`/`F2`/`F3` show and focus the editor/viewer/table of contents,
  # or hide it when it is already focused; `F4` hides the menu bar and the
  # status bar together, and brings them back (View → Menu and Status Bars,
  # `#bars?`); `Tab` cycles focus between the
  # shown panes, except in the editor, where it indents (`app_edit.cr`);
  # `Insert` toggles overwrite mode in the editor; `F5` cycles
  # the mouse mode; `F6` the theme (`app_theme.cr`); `Ctrl-Z` outside the
  # editor suspends md as the shell's `Ctrl-Z` would (in the editor it is
  # undo); `Alt-R` hands the keys to a divider (`app_panes.cr`), and `Enter`
  # and `Escape` take them back. The File, Edit
  # and View entries' keys — `Ctrl-S` saves, `Ctrl-O` opens, `Ctrl-R`
  # reloads, `Ctrl-F` searches, `Ctrl-G`/`Alt-G` repeat the search, `Alt-H`
  # replaces, `Ctrl-L` goes to a line, `Alt-Up`/`Alt-Down` jump between headings,
  # `Ctrl-Q` quits, `Ctrl-N` opens another window on the document and
  # `Ctrl-W` closes this one (`app_windows.cr`) — are the entries'
  # shortcuts (`app_menu.cr`), shown in the menus, and outside the editor
  # the pager keys `/`, `?`, `n`, `N`, `:`, `[`, `]` and `q` do the same
  # (`q` is Crysterm's default quit key as well, kept live while a pane
  # reads input; the editor consumes the `q` it inserts). Quitting closes
  # every window, each through its own unsaved-changes guard.
  class App
    # The three panes of the central area, in layout order.
    enum Pane
      Editor
      Viewer
      Toc
    end

    # Width of the table of contents column, in cells, until it is resized;
    # the other panes share the rest of the width equally.
    TOC_WIDTH = 30

    # How long a status bar notice (save result, warning) stays visible.
    NOTICE_TIMEOUT = 5.seconds

    getter window : Crysterm::Window
    getter main : Crysterm::Widget::MainWindow
    getter editor : MarkdownEdit
    getter viewer : Crysterm::Widget::TextBrowser
    getter toc : Crysterm::Widget::TocView
    # The document this window shows (`document.cr`): its text, which the
    # editor edits, and its file. Other windows may show it too.
    getter document : Document

    # The line a streamed document was asked to open on (`--line`), until the
    # stream has it (`#jump_to_pending_line`).
    @pending_line : Int32?
    # The viewer was not re-rendered after the last edit (it was hidden).
    @viewer_stale = false
    # The document's revision this window has caught up with
    # (`#document_changed`), and whether a catch-up is posted already.
    @seen_revision = 0_i64
    @catch_up_posted = false
    # The subscriptions this window holds on its document, dropped when it
    # leaves it (`#leave_document`).
    @document_subscriptions = Crysterm::Subscriptions.new
    # View → Sync Cursor; see the class comment. A reactive property, so
    # the menu entry binds to it (`#build_menus`); `#sync_cursor?` and
    # `#sync_cursor=` are its plain face.
    @sync_cursor : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    # View → Highlight Line; see the class comment. Likewise.
    @highlight_line : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    # View → Line Numbers → Editor: the editor's gutter (Crysterm's
    # `AbstractScrollArea#line_numbers`), numbering the source lines, as a
    # property the menu entry and the config link to; the editor's own
    # event keeps it in step with the editor (`#initialize`).
    @line_numbers : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    # View → Line Numbers → Viewer: the same gutter on the viewer, which
    # numbers the rendered rows 1 to N as shown (wrapped rows and the blank
    # rows between blocks each counted), not the source lines they came
    # from. Likewise.
    @viewer_line_numbers : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    # The status bar's fields (see `#build_status` in `app_status.cr`).
    @name_field : Crysterm::Widget::Label
    @position_field : Crysterm::Widget::Label
    @size_field : Crysterm::Widget::Label
    @encoding_field : Crysterm::Widget::Label
    @modified_field : Crysterm::Widget::Label
    @overwrite_button : Crysterm::Widget::ToolButton
    @mouse_button : Crysterm::Widget::ToolButton
    # Cached measurements of the text — newlines, words, CRLF, the last
    # character (`#measure_text`); `nil` after the text changed.
    @measured : {Int32, Int32, Bool, Char?}?

    # Builds the user interface for *source*. *text* is the document's initial
    # Markdown; *stream* is an IO the document is read from instead, as it
    # arrives; *view* chooses the initially shown pane (viewer, else editor).
    # A *window* can be supplied (e.g. a headless one in specs); by default one
    # is opened on the terminal. With a *history*, the file's remembered
    # position is restored and the recent files are offered and kept; with
    # *config*, the View and Options choices are linked to their options and
    # kept in the config file (`app_config.cr`); with *watch*, the file is followed from the start
    # (`--watch`). A *line* (`+N`, `--line N`) is where the panes start
    # instead of the remembered position: the user asked, so the history
    # does not get a say; on a stream, once the line has arrived
    # (`#jump_to_pending_line`).
    #
    # The window shows a new `Document` of its own, made from *source* and
    # *text*; a window on a document already open is made with the
    # document (`App.new(document, ...)`).
    def self.new(source : Source = Source.new, text : String = "", stream : IO? = nil,
                 view : Bool = !stream.nil? || !text.empty?, window : Crysterm::Window? = nil,
                 history : History? = nil, config : Bool = false, watch : Bool = false,
                 line : Int32? = nil) : App
      decoded = Source.decode text
      document = Document.new(source, decoded)
      document.watch_file.value = watch
      new(document, view: view, stream: stream, window: window, history: history, config: config,
        line: line, scrubbed: !decoded.same?(text))
    end

    # Builds the user interface on *document*, as the other constructor
    # does, the document's text being the initial Markdown: a window joining
    # a document other windows show (Window → New), or showing one made
    # beforehand (`CLI`). *scrubbed* says the text had bytes that were not
    # UTF-8, for the notice.
    def initialize(@document : Document, view : Bool = true, stream : IO? = nil,
                   window : Crysterm::Window? = nil, @history : History? = nil, @config : Bool = false,
                   line : Int32? = nil, scrubbed : Bool = false)
      # Titled for the document alone: the window's number on it, if any,
      # comes with the attach (`#enter_document`).
      @window = App.titled_window window, "#{@document.name} • MD"
      @window.always_propagated_chars << 'q'

      @main = Crysterm::Widget::MainWindow.new parent: @window
      @main.menu_bar # filled by `#build_menus`, once the panes exist
      @name_field = Crysterm::Widget::Label.new text: ""
      @vi_field = Crysterm::Widget::Label.new text: "", width: 9
      @position_field = Crysterm::Widget::Label.new text: "", width: POSITION_WIDTH
      @size_field = Crysterm::Widget::Label.new text: "", width: SIZE_WIDTH
      @encoding_field = Crysterm::Widget::Label.new text: "", width: ENCODING_WIDTH
      @modified_field = Crysterm::Widget::Label.new text: "", width: MODIFIED_WIDTH
      @overwrite_button = Crysterm::Widget::ToolButton.new text: "INS", width: 5
      @mouse_button = Crysterm::Widget::ToolButton.new text: "M=a", width: 7

      @editor = MarkdownEdit.new input_on_focus: true, document: @document.text
      @viewer = Crysterm::Widget::TextBrowser.new input_on_focus: true
      @toc = Crysterm::Widget::TocView.new document: @viewer.document
      @splitter = Crysterm::Widget::Splitter.new
      build_central

      wire_panes
      @window.on(Crysterm::Event::KeyPress) { |e| key_pressed e }
      # A paste no pane took (the editor takes its own): a file dropped on
      # the window arrives as its path (`#open_dropped`).
      @window.on(Crysterm::Event::Paste) { |e| open_dropped e.content }
      # Closing asks the window first (`Window#try_close`, which Quit and
      # Close Current go through, and Crysterm's default quit keys); with
      # unsaved changes the guard refuses and asks the user, closing the
      # window on their answer — the last window's close ends the app.
      # Only the last window on a document asks: closing any other loses
      # nothing, the document living on in the windows left.
      @window.on(Crysterm::Event::CloseRequest) do |e|
        next unless @confirm_discard.value && @document.text.modified? && last_view?
        e.ignore
        confirm_discard { @window.close }
      end
      # A pane coming on screen is brought up to date first — the editor from
      # a stream it missed, the viewer and table of contents from edits made
      # while they were hidden — then the panes are aligned and the status
      # refreshed. The keys (`#show_pane`) and the View menu (the panes'
      # `toggle_view_action`s) both show a pane through here.
      @editor.on(Crysterm::Event::Show) do
        fill_editor if @document.editor_stale?
        pane_shown
      end
      {@viewer, @toc}.each do |pane|
        pane.on(Crysterm::Event::Show) do
          render_viewer if @viewer_stale
          pane_shown
        end
      end
      Pane.each { |pane| widget(pane).on(Crysterm::Event::Hide) { refresh_status } }
      # The View settings take effect when they change, whoever changed them
      # (the menu entry bound to the property, or `#sync_cursor=`).
      @sync_cursor.on_change do
        sync_carets
        refresh_status
      end
      @highlight_line.on_change do
        @editor.highlight_current_line = @highlight_line.value
        @viewer.highlight_current_line = @highlight_line.value
        refresh_status
      end
      @line_numbers.on_change { @editor.line_numbers = @line_numbers.value }
      @viewer_line_numbers.on_change { @viewer.line_numbers = @viewer_line_numbers.value }
      @bars.on_change { apply_bars }
      @editor.on(Crysterm::Event::LineNumbersChanged) { |e| @line_numbers.value = e.visible }
      @viewer.on(Crysterm::Event::LineNumbersChanged) { |e| @viewer_line_numbers.value = e.visible }
      wire_theme
      wire_media
      wire_toolkit
      wire_view
      wire_resizable
      wire_vi
      wire_linking

      Pane.each { |pane| widget(pane).hide }
      enter_document
      stream(stream) if stream
      show_pane(view ? Pane::Viewer : Pane::Editor).focus
      build_menus
      build_key_actions
      wire_tips # where the entries' descriptions show, once the menus exist
      register_window
      build_status
      setup_clipboard
      apply_config
      if line.nil?
        restore_position
      elsif stream
        # A stream has none of its lines yet: the jump waits for the line
        # (`#receive`) or the stream's end (`#finish_stream`), as `less +N`
        # on a pipe waits.
        @pending_line = line
      else
        go_to_line line
      end
      refresh_recent_menu
      notice "Invalid UTF-8 in #{document_name} replaced by �" if scrubbed
      wire_autosave
    end

    # The panes' own events: edits re-render, carets follow, the outline
    # jumps and tracks the viewer's document.
    private def wire_panes : Nil
      @editor.on(Crysterm::Event::TextChanged) { edited unless @document.loading? }
      # The focused pane leads; the other pane's caret, set programmatically
      # to follow, reports a move too, which this guard keeps from bouncing.
      # The table of contents follows the leading pane's caret too: the
      # editor's while it has the focus, the viewer's otherwise.
      @editor.on(Crysterm::Event::CursorPositionChanged) do
        if @editor.focused? && !@mirroring
          sync_to_editor
          track_toc
        end
      end
      @viewer.on(Crysterm::Event::CursorPositionChanged) do
        sync_to_viewer if @viewer.focused? && !@mirroring
        track_toc unless @editor.focused? || @mirroring
      end
      @toc.on(Crysterm::Event::AnchorClick) { |e| jump_to e.url }
      wire_links
      wire_editing
      # A followed link may replace the viewer's document; keep the outline on
      # the document actually shown.
      @viewer.on(Crysterm::Event::SourceChanged) do
        doc = @viewer.document
        @toc.document = doc unless @toc.document.same? doc
        apply_base_url
      end
    end

    # Runs the event loop until the user quits — from this window or from
    # any opened from it (`app_windows.cr`): the loop runs while a window is
    # open; returns the exit status.
    def run : Int32
      # A handler of md's that raises must not take the app down with unsaved
      # text in the editor: opt into Crysterm continuing, with a notice.
      @main.report_handler_errors(NOTICE_TIMEOUT) { |error| error_notice error }
      watch_quit exec_application
      @started = true
      status = @window.exec
      finish
      status
    end

    # *window* given *title*, a window handed in (Window → New's, a
    # spec's) being titled as a new one is.
    def self.titled_window(window : Crysterm::Window?, title : String) : Crysterm::Window
      return Crysterm::Window.new(title: title) unless window
      window.title = title
      window
    end

    # The terminal's title: the window's name (`#window_name`), then the
    # program's — `README.md • MD`, or `[No Name] • MD` for a document
    # without one, as Vim names it; `README.md:2 • MD` while another window
    # shows the document too. Crysterm sends it on any terminal (one without
    # titles ignores it) and puts the terminal's own title back when md
    # hands the terminal back, at exit and while suspended.
    def title : String
      "#{window_name} • MD"
    end

    # Names the window anew wherever it is named, after its document or the
    # number of windows on it changed: the terminal's title, and the entry
    # for this window in the Window menu of every window.
    protected def retitle : Nil
      @window.title = title
      App.refresh_window_menus
    end

    # The document's name as the title, the Window menu and the notices
    # about windows give it: the file's name without its directory
    # (`README.md`, however the path was given — as typed on the command
    # line or expanded by File → Open), `stdin` for a stream, or
    # `[No Name]`. The status bar shows the whole path.
    def document_name : String
      @document.name
    end

    # This window's name: the document's (`#document_name`), with the
    # window's number on the document after a colon while two or more
    # windows show it — `README.md:1`, `README.md:2`, as Vim and Emacs tell
    # the windows on one buffer apart.
    def window_name : String
      (number = @document.number(self)) ? "#{document_name}:#{number}" : document_name
    end

    # Where the document comes from (`Document#source`).
    def source : Source
      @document.source
    end

    # Whether no other window shows this window's document: closing the
    # window, or opening another document in it, loses the document's
    # unsaved changes only then.
    def last_view? : Bool
      @document.views.size <= 1
    end

    # The document's current Markdown source.
    def markdown : String
      @document.markdown
    end

    # The widget of *pane*.
    def widget(pane : Pane) : Crysterm::Widget
      case pane
      in .editor? then @editor
      in .viewer? then @viewer
      in .toc?    then @toc
      end
    end

    # The panes currently shown, in layout order.
    def visible_panes : Array(Pane)
      Pane.values.select { |pane| widget(pane).visible? }
    end

    # Shows *pane* and returns its widget, so a caller can `.focus` it. The
    # pane's `Show` handler (see `#initialize`) brings its content up to
    # date, as it does for a show from the View menu.
    def show_pane(pane : Pane) : Crysterm::Widget
      w = widget(pane)
      w.show
      w
    end

    # Hides *pane*, unless it is the only one shown. Focus moves to the first
    # remaining pane when the hidden one held it. Returns whether it was hidden.
    def hide_pane(pane : Pane) : Bool
      w = widget(pane)
      return false unless w.visible?
      remaining = visible_panes.reject { |other| other == pane }
      return false if remaining.empty?
      had_focus = w.focused?
      w.hide
      widget(remaining.first).focus if had_focus
      true
    end

    # The key gesture of a pane's function key: a hidden or unfocused pane is
    # shown and focused; the focused pane is hidden.
    def toggle_pane(pane : Pane) : Nil
      w = widget(pane)
      if w.visible? && w.focused?
        hide_pane pane
      else
        show_pane(pane).focus
      end
    end

    # View → Menu and Status Bars (`F4`): whether the two bars are shown. A
    # reactive property, so the menu entry binds to it (`#build_menus`) and
    # the config keeps it (`app_config.cr`); `#bars?` and `#bars=` are its
    # plain face. Hidden, the panes take the whole terminal, as a text
    # editor's distraction-free view does; the entries' keys (`Ctrl-O`,
    # `Ctrl-S`…) keep working, where the bar's own `F10` and `Alt` letters
    # do not, and a question asked in place of the status bar shows the bar
    # for as long as it is open (`app_dialogs.cr`).
    @bars : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)

    def bars? : Bool
      @bars.value
    end

    # Shows or hides the menu bar and the status bar together.
    def bars=(value : Bool) : Bool
      @bars.value = value
    end

    # The key gesture of `F4`: the bars hidden when shown, shown when hidden.
    def toggle_bars : Nil
      self.bars = !bars?
    end

    # Puts the property on the two bars (from `#initialize`, on change). A
    # question up in place of the status bar keeps the bar until it is
    # answered, as it shows the bar in the first place (`app_dialogs.cr`).
    private def apply_bars : Nil
      shown = @bars.value
      @main.menu_bar.visible = shown
      @main.status_bar.visible = shown || @main.status_bar.prompting?
    end

    # Jumps to the heading *url* names (`"#anchor"`, as the table of contents
    # emits): the viewer goes to the heading, and the editor to the source
    # line it was rendered from, on the same viewport row — a link followed
    # (`app_links.cr`).
    def jump_to(url : String) : Nil
      follow_link url
    end

    def sync_cursor? : Bool
      @sync_cursor.value
    end

    # Turns the syncing on or off (View → Sync Cursor). Turning it on
    # aligns the panes at once, from the focused one (the property's change
    # handler, in `#initialize`).
    def sync_cursor=(value : Bool) : Bool
      @sync_cursor.value = value
    end

    def highlight_line? : Bool
      @highlight_line.value
    end

    # Turns the caret-line highlight on or off (View → Highlight Line) in
    # both panes (the property's change handler, in `#initialize`).
    def highlight_line=(value : Bool) : Bool
      @highlight_line.value = value
    end

    def line_numbers? : Bool
      @line_numbers.value
    end

    # Shows or hides the editor's line numbers (View → Line Numbers →
    # Editor).
    def line_numbers=(value : Bool) : Bool
      @line_numbers.value = value
    end

    def viewer_line_numbers? : Bool
      @viewer_line_numbers.value
    end

    # Shows or hides the viewer's line numbers (View → Line Numbers →
    # Viewer).
    def viewer_line_numbers=(value : Bool) : Bool
      @viewer_line_numbers.value = value
    end

    # The viewer position rendered from editor position *pos*: the start of
    # the first block imported from the caret's source line — or, for a line
    # that rendered nothing, from the nearest line above that did — plus the
    # caret's offset from that line's start, kept within the block. A caret
    # above everything rendered maps to the top.
    def viewer_position(pos : Int32) : Int32
      edoc = @editor.document
      vdoc = @viewer.document
      line = edoc.block_at(pos).index + 1
      return 0 unless block = vdoc.find_block_by_source_line(line)
      offset = pos - edoc.block_position((block.source_line || line) - 1)
      block.position + offset.clamp(0, block.size)
    end

    # The editor position viewer position *pos* was rendered from: the start
    # of its block's source line plus the caret's offset within the block,
    # kept within the lines the block was rendered from (up to the line
    # before the next rendered block's). Inside a generated block (a table
    # border, a quote's blank line) the nearest imported block above counts.
    def editor_position(pos : Int32) : Int32
      edoc = @editor.document
      vdoc = @viewer.document
      loc = vdoc.block_at(pos)
      return 0 unless line = vdoc.source_line_at(loc.index)
      return edoc.size if line > edoc.block_count
      start = edoc.block_position(line - 1)
      offset = vdoc.blocks[loc.index].source_line ? loc.offset : 0
      limit = edoc.size
      if (next_line = vdoc.next_source_line_after(loc.index)) && next_line - 1 < edoc.block_count
        limit = edoc.block_position(next_line - 1) - 1
      end
      (start + offset).clamp(start, Math.max(start, limit))
    end

    # After a pane was shown: the panes aligned, the status (and the View
    # menu's entries) refreshed.
    private def pane_shown : Nil
      sync_carets
      track_toc # the outline may have changed while the pane was hidden
      refresh_status
    end

    # Aligns the panes from the focused one, when syncing.
    private def sync_carets : Nil
      if @editor.focused?
        sync_to_editor
      elsif @viewer.focused?
        sync_to_viewer
      end
    end

    # Puts the viewer's caret where the editor's is rendered, on the same
    # viewport row. The viewer's own move reports back through its handler,
    # which ignores it (the viewer is not the focused pane).
    private def sync_to_editor : Nil
      return unless @sync_cursor.value && @viewer.visible? && @editor.visible?
      pos = viewer_position(@editor.cursor_position)
      @viewer.text_cursor = Crysterm::TextCursor.new(@viewer.document, pos)
      align_rows @editor, @viewer
    end

    # Puts the editor's caret on the source of the viewer's, on the same
    # viewport row.
    private def sync_to_viewer : Nil
      return unless @sync_cursor.value && @editor.visible? && @viewer.visible?
      pos = editor_position(@viewer.cursor_position)
      @editor.text_cursor = Crysterm::TextCursor.new(@editor.document, pos)
      align_rows @viewer, @editor
    end

    # Keeps the table of contents on the heading the reader is under
    # (`TocView#track`, an outline view's "synchronize with editor"): the
    # section the editor's caret is in while editing — its source position
    # mapped to the viewer's — and the viewer's caret otherwise, so the entry
    # of the heading above the caret is selected, or its nearest shown
    # ancestor while the branch is collapsed. From the panes' caret handlers;
    # a selection, not a jump, so nothing moves but the highlight.
    private def track_toc : Nil
      pos = @editor.focused? ? viewer_position(@editor.cursor_position) : @viewer.cursor_position
      @toc.track pos
    end

    # Scrolls *follower* so its caret sits on the same viewport row as
    # *leader*'s: editing in the middle of one pane shows the matching text
    # in the middle of the other (`#text_cursor=` alone scrolls just enough
    # to bring the caret to an edge).
    private def align_rows(leader : Crysterm::Widget, follower : Crysterm::Widget) : Nil
      follower.scroll_cursor_to_row leader.cursor_viewport_row
    end

    # Writes the document to its file, the file's previous contents kept as
    # a backup the first time (`app_autosave.cr`). Without a file name (a
    # new or streamed document) nothing is written yet: `#save_as_prompt`
    # asks for one, and the save follows the answer.
    #
    # The document is saved for every window showing it: one write, one
    # backup, the modified flag cleared in each; the notice is this
    # window's, which took the action.
    def save : Bool
      unless path = source.path
        save_as_prompt
        return false
      end
      saved path, @document.save(@backup_file.value)
    rescue ex : IO::Error
      notice "Cannot save #{path}: #{Md.error_text(ex)}"
      false
    end

    # A save's end: the status and the notice, naming a backup that failed.
    private def saved(path : String, backup_failure : String?) : Bool
      refresh_status
      notice(backup_failure ? "Saved #{path} (#{backup_failure})" : "Saved #{path}")
      true
    end

    # Asks for a file name (`#ask_text`, in place of the status bar or in
    # a dialog), the current name filled in, and saves under the answer
    # (`#save_as`); a cancelled or empty answer saves nothing. *done* hears
    # whether a save happened.
    def save_as_prompt(&done : Bool ->) : Nil
      ask_text("Save as: ", source.path || "") do |answer|
        path = answer.try &.strip
        done.call(path && !path.empty? ? save_as(path) : false)
      end
    end

    # :ditto:
    def save_as_prompt : Nil
      save_as_prompt { }
    end

    # Saves to *path* and makes it the document's file, in every window
    # showing it (`Document#save_as`; Watch File follows the document to
    # the new file). A save that fails (a directory that is not there, no
    # permission) leaves the document its old name, as Qt's editors set the
    # current file only once written.
    #
    # A file another window has open as another document is written over
    # only when that document has no unsaved changes, which the write would
    # lose: then its windows come over to this document (`#merge`), so the
    # file is one document again. With changes there, nothing is written.
    def save_as(path : String) : Bool
      other = Documents.find(path)
      other = nil if other.same?(@document)
      if other && other.text.modified?
        notice "#{other.name} has unsaved changes in another window"
        return false
      end
      failure = @document.save_as(path, @backup_file.value)
      merge other if other
      renamed
      saved path, failure
    rescue ex : IO::Error
      notice "Cannot save #{path}: #{Md.error_text(ex)}"
      false
    end

    # Brings the windows on *other* — an unmodified document of the file
    # this one was just saved as — over to this document, each keeping its
    # caret's line and column (clamped); *other*, left by its last window,
    # closes, and this document takes the file's key in the registry.
    private def merge(other : Document) : Nil
      other.views.dup.each do |view|
        line, column = view.source_position
        view.switch_document @document
        view.go_to_line line, column
      end
      Documents.rekey @document, nil
    end

    # Whether the document is streaming in (`Document#streaming?`).
    def streaming? : Bool
      @document.streaming?
    end

    # Reads *io* into the document as it arrives (`Document#start_stream`),
    # line by line, each line going to every window on the document. The
    # viewer follows the tail while it was already at the bottom, so new
    # text scrolls into view until the reader scrolls up.
    def stream(io : IO) : Nil
      @viewer.follow_tail = true
      @document.start_stream io
    end

    # Takes a streamed *chunk* of Markdown into the document
    # (`Document#receive`), which hands it to every window on it; this
    # window, on its own render fiber, appends it at once
    # (`#stream_appended`). A document that is no stream takes nothing.
    def receive(chunk : String) : Nil
      @document.receive chunk if @document.from_stream?
    end

    # The end of the stream (`Document#finish_stream`), for every window on
    # the document.
    def finish_stream : Nil
      @document.finish_stream if @document.from_stream?
    end

    # A streamed *chunk* for this window: appended to the viewer, and taken
    # into the status bar's counts (`#text_appended`) rather than measured
    # whole again, so a long stream costs each line its own length here
    # too; a `--line` waiting for the chunk is taken.
    private def stream_appended(chunk : String) : Nil
      return if @window.destroyed?
      @viewer.append_markdown chunk
      text_appended chunk
      jump_to_pending_line if (line = @pending_line) && line > 0 && line_rendered?(line)
      refresh_status
    end

    # The end of the stream for this window, with the error *message* that
    # cut it short: whatever the stream left incomplete is flushed, and a
    # `--line` the stream never reached, or that counts from the end, is
    # taken now that the end is known.
    private def stream_ended(message : String?) : Nil
      return if @window.destroyed?
      notice "Stream ended: #{message}" if message
      @viewer.flush_markdown
      @viewer.document.refresh_tocs
      highlight_matches Pane::Viewer
      jump_to_pending_line
      refresh_status
    end

    # Whether the viewer has rendered source line *line* of the stream: a
    # block starts on it, or a block from above it runs past it, a later
    # block being in. Crysterm's stream holds a construct back until the
    # blank line that ends it (and a list or a quote until something follows
    # it), so a line the editor's text already has may be in no block yet;
    # jumping then would leave the viewer on the nearest block above
    # (`#viewer_position`), where the jump of a file lands on the line.
    private def line_rendered?(line : Int32) : Bool
      vdoc = @viewer.document
      return false unless index = vdoc.block_from_source_line(line)
      vdoc.blocks[index].source_line == line || !vdoc.next_source_line_after(index).nil?
    end

    # `--line` on a stream, once the line has arrived or the stream ended:
    # the editor is brought up to date first, as `#go_to_line` counts the
    # editor's lines (and follows the rest of the stream from then on), and
    # the jump is the one a file gets. The viewer stays on the line rather
    # than following the tail: the line asked for is usually the last block
    # rendered yet, its view at the bottom, which follow-tail would scroll
    # away from on the next chunk (a jump at the stream's end has no tail
    # left to follow).
    private def jump_to_pending_line : Nil
      return unless line = @pending_line
      @pending_line = nil
      fill_editor if @document.editor_stale?
      go_to_line line
      @viewer.follow_tail = false
    end

    # Brings the editor up to date with the streamed text (`Document#fill`),
    # the viewer already showing it.
    private def fill_editor : Nil
      @document.fill self
    end

    # An edit made in this window: the document now holds the truth; the
    # viewer follows, now or when it is next shown. Run at once in the
    # window that edited (its editor's `TextChanged`, and md's own edits
    # after they change the text); the other windows on the document catch
    # up through `#document_changed`.
    private def edited : Nil
      @seen_revision = @document.revision
      text_changed
      highlight_matches Pane::Editor
      if @viewer.visible? || @toc.visible?
        render_viewer
      else
        @viewer_stale = true
      end
      refresh_status
    end

    # Re-renders the viewer from the editor text, keeping the reader's place
    # (a plain `set_markdown` rewinds to the top).
    private def render_viewer : Nil
      @viewer.set_markdown markdown, keep_view: true
      @viewer_stale = false
      highlight_matches Pane::Viewer
      # The viewer's caret kept its offset, not its place in the changed
      # text; an edit that left the editor's caret in place (a Delete)
      # reports no move to re-place it; the outline under the caret may have
      # changed too.
      sync_to_editor if @editor.focused?
      track_toc
    end

    # Application-level keys, after the focused widget had its turn, and not
    # while a question is up (`#asking?`): a `q` at the unsaved-changes
    # question must not quit over it. The menu entries' keys are not here:
    # they are the entries' shortcuts (`app_menu.cr`), which Crysterm fires
    # on the same terms.
    private def key_pressed(e : Crysterm::Event::KeyPress) : Nil
      return if e.accepted? || asking?
      # The pager's keys are letters the editor would have typed, so they
      # reach here only from the viewer or the table of contents.
      handled = (key = e.key) ? app_key(key) : pager_key(e.char)
      e.accept if handled
    end

    # The application's special keys — the way out of a divider being
    # moved, the panes' navigation keys and `Ctrl-N` while its entry is
    # disabled (`app_windows.cr`); returns whether *key* was one. The other
    # keys no menu entry has are named actions' shortcuts
    # (`#build_key_actions`).
    private def app_key(key : Tput::Key) : Bool
      case key
      when .ctrl_n?          then refuse_new_window
      when .enter?, .escape? then leave_divider
      else                        navigation_key(key)
      end
    end

    # What `Ctrl-Z` does outside the editor: the shell's suspend
    # (`Crysterm.suspend`, which hands the terminal back and stops the
    # process until `fg`). Raw mode keeps the key from the shell, so the app
    # does it for it; the editor's `Ctrl-Z` is its undo and never gets here.
    # Replaceable, so a spec can see the key without stopping the process.
    property suspender : Proc(Nil) = -> { Crysterm.suspend }

    private def suspend : Nil
      @suspender.call
    end

    # The pager keys of the viewer, each running a command
    # (`app_commands.cr`): `/` and `?` search, `n` and `N` repeat the
    # search, `:` is the command line (a number goes to that line), `[` and
    # `]` jump between headings, `q` quits — md's quit, which closes every
    # window through its guard, where Crysterm's default quit key (which `q`
    # is too, kept live while a pane reads input, and which stands down once
    # the key is taken here) asks this window alone. Returns whether *char*
    # was one.
    private def pager_key(char : Char) : Bool
      return false unless name = PAGER_KEYS[char]?
      run_command name
      true
    end

    PAGER_KEYS = {
      '/' => "find", '?' => "find-backward", 'n' => "find-next", 'N' => "find-previous",
      ':' => "command", '[' => "previous-heading", ']' => "next-heading", 'q' => "quit",
    }
  end
end
