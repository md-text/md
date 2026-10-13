module Md
  # The source pane: Crysterm's plain text editor (Qt's `QPlainTextEdit`)
  # with a hook ahead of its keys. `#key_filter` sees every key press first
  # and returns whether it took the key; a taken key is accepted and goes no
  # further — the editor would otherwise type the newline `Enter` stands
  # for, and the window would move the focus on `Tab`. Overriding the editor's key
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

    # The line a hard wrap (Format → Hard Wrap, Crysterm's `hard_wrap_column`)
    # carries over from *line*, the caret's, starts as a continuation of it
    # in the Markdown: with the item's content indentation on a list item,
    # with the quote markers and indentation of any other line
    # (`App.continuation_prefix`). A line that cannot be broken without
    # changing its meaning — a code block's, fenced or indented, a fence, a
    # heading, a table row, a rule (`App.unbreakable?`) — is left alone.
    def hard_wrap_prefix(line : String) : String?
      return if App.unbreakable?(document, document.block_at(cursor_position).index)
      App.continuation_prefix(line)
    end
  end

  class App
    # Markdown-aware editing: the syntax the editor knows, on top of
    # Crysterm's plain text editor — which, like Qt's `QPlainTextEdit`, has
    # no Markdown mode of its own.
    #
    # Lists. `Enter` on a list item — `- `, `* `, `+ `, `1. ` or `1) `, a
    # task `- [ ] ` or `- [x] `, indented or inside a blockquote `> ` (not
    # in a code block, nor a rule like `* * *`) — with
    # the caret past the marker continues the list: a new line with the same
    # indentation and marker, the number one higher and the task box empty,
    # taking along whatever followed the caret. On an empty item, the marker
    # alone, `Enter` ends the list instead, removing the marker, as editors
    # do (Qt's `QTextEdit` takes an empty item out of its list). On any
    # other line `Enter` keeps its meaning, a newline.
    #
    # `Tab` and `Shift-Tab` indent and outdent the caret's line, or the
    # selection's lines (Format → Indent and Outdent, `#indent_lines`). A
    # list item, or a selection with one in it, moves by the list's rules:
    # an item nests under the nearest item above it at the same or a
    # shallower level, by that item's content offset — two columns for
    # `- `, three for `1. ` — which is what CommonMark asks of a child list,
    # so a bullet under `1. step` is indented by three; outdenting goes back
    # to the indentation of the nearest shallower item, or to the margin.
    # Every line of the selection moves by the same amount, continuation
    # lines included. Any other line moves by Markdown's indent unit, four
    # spaces (`INDENT`); outdenting takes up to four spaces, or a tab, off
    # its front. So `Tab` never leaves the editor, as it does not leave a
    # `QPlainTextEdit` (`tabChangesFocus` is off by default): `F1`–`F3` and
    # the mouse put the focus elsewhere.
    #
    # Format → As a Task, a check entry, gives a list item a task box, or
    # takes off the one it has: `- item` ⇄ `- [ ] item`; its check shows
    # whether the caret's item is a task, read as the menu opens
    # (`#refresh_task_entry`, Qt's `aboutToShow`). Format → Toggle Task
    # Checkbox (`Alt-X`) ticks the box and unticks it, `- [ ] item` ⇄
    # `- [x] item`; an item without a box gets one ticked. A task box
    # belongs on a list item, so both make a line of text one first: `text`
    # → `- [ ] text` (`#edit_task_items`). Format → Bold, Italic and Code (`Ctrl-B`, `Alt-I`,
    # `Alt-C`) wrap the selection — or the word at the caret, or, with
    # neither, a pair the caret is put between — in `**`, `*` and backticks,
    # and take them off again from text that has them (`_` and `__` count
    # too), a toggle; the text stays selected, so a second press undoes the
    # first. Format → Code Block (`#toggle_code_block`) is the same toggle
    # for whole lines: ` ``` ` fences around the selection's lines or the
    # caret's paragraph, an empty block on a blank line, and off again from
    # anywhere in a fenced block. Format → Promote Heading and Demote Heading (`Ctrl-Up`,
    # `Ctrl-Down`) move the heading of the caret's section one level up or
    # down — the caret's line when it is a heading, the nearest heading
    # above it otherwise, so they work from anywhere in the section — a
    # paragraph being the level above `#` and `######` the last; a setext
    # heading moved becomes an ATX one, a task item's one stays setext,
    # keeping its box (`#shift_heading`, `#shift_task_heading`).
    #
    # Format → Rewrap — labelled with the column, `Rewrap (to 80 Columns)`
    # — → Paragraph (`Alt-Q`, Emacs's `fill-paragraph`, Kate's
    # Apply Word Wrap) refills the caret's paragraph — or every paragraph
    # the selection touches — and Rewrap → Document every paragraph of the
    # document, to the wrap column (`#wrap_column`, `app_view.cr`), the
    # companion of Format → Hard Wrap, which breaks lines as they are typed. A paragraph is a run of lines without a blank one,
    # in the same blockquote, that no list item, heading, fence, table row
    # or rule starts or interrupts (`#continues?`); a list item's lines
    # keep the marker and take the item's content indentation, a quote's
    # keep the `> `, and a code block, fenced or indented
    # (`App.code_lines`), is not a paragraph, nor is a link reference
    # definition (`[id]: url`). A hard break (two spaces or a backslash
    # ending a line) stays where it is. No line is broken where the
    # next would start with Markdown of its own — a `-`, `1.`, `#` or `>`
    # in the text — nor after a backslash, which would end the line in a
    # hard break (`.breakable?`). The caret keeps its place in
    # the text, counted in the characters that are not spaces.
    #
    # The keys: `Ctrl-B` is Qt's bold, and the editor does not use it;
    # `Alt-Q` is Emacs's fill, free in the editor too. Qt's
    # `Ctrl-I` is out of reach — a terminal sends the same byte for `Ctrl-I`
    # and `Tab` — and so is `Ctrl-Shift-X`, which a terminal does not tell
    # from `Ctrl-X`, so Italic, Code and Toggle Task Checkbox take `Alt` chords the
    # editor leaves alone (`Alt-B` and `Alt-F` are readline's word moves
    # there). `Enter`, `Tab` and `Shift-Tab` are the editor's own
    # (`MarkdownEdit#key_filter`), taken ahead of its editing keys — and of
    # the window's focus cycling, which would otherwise have `Tab`. Indent
    # and Outdent still show `Tab` and `Shift+Tab` as their shortcuts, in
    # Qt's way of a key that is an entry's only in one widget: the actions
    # are added to the editor (`QWidget::addAction`) with the `Widget`
    # shortcut context (`Qt::WidgetShortcut`), so Crysterm fires them only
    # while the editor has the focus, and elsewhere `Tab` cycles the panes
    # as before. The filter has the key first and accepts it, so a press
    # indents once, whichever path it takes.
    #
    # Every change is one edit of the editor's document — one undo step —
    # and goes through `#edited` like typing, so the viewer follows. The
    # Format entries work from any pane: from the viewer they act on the
    # editor at the source of the viewer's caret, showing the editor when
    # it is hidden.

    # The Format → As a Task entry, whose check follows the caret's item.
    @task_action : Crysterm::Action?

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

      # The indentation inside the quote: the one space after a `>` is the
      # marker's (`QUOTE_MARKERS`), not indentation, so `> - item` is at
      # the quote's margin.
      def inner_indent : Int32
        quote.empty? ? indent.size : indent.lchop(' ').size
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

    # A link reference definition's label, `[id]:`, opening a line (in a
    # quote too): the definition, URL and title, is no paragraph text, and
    # each is a line of its own that a rewrap leaves as it is.
    LINK_DEFINITION = /\A(?:[ \t]*>)*[ \t]{0,3}\[(?:[^\]\\]|\\.)+\]:/

    # Markdown's indent unit for a line in no list: the four spaces of an
    # indented code block or a continuation paragraph.
    INDENT = 4

    # A line's heading prefix: what precedes the hashes (blockquote markers,
    # list markers, indentation), then the hashes with their spacing when
    # there are any. A list marker counts with one to four columns of
    # spacing after it, so `- ## Title` is a heading in the item while
    # `-     # code`, five columns in, is the item's indented code
    # (CommonMark's list items), and a task box is text: `- [ ] ## x` is
    # no heading, as markd, which md renders with, reads it with GFM off.
    HEADING = /\A(?<lead>(?:[ \t]*(?:>|(?:[-*+]|\d{1,9}[.)])[ \t]{1,4}(?=[^ \t])))*[ \t]*)(?:(?<hashes>\#{1,6})(?:[ \t]+|$))?/

    # The blockquote markers a line starts with and the indentation after
    # them: what a wrapped line's continuation starts with outside a list.
    QUOTE_LEAD = /\A(?:[ \t]*>)*[ \t]*/

    # A line opening with a code fence, in a quote or indented however far:
    # a fence proper when it is indented at most three columns past the
    # content around it (`.code_lines` tells), and a code block's own line
    # otherwise — unbreakable either way.
    FENCE = /\A(?:[ \t]*>)*[ \t]*(?<fence>`{3,}|~{3,})/

    # A line that can close a fenced code block: a run of backticks or
    # tildes alone on it (the quote markers taken off).
    CLOSING_FENCE = /\A[ \t]*(?<fence>`{3,}|~{3,})[ \t]*\z/

    # A setext heading's underline: a run of `=` (level 1) or `-` (level
    # 2) alone on a line, after any quote markers and at most three
    # columns of indentation. It underlines the paragraph above it; after
    # a blank line, a `---` is a rule (`RULE`) instead.
    SETEXT_UNDERLINE = /\A(?:[ \t]*>)*[ \t]{0,3}(?<mark>=+|-+)[ \t]*\z/

    # A heading of a document by its lines: *first* and *last* are the
    # same line for an ATX heading (`## Title`), the paragraph's first line
    # and the underline for a setext one (`Title` over `---`); *level* is
    # 1 to 6, or 0 for a line that is no heading.
    record Heading, first : Int32, last : Int32, level : Int32 do
      def setext? : Bool
        last > first
      end
    end

    # A table row (or its delimiter row).
    TABLE_ROW = /\A(?:[ \t]*>)*[ \t]*\|/

    # A thematic break (`---`, `* * *`, `___`) or a setext heading's
    # underline (`===`, `---`): a line that joined to the one above would
    # be its text, or make it a heading.
    RULE = /\A(?:[ \t]*>)*[ \t]{0,3}(?:(?:-[ \t]*){3,}|(?:\*[ \t]*){3,}|(?:_[ \t]*){3,}|=+[ \t]*)\z/

    # The blockquote markers a line starts with, each with the one space it
    # may take: what comes after is the line as the quote holds it, its
    # indentation counted from there.
    QUOTE_MARKERS = /\A(?:[ \t]*> ?)*/

    # A word that, starting a line of a paragraph, would be Markdown of its
    # own there: a list marker, an ATX heading's hashes, a setext underline
    # or a rule, a quote marker, a code fence or a table row — the line a
    # list item, a heading, a quote, the start of a code block or a table,
    # or the paragraph above it a heading. Between words, `- ` or `1. ` is
    # text.
    BLOCK_WORD = /\A(?:[-+*]|\d{1,9}[.)]|\#{1,6}|=+|-+|\*{3,}|_{3,}|>.*|`{3,}.*|~{3,}.*|\|.*)\z/

    # Whether a paragraph's line may be broken between the words *before*
    # and *after*, *after* starting the next line: not when *after* would
    # start something else there (`BLOCK_WORD`), nor after a backslash
    # ending *before*, which at a line's end is a hard line break.
    def self.breakable?(before : String, after : String) : Bool
      !BLOCK_WORD.matches?(after) && (before.size - before.rstrip('\\').size).even?
    end

    # Whether line *index* of *doc* must not be broken or refilled: a code
    # block's line, a fence, a heading, a table row or a rule. One line's
    # answer, with a scan of the lines above it (`.code_lines`); a caller
    # that asks about many lines takes the scan once instead.
    def self.unbreakable?(doc : Crysterm::TextDocument, index : Int32) : Bool
      unbreakable_line?(doc.blocks[index].text) || code_lines(doc, index)[index]
    end

    # Whether *line* is unbreakable on its own account — a fence, a heading,
    # a table row or a rule — whatever surrounds it.
    def self.unbreakable_line?(line : String) : Bool
      FENCE.matches?(line) || TABLE_ROW.matches?(line) || heading?(line) || RULE.matches?(line)
    end

    # Which of lines 0 to *upto* of *doc* are a code block's: between two
    # fences (the fences themselves not counted), or indented four columns
    # past the content of the list item holding them — past the margin
    # outside a list — where paragraph text does not continue, which is
    # CommonMark's indented code block (`    code` after a blank line; a
    # line indented so right under text is the paragraph's). Indentation
    # is counted from the item's content as CommonMark counts it, so a
    # fence four columns in under a nested item is still a fence, and a
    # marker four columns in after a blank line is code, not an item. One
    # pass over the lines, the items open at each kept as a stack of their
    # content columns, so a rewrap asks about every line of its range, and
    # a hard wrap about the caret's, without a scan of the lines above each.
    def self.code_lines(doc : Crysterm::TextDocument, upto : Int32 = doc.block_count - 1) : Array(Bool)
      scan = CodeScan.new
      Array(Bool).new(upto + 1) { |i| scan.code?(doc.blocks[i].text) }
    end

    # What `.code_lines` carries from one line to the next: the fence of
    # the code block open (nil outside one), the content columns of the
    # list items open, innermost last, and whether paragraph text runs on
    # from above.
    private class CodeScan
      @fence : String? = nil
      @items = [] of Int32
      @text_above = false

      # Whether the scan is inside a fenced code block: after a fence that
      # opened one, and not after the one that closed it.
      def fenced? : Bool
        !@fence.nil?
      end

      # Whether *line* is a code block's, the scan moved past it.
      def code?(line : String) : Bool
        body = line.sub(QUOTE_MARKERS, "")
        indent = indent_width body
        if @fence && !body.blank? && (top = @items.last?) && indent < top
          # A line less indented than the item's content ends the item, and
          # the code block in it.
          @fence = nil
        end
        if open = @fence
          @fence = nil if closes?(body, open, indent)
          !@fence.nil?
        elsif body.blank?
          @text_above = false
          false
        else
          outside_fence? body, indent
        end
      end

      # Whether *body*, a line with text outside a fenced block, is an
      # indented code block's; a fence, an item or text it opens is noted.
      private def outside_fence?(body : String, indent : Int32) : Bool
        # A line less indented than an item's content ends the item (a
        # sibling replaces one).
        while (top = @items.last?) && top > indent
          @items.pop
        end
        # Four columns past the content: code, unless paragraph text runs
        # on from above.
        return !@text_above if indent - margin >= INDENT
        if run = FENCE.match(body).try(&.["fence"])
          @fence = run
          @text_above = false
        elsif !RULE.matches?(body) && (item = ListItem.parse(body))
          # An item opens (`* * *` is a rule, not one); its text can run on
          # to the next line, or it opens a fenced block (`- ``` `).
          @items << indent + item.content_offset
          @text_above = !item.empty?
          if item.task.nil? && (run = FENCE.match(item.text).try(&.["fence"]))
            @fence = run
            @text_above = false
          end
        else
          @text_above = !App.unbreakable_line?(body)
        end
        false
      end

      # Whether *body* closes the fenced block *open* began: a run of the
      # same character, no shorter, with nothing after it, at most three
      # columns past the content around the block. Any other line is the
      # block's own.
      private def closes?(body : String, open : String, indent : Int32) : Bool
        run = CLOSING_FENCE.match(body).try(&.["fence"]) || return false
        run[0] == open[0] && run.size >= open.size && indent - margin < INDENT
      end

      # The content column of the innermost item open, 0 outside a list.
      private def margin : Int32
        @items.last? || 0
      end

      private def indent_width(text : String) : Int32
        App.indent_width text
      end
    end

    # The columns *text*'s leading whitespace takes, a tab reaching the
    # next multiple of four as CommonMark counts it.
    def self.indent_width(text : String) : Int32
      width = 0
      text.each_char do |char|
        case char
        when ' '  then width += 1
        when '\t' then width += INDENT - width % INDENT
        else           break
        end
      end
      width
    end

    # Whether *line* is an ATX heading.
    def self.heading?(line : String) : Bool
      !HEADING.match(line).try(&.["hashes"]?).nil?
    end

    # A task box opening an item's text, with text after it: GFM's task
    # list item marker.
    TASK_BOX = /\A\[[ xX]\][ \t]+[^ \t]/

    # The quote and list markers before the box when *line* is a task
    # item's first line (`- [ ] text`, `> 1. [x] text`, `- - [ ] text`),
    # nil otherwise. A box after an ATX heading's hashes is text
    # (`- ## [ ] x`), as GFM reads it.
    def self.task_lead(line : String) : String?
      return unless ListItem.parse(line)
      lead = HEADING.match(line).try(&.["lead"]) || return
      lead if TASK_BOX.matches?(line[lead.size..])
    end

    # The headings of *doc*, in order: ATX ones (`## Title`) and setext
    # ones (`Title` over a line of `=` or `-`), a code block's line
    # (*code*, `.code_lines` of the whole of *doc*) being no part of
    # either; in a list item too, at any depth (`- ## Title`, or `- Title`
    # over a `---` indented to the item's content). A setext heading's
    # text is the paragraph right above the underline, in the same
    # blockquote and list item: a run of lines of text that no blank line,
    # list item, fence, table row, rule or ATX heading interrupts, the
    # underline indented at least to the item's content and less than
    # four columns past it. So `- item` over a `---` at the margin is the
    # list then a rule, and over a `===` there it is the item's text run
    # on lazily. A paragraph that runs on lazily in an item, on a line
    # less indented, is still one, as markd reads it; a quote's that runs
    # on to a line without its markers is not, so the `---` under it is a
    # rule.
    def self.headings(doc : Crysterm::TextDocument, code : Array(Bool)) : Array(Heading)
      scan = HeadingScan.new
      headings = [] of Heading
      code.each_with_index do |is_code, i|
        text = doc.blocks[i].text
        if is_code || text.blank?
          scan.reset
        elsif heading = scan.heading(i, text)
          headings << heading
        end
      end
      headings
    end

    # What `.headings` carries from one line to the next: the paragraph an
    # underline would make a heading, by its first line, quote depth and
    # the content column of the item it is in (0 outside a list); whether
    # it ran on lazily out of a quote, which no underline follows; and the
    # content columns of the list items open at each quote depth,
    # innermost last.
    private class HeadingScan
      @start : Int32? = nil
      @depth = 0
      @column = 0
      @lazy = false
      @items = [[] of Int32]

      # A blank line or a code block's: no paragraph runs on past it.
      def reset : Nil
        @start = nil
        @lazy = false
      end

      # The heading line *index*, *text*, ends or is, the scan moved past it.
      def heading(index : Int32, text : String) : Heading?
        quotes = QUOTE.match(text).try(&.[0].count('>')) || 0
        body = text.sub(QUOTE_MARKERS, "")
        indent = App.indent_width body
        if first = @start
          if underline?(body, indent, quotes)
            @start = nil
            return Heading.new(first, index, body.lstrip.starts_with?('=') ? 1 : 2)
          end
          if runs_on?(body, indent, quotes)
            @lazy ||= quotes < @depth
            return
          end
        end
        reset
        block index, text, body, indent, quotes
      end

      # Notes line *index*, *text*, which no paragraph runs on to: its
      # *body* (the line inside its quote markers, indented *indent*
      # columns) closes the items it is less indented than, opens any it
      # starts with, and is an ATX heading, or a paragraph's first line,
      # or neither.
      private def block(index : Int32, text : String, body : String, indent : Int32, quotes : Int32) : Heading?
        items = items_at quotes
        while (top = items.last?) && top > indent
          items.pop
        end
        rest = body.lstrip
        column = indent
        # `- - -` is a rule, not items; `* ---` an item holding one.
        while !RULE.matches?(rest) && (item = ListItem.parse(rest)) && item.quote.empty?
          column += item.content_offset
          items << column
          rest = "#{item.task}#{item.text}"
        end
        if hashes = HEADING.match(text).try(&.["hashes"]?)
          return Heading.new(index, index, hashes.size)
        end
        unless rest.empty? || App.unbreakable_line?(rest)
          @start, @depth, @column = index, quotes, items.last? || 0
        end
        nil
      end

      # Whether *body*, indented *indent* at quote depth *quotes*, is the
      # paragraph's setext underline: in its quote and item, at most three
      # columns past the item's content.
      private def underline?(body : String, indent : Int32, quotes : Int32) : Bool
        !@lazy && quotes == @depth && indent >= @column && indent - @column < INDENT &&
          SETEXT_UNDERLINE.matches?(body.lstrip)
      end

      # Whether *body*, no underline, is paragraph text running on: any
      # line but one that opens a quote, or a block that interrupts a
      # paragraph — an ATX heading, a fence, a table row, a rule or a list
      # item — less than four columns past the content of the item it is
      # in. A `===` that underlines nothing, out of the paragraph's item,
      # is text.
      private def runs_on?(body : String, indent : Int32, quotes : Int32) : Bool
        return false if quotes > @depth
        margin = @items[quotes]?.try(&.reverse_each.find { |column| column <= indent }) || 0
        return true if indent - margin >= INDENT
        line = body.lstrip
        line.starts_with?('=') || !(App.unbreakable_line?(line) || ListItem.parse(line))
      end

      # The content columns of the items open at quote depth *quotes*,
      # those of deeper quotes, now closed, dropped.
      private def items_at(quotes : Int32) : Array(Int32)
        @items = @items.first(quotes + 1)
        (quotes + 1 - @items.size).times { @items << [] of Int32 }
        @items[quotes]
      end
    end

    # What a line continuing *line* starts with: the quote markers and the
    # item's content indentation for a list item, the quote markers and
    # indentation of any other line (empty for a plain paragraph).
    def self.continuation_prefix(line : String) : String
      if item = ListItem.parse(line)
        "#{item.quote}#{item.indent}#{" " * item.content_offset}"
      else
        QUOTE_LEAD.match(line).try(&.[0]) || ""
      end
    end

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

    # Format → Code Block: the caret's lines in a fenced code block, or out
    # of the one they are in. Inside a fenced block — on a line of its
    # code or on one of its fences — the two fences come off (just the
    # opening one of a block left open to the end), leaving the code as
    # it was. Elsewhere, the selection's lines, or with no selection the
    # run of lines around the caret that no blank line, heading or other
    # fenced block ends, are put between
    # ` ``` ` fences carrying the first line's quote markers and
    # indentation; on a blank line an empty block goes in, the caret on
    # its middle line, ready to type code. The caret, and a selection,
    # keep their place in the text. Returns true.
    def toggle_code_block : Bool
      editor = formatting_editor
      doc = editor.document
      first, last = selected_blocks
      if block = fenced_blocks(doc).find { |open, _, end_line| open <= last && end_line >= first }
        unfence doc, block[0], block[1]
      elsif !editor.selection? && doc.blocks[first].text.blank?
        at = doc.blocks[first].position
        doc.edit { Crysterm::TextCursor.new(doc, at, at + doc.blocks[first].size).insert_text "```\n\n```" }
        editor.text_cursor = Crysterm::TextCursor.new(doc, at + 4)
      else
        first, last = code_paragraph(doc, App.code_lines(doc), first) unless editor.selection?
        fence first, last
      end
      edited
      true
    end

    # Format → As a Task: a task box on the caret's list item, or on every
    # list item of the selection — `[ ] ` added to an item without one, and
    # taken off an item that has one; a line of text is made an item with a
    # box (`#edit_task_items`), the `[ ]` or `[x]` it starts with, if any,
    # being that box. Returns whether there was an item or a line of text,
    # with a notice when there was not.
    def toggle_task_box : Bool
      edit_task_items do |doc, box, item, made|
        if task = item.task
          Crysterm::TextCursor.new(doc, box, box + task.size).remove_selected_text unless made
        else
          Crysterm::TextCursor.new(doc, box).insert_text(item.spacing.empty? ? " [ ] " : "[ ] ")
        end
      end
    end

    # Format → Toggle Task Checkbox: the box ticked when empty and emptied when
    # ticked, on the same items; an item without a box gets a ticked one,
    # so a plain item is done in one key, and a line of text made an item
    # has its box ticked. Likewise.
    def check_task : Bool
      edit_task_items do |doc, box, item, made|
        if task = item.task
          Crysterm::TextCursor.new(doc, box + 1, box + 2).insert_text(made || task[1] == ' ' ? "x" : " ")
        else
          Crysterm::TextCursor.new(doc, box).insert_text(item.spacing.empty? ? " [x] " : "[x] ")
        end
      end
    end

    # Format → Rewrap → Paragraph: the caret's paragraph, or the selection's
    # paragraphs, refilled to the wrap column (see the class comment).
    # Returns whether there was a paragraph, with a notice when there was
    # not (a blank line, a code block).
    def rewrap_paragraph : Bool
      editor = formatting_editor
      first, last = selected_blocks
      code = App.code_lines editor.document
      # The whole of each paragraph the selection touches, not just its
      # lines (`#paragraph_start` and `#paragraph_end` leave a line in no
      # paragraph where it is).
      rewrap_blocks paragraph_start(first, code), paragraph_end(last, code), code
    end

    # Format → Rewrap → Document: every paragraph of the document refilled,
    # as one undo step; code blocks, headings and table rows stay. Returns
    # whether there was a paragraph, with a notice when there was none.
    def rewrap_document : Bool
      doc = formatting_editor.document
      rewrap_blocks 0, doc.block_count - 1, App.code_lines(doc)
    end

    # Lines *first* to *last* of the editor's document refilled paragraph by
    # paragraph, the caret keeping its place; the shared body of the two
    # Rewrap entries. *code* says which lines are a code block's
    # (`.code_lines`).
    private def rewrap_blocks(first : Int32, last : Int32, code : Array(Bool)) : Bool
      editor = formatting_editor
      doc = editor.document
      lines = (first..last).map { |i| doc.blocks[i].text }
      filled = [] of String
      found = false
      i = 0
      while i < lines.size
        if lines[i].blank? || code[first + i] || App.unbreakable_line?(lines[i]) || LINK_DEFINITION.matches?(lines[i])
          filled << lines[i]
          i += 1
          next
        end
        stop = Math.min(paragraph_end(first + i, code), last) - first
        filled.concat fill(lines[i..stop], wrap_column)
        found = true
        i = stop + 1
      end
      unless found
        notice "Not a paragraph"
        return false
      end
      return true if filled == lines
      from = doc.blocks[first].position
      to = doc.blocks[last].position + doc.blocks[last].size
      text = filled.join('\n')
      caret = text_caret(doc.plain_text(from, to), editor.cursor_position - from, text)
      doc.edit { Crysterm::TextCursor.new(doc, from, to).insert_text text }
      editor.text_cursor = Crysterm::TextCursor.new(doc, from + caret)
      edited
      true
    end

    # Format → Indent and Outdent, and `Tab`/`Shift-Tab` in the editor: the
    # caret's line, or the selection's lines, moved one level in
    # (*direction* 1) or out (-1) — by the list's rules with a list item
    # among them, by `INDENT` otherwise; see the class comment. Returns
    # whether the lines moved: an item cannot nest deeper than one level
    # under the item above, and nothing comes off a line at the margin.
    def indent_lines(direction : Int32) : Bool
      editor = formatting_editor
      doc = editor.document
      first, last = selected_blocks
      delta = (found = first_item(doc, first, last)) ? item_delta(found[0], found[1], direction) : direction * INDENT
      return false unless delta
      moved = false
      doc.edit do
        (first..last).each do |i|
          block = doc.blocks[i]
          text = block.text
          next if text.blank?
          # The indentation starts after the quote markers and the one
          # space each may take, which is the marker's, not indentation.
          quote = QUOTE_MARKERS.match(text).try(&.[0].size) || 0
          start = block.position + quote
          if delta > 0
            Crysterm::TextCursor.new(doc, start).insert_text " " * delta
            moved = true
          else
            # A leading tab is one unit of indentation; spaces come off by
            # the count, as far as there are any.
            room = text[quote]? == '\t' ? 1 : Math.min(-delta, text.size - quote - text[quote..].lstrip(' ').size)
            next if room == 0
            Crysterm::TextCursor.new(doc, start, start + room).remove_selected_text
            moved = true
          end
        end
        nil
      end
      edited if moved
      moved
    end

    # Format → Promote Heading: the caret's section's heading one level up
    # (`##` → `#`; `#` → a paragraph), from the heading line or anywhere in
    # the section's text (`#shift_heading`). Returns whether it could go
    # up, with a notice when not.
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
    # list item, `Tab` and `Shift-Tab` on any line — taken whether or not
    # the lines could move, so `Tab` stays in the editor. Returns whether
    # the key was taken.
    private def markdown_key(e : Crysterm::Event::KeyPress) : Bool
      case e.key
      when Tput::Key::Enter then continue_list
      when Tput::Key::Tab
        indent_lines 1
        true
      when Tput::Key::ShiftTab
        indent_lines -1
        true
      else
        false
      end
    end

    # The first line of the paragraph line *index* is in: up from it while
    # the line above continues into it (`#continues?`). *code* is the
    # document's `.code_lines`.
    private def paragraph_start(index : Int32, code : Array(Bool)) : Int32
      doc = @editor.document
      while index > 0 && continues?(doc, index - 1, index, code)
        index -= 1
      end
      index
    end

    # The last line of the paragraph line *index* is in: down from it while
    # the next line continues it.
    private def paragraph_end(index : Int32, code : Array(Bool)) : Int32
      doc = @editor.document
      while index + 1 < doc.block_count && continues?(doc, index, index + 1, code)
        index += 1
      end
      index
    end

    # Whether line *below* continues the paragraph line *above* is in: both
    # are breakable text, in the same blockquote, and *below* starts nothing
    # of its own (a list item would). A link reference definition is no
    # paragraph's (`[id]: url`, one to a line), and the text under an empty
    # item (`- ` alone) is the item's only when indented to its content —
    # otherwise the list has ended and the text is a paragraph after it.
    private def continues?(doc : Crysterm::TextDocument, above : Int32, below : Int32, code : Array(Bool)) : Bool
      a = doc.blocks[above].text
      b = doc.blocks[below].text
      return false if a.blank? || b.blank? || code[above] || code[below]
      return false if App.unbreakable_line?(a) || App.unbreakable_line?(b) || ListItem.parse(b)
      return false if LINK_DEFINITION.matches?(a) || LINK_DEFINITION.matches?(b)
      quote_depth(a) == quote_depth(b) && !leaves_empty_item?(a, b)
    end

    # Whether *below* is out of the item *above* is, when that is an empty
    # item (the marker alone): less indented than the item's content.
    private def leaves_empty_item?(above : String, below : String) : Bool
      item = ListItem.parse(above) || return false
      return false unless item.empty? && item.task.nil?
      App.indent_width(below.sub(QUOTE_MARKERS, "")) < item.inner_indent + item.marker.size + 1
    end

    # How many blockquote markers *line* starts with.
    private def quote_depth(line : String) : Int32
      QUOTE.match(line).try(&.[0].count('>')) || 0
    end

    # *lines*, one paragraph, refilled to *column*: the first line keeps its
    # own prefix (a list marker, the quote), the next ones take the
    # continuation prefix, and the words flow across them, as many to a
    # line as fit; a word longer than the line has one to itself. No line
    # is broken where the next would start with Markdown of its own
    # (`.breakable?`): the word that would, a `-` or a `#` in the text,
    # stays with the one before it. A line ending in a hard break — two
    # spaces or a backslash — still ends there, its break kept, and the
    # words after it flow on from the next line.
    private def fill(lines : Array(String), column : Int32) : Array(String)
      first = lines[0]
      item = ListItem.parse(first)
      head = item ? first[0, item.prefix_size] : (QUOTE_LEAD.match(first).try(&.[0]) || "")
      rest = App.continuation_prefix(first)
      out = [] of String
      start = 0
      lines.each_with_index do |line, i|
        last = i == lines.size - 1
        next unless last || App.hard_break?(line)
        texts = (start..i).map { |k| k == 0 ? first[head.size..] : lines[k].sub(QUOTE_LEAD, "") }
        segment = fill_words(start == 0 ? head : rest, rest, texts.join(' ').split, column)
        segment[-1] += "  " if !last && line.ends_with?("  ")
        out.concat segment
        start = i + 1
      end
      out
    end

    # *words* laid out from *head* on, a line starting with *rest* taking
    # each word that does not fit the line before (see `#fill`). A list
    # marker with no space after it (`-` over its text) takes one before
    # its first word.
    private def fill_words(head : String, rest : String, words : Array(String), column : Int32) : Array(String)
      units = [] of String
      words.each do |word|
        if (last = units.last?) && !App.breakable?(last, word)
          units[-1] = "#{last} #{word}"
        else
          units << word
        end
      end
      out = [] of String
      current = head
      empty = true
      units.each do |unit|
        if empty
          current += " " if (item = ListItem.parse(head)) && item.spacing.empty?
          current += unit
          empty = false
        elsif current.size + 1 + unit.size <= column
          current += " #{unit}"
        else
          out << current
          current = "#{rest}#{unit}"
        end
      end
      out << current
    end

    # Whether *line* of a paragraph ends in a hard line break: two spaces
    # or more, or a backslash (not one escaped by another).
    def self.hard_break?(line : String) : Bool
      line.ends_with?("  ") || (line.size - line.rstrip('\\').size).odd?
    end

    # Where the caret at *offset* of *before* lands in *after*, the same
    # text refilled: after as many characters that are not spaces as came
    # before it.
    private def text_caret(before : String, offset : Int32, after : String) : Int32
      kept = before[0, offset.clamp(0, before.size)].count { |char| !char.whitespace? }
      return 0 if kept == 0
      after.each_char_with_index do |char, i|
        next if char.whitespace?
        kept -= 1
        return i + 1 if kept == 0
      end
      after.size
    end

    # The Format menu, between Edit and View (from `#build_menus`).
    private def build_format_menu(bar : Crysterm::Widget::MenuBar) : Nil
      format = bar.add_menu "For&mat"
      named "bold", tip format.add_action("&Bold", shortcut: "Ctrl+B") { toggle_bold }, "Put ** around the selection or the word at the caret, or take it off"
      named "italic", tip format.add_action("&Italic", shortcut: "Alt+I") { toggle_italic }, "Put * around the selection or the word at the caret, or take it off"
      named "code", tip format.add_action("&Code", shortcut: "Alt+C") { toggle_code }, "Put backticks around the selection or the word at the caret, or take them off"
      named "code-block", tip format.add_action("Code B&lock") { toggle_code_block }, "Put ``` fences around the selection's lines or the caret's paragraph, or an empty block on a blank line; inside a fenced block, take its fences off"
      # Then the entries for whole lines: their indentation, their task
      # boxes, their heading level.
      format.add_separator
      indent = named "indent", tip format.add_action("I&ndent", shortcut: "Tab") { indent_lines 1 }, "Indent the caret's line or the selection's lines; a list item nests under the one above"
      outdent = named "outdent", tip format.add_action("&Outdent", shortcut: "Shift+Tab") { indent_lines -1 }, "Outdent the caret's line or the selection's lines, one level or four spaces"
      # The editor's keys (see the class comment): the entries' shortcuts
      # only while the editor has the focus.
      {indent, outdent}.each do |action|
        action.shortcut_context = Crysterm::Action::ShortcutContext::Widget
        @editor.add_action action
      end
      format.add_separator
      # The check is the caret's item's, read as the menu opens; picking the
      # entry flips it and the box with it.
      task = Crysterm::Action.new "As a &Task", checkable: true, name: "task"
      # With no item nor text to make one of, nothing changes, and the
      # check flipped by the pick is put back.
      task.on(Crysterm::Event::Triggered) { refresh_task_entry unless toggle_task_box }
      format.add_action tip(task, "Give the caret's list item a task box, [ ], or take it off, making a line of text an item first; the selection's items too")
      @task_action = task
      format.on(Crysterm::Event::AboutToShow) { refresh_task_entry }
      named "toggle-task", tip format.add_action("Toggle Task Chec&kbox", shortcut: "Alt+X") { check_task }, "Tick the caret's task box, or empty it; an item without a box, or a line of text, gets a ticked one"
      format.add_separator
      named "promote-heading", tip format.add_action("&Promote Heading", shortcut: "Ctrl+Up") { promote_heading }, "Take one # off the heading of the caret's section, from anywhere in it; a # heading becomes a paragraph"
      named "demote-heading", tip format.add_action("&Demote Heading", shortcut: "Ctrl+Down") { demote_heading }, "Add a # to the heading of the caret's section, from anywhere in it, down to ######; before any heading, the caret's line becomes a # heading"
      format.add_separator
      # How the lines wrap, as typed and shown, and how wide the text is
      # (`app_view.cr`), with Rewrap, which refills to that width. Soft
      # Wrap is the one setting with a key (`Alt+W`, free in the editor,
      # where `Alt+Z` is redo).
      add_toggle(format, "&Soft Wrap", "soft-wrap", @soft_wrap, option_tip("md.soft_wrap")).shortcut = "Alt+W"
      add_toggle format, "&Hard Wrap", "hard-wrap", @hard_wrap, option_tip("md.hard_wrap")
      # To Last Guide sets the width by a guide (`app_view.cr`).
      last_guide = Crysterm::Action.new "To &Last Guide", name: "text-width-to-last-guide"
      last_guide.on(Crysterm::Event::Triggered) { text_width_to_last_guide }
      tip last_guide, "Set the text width by the last guide pulled off the column ruler"
      add_choices(format, "Te&xt Width", "text-width", TEXT_WIDTHS, @text_width, option_tip("md.text_width"), ->text_width_tip(Int32), [last_guide]) { |width| text_width_label width }
      paragraph = Crysterm::Action.new "&Paragraph", name: "rewrap-paragraph"
      paragraph.shortcut = "Alt+Q"
      paragraph.on(Crysterm::Event::Triggered) { rewrap_paragraph }
      tip paragraph, "Refill the caret's paragraph, or the selection's, to the wrap column: the text width, or 80 without one"
      document = Crysterm::Action.new "&Document", name: "rewrap-document"
      document.on(Crysterm::Event::Triggered) { rewrap_document }
      tip document, "Refill every paragraph of the document to the wrap column, as one undo step"
      # The label names the wrap column, kept up to date as the text width
      # changes.
      rewrap = tip format.add_submenu(rewrap_label, [paragraph, document]), "Refill paragraphs to the wrap column, a list item keeping its marker and a quote its markers"
      @text_width.on_change { rewrap.text = rewrap_label }
    end

    # The Rewrap submenu's label, naming the column it refills to
    # (`#wrap_column`): `Rewrap (to 72 Columns)`, or 80 without a text width.
    private def rewrap_label : String
      "Re&wrap (to #{wrap_column} Columns)"
    end

    # Puts the caret's item's state on the Task entry as the Format menu
    # opens: checked when the item at the caret — the first list item of
    # the selection, when there is one — has a task box; unchecked on an
    # item without one, and on a line that is no item. Read without moving
    # anything (opening a menu is not an edit): the editor's caret while
    # editing, the source of the viewer's otherwise.
    private def refresh_task_entry : Nil
      action = @task_action || return
      doc = @editor.document
      first, last = if @editor.focused?
                      selected_blocks
                    else
                      line = doc.block_at(editor_position(@viewer.cursor_position)).index
                      {line, line}
                    end
      action.checked = !first_item(doc, first, last).try(&.[1].task).nil?
    end

    # The first list item among lines *first* to *last* of *doc*, with its
    # line, or nil.
    private def first_item(doc : Crysterm::TextDocument, first : Int32, last : Int32) : {Int32, ListItem}?
      (first..last).each do |i|
        if item = ListItem.parse(doc.blocks[i].text)
          return {i, item}
        end
      end
      nil
    end

    # `Enter` on a list item with the caret past the marker: the item
    # continued below, or the list ended when the item is empty. Returns
    # whether that was the case; a selection is left to the editor, which
    # replaces it with the newline, and so is a line that only looks like
    # an item: a rule (`* * *`), a code block's line, an item opening a
    # fenced block (`- ``` `), whose next line is code.
    private def continue_list : Bool
      return false if @editor.selection?
      cursor = @editor.text_cursor
      block = cursor.block
      item = ListItem.parse(block.text) || return false
      return false if cursor.position_in_block < item.prefix_size
      return false if RULE.matches?(block.text) || (item.task.nil? && FENCE.matches?(item.text))
      doc = @editor.document
      return false if App.code_lines(doc, line = block.block_number)[line]
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

    # How many columns list item *item*, on line *index*, moves in
    # *direction* — and the lines selected with it: in, to nest under the
    # item above; out, to the indentation of the nearest shallower item or
    # the margin. Nil, with a notice, when it cannot move.
    private def item_delta(index : Int32, item : ListItem, direction : Int32) : Int32?
      if direction > 0
        # Markdown has no deeper level without an item to hold it: an item
        # nests one level under the item above, and no further — an item
        # already there, or indented past it, has nowhere to go in.
        unless parent = nesting_parent(index, item)
          notice "No list item above to nest under"
          return
        end
        delta = parent.inner_indent + parent.content_offset - item.inner_indent
        return delta if delta > 0
        notice "Already nested under the item above"
      else
        delta = outdented_indent(index, item) - item.inner_indent
        return delta if delta < 0
        notice "Not indented"
      end
      nil
    end

    # The nearest item above line *index* at *item*'s level or a shallower
    # one (in the same quote), under which *item* nests when indented — by
    # that item's content offset; nil when there is none, as for a list's
    # first item, which no indentation would nest.
    private def nesting_parent(index : Int32, item : ListItem) : ListItem?
      item_above(index) { |other| other.quote == item.quote && other.indent.size <= item.indent.size }
    end

    # The indentation (`ListItem#inner_indent`) of the nearest shallower
    # item above line *index* (in the same quote), or the margin.
    private def outdented_indent(index : Int32, item : ListItem) : Int32
      parent = item_above(index) { |other| other.quote == item.quote && other.indent.size < item.indent.size }
      parent ? parent.inner_indent : 0
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

    # The list items the caret's line or the selection's lines hold (a
    # code block's line holding none, whatever it looks like), each
    # yielded with the document and the position of its task box — where
    # the box is, or where one would go, after the marker's spacing — for
    # the block to edit, all in one undo step. Without a list item among
    # them, the lines of text become items first, a `- ` put after their
    # quote markers and indentation, since a task box belongs on an item;
    # a blank line, a code block's, a heading, a fence, a table row and a
    # rule do not; the block is told an item was made of the line (a box
    # the line's text started with is then the new item's). An item that
    # is an ATX heading, `- ## Title`, is made a setext one first, which
    # GFM boxes (`#untitle_task`). Returns whether there was an item or a
    # line to make one of and one was edited, with a notice when not. The
    # position is taken as each item's turn comes, so an earlier item's
    # edit has already moved it.
    private def edit_task_items(& : Crysterm::TextDocument, Int32, ListItem, Bool ->) : Bool
      editor = formatting_editor
      doc = editor.document
      first, last = selected_blocks
      # A code block's line is code, whatever it looks like.
      code = App.code_lines doc, last
      lines = (first..last).select { |i| !code[i] && ListItem.parse(doc.blocks[i].text) }
      bare = lines.empty?
      if bare
        lines = (first..last).select do |i|
          text = doc.blocks[i].text
          !text.blank? && !code[i] && !App.unbreakable_line?(text)
        end
      end
      if lines.empty?
        notice "Not a list item or a line of text"
        return false
      end
      changed = false
      doc.edit do
        lines.each do |i|
          if bare
            lead = QUOTE_LEAD.match(doc.blocks[i].text).try(&.[0].size) || 0
            Crysterm::TextCursor.new(doc, doc.blocks[i].position + lead).insert_text "- "
          end
          block = doc.blocks[i]
          item = ListItem.parse(block.text) || next
          at = block.position + item.quote.size + item.indent.size + item.content_offset
          next unless item.task || untitle_task(doc, block, at, item.text)
          yield doc, at, item, bare
          changed = true
        end
        nil
      end
      edited if changed
      changed
    end

    # An item's ATX heading, *text* at *at* in *block* of *doc*, about to
    # take a task box at *at*, made the setext heading GFM boxes, as
    # `#shift_task_heading` keeps a task item's: `- ## Title` becomes
    # `- Title` over `---` (`===` for `#`), its hashes, and any closing
    # ones, taken off. Text that is no heading stays. Returns false, the
    # line left, for a heading below level 2, which a task item cannot
    # have, with the notice Demote gives.
    private def untitle_task(doc : Crysterm::TextDocument, block : Crysterm::TextBlock, at : Int32, text : String) : Bool
      m = HEADING.match(text)
      return true unless m && m["lead"].empty? && (hashes = m["hashes"]?)
      if hashes.size > 2
        notice "No task heading below level 2"
        return false
      end
      title = text[m[0].size..].sub(/(?:\A|[ \t]+)#+[ \t]*\z/, "").rstrip
      from = at + m[0].size + title.size
      underline = title.empty? ? "" : task_underline(block.text[0, at - block.position], hashes.size)
      Crysterm::TextCursor.new(doc, from, block.position + block.text.size).insert_text underline
      Crysterm::TextCursor.new(doc, at, at + m[0].size).remove_selected_text
      true
    end

    # The line that makes a task item's text a heading at *level*, 1 or
    # 2, with the newline before it: `===` or `---` at the item's content
    # column, under *lead*, the quote and list markers before the box.
    private def task_underline(lead : String, level : Int32) : String
      "\n#{lead.gsub(/[^>\t]/, ' ')}#{level == 1 ? "===" : "---"}"
    end

    # Wraps the selection — or the word at the caret — in *marker*, or
    # unwraps it, and leaves the text selected; with nothing to wrap,
    # inserts the pair and puts the caret between. The markers hug the
    # text: spaces at the selection's ends stay outside them, since `**word
    # **` is no emphasis in Markdown. Returns true.
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
      # The spaces at the selection's ends are left out first, so the
      # markers already around the text are found and taken off, and new
      # ones go against it.
      from, to = cursor.selection_start, cursor.selection_end
      text = doc.plain_text(from, to)
      unless text.blank?
        from += text.size - text.lstrip.size
        to -= text.size - text.rstrip.size
      end
      from, to = widen(doc, from, to, marker[0])
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
      # A marker on one end alone (`` `code `` selected) wraps nothing.
      return if run == 0 || text.size < 2 * run
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

    # The lines, first and last, of the paragraph around line *index* of
    # *doc* that Format → Code Block fences: the run of lines no blank
    # line ends, nor a heading, a fence or a fenced block's code (*code*,
    # `.code_lines` of the whole of *doc*), which are no part of it; a
    # heading on line *index* is alone.
    private def code_paragraph(doc : Crysterm::TextDocument, code : Array(Bool), index : Int32) : {Int32, Int32}
      ends = ->(i : Int32) do
        text = doc.blocks[i].text
        text.blank? || code[i] || FENCE.matches?(text) || App.heading?(text)
      end
      first = last = index
      return {first, last} if App.heading?(doc.blocks[index].text)
      while first > 0 && !ends.call(first - 1)
        first -= 1
      end
      while last + 1 < doc.block_count && !ends.call(last + 1)
        last += 1
      end
      {first, last}
    end

    # The fenced code blocks of *doc*, each as the lines of its opening
    # and its closing fence and its last line; the closing fence is nil
    # for a block that runs to the end of the document, or that an outdent
    # ends inside a list item, its last line then the one before the
    # outdented line. A block opens where `.code_lines`' scan opens one, so
    # a fence shown inside a block's code, in an indented code block, or
    # on a paragraph's line indented four columns (its text run on) does
    # not count; the scan tells a fence that closes a block from one an
    # outdent ended the block on, which opens another.
    private def fenced_blocks(doc : Crysterm::TextDocument) : Array({Int32, Int32?, Int32})
      blocks = [] of {Int32, Int32?, Int32}
      scan = CodeScan.new
      open = nil
      doc.block_count.times do |i|
        text = doc.blocks[i].text
        next if scan.code?(text)
        fence = FENCE.matches?(text)
        if start = open
          # The first line after the opening fence that is no code ends
          # the block: its closing fence, or the line an outdent ended it on.
          closing = fence && !scan.fenced?
          blocks << (closing ? {start, i, i} : {start, nil, i - 1})
          open = nil
          next if closing
        end
        open = i if scan.fenced?
      end
      open.try { |start| blocks << {start, nil, doc.block_count - 1} }
      blocks
    end

    # Lines *first* to *last* of *doc* put between two fences, with the
    # first line's quote markers and indentation; the editor's caret, or
    # selection, kept on the same text.
    private def fence(first : Int32, last : Int32) : Nil
      doc = @editor.document
      lead = QUOTE_LEAD.match(doc.blocks[first].text).try(&.[0]) || ""
      from = doc.blocks[first].position
      to = doc.blocks[last].position + doc.blocks[last].size
      cursor = @editor.text_cursor
      anchor, position = cursor.anchor, cursor.position
      doc.edit do
        Crysterm::TextCursor.new(doc, to).insert_text "\n#{lead}```"
        Crysterm::TextCursor.new(doc, from).insert_text "#{lead}```\n"
        nil
      end
      # Past the last line (a whole-line selection ends at the next line's
      # start) a position moves over both fences, inside over the opening.
      size = lead.size + 4
      shift = ->(at : Int32) { at > to ? at + 2 * size : (at >= from ? at + size : at) }
      @editor.text_cursor = Crysterm::TextCursor.new(doc, shift.call(anchor), shift.call(position))
    end

    # The fence lines *open* and *close* (nil for none) taken out of
    # *doc*, each with its line break; the editor's caret, or selection,
    # kept on the same text.
    private def unfence(doc : Crysterm::TextDocument, open : Int32, close : Int32?) : Nil
      if close && close == open + 1 && close == doc.block_count - 1
        # An empty block ending the document: the two fences go as one span,
        # with the break before them, where two would overlap on it.
        last = doc.blocks[close]
        return replace_spans doc, [{Math.max(doc.blocks[open].position - 1, 0), last.position + last.size, ""}]
      end
      spans = [line_span(doc, open)]
      close.try { |line| spans << line_span(doc, line) }
      replace_spans doc, spans
    end

    # Line *index* of *doc* with its line break, as the positions from and
    # to and nothing to put there (`#replace_spans`): the break after it,
    # or before it for the last line.
    private def line_span(doc : Crysterm::TextDocument, index : Int32) : {Int32, Int32, String}
      block = doc.blocks[index]
      if index + 1 < doc.block_count
        {block.position, doc.blocks[index + 1].position, ""}
      else
        {Math.max(block.position - 1, 0), block.position + block.size, ""}
      end
    end

    # The heading of the caret's section moved *by* levels, its hashes
    # replaced: the caret's line when it is a heading (or a setext
    # heading's text or underline), else the nearest heading above it —
    # so the entries work from anywhere in the section's text, as the task
    # entries do from anywhere on the line — a line in a fenced or
    # indented code block being no heading. A setext heading (`Title` over
    # `===` or `---`) moved becomes an ATX one at the new level, `## Title`
    # or `### Title` from a `---` one, its lines joined into one; a `===`
    # one promoted loses its underline and is a paragraph. Before the
    # first heading there is no section, and the caret's line itself is
    # shifted: a line of text becomes a `#` heading on Demote and stays on
    # Promote, and a code block's line stays as it is. A task item's
    # heading moves by `#shift_task_heading` instead. The caret keeps its
    # place in the text.
    private def shift_heading(by : Int32) : Bool
      editor = formatting_editor
      doc = editor.document
      unless heading = section_heading(doc, doc.block_at(editor.cursor_position).index)
        notice "Not a heading"
        return false
      end
      target = heading.level + by
      if lead = App.task_lead(doc.blocks[heading.first].text)
        return shift_task_heading(doc, heading, lead, target)
      end
      if target > 6
        notice "No heading level below 6"
        return false
      elsif target < 0
        notice "Not a heading"
        return false
      end
      hashes = target == 0 ? "" : "#" * target + " "
      replace_spans doc, heading_spans(doc, heading, hashes)
      edited
      true
    end

    # `#shift_heading` on a task item's text, `- [ ] Title` (*lead* the
    # markers before its box), at level *target*. GFM gives the box only
    # to an item whose first paragraph starts with it, which an underline
    # may make a setext heading, as github.com shows it: `- ## [ ] Title`
    # is a heading with no box and `- [ ] ## Title` a task whose text is
    # `## Title`. So the heading goes between a paragraph, `===` (level 1)
    # and `---` (level 2) under the paragraph at the item's content
    # column, the box kept, and no lower: Markdown has no task heading
    # past level 2, and the entry says so and leaves the line.
    private def shift_task_heading(doc : Crysterm::TextDocument, heading : Heading, lead : String, target : Int32) : Bool
      if target > 2
        notice "No task heading below level 2"
        return false
      elsif target < 0
        notice "Not a heading"
        return false
      end
      if !heading.setext?
        last = doc.blocks[paragraph_end(heading.first, App.code_lines(doc))]
        at = last.position + last.text.size
        replace_spans doc, [{at, at, task_underline(lead, target)}]
      elsif target == 0
        replace_spans doc, heading_spans(doc, heading, "")
      else
        underline = doc.blocks[heading.last]
        run = /[=-]+/.match(underline.text) || return false
        from = underline.position + run.begin
        replace_spans doc, [{from, from + run[0].size, target == 1 ? "===" : "---"}]
      end
      edited
      true
    end

    # The edits that give *heading* of *doc* the prefix *hashes* (empty
    # for none), as `#replace_spans` takes them: an ATX heading's hashes
    # replaced; a setext heading's underline taken off and, unless it is
    # to be a paragraph, its lines joined into one after the hashes.
    private def heading_spans(doc : Crysterm::TextDocument, heading : Heading, hashes : String) : Array({Int32, Int32, String})
      first = doc.blocks[heading.first]
      m = HEADING.match(first.text) || return [] of {Int32, Int32, String}
      start = first.position + m["lead"].size
      return [{start, first.position + m[0].size, hashes}] unless heading.setext?
      spans = [] of {Int32, Int32, String}
      spans << {start, start, hashes} unless hashes.empty?
      (heading.first...heading.last).each do |i|
        line = doc.blocks[i]
        next_line = doc.blocks[i + 1]
        from = line.position + line.text.rstrip.size
        if i + 1 == heading.last
          spans << {from, next_line.position + next_line.size, ""}
        elsif !hashes.empty?
          spans << {from, next_line.position + (QUOTE_LEAD.match(next_line.text).try(&.[0].size) || 0), " "}
        end
      end
      spans
    end

    # The heading whose section line *index* of *doc* is in: the one on
    # *index*, or whose text or underline it is, else the nearest heading
    # above it, no code block's line being one (`.headings`). Line *index*
    # alone, at level 0, when there is none; nil when *index* is then a
    # code block's own line.
    private def section_heading(doc : Crysterm::TextDocument, index : Int32) : Heading?
      code = App.code_lines doc
      App.headings(doc, code).reverse_each do |heading|
        return heading if heading.first <= index
      end
      Heading.new(index, index, 0) unless code[index]
    end

    # Replaces each span of *doc* — its start, its end and the text put
    # there, the spans in document order and apart — as one undo step,
    # the editor's caret, or selection, kept on the same text: a position
    # past a span moves with the text after it, one inside it goes to the
    # end of what replaced it.
    private def replace_spans(doc : Crysterm::TextDocument, spans : Array({Int32, Int32, String})) : Nil
      cursor = @editor.text_cursor
      anchor, position = cursor.anchor, cursor.position
      doc.edit do
        spans.reverse_each do |(from, to, text)|
          edit = Crysterm::TextCursor.new(doc, from, to)
          text.empty? ? edit.remove_selected_text : edit.insert_text(text)
        end
        nil
      end
      @editor.text_cursor = Crysterm::TextCursor.new(doc, shifted(spans, anchor), shifted(spans, position))
    end

    # Position *at* of a document after `#replace_spans` made *spans*.
    private def shifted(spans : Array({Int32, Int32, String}), at : Int32) : Int32
      offset = 0
      spans.each do |(from, to, text)|
        if at >= to
          offset += text.size - (to - from)
        elsif at > from
          return from + offset + text.size
        else
          break
        end
      end
      at + offset
    end

    # The editor, for a Format entry (and a paste, `app_clipboard.cr`):
    # shown when it is hidden, and with the viewer leading — the entry
    # chosen while reading, in the viewer or the table of contents — its
    # caret put on the source of the viewer's, so the entry acts on what the
    # reader looks at.
    private def formatting_editor : Crysterm::Widget::PlainTextEdit
      from_viewer = !@editor.focused?
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
