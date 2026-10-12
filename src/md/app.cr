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
    getter source : Source

    # Text received from the stream. The editor is filled from it only when it
    # is shown (`@editor_stale`), so a long stream into a hidden editor costs
    # nothing per chunk.
    @streamed = IO::Memory.new
    @editor_stale = false
    # The line a streamed document was asked to open on (`--line`), until the
    # stream has it (`#jump_to_pending_line`).
    @pending_line : Int32?
    # The viewer was not re-rendered after the last edit (it was hidden).
    @viewer_stale = false
    # Set while the editor's text is replaced programmatically, so the
    # resulting `TextChanged` is not mistaken for a user edit.
    @loading = false
    getter? streaming : Bool = false
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
    def initialize(@source : Source, text : String = "", stream : IO? = nil,
                   view : Bool = !stream.nil? || !text.empty?, window : Crysterm::Window? = nil,
                   @history : History? = nil, @config : Bool = false, watch : Bool = false,
                   line : Int32? = nil)
      @window = window || Crysterm::Window.new(title: title)
      # A window handed in (Window → New's, a spec's) is titled as well.
      @window.title = title if window
      @window.always_propagated_chars << 'q'

      @main = Crysterm::Widget::MainWindow.new parent: @window
      @main.menu_bar # filled by `#build_menus`, once the panes exist
      @name_field = Crysterm::Widget::Label.new text: ""
      @position_field = Crysterm::Widget::Label.new text: "", width: POSITION_WIDTH
      @size_field = Crysterm::Widget::Label.new text: "", width: SIZE_WIDTH
      @encoding_field = Crysterm::Widget::Label.new text: "", width: ENCODING_WIDTH
      @modified_field = Crysterm::Widget::Label.new text: "", width: MODIFIED_WIDTH
      @overwrite_button = Crysterm::Widget::ToolButton.new text: "INS", width: 5
      @mouse_button = Crysterm::Widget::ToolButton.new text: "M=a", width: 7

      @editor = MarkdownEdit.new input_on_focus: true
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
      @window.on(Crysterm::Event::CloseRequest) do |e|
        next unless @confirm_discard.value && @editor.document.modified?
        e.ignore
        confirm_discard { @window.close }
      end
      # A pane coming on screen is brought up to date first — the editor from
      # a stream it missed, the viewer and table of contents from edits made
      # while they were hidden — then the panes are aligned and the status
      # refreshed. The keys (`#show_pane`) and the View menu (the panes'
      # `toggle_view_action`s) both show a pane through here.
      @editor.on(Crysterm::Event::Show) do
        fill_editor if @editor_stale
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
      @watch_file.on_change do
        setup_file
        refresh_status
      end
      wire_theme
      wire_media
      wire_toolkit
      wire_view
      wire_resizable
      wire_vi

      Pane.each { |pane| widget(pane).hide }
      load text unless text.empty?
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
      self.watch_file = watch
      wire_autosave
    end

    # The panes' own events: edits re-render, carets follow, the outline
    # jumps and tracks the viewer's document.
    private def wire_panes : Nil
      @editor.on(Crysterm::Event::TextChanged) { edited unless @loading }
      # The focused pane leads; the other pane's caret, set programmatically
      # to follow, reports a move too, which this guard keeps from bouncing.
      # The table of contents follows the leading pane's caret too: the
      # editor's while it has the focus, the viewer's otherwise.
      @editor.on(Crysterm::Event::CursorPositionChanged) do
        if @editor.focused?
          sync_to_editor
          track_toc
        end
      end
      @viewer.on(Crysterm::Event::CursorPositionChanged) do
        sync_to_viewer if @viewer.focused?
        track_toc unless @editor.focused?
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

    # The terminal's title: the document's name, then the program's —
    # `README.md • MD`, or `[No Name] • MD` for a document without one, as
    # Vim names it. Crysterm sends it on any terminal (one without titles
    # ignores it) and puts the terminal's own title back when md hands the
    # terminal back, at exit and while suspended.
    def title : String
      "#{document_name} • MD"
    end

    # The document's name as the title, the Window menu and the notices
    # about windows give it: the file's, `stdin` for a stream, or
    # `[No Name]`.
    def document_name : String
      @source.name || "[No Name]"
    end

    # The document's current Markdown source.
    def markdown : String
      @editor_stale ? @streamed.to_s : @editor.value
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
    def save : Bool
      unless path = @source.path
        save_as_prompt
        return false
      end
      backup_failure = backup path
      File.write path, markdown
      @editor.document.modified = false
      autosave_settled
      refresh_status
      notice(backup_failure ? "Saved #{path} (#{backup_failure})" : "Saved #{path}")
      true
    rescue ex : IO::Error
      notice "Cannot save #{path}: #{ex.message}"
      false
    end

    # Asks for a file name (`#ask_text`, in place of the status bar or in
    # a dialog), the current name filled in, and saves under the answer
    # (`#save_as`); a cancelled or empty answer saves nothing. *done* hears
    # whether a save happened.
    def save_as_prompt(&done : Bool ->) : Nil
      ask_text("Save as: ", @source.path || "") do |answer|
        path = answer.try &.strip
        done.call(path && !path.empty? ? save_as(path) : false)
      end
    end

    # :ditto:
    def save_as_prompt : Nil
      save_as_prompt { }
    end

    # Makes *path* the document's file and saves to it.
    def save_as(path : String) : Bool
      @source = Source.new path: path
      @window.title = title
      apply_base_url
      # Watch File follows the document: the watcher on the old path is
      # replaced by one on the new (`app_file.cr`).
      setup_file
      save
    end

    # Reads *io* in the background (`Window#pump`), line by line, feeding
    # each line to `#receive` on the render fiber and ending with
    # `#finish_stream`. The viewer follows the tail while it was already at
    # the bottom, so new text scrolls into view until the reader scrolls up.
    # A window destroyed under the stream ends the read, and Crysterm then
    # runs *ended* at once on the reader fiber: the app is torn down by then,
    # so nothing of it is touched.
    def stream(io : IO) : Nil
      @streaming = true
      @editor_stale = true
      @viewer.follow_tail = true
      ended = ->(error : IO::Error?) do
        unless @window.destroyed?
          notice "Stream ended: #{error.message}" if error
          finish_stream
        end
      end
      @window.pump(io, name: "md-stream", done: ended) { |line| receive line }
    end

    # Appends a streamed *chunk* of Markdown to the document — and to the
    # editor's text when the editor is shown. The status bar's counts take
    # the chunk in (`#text_appended`) rather than measure the whole text
    # again, so a long stream costs each line its own length here too. Must
    # run on the render fiber (see `Crysterm::Window#post`); a chunk that
    # arrives after the window was destroyed is dropped.
    def receive(chunk : String) : Nil
      return if @stream_abandoned || @window.destroyed?
      @streamed << chunk
      @viewer.append_markdown chunk
      append_to_editor chunk unless @editor_stale
      text_appended chunk
      jump_to_pending_line if (line = @pending_line) && line > 0 && line_rendered?(line)
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

    # Appends *chunk* to the editor's text at its end — an insertion, so a
    # long stream costs each line its own length rather than the whole
    # text's, and edits the user made meanwhile stay. Not a user edit: no
    # re-render, and the document's clean state is kept (a stream is not a
    # modification).
    private def append_to_editor(chunk : String) : Nil
      doc = @editor.document
      was_modified = doc.modified?
      @loading = true
      Crysterm::TextCursor.new(doc, doc.size).insert_text chunk
      @loading = false
      doc.modified = was_modified
    end

    # Flushes whatever the stream left incomplete; the end-of-stream signal.
    # A `--line` the stream never reached, or that counts from the end, is
    # taken now that the end is known. Nothing to do once the window is
    # destroyed.
    def finish_stream : Nil
      return if @stream_abandoned || @window.destroyed?
      @viewer.flush_markdown
      @viewer.document.refresh_tocs
      @streaming = false
      highlight_matches Pane::Viewer
      jump_to_pending_line
      refresh_status
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
      fill_editor if @editor_stale
      go_to_line line
      @viewer.follow_tail = false
    end

    # Replaces the editor text as a reset, not an edit: no undo entry, and no
    # re-render of the viewer (which already shows this text).
    private def load(text : String) : Nil
      @loading = true
      @editor.plain_text = text
      @loading = false
      @editor_stale = false
      @streamed.clear
      @viewer.set_markdown text
      @viewer_stale = false
      text_changed
    end

    # Brings the editor up to date with the streamed text.
    private def fill_editor : Nil
      @loading = true
      @editor.plain_text = @streamed.to_s
      @loading = false
      @editor_stale = false
    end

    # A user edit: the editor now holds the truth; the viewer follows, now or
    # when it is next shown.
    private def edited : Nil
      @editor_stale = false
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
