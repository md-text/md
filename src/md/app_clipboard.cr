module Md
  class App
    # Edit → Copy and Copy as Markdown, and Options → Clipboard: the way a
    # copy leaves md.
    #
    # Copy takes what the focused pane offers. In the editor, the selection,
    # or the caret's line when nothing is selected. In the viewer and the
    # table of contents, the viewer's selection, or the block the viewer's
    # caret is in — a paragraph, a heading, a list item, or a fenced code
    # block whole, every line of it — as plain text, the way it reads. Copy
    # as Markdown copies the source instead: the lines of the editor's text
    # the selected or current block was rendered from, fences included (the
    # importer stamps each block with its source line, `TextBlock#source_line`,
    # as Sync Cursor relies on); in the editor the text is the source
    # already, so it copies what Copy does. `Ctrl+C` is Copy's key: a pane
    # with a selection copies it itself (Crysterm's clipboard keys), and
    # with nothing selected the key reaches the entry.
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
    alias ClipboardMode = Crysterm::Application::Clipboard::Mode

    # A reactive property, so the Options → Clipboard entries bind to it
    # (`#build_menus`); `#clipboard_mode` and `#clipboard_mode=` are its
    # plain face. Applied to the clipboard as it changes (`#setup_clipboard`).
    @clipboard_mode : Crysterm::Reactive::Property(ClipboardMode) = Crysterm::Reactive::Property.new(ClipboardMode::Terminal)

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
      lines = text.count('\n') + 1
      amount = lines > 1 ? "#{lines} lines" : "#{text.size} #{text.size == 1 ? "character" : "characters"}"
      if error = clipboard.error
        notice "Copied #{amount} within md only: #{error}"
      else
        notice "Copied #{amount}"
      end
    end

    # The viewer blocks a copy takes, as a range of block indexes: the
    # blocks the selection touches, else the caret's block — a fenced code
    # block's line with the neighbouring lines of the same block, since a
    # code block renders as one block per line.
    private def viewer_block_span : Range(Int32, Int32)
      vdoc = @viewer.document
      if range = @viewer.selection_range
        return vdoc.block_at(range.begin).index..vdoc.block_at(range.end - 1).index
      end
      index = vdoc.block_at(@viewer.cursor_position).index
      return index..index unless code_block?(index)
      first = index
      while first > 0 && code_block?(first - 1)
        first -= 1
      end
      last = index
      while last + 1 < vdoc.block_count && code_block?(last + 1)
        last += 1
      end
      first..last
    end

    private def code_block?(index : Int32) : Bool
      @viewer.document.blocks[index].block_format.code_block?
    end

    # The plain text of the current block (`#viewer_block_span`), its lines
    # joined by newlines.
    private def current_block_text : String
      blocks = @viewer.document.blocks
      viewer_block_span.join('\n') { |index| blocks[index].text }
    end

    # The Markdown source of the current block (`#viewer_block_span`): the
    # lines from its first block's source line up to the line before the
    # next rendered block's, less what is not the block's own — the blank
    # lines after it, and the fence that opens a following code block (a
    # fence line renders nothing, so no block is stamped with it) — and,
    # for a code block, with its fences: the opening one above the stamped
    # first line and the closing one after the last. Empty for a block that
    # came from no source line (a table border, a quote's blank line, with
    # nothing stamped above it).
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
    # the first block's line to the line before the next rendered block's —
    # for a code block, no further than its closing fence. Nil when no line
    # is stamped at or above the span, or none is left.
    private def source_line_range(span : Range(Int32, Int32), source : Array(String)) : {Int32, Int32}?
      vdoc = @viewer.document
      return unless from = vdoc.source_line_at(span.begin)
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
  end
end
