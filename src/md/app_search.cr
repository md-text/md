module Md
  class App
    # Searching and jumping — the pager's keys, asked like Save As
    # (`app_dialogs.cr`: in place of the status bar, or in a dialog).
    #
    # Search: `/` (forward) and `?` (backward) in the viewer or the table of
    # contents, `Ctrl-F` anywhere (Edit → Find…), ask for a pattern; `n` and
    # `N` (`Ctrl-G` and `Alt-G` anywhere, Edit → Find Next and Find Previous)
    # repeat it in the search's direction and against it. The pane in use is
    # searched: the editor's Markdown source while
    # editing, the viewer's rendered text otherwise. The pattern is a
    # regular expression when it compiles and literal text when it does not,
    # case-insensitive unless it has an uppercase letter (vi's `smartcase`).
    # The search wraps around with a notice, as vi's does. Every match is
    # underlined (`ExtraSelection`s, re-made as the text changes) and the
    # current one is the pane's selection; Edit → Clear Search Highlights takes the
    # underlines off until the next search, `n` included (vi's `:nohlsearch`).
    #
    # Go to line (`:` in the viewer, `Ctrl-L` anywhere, Edit → Go to Line…)
    # asks for a source line and puts both panes there; `[` and `]` in the
    # viewer (`Alt-Up` and `Alt-Down` anywhere, Edit → Previous Heading and
    # Next Heading) jump to the previous and next heading.
    #
    # Replace (`Alt-H` anywhere, Edit → Replace…) is vi's `:s///c` at the
    # same prompt: it asks for the pattern (the last search's by default)
    # and for the replacement, then steps through the matches from the
    # caret, each selected in the editor and asked about — `y` replaces it,
    # `n` leaves it, `a` replaces it and every other one, `q` stops — with
    # the search's rules for the pattern and its wrap-around. It works on
    # the Markdown source, the editor being the source of truth, so from
    # the viewer it shows and focuses the editor first. Every replacement
    # goes through a `TextCursor`, so `Ctrl-Z` undoes it; `a` is one undo
    # step, as Qt's `QTextCursor::beginEditBlock` groups one. In the
    # replacement `\1`–`\9` stand for the pattern's groups and `\0` for
    # the whole match, as in Crystal's `String#sub`. Qt's key for Replace,
    # `Ctrl-H`, is a byte the terminal cannot tell from Backspace (both
    # erase in the editor), hence `Alt-H`.

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
    # Whether the matches are underlined: from a search until Clear Search
    # Highlights, which lasts until the next search — `n` is one, as it is
    # for vi's `:nohlsearch` — so an edit meanwhile neither brings the
    # underlines back nor pays for the scan that would.
    @highlighting = false

    # A replace in progress: what the matches become, where it started (so
    # the wrap-around stops there), whether it has wrapped, whether it found
    # a match at all, and how many matches it replaced.
    private class Replacement
      getter replacement : String
      property origin : Int32
      property? wrapped = false
      property? found = false
      property count = 0

      def initialize(@replacement, @origin)
      end
    end

    @replacing : Replacement?
    # The single-key handler on the prompt's field while the replace
    # question is up, and the key it took.
    @replace_key : EventHandler::Subscription?
    @replace_answer : String?

    # Asks for a pattern (`#ask_text`) and searches for it; an empty or
    # cancelled answer searches nothing.
    def search_prompt(backward : Bool = false) : Nil
      ask_text(backward ? "?" : "/", "", question: backward ? "Find backward:" : "Find:") do |answer|
        search answer, backward if answer && !answer.empty?
      end
    end

    # Searches for *pattern* from the caret, in the given direction, and
    # highlights its matches in both panes. Returns whether a match was found.
    def search(pattern : String, backward : Bool = false) : Bool
      @search_pattern = pattern
      @search_backward = backward
      @search_regex = compile_pattern pattern
      @highlighting = true
      highlight_matches_everywhere
      # Linked windows take the search even when no match moved the caret.
      mark_view_moved
      find_next
    end

    # Moves to the next match in the search's direction, or against it with
    # *reverse*, wrapping around the document with a notice; the underlines
    # come back when they were cleared. Returns whether a match was found;
    # without a search yet it says so and returns false.
    def find_next(reverse : Bool = false) : Bool
      unless regex = @search_regex
        notice "No previous search"
        return false
      end
      unless @highlighting
        @highlighting = true
        highlight_matches_everywhere
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

    # Asks for a pattern (the last search's filled in) and a replacement
    # (`#ask_text`), one after the other, and replaces (`#replace`); an
    # empty or cancelled pattern, or a cancelled replacement, does nothing.
    def replace_prompt : Nil
      ask_text("Replace: ", @search_pattern || "") do |pattern|
        next if pattern.nil? || pattern.empty?
        ask_text("With: ", "") do |replacement|
          replace pattern, replacement if replacement
        end
      end
    end

    # Replaces matches of *pattern* (the search's rules) with *replacement*
    # in the editor, shown and focused, match by match from the caret with
    # a question at each (`#ask_replace`) — or, with *all*, every one from
    # the caret around to it again, unasked. The pattern becomes the
    # search's, so `n` finds what was left.
    def replace(pattern : String, replacement : String, all : Bool = false) : Nil
      # A question still up (a replace started over one) is answered with
      # nothing first, so its session ends before this one begins.
      @main.status_bar.line_prompt.cancel if @main.status_bar.prompting?
      end_replace
      show_pane(Pane::Editor).focus unless @editor.focused?
      @search_pattern = pattern
      @search_backward = false
      @search_regex = compile_pattern pattern
      @highlighting = true
      highlight_matches_everywhere
      # A selection (the last search's match, say) is where the first match
      # is looked for, not past.
      if @editor.selection?
        @editor.text_cursor = Crysterm::TextCursor.new(@editor.document, @editor.text_cursor.selection_start)
      end
      @replacing = Replacement.new replacement, @editor.cursor_position
      all ? replace_rest : replace_step
    end

    # How many matches the replace in progress has replaced.
    def replace_count : Int32
      @replacing.try(&.count) || 0
    end

    # Selects the next match and asks about it; without one, finishes.
    private def replace_step : Nil
      next_replace_match ? ask_replace : end_replace
    end

    # The question at a match, in place of the status bar, answered by one
    # key: the prompt's field takes the key as text, and a handler
    # registered after the prompt's own listener — so it runs once the key
    # is in — hands it over, submitting an empty answer (which the field's
    # Up/Down history skips). Escape and a bare Enter come as `nil` and
    # `""`. A key typed before the question is up goes into the editor.
    private def ask_replace : Nil
      prompt = @main.status_bar.line_prompt
      status_prompt("Replace? (y)es (n)o (a)ll (q)uit ", "") { |text| replace_answered text }
      field = prompt.field
      @replace_key = field.on(Crysterm::Event::KeyPress) do |e|
        next if e.key || !e.char.in?('y', 'n', 'a', 'q')
        @replace_answer = e.char.to_s
        field.value = ""
        field.submit
      end
    end

    # The answer to the question: the key it was answered with, else the
    # text (`nil` for Escape; anything else asks again).
    private def replace_answered(text : String?) : Nil
      @replace_key.try &.off
      @replace_key = nil
      answer = @replace_answer || text
      @replace_answer = nil
      return end_replace unless answer && @replacing
      case answer
      when "y"
        replace_match
        replace_step
      when "n" then replace_step
      when "a" then replace_rest
      when "q" then end_replace
      else          ask_replace
      end
    end

    # Replaces the selected match (the one `#next_replace_match` selected):
    # one undo step, the caret left after the new text. The editor reports
    # its own edits (`TextChanged`), not a `TextCursor`'s, so the change is
    # reported here (`#edited`: the viewer re-rendered, the highlight and
    # the status refreshed).
    private def replace_match : Nil
      return unless (session = @replacing) && (regex = @search_regex) && @editor.selection?
      doc = @editor.document
      start = @editor.text_cursor.selection_start
      return unless (match = regex.match(doc.to_plain_text, start)) && match.begin(0) == start
      text = expand_replacement session.replacement, match
      cursor = Crysterm::TextCursor.new(doc, start, match.end(0))
      cursor.insert_text text
      @editor.text_cursor = cursor
      session.count += 1
      # Past the wrap the start is ahead of the caret and moves with the
      # text before it.
      session.origin += text.size - match[0].size if session.wrapped?
      edited
    end

    # Replaces every match left — from the caret to the end, then from the
    # top to where the replace started — in one undo step, reported once
    # (`#edited`, as in `#replace_match`). The matches come from one scan of
    # the text, each one's position shifted by what the replacements before
    # it changed, rather than from a scan per match; the caret is put after
    # the last replacement once, not moved — and the other pane with it —
    # at every match.
    private def replace_rest : Nil
      return unless (session = @replacing) && (regex = @search_regex)
      doc = @editor.document
      ahead, behind = matches_left session, regex, doc.to_plain_text
      notice "Search hit BOTTOM, continuing at TOP" if ahead.empty? && !behind.empty?
      session.found = true unless ahead.empty? && behind.empty?
      last = nil
      doc.edit do
        {ahead, behind}.each do |group|
          delta = 0
          group.each do |match|
            replacement = expand_replacement session.replacement, match
            cursor = Crysterm::TextCursor.new(doc, match.begin(0) + delta, match.end(0) + delta)
            cursor.insert_text replacement
            last = cursor
            delta += replacement.size - match[0].size
            session.count += 1
          end
        end
        nil
      end
      @editor.text_cursor = last if last
      edited if session.found?
      end_replace
    end

    # The matches *session* has left in *text*, in the order it visits
    # them: those from the caret — or the selected match, the one being
    # asked about — to the end, or up to where it started once it has
    # wrapped, and those from the top to where it started, empty once it
    # has wrapped.
    private def matches_left(session : Replacement, regex : Regex, text : String) : {Array(Regex::MatchData), Array(Regex::MatchData)}
      from = @editor.selection? ? @editor.text_cursor.selection_start : @editor.cursor_position
      ahead = [] of Regex::MatchData
      behind = [] of Regex::MatchData
      each_match(regex, text) do |match|
        start = match.begin(0)
        if start >= from
          ahead << match unless session.wrapped? && start >= session.origin
        elsif start < session.origin && !session.wrapped?
          behind << match
        end
      end
      {ahead, behind}
    end

    # Selects the next match for the replace: from the caret (past a
    # selected match) to the end, then — wrapping with the search's notice —
    # from the top to where the replace started. Returns whether there was
    # one; without, the replace is over.
    private def next_replace_match : Bool
      return false unless (session = @replacing) && (regex = @search_regex)
      doc = @editor.document
      text = doc.to_plain_text
      from = @editor.selection? ? @editor.text_cursor.selection_end : @editor.cursor_position
      match = first_match(regex, text, from)
      match = nil if match && session.wrapped? && match.begin(0) >= session.origin
      unless match
        return false if session.wrapped?
        session.wrapped = true
        match = first_match(regex, text)
        return false unless match && match.begin(0) < session.origin
        notice "Search hit BOTTOM, continuing at TOP"
      end
      @editor.text_cursor = Crysterm::TextCursor.new(doc, match.begin(0), match.end(0))
      session.found = true
      true
    end

    # Ends the replace with its tally — the search's miss when it found
    # nothing at all.
    private def end_replace : Nil
      @replace_key.try &.off
      @replace_key = nil
      @replace_answer = nil
      return unless session = @replacing
      @replacing = nil
      if session.found?
        notice "#{session.count} replacement#{"s" unless session.count == 1}"
      else
        notice "Pattern not found: #{@search_pattern}"
      end
    end

    # Yields the non-empty matches of *regex* in *text* from *from* on, in
    # order and without overlap: what the highlight shows, and what a
    # replace steps through (an empty match would be replaced at the same
    # spot forever).
    private def each_match(regex : Regex, text : String, from : Int32 = 0, & : Regex::MatchData ->) : Nil
      pos = from
      while match = regex.match(text, pos)
        s = match.begin(0)
        e = match.end(0)
        yield match if e > s
        pos = e > s ? e : s + 1
      end
    end

    # The first of `#each_match`'s matches, if any.
    private def first_match(regex : Regex, text : String, from : Int32 = 0) : Regex::MatchData?
      each_match(regex, text, from) { |match| return match }
      nil
    end

    # What a match becomes: *replacement* with `\0`–`\9` standing for the
    # match and its groups (nothing for a group that did not take part) and
    # `\\` for a backslash, as `String#sub` reads them; any other `\` stays.
    private def expand_replacement(replacement : String, match : Regex::MatchData) : String
      return replacement unless replacement.includes? '\\'
      chars = replacement.chars
      String.build do |io|
        i = 0
        while i < chars.size
          c = chars[i]
          n = chars[i + 1]?
          if c == '\\' && n && n.ascii_number?
            io << match[n - '0']?
            i += 2
          elsif c == '\\' && n == '\\'
            io << '\\'
            i += 2
          else
            io << c
            i += 1
          end
        end
      end
    end

    # Takes the match highlight off both panes, until the next search or
    # `n`; the pattern stays.
    def clear_search_highlight : Nil
      @highlighting = false
      Pane.each { |pane| set_match_selections pane, [] of Crysterm::Widget::TextEdit::ExtraSelection }
      mark_view_moved # linked windows clear theirs too
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

    # Asks for a source line (`#ask_text`) and goes there.
    def go_to_line_prompt : Nil
      ask_text(":", "", question: "Go to line:") do |answer|
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
    # table of contents jump does, the editor on the heading's source line;
    # the table of contents follows as it does any move (`#track_toc`).
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
                outline.reverse_each.find { |e| e.block < block }
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
    # an edit, a stream chunk or a re-render replaced the text under it —
    # while the matches are highlighted at all.
    private def highlight_matches(pane : Pane = search_pane) : Nil
      regex = @search_regex
      return unless regex && @highlighting
      doc = pane.editor? ? @editor.document : @viewer.document
      text = doc.to_plain_text
      format = Crysterm::TextCharFormat.new(underline: true)
      selections = [] of Crysterm::Widget::TextEdit::ExtraSelection
      each_match(regex, text) do |match|
        break if selections.size >= MAX_HIGHLIGHTS
        selections << Crysterm::Widget::TextEdit::ExtraSelection.new(Crysterm::TextCursor.new(doc, match.begin(0), match.end(0)), format)
      end
      set_match_selections pane, selections
    end

    # Both panes' overlays remade (the panes share the pattern, not the text).
    private def highlight_matches_everywhere : Nil
      return unless @search_regex && @highlighting
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
