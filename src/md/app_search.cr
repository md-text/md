module Md
  class App
    # Searching and jumping — the pager's keys, in place of the status bar
    # like Save As.
    #
    # Search: `/` (forward) and `?` (backward) in the viewer or the table of
    # contents, `Ctrl-F` anywhere, ask for a pattern; `n` and `N` (`Ctrl-G`
    # and `Alt-G` anywhere) repeat it in the search's direction and against
    # it. The pane in use is searched: the editor's Markdown source while
    # editing, the viewer's rendered text otherwise. The pattern is a
    # regular expression when it compiles and literal text when it does not,
    # case-insensitive unless it has an uppercase letter (vi's `smartcase`).
    # The search wraps around with a notice, as vi's does. Every match is
    # underlined (`ExtraSelection`s, re-made as the text changes) and the
    # current one is the pane's selection; Edit → Clear Highlight takes the
    # underlines off (vi's `:nohlsearch`).
    #
    # Go to line (`:` in the viewer, `Ctrl-L` anywhere) asks for a source
    # line and puts both panes there; `[` and `]` in the viewer (`Alt-Up` and
    # `Alt-Down` anywhere) jump to the previous and next heading.

    # The most matches highlighted at once: beyond this a search still finds
    # its way, match by match, but the overlay stops, so an edit in a long
    # document is not followed by a scan of thousands of matches.
    MAX_HIGHLIGHTS = 500

    # The last pattern searched, as entered, and its compiled form; `nil`
    # before the first search or after `#clear_search`.
    getter search_pattern : String?
    @search_regex : Regex?
    # The direction the last search was given with (`?` and `N` backward).
    getter? search_backward : Bool = false
    # The overlays this search put on each pane, so re-highlighting replaces
    # ours and leaves the pane's own (the viewer's focused link) alone.
    @match_selections = {} of Pane => Array(Crysterm::Widget::TextEdit::ExtraSelection)

    # Asks for a pattern in place of the status bar and searches for it;
    # an empty or cancelled answer searches nothing.
    def search_prompt(backward : Bool = false) : Nil
      @main.status_bar.prompt(backward ? "?" : "/", "") do |answer|
        search answer, backward if answer && !answer.empty?
      end
    end

    # Searches for *pattern* from the caret, in the given direction, and
    # highlights its matches in both panes. Returns whether a match was found.
    def search(pattern : String, backward : Bool = false) : Bool
      @search_pattern = pattern
      @search_backward = backward
      @search_regex = compile_pattern pattern
      highlight_matches_everywhere
      find_next
    end

    # Moves to the next match in the search's direction, or against it with
    # *reverse*, wrapping around the document with a notice. Returns whether a
    # match was found; without a search yet it says so and returns false.
    def find_next(reverse : Bool = false) : Bool
      unless regex = @search_regex
        notice "No previous search"
        return false
      end
      backward = @search_backward != reverse
      found = search_pane.editor? ? find_in(@editor, regex, backward) : find_in(@viewer, regex, backward)
      notice "Pattern not found: #{@search_pattern}" unless found
      found
    end

    # The search step in *w* (the editor or the viewer; untyped so each gets
    # its own compilation): the next match from the caret — past the
    # selection when the caret sits on a match — or, wrapping around, from
    # the document's far end, selected and scrolled into view.
    private def find_in(w, regex : Regex, backward : Bool) : Bool
      doc = w.document
      from = if backward
               w.selection? ? w.text_cursor.selection_start : w.cursor_position
             else
               w.selection? ? w.text_cursor.selection_end : w.cursor_position + 1
             end
      flags = backward ? Crysterm::TextDocument::FindFlag::Backward : Crysterm::TextDocument::FindFlag::None
      found = doc.find(regex, from: from.clamp(0, doc.size), flags: flags)
      unless found
        found = doc.find(regex, from: backward ? doc.size : 0, flags: flags)
        return false unless found
        notice(backward ? "Search hit TOP, continuing at BOTTOM" : "Search hit BOTTOM, continuing at TOP")
      end
      w.text_cursor = found
      true
    end

    # Takes the match highlight off both panes; the pattern stays for `n`.
    def clear_search_highlight : Nil
      Pane.each { |pane| set_match_selections pane, [] of Crysterm::Widget::TextEdit::ExtraSelection }
    end

    # Forgets the search: no highlight, no pattern for `n` to repeat.
    def clear_search : Nil
      clear_search_highlight
      @search_pattern = nil
      @search_regex = nil
    end

    # The pane a search applies to: the editor while it has focus (or is the
    # only text pane shown), else the viewer — also from the table of
    # contents, which shows the viewer's document.
    def search_pane : Pane
      if @editor.focused? || (!@viewer.visible? && @editor.visible?)
        Pane::Editor
      else
        Pane::Viewer
      end
    end

    # Asks for a source line in place of the status bar and goes there.
    def go_to_line_prompt : Nil
      @main.status_bar.prompt(":", "") do |answer|
        next unless answer
        text = answer.strip
        next if text.empty?
        if line = text.to_i?
          go_to_line line
        else
          notice "Not a line number: #{text}"
        end
      end
    end

    # Puts both panes on source line *line* (1-based, clamped to the
    # document; `0` and negative count from the end as `$`): the editor's
    # caret at *column*, the viewer on the block rendered from that line.
    # Each pane is centered on the spot.
    def go_to_line(line : Int32, column : Int32 = 1) : Nil
      edoc = @editor.document
      count = edoc.block_count
      line = count + line if line <= 0
      line = line.clamp(1, Math.max(1, count))
      start = edoc.block_position(line - 1)
      length = edoc.blocks[line - 1].size
      pos = start + (column - 1).clamp(0, length)
      @editor.text_cursor = Crysterm::TextCursor.new(edoc, pos)
      @editor.center_cursor
      @viewer.text_cursor = Crysterm::TextCursor.new(@viewer.document, viewer_position(pos))
      @viewer.center_cursor
    end

    # Jumps to the heading after the caret (`dir` 1) or before it (-1), in
    # both panes: the viewer lands with the heading on its top row as a
    # table of contents jump does, the editor on the heading's source line.
    # Returns whether there was one.
    def jump_heading(dir : Int32) : Bool
      vdoc = @viewer.document
      outline = vdoc.outline
      return false if outline.empty?
      vpos = @editor.focused? ? viewer_position(@editor.cursor_position) : @viewer.cursor_position
      block = vdoc.block_at(vpos).index
      entry = if dir > 0
                outline.find { |e| e.block > block }
              else
                outline.reverse.find { |e| e.block < block }
              end
      unless entry
        notice(dir > 0 ? "No heading below" : "No heading above")
        return false
      end
      @viewer.text_cursor = Crysterm::TextCursor.new(vdoc, vdoc.block_position(entry.block))
      @viewer.scroll_cursor_to_row 0
      if @editor.visible?
        @editor.text_cursor = Crysterm::TextCursor.new(@editor.document, editor_position(@viewer.cursor_position))
        align_rows @viewer, @editor if @viewer.visible?
      end
      true
    end

    # The search's overlay on *pane*, remade from the current text — after
    # an edit, a stream chunk or a re-render replaced the text under it.
    private def highlight_matches(pane : Pane = search_pane) : Nil
      regex = @search_regex
      return unless regex
      doc = pane.editor? ? @editor.document : @viewer.document
      text = doc.to_plain_text
      format = Crysterm::TextCharFormat.new(underline: true)
      selections = [] of Crysterm::Widget::TextEdit::ExtraSelection
      pos = 0
      while (m = regex.match(text, pos)) && selections.size < MAX_HIGHLIGHTS
        s = m.begin(0)
        e = s + m[0].size
        selections << Crysterm::Widget::TextEdit::ExtraSelection.new(Crysterm::TextCursor.new(doc, s, e), format) if e > s
        pos = e > s ? e : s + 1
      end
      set_match_selections pane, selections
    end

    # Both panes' overlays remade (the panes share the pattern, not the text).
    private def highlight_matches_everywhere : Nil
      return unless @search_regex
      highlight_matches Pane::Editor
      highlight_matches Pane::Viewer
    end

    # Swaps our overlays on *pane* for *selections*, keeping any others.
    private def set_match_selections(pane : Pane, selections : Array(Crysterm::Widget::TextEdit::ExtraSelection)) : Nil
      old = @match_selections[pane]?
      return if (old.nil? || old.empty?) && selections.empty?
      case pane
      in .editor? then swap_selections @editor, old, selections
      in .viewer? then swap_selections @viewer, old, selections
      in .toc?    then return
      end
      @match_selections[pane] = selections
    end

    # Replaces *old* among *w*'s overlays with *selections*.
    private def swap_selections(w, old, selections) : Nil
      others = old ? w.extra_selections.reject { |sel| old.includes? sel } : w.extra_selections
      w.extra_selections = others + selections
    end

    # The regular expression for *pattern*: the pattern itself when it is
    # one, the pattern as literal text when it is not (an unbalanced `(`
    # finds a `(`), case-insensitive unless it has an uppercase letter.
    private def compile_pattern(pattern : String) : Regex
      options = pattern.each_char.any?(&.uppercase?) ? Regex::Options::None : Regex::Options::IGNORE_CASE
      begin
        Regex.new(pattern, options)
      rescue ArgumentError
        Regex.new(Regex.escape(pattern), options)
      end
    end
  end
end
