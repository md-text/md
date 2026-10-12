module Md
  class App
    # The View menu's layout choices for the text: whether the editor soft
    # wraps, how wide the text may be and where the column sits — Qt's
    # `QPlainTextEdit::setLineWrapMode` and `QTextEdit`'s
    # `setLineWrapColumnOrWidth` in md's clothes.
    #
    # View → Soft Wrap (`#soft_wrap?`) is the editor's line wrap mode: on,
    # a long line folds at the pane's edge (`WidgetWidth`); off, it runs
    # past it and the pane scrolls sideways (`NoWrap`). The viewer always
    # wraps, as a page does.
    #
    # View → Text Width (`#text_width`) caps the width the text is laid
    # out in — 72, 80, 100 or 120 columns, or no cap — for a wide terminal,
    # where a line that runs the whole width is hard to read. It applies to
    # both panes (Crysterm's `line_wrap_column`), so with Sync Cursor the
    # two keep the same measure. View → Center Text (`#center_text?`)
    # places the column in the middle of a wider pane rather than at its
    # left edge (`line_wrap_column_alignment`).
    #
    # View → Rulers → Horizontal (`#horizontal_ruler?`) puts a column ruler
    # along the top row of each pane and Vertical (`#vertical_ruler?`) a row
    # ruler down its left, each on its own (`#rulers=` sets the pair) —
    # Crysterm's `AbstractScrollArea#column_ruler` and
    # `#row_ruler`, counted in the text's columns, so with a
    # text width set and centered the tape starts where the text does, and
    # in the editor the row ruler stands between the line-number gutter and
    # the text, as ticks alone while the gutter numbers the lines. View →
    # Guides (`#guides?`) draws a vertical line in the column just before the
    # text and the one just after it (`AbstractScrollArea#guides_enabled`):
    # with a text width set in a wider pane, the capped column's edges; with
    # the rulers shown, more guides are pulled off the column ruler with the
    # mouse, dragged by their ruler end, and dropped on another guide, or
    # back on the ruler, to be rid of them. The two edge guides stay.
    #
    # View → Hard Wrap (`#hard_wrap?`) is Kate's static word wrap
    # (Settings → Editor → Editing → Static Word Wrap) in the editor: a line
    # that grows past the wrap column as it is typed is broken at the last
    # space before the column and the rest carried to a new line
    # (Crysterm's `hard_wrap_column`), the keystroke and the wrap one undo
    # step. The column (`#wrap_column`) is the Text Width when one is set,
    # else `HARD_WRAP_COLUMN`. The carried line keeps its place in the
    # Markdown — a list item's content indentation, a blockquote's marker
    # (`MarkdownEdit#hard_wrap_prefix`, `app_edit.cr`) — and the lines that
    # cannot be broken without changing their meaning (a code block's, a
    # heading, a table row) are left alone. Off by default: soft wrap shows
    # a long line folded without touching the source. Format → Rewrap
    # (`app_edit.cr`) refills a paragraph, or the document, to the same column.
    #
    # The widths offered; 0 is no cap.
    TEXT_WIDTHS = [0, 72, 80, 100, 120]

    # The hard wrap column while no Text Width is set: Kate's default too.
    HARD_WRAP_COLUMN = 80

    # Reactive properties, so the menu entries bind to them
    # (`#build_menus`); the plain accessors below are their faces.
    @soft_wrap : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @text_width : Crysterm::Reactive::Property(Int32) = Crysterm::Reactive::Property.new(0)
    @center_text : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @horizontal_ruler : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @vertical_ruler : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @guides : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @hard_wrap : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    def soft_wrap? : Bool
      @soft_wrap.value
    end

    # Turns the editor's soft wrap on or off (View → Soft Wrap).
    def soft_wrap=(value : Bool) : Bool
      @soft_wrap.value = value
    end

    # The text width in columns, 0 for the pane's width.
    def text_width : Int32
      @text_width.value
    end

    # Caps the text width (View → Text Width); any width goes, the menu
    # offers `TEXT_WIDTHS`.
    def text_width=(value : Int32) : Int32
      @text_width.value = Math.max(value, 0)
    end

    def center_text? : Bool
      @center_text.value
    end

    # Centers the text column in a wider pane, or keeps it at the left
    # (View → Center Text). Makes a difference only with a text width set.
    def center_text=(value : Bool) : Bool
      @center_text.value = value
    end

    def horizontal_ruler? : Bool
      @horizontal_ruler.value
    end

    # Shows or hides the column ruler on both panes (View → Rulers → Horizontal).
    def horizontal_ruler=(value : Bool) : Bool
      @horizontal_ruler.value = value
    end

    def vertical_ruler? : Bool
      @vertical_ruler.value
    end

    # Shows or hides the row ruler on both panes (View → Rulers → Vertical).
    def vertical_ruler=(value : Bool) : Bool
      @vertical_ruler.value = value
    end

    # Shows or hides both rulers at once (there is no `rulers?`: Crysterm's
    # means either, which a pair of entries has no use for).
    def rulers=(value : Bool) : Bool
      self.horizontal_ruler = value
      self.vertical_ruler = value
    end

    def guides? : Bool
      @guides.value
    end

    # Shows or hides the guides on both panes (View → Guides).
    def guides=(value : Bool) : Bool
      @guides.value = value
    end

    def hard_wrap? : Bool
      @hard_wrap.value
    end

    # Turns the editor's hard wrap on or off (View → Hard Wrap).
    def hard_wrap=(value : Bool) : Bool
      @hard_wrap.value = value
    end

    # The column lines are hard wrapped and paragraphs refilled to: the
    # Text Width, or `HARD_WRAP_COLUMN` without one.
    def wrap_column : Int32
      text_width > 0 ? text_width : HARD_WRAP_COLUMN
    end

    # The choices take effect when they change, whoever changed them (a
    # menu entry bound to the property, a setter, the settings restored at
    # start). The defaults are the panes' own, so nothing is applied until
    # a choice differs from them.
    private def wire_view : Nil
      @soft_wrap.on_change do
        @editor.wrap_content = @soft_wrap.value
        refresh_status
      end
      @text_width.on_change do
        apply_text_width
        apply_hard_wrap
      end
      @center_text.on_change { apply_text_width }
      @horizontal_ruler.on_change do
        @editor.column_ruler = @horizontal_ruler.value
        @viewer.column_ruler = @horizontal_ruler.value
        refresh_status
      end
      @vertical_ruler.on_change do
        @editor.row_ruler = @vertical_ruler.value
        @viewer.row_ruler = @vertical_ruler.value
        refresh_status
      end
      @guides.on_change do
        @editor.guides_enabled = @guides.value
        @viewer.guides_enabled = @guides.value
        refresh_status
      end
      @hard_wrap.on_change { apply_hard_wrap }
    end

    # Puts the wrap column on the editor, or takes it off.
    private def apply_hard_wrap : Nil
      @editor.hard_wrap_column = @hard_wrap.value ? wrap_column : nil
      refresh_status
    end

    # Puts the width and its placement on both panes.
    private def apply_text_width : Nil
      alignment = @center_text.value ? Tput::AlignFlag::HCenter : Tput::AlignFlag::Left
      {@editor, @viewer}.each do |pane|
        pane.line_wrap_column = @text_width.value
        pane.line_wrap_column_alignment = alignment
      end
      refresh_status
    end

    # View → Text Width → To Last Guide: the width set to the column of the
    # rightmost guide pulled onto the focused pane (the editor while
    # editing, the viewer otherwise) — where the text is to end — so a guide
    # dragged to a good place becomes the width, as a design tool's margin
    # guide does. The two bound guides are not candidates: they are the
    # width. A notice without a guide to go by, or with the guides hidden.
    # Returns whether the width was set.
    def text_width_to_last_guide : Bool
      pane = @editor.focused? ? @editor : @viewer
      unless @guides.value
        notice "Guides are hidden (View → Guides)"
        return false
      end
      unless column = pane.guides.max?
        notice "No guide to set the width by: pull one off the column ruler"
        return false
      end
      self.text_width = column
      notice "Text width #{column}, to the last guide"
      true
    end

    # The Text Width entry's label for *width*: the count, or Unlimited.
    private def text_width_tip(width : Int32) : String
      width == 0 ? "Lay the text out as wide as the pane" : "Lay the text out in at most #{width} columns, in both panes"
    end

    private def text_width_label(width : Int32) : String
      case width
      when   0 then "&Unlimited"
      when 120 then "1&20 Columns"
      else          "&#{width} Columns"
      end
    end
  end
end
