module Md
  class App
    # Edit → Copy and Copy as Markdown, and Options → Clipboard: the way a
    # copy leaves md.
    #
    # Copy takes what the focused pane offers. In the editor, the selection,
    # or the caret's line when nothing is selected. In the viewer and the
    # table of contents, the viewer's selection, or the block the viewer's
    # caret is in — a paragraph, a heading, a list item, or a fenced code
    # block or a table whole, every line of it — as plain text, the way it
    # reads. Copy as Markdown copies the source instead: the lines of the
    # editor's text the selected or current block was rendered from, fences
    # included (the importer stamps each block with its source line,
    # `TextBlock#source_line`, as Sync Cursor relies on); in the editor the
    # text is the source already, so it copies what Copy does. `Ctrl+C` is
    # Copy's key: a pane with a selection copies it itself (Crysterm's
    # clipboard keys), and with nothing selected the key reaches the entry.
    #
    # Where a copy goes is the clipboard mode (`ClipboardMode`, Crysterm's
    # `Application::Clipboard::Mode`): the terminal's clipboard escape,
    # OSC 52, which most terminals forward to the system clipboard; a
    # system command — `pbcopy`, `wl-copy`, `xclip`, `xsel`, or tmux's
    # buffer, whichever is found — for where the escape does not get
    # through (tmux and screen without passthrough, SSH, terminals that
    # ignore it); or md alone, for a terminal that garbles the escape. The
    # mode is the application clipboard's, so the editor's own `Ctrl-C`,
    # `Ctrl-X` and `Ctrl-V` follow it too: in Command mode a paste reads the
    # paired command (`pbpaste`, `wl-paste`, `xclip -o`…), and in every
    # mode the terminal's own paste works, as bracketed paste. Whatever the
    # mode, copy and paste within md work through the in-process clipboard.
    #
    # Edit → Paste (`#paste`, `Ctrl+V`) pastes the clipboard as the mode
    # reads it, into the editor at the caret, replacing a selection, as one
    # undo step. In the editor `Ctrl-V` is the editor's own paste and does
    # the same; from the viewer or the table of contents the key reaches
    # the entry, which shows and focuses the editor with its caret on the
    # source of the viewer's (`#formatting_editor`, as the Format entries
    # do) and pastes there. Edit → Paste Special (`#paste_from_terminal`,
    # `#paste_from_command`, `#paste_from_internal`, `#paste_from_kill_ring`)
    # names the source instead of leaving it to the mode, the way editors'
    # "Paste from…" menus do (`QTextEdit` has none; emacs has `yank-pop`):
    # the terminal's clipboard, asked for through OSC 52 and pasted when the
    # terminal answers, or given up on with a notice after
    # `#terminal_paste_timeout`, since many terminals never answer a read;
    # the paste command's output (`pbpaste`, `wl-paste`…), an entry that
    # cannot be picked when none was found; the in-process buffer, what md
    # itself last copied; and the editor's kill ring — what `Ctrl-K`,
    # `Ctrl-U` and `Alt-D` killed — as a submenu remade each time the Edit
    # menu opens (`Event::AboutToShow`), most recent first, numbered
    # `1`–`9` and `0` for the tenth, so `Ctrl-Y`'s entry is `1` and any
    # older one is a pick away, a `yank-pop` without the cycling.
    alias ClipboardMode = Crysterm::Application::Clipboard::Mode

    # A reactive property, so the Options → Clipboard entries bind to it
    # (`#build_menus`); `#clipboard_mode` and `#clipboard_mode=` are its
    # plain face. Applied to the clipboard as it changes (`#setup_clipboard`).
    @clipboard_mode : Crysterm::Reactive::Property(ClipboardMode) = Crysterm::Reactive::Property.new(ClipboardMode::Terminal)

    # How long a paste from the terminal waits for the OSC 52 answer before
    # it is given up on with a notice.
    TERMINAL_PASTE_TIMEOUT = 2.seconds

    # How many kill ring entries the From Kill Ring submenu lists, and how
    # many columns of each it shows.
    KILL_RING_MENU_MAX = 10
    KILL_RING_PREVIEW  = 40

    # The wait for the terminal's answer to the next paste from it (specs
    # shorten it).
    property terminal_paste_timeout : Time::Span = TERMINAL_PASTE_TIMEOUT

    # A paste from the terminal in flight: the window handler waiting for
    # the answer, the timer that gives up on it, and the request's number,
    # so a timer that fires after its request was answered reports nothing.
    @terminal_paste : EventHandler::Subscription?
    @terminal_paste_timer : Crysterm::Timer?
    @terminal_paste_request = 0
    # The From Kill Ring submenu's action, remade as the Edit menu opens.
    @kill_ring_action : Crysterm::Action?

    def clipboard_mode : ClipboardMode
      @clipboard_mode.value
    end

    def clipboard_mode=(mode : ClipboardMode) : ClipboardMode
      @clipboard_mode.value = mode
    end

    # The application clipboard the panes copy to and paste from
    # (Crysterm's `Application::Clipboard`, one per process), whose mode md
    # sets. The window's application, or the global one when the window has
    # none (a headless window in specs), as the panes themselves look it up.
    def clipboard : Crysterm::Application::Clipboard
      (@window.application || Crysterm::Application.global).clipboard
    end

    # Edit → Copy; see the class comment. Copies nothing, with a notice,
    # from an empty block.
    def copy : Nil
      if @editor.focused?
        if @editor.selection?
          @editor.copy
          copied @editor.selected_text
        else
          copy_text @editor.document.find_block(@editor.cursor_position).text
        end
      elsif @viewer.selection?
        # The viewer's own copy carries its formats along for a paste
        # within md.
        @viewer.copy
        copied @viewer.selected_text
      else
        copy_text current_block_text
      end
    end

    # Edit → Copy as Markdown; see the class comment.
    def copy_as_markdown : Nil
      if @editor.focused?
        copy
      else
        copy_text current_source_text
      end
    end

    # Edit → Paste; see the class comment. In Command mode a paste command
    # that fails, or none found, pastes nothing, with the clipboard's word
    # on why.
    def paste : Nil
      text = clipboard.text
      if error = clipboard.error
        notice "Cannot paste: #{error}"
        return
      end
      paste_text text
    end

    # Paste Special → From Terminal Clipboard; see the class comment. The
    # terminal is asked (`Window#request_clipboard`, OSC 52) and the paste
    # waits for its answer, which arrives on the input as
    # `Event::ClipboardChanged`; a request still waiting when the next is
    # made is dropped.
    def paste_from_terminal : Nil
      end_terminal_paste
      request = @terminal_paste_request += 1
      @terminal_paste = @window.on(Crysterm::Event::ClipboardChanged) do |e|
        end_terminal_paste
        paste_text e.content
      end
      @terminal_paste_timer = @window.after(@terminal_paste_timeout) do
        # The timer fires on its own fiber; the editor is touched on the
        # render fiber, where the answer may have landed meanwhile.
        @window.post do
          next unless @terminal_paste && request == @terminal_paste_request
          end_terminal_paste
          notice "The terminal did not answer the clipboard request"
        end
      end
      @window.request_clipboard
      notice "Asking the terminal for its clipboard…"
    end

    # Paste Special → From Command: the paste command's output, whatever
    # the mode; a command that fails pastes nothing, with a notice.
    def paste_from_command : Nil
      unless argv = clipboard.paste_command
        notice "No clipboard command found"
        return
      end
      if text = clipboard.command_runner.call(argv, "")
        paste_text text
      else
        notice "Cannot paste: #{argv[0]} failed"
      end
    end

    # Paste Special → From Internal Buffer: what md last copied, or last
    # received from the terminal, whatever the mode.
    def paste_from_internal : Nil
      paste_text clipboard.internal_text
    end

    # The editor's kill ring, most recent entry first: `#paste_from_kill_ring`
    # takes an index into this.
    def kill_ring_entries : Array(String)
      @editor.kill_ring.entries.reverse
    end

    # Paste Special → From Kill Ring: pastes entry *index* of
    # `#kill_ring_entries` — 0 is the most recent, what `Ctrl-Y` yanks.
    def paste_from_kill_ring(index : Int32 = 0) : Nil
      unless text = kill_ring_entries[index]?
        notice(index == 0 ? "Nothing killed yet" : "No kill ring entry #{index + 1}")
        return
      end
      paste_text text
    end

    # Pastes *text* into the editor — shown and focused, its caret on the
    # source of the viewer's when the viewer led — at the caret, replacing
    # the selection, as one undo step (`#insert_text`, what typing it would
    # do), and says how much. Nothing to paste is a notice.
    private def paste_text(text : String) : Nil
      if text.empty?
        notice "Nothing to paste"
        return
      end
      editor = formatting_editor
      editor.focus unless editor.focused?
      editor.insert_text text
      notice "Pasted #{amount text}"
    end

    # Takes down a paste from the terminal still waiting: answered, given
    # up on, or superseded.
    private def end_terminal_paste : Nil
      @terminal_paste.try &.off
      @terminal_paste = nil
      @terminal_paste_timer.try &.stop
      @terminal_paste_timer = nil
    end

    # The Edit menu's Paste and Paste Special entries (from `#build_menus`).
    # The Command entry names the command found, like Options → Clipboard's,
    # and cannot be picked when there is none; the kill ring submenu starts
    # empty and is filled as the menu opens.
    private def add_paste_actions(edit : Crysterm::Widget::Menu) : Nil
      # `Ctrl+V` reaches the entry from a pane that does not paste itself
      # (the editor's own `Ctrl-V` is its paste).
      named "paste", tip edit.add_action("&Paste", shortcut: "Ctrl+V") { paste }, "Paste the clipboard into the editor at the caret, as the clipboard mode reads it"
      terminal = Crysterm::Action.new "From &Terminal Clipboard", name: "paste-from-terminal"
      terminal.on(Crysterm::Event::Triggered) { paste_from_terminal }
      tip terminal, "Paste what the terminal's clipboard holds, asked for through OSC 52"
      argv = clipboard.paste_command
      command = Crysterm::Action.new "From &Command (#{argv ? argv[0] : "none found"})", name: "paste-from-command"
      command.enabled = !argv.nil?
      command.on(Crysterm::Event::Triggered) { paste_from_command }
      tip command, (argv ? "Paste the output of #{argv[0]}, the paste command found on this system" : "No paste command was found on this system")
      internal = Crysterm::Action.new "From &Internal Buffer", name: "paste-from-internal"
      internal.on(Crysterm::Event::Triggered) { paste_from_internal }
      tip internal, "Paste what md itself last copied"
      ring = Crysterm::Action.new "From &Kill Ring"
      ring.enabled = false
      tip ring, "Paste a text killed in the editor with Ctrl-K, Ctrl-U or Alt-D, the most recent first"
      @kill_ring_action = ring
      tip edit.add_submenu("Paste &Special", [terminal, command, internal, ring]), "Paste from a source named here rather than the one the clipboard mode reads"
      edit.on(Crysterm::Event::AboutToShow) { refresh_kill_ring_menu }
    end

    # Remakes the From Kill Ring submenu from the ring as the Edit menu
    # opens (Qt's `aboutToShow`): the entries most recent first, up to
    # `KILL_RING_MENU_MAX`, each numbered and previewed; the entry is
    # disabled while the ring is empty.
    private def refresh_kill_ring_menu : Nil
      return unless action = @kill_ring_action
      actions = kill_ring_entries.first(KILL_RING_MENU_MAX).map_with_index do |text, index|
        a = Crysterm::Action.new "&#{(index + 1) % 10} #{kill_preview text}"
        a.on(Crysterm::Event::Triggered) { paste_from_kill_ring index }
        tip a, "Paste this killed text into the editor at the caret"
      end
      action.menu = actions
      action.enabled = !actions.empty?
    end

    # A kill ring entry on one menu row: its line breaks shown as `⏎`, cut
    # to `KILL_RING_PREVIEW` columns, and its `&` kept from reading as a
    # mnemonic.
    private def kill_preview(text : String) : String
      line = literal_label text.gsub('\n', '⏎')
      line.size > KILL_RING_PREVIEW ? "#{line[0, KILL_RING_PREVIEW - 1]}…" : line
    end

    # Puts the mode on the clipboard now and whenever it changes.
    private def setup_clipboard : Nil
      clipboard.mode = @clipboard_mode.value
      @clipboard_mode.on_change { clipboard.mode = @clipboard_mode.value }
    end

    # Copies *text* through the clipboard, routed to this window's terminal
    # (`Clipboard#copy`'s window: the copy must reach the terminal md runs
    # on, not another window's), and says so.
    private def copy_text(text : String) : Nil
      if text.empty?
        notice "Nothing to copy"
        return
      end
      clipboard.copy text, @window
      copied text
    end

    # The notice for a copy of *text*: its lines when there are several,
    # else its characters — and, when the clipboard could not pass it on
    # (Command mode without a working command), that it stayed within md.
    private def copied(text : String) : Nil
      if error = clipboard.error
        notice "Copied #{amount text} within md only: #{error}"
      else
        notice "Copied #{amount text}"
      end
    end

    # How much *text* is, for a notice: its lines when there are several,
    # else its characters.
    private def amount(text : String) : String
      lines = text.count('\n') + 1
      lines > 1 ? "#{lines} lines" : "#{text.size} #{text.size == 1 ? "character" : "characters"}"
    end

    # The viewer blocks a copy takes, as a range of block indexes: the
    # blocks the selection touches, else the caret's block — a fenced code
    # block's line or a table's row with the neighbouring lines of the same
    # block, since a code block renders as one block per line and a table
    # as one per row and border.
    private def viewer_block_span : Range(Int32, Int32)
      vdoc = @viewer.document
      if range = @viewer.selection_range
        return vdoc.block_at(range.begin).index..vdoc.block_at(range.end - 1).index
      end
      index = vdoc.block_at(@viewer.cursor_position).index
      return index..index unless code_block?(index) || table?(index)
      first = index
      while first > 0 && same_block?(first - 1, index)
        first -= 1
      end
      last = index
      while last + 1 < vdoc.block_count && same_block?(last + 1, index)
        last += 1
      end
      first..last
    end

    private def code_block?(index : Int32) : Bool
      @viewer.document.blocks[index].block_format.code_block?
    end

    private def table?(index : Int32) : Bool
      !@viewer.document.blocks[index].block_format.table_format.nil?
    end

    # Whether viewer blocks *index* and *other* render lines of the same
    # code block, or rows of the same table (whose blocks share one
    # `TextTableFormat`, the table's identity).
    private def same_block?(index : Int32, other : Int32) : Bool
      blocks = @viewer.document.blocks
      if table = blocks[other].block_format.table_format
        blocks[index].block_format.table_format.same? table
      else
        code_block?(index)
      end
    end

    # The plain text of the current block (`#viewer_block_span`), its lines
    # joined by newlines — the way it reads: a table row whose cells wrap
    # gives its display lines (`TextDocumentFragment#to_plain_text`).
    private def current_block_text : String
      doc = @viewer.document
      span = viewer_block_span
      from = doc.block_position(span.begin)
      to = doc.block_position(span.end) + doc.blocks[span.end].size
      doc.copy_fragment(from, to).to_plain_text
    end

    # The Markdown source of the current block (`#viewer_block_span`): the
    # lines from its first block's source line up to the line before the
    # next rendered block's, less what is not the block's own — the blank
    # lines after it, and the fence that opens a following code block (a
    # fence line renders nothing, so no block is stamped with it) — and,
    # for a code block, with its fences: the opening one above the stamped
    # first line and the closing one after the last. Empty for a span that
    # holds no block stamped with a source line (a quote's blank line on
    # its own).
    private def current_source_text : String
      span = viewer_block_span
      source = markdown.lines
      return "" unless range = source_line_range(span, source)
      from, to = range
      lines = source[(from - 1)..(to - 1)]
      lines.unshift source[from - 2] if code_block?(span.begin) && from > 1 && fence?(source[from - 2])
      trim_blank_tail lines
      unless code_block?(span.end)
        lines.pop if lines.size > 1 && fence?(lines.last)
        trim_blank_tail lines
      end
      lines.join('\n')
    end

    # The first and last source line (1-based) of viewer blocks *span*: from
    # the first stamped block's line (a table's top border is stamped with
    # none; its header row is) to the line before the next rendered block's
    # — for a code block, no further than its closing fence. Nil when no
    # block of the span is stamped, or no line is left.
    private def source_line_range(span : Range(Int32, Int32), source : Array(String)) : {Int32, Int32}?
      vdoc = @viewer.document
      return unless from = span.each.compact_map { |index| vdoc.blocks[index].source_line }.first?
      to = Math.min((vdoc.next_source_line_after(span.end) || source.size + 1) - 1, source.size)
      if code_block?(span.end) && (last = vdoc.blocks[span.end].source_line)
        to = Math.min(to, last < source.size && fence?(source[last]) ? last + 1 : last)
      end
      to < from ? nil : {from, to}
    end

    private def trim_blank_tail(lines : Array(String)) : Nil
      while lines.size > 1 && lines.last.blank?
        lines.pop
      end
    end

    # Whether source *line* opens or closes a fenced code block.
    private def fence?(line : String) : Bool
      stripped = line.lstrip
      stripped.starts_with?("```") || stripped.starts_with?("~~~")
    end

    private def clipboard_label(mode : ClipboardMode) : String
      case mode
      in .terminal? then "&Terminal (OSC 52)"
      in .command?  then "&Command (#{(command = clipboard.copy_command) ? command[0] : "None Found"})"
      in .internal? then "&Internal (Within md)"
      end
    end

    private def clipboard_tip(mode : ClipboardMode) : String
      case mode
      in .terminal? then "Copy and paste through the terminal's clipboard escape, OSC 52"
      in .command?  then (command = clipboard.copy_command) ? "Copy and paste through #{command[0]}, the command found on this system" : "No copy command was found on this system"
      in .internal? then "Copy and paste within md alone, for a terminal that garbles the escape"
      end
    end
  end
end
