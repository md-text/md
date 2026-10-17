module Md
  class App
    # The Insert menu: templates of Markdown's syntax, put into the editor's
    # text where the caret is — the source of the viewer's caret while
    # reading (`#formatting_editor`), as the Format entries do. Each is one
    # undo step and leaves its first placeholder selected (`Heading`,
    # `Column 1`, `text`), so typing replaces it.
    #
    # A block — a heading, a table, a list, a quote, an alert, a rule — goes
    # on the caret's line when that is blank, and after the paragraph the
    # caret is in otherwise, with a blank line kept on each side so it
    # starts and ends as a block of its own (a `---` right under a line of
    # text would make that line a heading). Not inside a code block, where
    # it would be code. A link, an image and a footnote reference go in at
    # the caret, around the selection when there is one.
    #
    # Table → a size from a list of common ones, or Custom Size…, which asks
    # for the columns and the rows (`3x4`, `3 × 4`, `3 4`); the header row
    # comes besides the rows.

    # Table → the preset sizes, as {columns, rows}.
    TABLE_SIZES = [{2, 2}, {3, 3}, {3, 5}, {4, 4}, {4, 8}, {6, 6}]

    # The largest table Custom Size… makes.
    MAX_TABLE_COLUMNS =  20
    MAX_TABLE_ROWS    = 100

    # GFM's alerts, as Alert → offers them: the label and the type.
    ALERTS = [{"&Note", "NOTE"}, {"&Tip", "TIP"}, {"&Important", "IMPORTANT"}, {"&Warning", "WARNING"}, {"&Caution", "CAUTION"}]

    # Custom Size…'s answer: columns and rows, apart by an `x`, a `×`, a
    # `*`, a comma or spaces.
    TABLE_SIZE = /\A\s*(\d{1,3})\s*(?:[xX×*,]|\s)\s*(\d{1,3})\s*\z/

    # What Custom Size… offers first: the size asked for last.
    @table_size = "3x3"

    # Between Edit and Format, as word processors put Insert: what goes into
    # the text, then how it looks. The task entries close it, apart: they
    # make a task of what is there rather than insert a template.
    private def build_insert_menu(bar : Crysterm::Widget::MenuBar) : Nil
      insert = bar.add_menu "In&sert"
      levels = (1..6).map do |level|
        command_action("Level &#{level}", "insert-heading-#{level}", "A #{"#" * level} heading") { insert_heading level }
      end
      tip insert.add_submenu("&Heading", levels), "A heading of the level chosen, # to ######"
      tables = TABLE_SIZES.map_with_index do |(columns, rows), i|
        command_action("&#{i + 1}  #{columns} Columns × #{rows} Rows", "insert-table-#{columns}x#{rows}", "A table of #{columns} columns and #{rows} rows, under a header row") { insert_table columns, rows }
      end
      tables << Crysterm::Action.separator
      tables << command_action("&Custom Size…", "insert-table-custom", "A table of the columns and rows asked for, as 3x4") { insert_table_prompt }
      tip insert.add_submenu("T&able", tables), "A table of the size chosen, its header cells to type over"
      named "insert-link", tip insert.add_action("&Link") { insert_link }, "A link, [text](url), the selection its text"
      named "insert-image", tip insert.add_action("&Image") { insert_image }, "An image, ![alt text](url), the selection its alt text"
      named "insert-footnote", tip insert.add_action("&Footnote") { insert_footnote }, "A footnote reference, [^1], at the caret, and its definition at the end of the document"
      insert.add_separator
      named "insert-bulleted-list", tip insert.add_action("&Bulleted List") { insert_block "- Item", "Item" }, "A bulleted list item, - Item"
      named "insert-numbered-list", tip insert.add_action("&Numbered List") { insert_block "1. Item", "Item" }, "A numbered list item, 1. Item"
      named "insert-blockquote", tip insert.add_action("Block&quote") { insert_block "> Quote", "Quote" }, "A blockquote, > Quote"
      alerts = ALERTS.map do |label, type|
        command_action(label, "insert-alert-#{type.downcase}", "A #{type.downcase} alert, > [!#{type}], as GitHub renders it") { insert_block "> [!#{type}]\n> Text", "Text" }
      end
      tip insert.add_submenu("Al&ert", alerts), "A GitHub alert: a blockquote with a note, tip, important, warning or caution title"
      named "insert-rule", tip insert.add_action("Horizontal &Rule") { insert_block "---" }, "A horizontal rule, ---"
      insert.add_separator
      # The check is the caret's item's, read as the menu opens; picking the
      # entry flips it and the box with it.
      task = Crysterm::Action.new "As a &Task", checkable: true, name: "task"
      # With no item nor text to make one of, nothing changes, and the
      # check flipped by the pick is put back.
      task.on(Crysterm::Event::Triggered) { refresh_task_entry unless toggle_task_box }
      insert.add_action tip(task, "Give the caret's list item a task box, [ ], or take it off, making a line of text an item first; the selection's items too")
      @task_action = task
      insert.on(Crysterm::Event::AboutToShow) { refresh_task_entry }
      named "toggle-task", tip insert.add_action("Toggle Task Chec&kbox", shortcut: "Alt+X") { check_task }, "Tick the caret's task box, or empty it; an item without a box, or a line of text, gets a ticked one"
    end

    # A submenu's entry: *label*, named *name* (a command), described by
    # *text*, running the block when picked.
    private def command_action(label : String, name : String, text : String, &block : ->) : Crysterm::Action
      action = Crysterm::Action.new label, name: name
      action.on(Crysterm::Event::Triggered) { block.call }
      tip action, text
    end

    # Insert → Heading: a heading of *level* (1 to 6), `Heading` selected.
    def insert_heading(level : Int32) : Bool
      insert_block "#{"#" * level} Heading", "Heading"
    end

    # Insert → Table: a table of *columns* and *rows* under its header row,
    # the cells as wide as the header's `Column 1`, `Column 1` selected.
    def insert_table(columns : Int32, rows : Int32) : Bool
      headers = (1..columns).map { |i| "Column #{i}" }
      row = ->(cells : Array(String)) { "| #{cells.join(" | ")} |" }
      lines = [row.call(headers), row.call(headers.map { |header| "-" * header.size })]
      rows.times { lines << row.call(headers.map { |header| " " * header.size }) }
      insert_block lines.join('\n'), "Column 1"
    end

    # Insert → Table → Custom Size…: asks for the columns and the rows,
    # offering the size asked for last, and inserts that table.
    def insert_table_prompt : Nil
      ask_text("Table size: ", @table_size, question: "Table size (columns x rows):", completer: nil) do |answer|
        next unless answer
        text = answer.strip
        next if text.empty?
        m = TABLE_SIZE.match(text)
        columns, rows = m ? {m[1].to_i, m[2].to_i} : {0, 0}
        if columns.in?(1..MAX_TABLE_COLUMNS) && rows.in?(1..MAX_TABLE_ROWS)
          @table_size = "#{columns}x#{rows}"
          insert_table columns, rows
        else
          notice "Not a table size: #{text} (1 to #{MAX_TABLE_COLUMNS} columns, 1 to #{MAX_TABLE_ROWS} rows, as 3x4)"
        end
      end
    end

    # Insert → Link: `[text](url)` at the caret; with a selection, the
    # selection is the text and `url` is selected, and `text` otherwise.
    def insert_link : Bool
      insert_inline "[", "text", "](url)"
    end

    # Insert → Image: `![alt text](url)`, likewise.
    def insert_image : Bool
      insert_inline "![", "alt text", "](url)"
    end

    # Insert → Footnote: a reference, `[^1]`, after the caret or the
    # selection, numbered one past the document's highest, and its
    # definition at the end of the document, apart by a blank line, its
    # `Footnote` selected there.
    def insert_footnote : Bool
      editor = formatting_editor
      doc = editor.document
      text = doc.plain_text
      number = (text.scan(/\[\^(\d+)\]/).max_of?(&.[1].to_i) || 0) + 1
      at = editor.text_cursor.selection_end
      ref = "[^#{number}]"
      gap = text.empty? || text.ends_with?("\n\n") ? "" : (text.ends_with?('\n') ? "\n" : "\n\n")
      definition = "#{gap}#{ref}: Footnote\n"
      doc.edit do
        # The definition first, so the caret's position still holds.
        Crysterm::TextCursor.new(doc, doc.size).insert_text definition
        Crysterm::TextCursor.new(doc, at).insert_text ref
        nil
      end
      start = doc.size - "Footnote\n".size
      editor.text_cursor = Crysterm::TextCursor.new(doc, start, start + "Footnote".size)
      edited
      true
    end

    # *open*, the selection or *placeholder*, and *close* in place of the
    # selection; the placeholder selected when it went in, and with a
    # selection the first word between parentheses in *close* (the `url`).
    private def insert_inline(open : String, placeholder : String, close : String) : Bool
      editor = formatting_editor
      doc = editor.document
      cursor = editor.text_cursor
      from, to = cursor.selection_start, cursor.selection_end
      wrapping = editor.selection?
      inner = wrapping ? cursor.selected_text : placeholder
      doc.edit { Crysterm::TextCursor.new(doc, from, to).insert_text "#{open}#{inner}#{close}" }
      if wrapping
        start = from + open.size + inner.size + close.index!('(') + 1
        editor.text_cursor = Crysterm::TextCursor.new(doc, start, start + close.size - close.index!('(') - 2)
      else
        start = from + open.size
        editor.text_cursor = Crysterm::TextCursor.new(doc, start, start + inner.size)
      end
      edited
      true
    end

    # *block*, whole lines without the last line break, on the caret's line
    # when it is blank — the last of the selection's — and after the
    # paragraph the caret is in otherwise, a blank line kept between it and
    # the text on either side; *placeholder*, the first one in it,
    # selected, or the caret put at the block's end without one. Returns
    # whether it went in: not inside a code block, with a notice.
    private def insert_block(block : String, placeholder : String? = nil) : Bool
      editor = formatting_editor
      doc = editor.document
      _, last = selected_blocks
      code = App.code_lines(doc)
      if code[last]
        notice "Not inside a code block"
        return false
      end
      line = doc.blocks[last]
      if line.text.blank?
        index = last
        from, to = line.position, line.position + line.size
        lead = index > 0 && !doc.blocks[index - 1].text.blank? ? "\n" : ""
      else
        index = paragraph_end(last, code)
        from = to = doc.blocks[index].position + doc.blocks[index].size
        lead = "\n\n"
      end
      # A line of text below is kept apart; on the last line, the text
      # still ends with a line break.
      trail = index + 1 == doc.block_count || !doc.blocks[index + 1].text.blank? ? "\n" : ""
      doc.edit { Crysterm::TextCursor.new(doc, from, to).insert_text "#{lead}#{block}#{trail}" }
      start = from + lead.size
      if placeholder && (offset = block.index(placeholder))
        editor.text_cursor = Crysterm::TextCursor.new(doc, start + offset, start + offset + placeholder.size)
      else
        editor.text_cursor = Crysterm::TextCursor.new(doc, start + block.size)
      end
      edited
      true
    end
  end
end
