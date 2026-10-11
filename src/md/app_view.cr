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
    # View → Rulers (`#rulers?`) puts a column ruler along the top row of
    # each pane and a row ruler down its left — Crysterm's
    # `AbstractScrollArea#rulers`, counted in the text's columns, so with a
    # text width set and centered the tape starts where the text does, and
    # in the editor the row ruler sits outside the line-number gutter, which
    # keeps numbering source lines while the ruler numbers rows.
    #
    # The widths offered; 0 is no cap.
    TEXT_WIDTHS = [0, 72, 80, 100, 120]

    # Reactive properties, so the menu entries bind to them
    # (`#build_menus`); the plain accessors below are their faces.
    @soft_wrap : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @text_width : Crysterm::Reactive::Property(Int32) = Crysterm::Reactive::Property.new(0)
    @center_text : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @rulers : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

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

    def rulers? : Bool
      @rulers.value
    end

    # Shows or hides the rulers on both panes (View → Rulers).
    def rulers=(value : Bool) : Bool
      @rulers.value = value
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
      @text_width.on_change { apply_text_width }
      @center_text.on_change { apply_text_width }
      @rulers.on_change do
        @editor.rulers = @rulers.value
        @viewer.rulers = @rulers.value
        refresh_status
      end
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

    # The Text Width entry's label for *width*: the count, or Unlimited.
    private def text_width_label(width : Int32) : String
      case width
      when   0 then "&Unlimited"
      when 120 then "1&20 Columns"
      else          "&#{width} Columns"
      end
    end
  end
end
