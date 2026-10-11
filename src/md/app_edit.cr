module Md
  # The source pane: Crysterm's plain text editor (Qt's `QPlainTextEdit`)
  # with a hook ahead of its keys. `#key_filter` sees every key press first
  # and returns whether it took the key; a taken key is accepted and goes no
  # further — the editor would otherwise type the newline `Enter` stands
  # for, and `Tab` would move the focus. Overriding the editor's key
  # handling is how Qt does it too (`keyPressEvent`, returning without
  # calling the base); a handler subscribed on the widget would not do,
  # since the editor's own handling runs whether or not an earlier handler
  # accepted the key. `App#markdown_key` is the filter (`app_edit.cr`).
  class MarkdownEdit < Crysterm::Widget::PlainTextEdit
    property key_filter : Proc(Crysterm::Event::KeyPress, Bool)?

    def _listener(e : Crysterm::Event::KeyPress)
      if (filter = @key_filter) && !read_only? && filter.call(e)
        e.accept
        return
      end
      super
    end
  end

  class App
    # Markdown-aware editing: the syntax the editor knows, on top of
    # Crysterm's plain text editor — which, like Qt's `QPlainTextEdit`, has
    # no Markdown mode of its own.
    #
    # Lists. `Enter` on a list item — `- `, `* `, `+ `, `1. ` or `1) `, a
    # task `- [ ] ` or `- [x] `, indented or inside a blockquote `> ` — with
    # the caret past the marker continues the list: a new line with the same
    # indentation and marker, the number one higher and the task box empty,
    # taking along whatever followed the caret. On an empty item, the marker
    # alone, `Enter` ends the list instead, removing the marker, as editors
    # do (Qt's `QTextEdit` takes an empty item out of its list). `Tab` and
    # `Shift-Tab` on a list item, or on a selection with one in it, indent
    # and outdent the lines (Format → Indent and Outdent): an item nests
    # under the nearest item above it at the same or a shallower level, by
    # that item's content offset — two columns for `- `, three for `1. ` —
    # which is what CommonMark asks of a child list, so a bullet under
    # `1. step` is indented by three; outdenting goes back to the
    # indentation of the nearest shallower item, or to the margin. Every
    # line of the selection moves by the same amount, continuation lines
    # included. On any other line `Enter` and `Tab` keep their meanings: a
    # newline, and focus to the next pane.
    #
    # Format → Task Box gives a list item a task box, or takes off the one
    # it has: `- item` ⇄ `- [ ] item`. Format → Check Task (`Alt-X`) ticks
    # the box and unticks it, `- [ ] item` ⇄ `- [x] item`; an item without
    # a box gets one ticked. Format → Bold, Italic and Code (`Ctrl-B`, `Alt-I`,
    # `Alt-C`) wrap the selection — or the word at the caret, or, with
    # neither, a pair the caret is put between — in `**`, `*` and backticks,
    # and take them off again from text that has them (`_` and `__` count
    # too), a toggle; the text stays selected, so a second press undoes the
    # first. Format → Promote Heading and Demote Heading (`Ctrl-Up`,
    # `Ctrl-Down`) move the caret's line one heading level up or down, a
    # paragraph being the level above `#` and `######` the last.
    #
    # The keys: `Ctrl-B` is Qt's bold, and the editor does not use it. Qt's
    # `Ctrl-I` is out of reach — a terminal sends the same byte for `Ctrl-I`
    # and `Tab` — and so is `Ctrl-Shift-X`, which a terminal does not tell
    # from `Ctrl-X`, so Italic, Code and Check Task take `Alt` chords the
    # editor leaves alone (`Alt-B` and `Alt-F` are readline's word moves
    # there). The list keys are the editor's own (`MarkdownEdit#key_filter`),
    # taken ahead of its editing keys and only on list lines, so they are
    # not menu shortcuts and Indent and Outdent show none.
    #
    # Every change is one edit of the editor's document — one undo step —
    # and goes through `#edited` like typing, so the viewer follows. The
    # Format entries work from any pane: from the viewer they act on the
    # editor at the source of the viewer's caret, showing the editor when
    # it is hidden.

    # A list item line taken apart: the blockquote markers before it (`>`
    # with the spacing between them; empty outside a quote), its
    # indentation, its marker, the spacing after the marker, its task box
    # with the spacing after it (nil without one) and its text.
    record ListItem, quote : String, indent : String, marker : String, spacing : String, task : String?, text : String do
      # A bullet or an ordered marker (nine digits at most, as CommonMark
      # allows) followed by spacing or the line's end — so `*emphasis*` and
      # `---` are not items — then a task box when it too is followed by
      # spacing or the end.
      PATTERN = /\A(?<quote>(?:[ \t]*>)*)(?<indent>[ \t]*)(?<marker>[-*+]|\d{1,9}[.)])(?:(?<spacing>[ \t]+)(?<task>\[[ xX]\](?:[ \t]+|$))?(?<text>.*))?\z/

      def self.parse(line : String) : ListItem?
        m = PATTERN.match(line) || return
        new m["quote"], m["indent"], m["marker"], m["spacing"]? || "", m["task"]?, m["text"]? || ""
      end

      # The marker (and task box) alone.
      def empty? : Bool
        text.empty?
      end

      # Columns from the marker to the item's content: a child list indented
      # this far from the marker belongs to the item (a task box is content).
      def content_offset : Int32
        marker.size + spacing.size
      end

      # The characters before the text.
      def prefix_size : Int32
        quote.size + indent.size + content_offset + (task.try(&.size) || 0)
      end

      # The marker of the item after this one: the next number, or the same
      # bullet.
      def next_marker : String
        return marker unless marker[0].ascii_number?
        "#{marker[0...-1].to_i + 1}#{marker[-1]}"
      end
    end

    # The blockquote markers a line starts with.
    QUOTE = /\A(?:[ \t]*>)*/

    # A line's heading prefix: what precedes the hashes (blockquote markers,
    # indentation), then the hashes with their spacing when there are any.
    HEADING = /\A(?<lead>(?:[ \t]*>)*[ \t]*)(?:(?<hashes>\#{1,6})(?:[ \t]+|$))?/

    # Format → Bold: `**` around the selection or the word at the caret, or
    # off again. Returns whether anything changed.
    def toggle_bold : Bool
      toggle_wrap "**"
    end

    # Format → Italic: `*`, likewise.
    def toggle_italic : Bool
      toggle_wrap "*"
    end

    # Format → Code: backticks, likewise.
    def toggle_code : Bool
      toggle_wrap "`"
    end

    # Format → Task Box: a task box on the caret's list item, or on every
    # list item of the selection — `[ ] ` added to an item without one, and
    # taken off an item that has one. Returns whether there was an item,
    # with a notice when there was not.
    def toggle_task_box : Bool
      edit_task_items do |doc, box, item|
        if task = item.task
          Crysterm::TextCursor.new(doc, box, box + task.size).remove_selected_text
        else
          Crysterm::TextCursor.new(doc, box).insert_text(item.spacing.empty? ? " [ ] " : "[ ] ")
        end
      end
    end

    # Format → Check Task: the box ticked when empty and emptied when
    # ticked, on the same items; an item without a box gets a ticked one,
    # so a plain item is done in one key. Likewise.
    def check_task : Bool
      edit_task_items do |doc, box, item|
        if task = item.task
          Crysterm::TextCursor.new(doc, box + 1, box + 2).insert_text(task[1] == ' ' ? "x" : " ")
        else
          Crysterm::TextCursor.new(doc, box).insert_text(item.spacing.empty? ? " [x] " : "[x] ")
        end
      end
    end

    # Format → Indent and Outdent, and `Tab`/`Shift-Tab` in the editor: the
    # caret's line, or the selection's lines, moved one list level in
    # (*direction* 1) or out (-1); see the class comment. Returns whether a
    # list item was among the lines — nothing else is indented, so `Tab`
    # keeps moving focus elsewhere.
    def indent_list(direction : Int32) : Bool
      editor = formatting_editor
      doc = editor.document
      first, last = selected_blocks
      found = (first..last).each do |i|
        if item = ListItem.parse(doc.blocks[i].text)
          break({i, item})
        end
      end
      return false unless found
      index, item = found
      target = direction > 0 ? nested_indent(index, item) : outdented_indent(index, item)
      delta = target - item.indent.size
      return true if delta == 0
      doc.edit do
        (first..last).each do |i|
          block = doc.blocks[i]
          text = block.text
          next if text.blank?
          quote = QUOTE.match(text).try(&.[0].size) || 0
          start = block.position + quote
          if delta > 0
            Crysterm::TextCursor.new(doc, start).insert_text " " * delta
          else
            room = text.size - quote - text[quote..].lstrip(" \t").size
            Crysterm::TextCursor.new(doc, start, start + Math.min(-delta, room)).remove_selected_text
          end
        end
        nil
      end
      edited
      true
    end

    # Format → Promote Heading: the caret's line one level up (`##` → `#`;
    # `#` → a paragraph). Returns whether it could go up, with a notice
    # when not.
    def promote_heading : Bool
      shift_heading -1
    end

    # Format → Demote Heading: one level down (a paragraph → `#`, `#` →
    # `##`, down to `######`).
    def demote_heading : Bool
      shift_heading 1
    end

    # Gives the editor its Markdown keys (from `#wire_panes`).
    private def wire_editing : Nil
      @editor.key_filter = ->(e : Crysterm::Event::KeyPress) { markdown_key e }
    end

    # The editor's keys that know the syntax, ahead of its own: `Enter` on a
    # list item, `Tab` and `Shift-Tab` on list lines. Returns whether the
    # key was taken.
    private def markdown_key(e : Crysterm::Event::KeyPress) : Bool
      case e.key
      when Tput::Key::Enter    then continue_list
      when Tput::Key::Tab      then indent_list 1
      when Tput::Key::ShiftTab then indent_list -1
      else                          false
      end
    end

    # The Format menu, between Edit and View (from `#build_menus`).
    private def build_format_menu(bar : Crysterm::Widget::MenuBar) : Nil
      format = bar.add_menu "For&mat"
      format.add_action("&Bold", shortcut: "Ctrl+B") { toggle_bold }
      format.add_action("&Italic", shortcut: "Alt+I") { toggle_italic }
      format.add_action("&Code", shortcut: "Alt+C") { toggle_code }
      format.add_separator
      format.add_action("&Task Box") { toggle_task_box }
      format.add_action("Chec&k Task", shortcut: "Alt+X") { check_task }
      format.add_action("I&ndent") { indent_list(1) || notice "Not a list item" }
      format.add_action("&Outdent") { indent_list(-1) || notice "Not a list item" }
      format.add_separator
      format.add_action("&Promote Heading", shortcut: "Ctrl+Up") { promote_heading }
      format.add_action("&Demote Heading", shortcut: "Ctrl+Down") { demote_heading }
    end

    # `Enter` on a list item with the caret past the marker: the item
    # continued below, or the list ended when the item is empty. Returns
    # whether that was the case; a selection is left to the editor, which
    # replaces it with the newline.
    private def continue_list : Bool
      return false if @editor.selection?
      cursor = @editor.text_cursor
      block = cursor.block
      item = ListItem.parse(block.text) || return false
      return false if cursor.position_in_block < item.prefix_size
      doc = @editor.document
      if item.empty?
        # The marker goes, and the indentation with it; the quote stays.
        cursor = Crysterm::TextCursor.new(doc, block.position, block.position + block.size)
        cursor.insert_text(item.quote.empty? ? "" : "#{item.quote} ")
      else
        # The text after the caret starts the new item, less the space that
        # separated it from the text before.
        prefix = "#{item.quote}#{item.indent}#{item.next_marker}#{item.spacing}#{item.task ? "[ ] " : ""}"
        rest = block.text[cursor.position_in_block..].lstrip(' ')
        at = cursor.position
        cursor = Crysterm::TextCursor.new(doc, at, block.position + block.size)
        cursor.insert_text "\n#{prefix}#{rest}"
        cursor.set_position at + 1 + prefix.size
      end
      @editor.text_cursor = cursor
      edited
      true
    end

    # The indentation of a child of the nearest item above line *index* at
    # *item*'s level or a shallower one (in the same quote): that item's
    # indentation plus its content offset. Without one, *item* is its own
    # measure.
    private def nested_indent(index : Int32, item : ListItem) : Int32
      parent = item_above(index) { |other| other.quote == item.quote && other.indent.size <= item.indent.size }
      parent ||= item
      parent.indent.size + parent.content_offset
    end

    # The indentation of the nearest shallower item above line *index* (in
    # the same quote), or the margin.
    private def outdented_indent(index : Int32, item : ListItem) : Int32
      parent = item_above(index) { |other| other.quote == item.quote && other.indent.size < item.indent.size }
      parent ? parent.indent.size : 0
    end

    # The first list item above line *index*, searching upward, that *fits*.
    private def item_above(index : Int32, &fits : ListItem -> Bool) : ListItem?
      doc = @editor.document
      (index - 1).downto(0) do |i|
        item = ListItem.parse(doc.blocks[i].text) || next
        return item if fits.call item
      end
      nil
    end

    # The list items the caret's line or the selection's lines hold, each
    # yielded with the document and the position of its task box — where
    # the box is, or where one would go, after the marker's spacing — for
    # the block to edit, all in one undo step. Returns whether there was an
    # item, with a notice when there was not. The position is taken as each
    # item's turn comes, so an earlier item's edit has already moved it.
    private def edit_task_items(& : Crysterm::TextDocument, Int32, ListItem ->) : Bool
      editor = formatting_editor
      doc = editor.document
      first, last = selected_blocks
      items = (first..last).compact_map do |i|
        (item = ListItem.parse(doc.blocks[i].text)) ? {i, item} : nil
      end
      if items.empty?
        notice "Not a list item"
        return false
      end
      doc.edit do
        items.each do |i, item|
          at = doc.blocks[i].position + item.quote.size + item.indent.size + item.content_offset
          yield doc, at, item
        end
        nil
      end
      edited
      true
    end

    # Wraps the selection — or the word at the caret — in *marker*, or
    # unwraps it, and leaves the text selected; with nothing to wrap,
    # inserts the pair and puts the caret between. Returns true.
    private def toggle_wrap(marker : String) : Bool
      editor = formatting_editor
      doc = editor.document
      cursor = editor.text_cursor
      cursor.select :word_under_cursor unless cursor.selection?
      unless cursor.selection?
        cursor.insert_text marker * 2
        cursor.set_position cursor.position - marker.size
        editor.text_cursor = cursor
        edited
        return true
      end
      from, to = widen(doc, cursor.selection_start, cursor.selection_end, marker[0])
      if depth = wrapped_depth(doc.plain_text(from, to), marker)
        doc.edit do
          Crysterm::TextCursor.new(doc, to - depth, to).remove_selected_text
          Crysterm::TextCursor.new(doc, from, from + depth).remove_selected_text
          nil
        end
        to -= 2 * depth
      else
        doc.edit do
          Crysterm::TextCursor.new(doc, to).insert_text marker
          Crysterm::TextCursor.new(doc, from).insert_text marker
          nil
        end
        from += marker.size
        to += marker.size
      end
      editor.text_cursor = Crysterm::TextCursor.new(doc, from, to)
      edited
      true
    end

    # *from*...*to* grown over the *mark* characters on both sides of it —
    # the markers around a selected word — by up to three (`***`), one for
    # a backtick. `_` stands in for `*`.
    private def widen(doc : Crysterm::TextDocument, from : Int32, to : Int32, mark : Char) : {Int32, Int32}
      (mark == '`' ? 1 : 3).times do
        break unless from > 0 && to < doc.size
        before = doc.plain_text(from - 1, from)
        break unless before == doc.plain_text(to, to + 1) && emphasis_char?(before[0], mark)
        from -= 1
        to += 1
      end
      {from, to}
    end

    # How many characters *marker*'s wrapping takes off each end of *text*,
    # or nil when *text* is not wrapped in it: two for bold from `**bold**`
    # and `***both***`, one for italic from `*it*` and `***both***` but none
    # from `**bold**`, one for code from `` `code` ``.
    private def wrapped_depth(text : String, marker : String) : Int32?
      first = text[0]? || return
      return unless emphasis_char?(first, marker[0])
      lead = text.each_char.take_while(&.==(first)).size
      trail = text.reverse.each_char.take_while(&.==(first)).size
      run = {lead, trail, 3}.min
      return if text.size < 2 * run
      case marker
      when "**" then run >= 2 ? 2 : nil
      when "*"  then run.odd? ? 1 : nil
      else           1
      end
    end

    # Whether *char* is *mark* or its spelling variant (`_` for `*`).
    private def emphasis_char?(char : Char, mark : Char) : Bool
      char == mark || (mark == '*' && char == '_')
    end

    # The caret's line moved *by* heading levels: its hashes replaced.
    private def shift_heading(by : Int32) : Bool
      editor = formatting_editor
      doc = editor.document
      block = editor.text_cursor.block
      m = HEADING.match(block.text) || return false
      level = m["hashes"]?.try(&.size) || 0
      target = level + by
      if target > 6
        notice "No heading level below 6"
        return false
      elsif target < 0
        notice "Not a heading"
        return false
      end
      from = block.position + m["lead"].size
      Crysterm::TextCursor.new(doc, from, block.position + m[0].size).insert_text(target == 0 ? "" : "#" * target + " ")
      edited
      true
    end

    # The editor, for a Format entry: shown when it is hidden, and with the
    # viewer leading — the entry chosen while reading — its caret put on the
    # source of the viewer's, so the entry acts on what the reader looks at.
    private def formatting_editor : Crysterm::Widget::PlainTextEdit
      from_viewer = @viewer.focused?
      show_pane Pane::Editor unless @editor.visible?
      if from_viewer
        pos = editor_position(@viewer.cursor_position)
        @editor.text_cursor = Crysterm::TextCursor.new(@editor.document, pos)
      end
      @editor
    end

    # The lines the editor's caret or selection covers, as the first and
    # last block indices. A selection ending at a line's start leaves that
    # line out, as a whole-line selection ends there.
    private def selected_blocks : {Int32, Int32}
      doc = @editor.document
      cursor = @editor.text_cursor
      first = doc.block_at(cursor.selection_start).index
      last = doc.block_at(cursor.selection_end)
      {first, last.index > first && last.offset == 0 ? last.index - 1 : last.index}
    end
  end
end
