module Md
  class App
    # Mouse support, modeled on vi's `set mouse=` option: which of md's two
    # activities the mouse serves. While it serves neither, mouse reporting is
    # off in the terminal, so the terminal's own text selection and copy work
    # everywhere on the screen.
    enum MouseMode
      # `mouse=a` — always.
      All
      # `mouse=n` — while reading: the viewer or the table of contents has
      # focus (vi's Normal mode).
      Normal
      # `mouse=i` — while editing: the editor has focus (vi's Insert mode).
      Insert
      # `mouse=` — never.
      Off

      # The value as `set mouse=` spells it.
      def vi_value : String
        case self
        in .all?    then "a"
        in .normal? then "n"
        in .insert? then "i"
        in .off?    then ""
        end
      end

      # The mode after this one in the cycle the status bar button runs.
      def next_mode : MouseMode
        case self
        in .all?    then Normal
        in .normal? then Insert
        in .insert? then Off
        in .off?    then All
        end
      end

      # Whether the mouse serves the activity at hand.
      def active?(editing : Bool) : Bool
        case self
        in .all?    then true
        in .normal? then !editing
        in .insert? then editing
        in .off?    then false
        end
      end
    end

    # Percentages of the status bar the information fields take; the name
    # field takes what is left, and the two buttons their fixed widths.
    POSITION_WIDTH = "13%"
    SIZE_WIDTH     = "21%"
    ENCODING_WIDTH = "9%"
    MODIFIED_WIDTH = "10%"

    # A reactive property, so the Options → Mouse entries bind to it
    # (`#build_menus`); `#mouse_mode` and `#mouse_mode=` are its plain face.
    @mouse_mode : Crysterm::Reactive::Property(MouseMode) = Crysterm::Reactive::Property.new(MouseMode::All)

    def mouse_mode : MouseMode
      @mouse_mode.value
    end

    # Switches the mouse mode; it is applied to the terminal when it changes
    # (the property's change handler, in `#build_status`).
    def mouse_mode=(mode : MouseMode) : MouseMode
      @mouse_mode.value = mode
    end

    # Steps to the next mouse mode (the status bar button's click, `F5`).
    def cycle_mouse_mode : MouseMode
      self.mouse_mode = @mouse_mode.value.next_mode
    end

    # Whether the mouse currently serves: the mode, against which pane has
    # focus.
    def mouse_active? : Bool
      @mouse_mode.value.active? @editor.focused?
    end

    # Fills the status bar: the document's name, the caret or reading
    # position, the size, encoding and line endings, the modified flag, then
    # the two toggles — INS/OVR for the editor's overwrite mode and `mouse=`
    # for the mouse mode — and wires the refreshes. Fields are a
    # `Layout::HBox` row (see `StatusBar`), so the percentage widths divide
    # the bar at any terminal width. The name field is the bar's one normal
    # field: it takes the rest of the width, and gives it up to a passing
    # notice (`#notice`, the bar's `show_message`).
    private def build_status : Nil
      bar = @main.status_bar
      bar.add_widget @name_field
      {@position_field, @size_field, @encoding_field, @modified_field,
       @overwrite_button, @mouse_button}.each { |field| bar.add_permanent_widget field }

      # The toggles act on click without taking the keyboard focus from the
      # pane being used (Qt's tool buttons likewise do not focus on click).
      {@overwrite_button, @mouse_button}.each &.focus_policy = Crysterm::Widget::FocusPolicy::None
      @overwrite_button.on_clicked { @editor.overwrite_mode = !@editor.overwrite_mode? }
      @mouse_button.on_clicked { cycle_mouse_mode }

      # The Save As prompt completes file names with Tab, as a shell does.
      bar.line_prompt.completer = Crysterm::Widget::LinePrompt.path_completer

      @editor.on(Crysterm::Event::CursorPositionChanged) { refresh_status }
      @editor.on(Crysterm::Event::OverwriteModeChanged) { refresh_status }
      @viewer.on(Crysterm::Event::Scroll) { refresh_status }
      # The reading position depends on the viewer's size, known only once
      # it is laid out (and again after every resize).
      @viewer.on(Crysterm::Event::Resize) { refresh_status }
      Pane.each { |pane| widget(pane).on(Crysterm::Event::FocusIn) { refresh_status } }
      # The mode decides per focused pane whether the mouse serves; Crysterm
      # applies the answer to the terminal on every focus change, and
      # `#mouse_mode=` re-applies it when the mode changes.
      @window.mouse_policy = ->(focused : Crysterm::Widget?) { @mouse_mode.value.active?(focused.same?(@editor)) }
      @mouse_mode.on_change do
        @window.apply_mouse_policy
        refresh_status
      end
      refresh_status
    end

    # Brings every status field up to date with the document and the modes.
    def refresh_status : Nil
      @name_field.text = " #{name_text}"
      @position_field.text = position_text
      lines, words, crlf = measure
      @size_field.text = "#{lines} #{lines == 1 ? "line" : "lines"}, #{words} #{words == 1 ? "word" : "words"}"
      @encoding_field.text = "UTF-8 #{crlf ? "CRLF" : "LF"}"
      @modified_field.text = @editor.document.modified? ? "✎ modified" : ""
      @overwrite_button.text = @editor.overwrite_mode? ? "OVR" : "INS"
      @mouse_button.text = "#{mouse_icon}=#{@mouse_mode.value.vi_value}"
      refresh_menus
    end

    # Reports an error that escaped one of md's handlers the way `#run` has
    # Crysterm report them (`MainWindow#report_handler_errors`): the app goes
    # on, so unsaved text can still be saved, a notice names the error in
    # the status bar, and the backtrace goes to the log (`CLI` points
    # Crysterm's `log.file` at md's cache directory).
    def internal_error(error : Exception) : Nil
      @main.report_handler_error(error, NOTICE_TIMEOUT) { |e| error_notice e }
    end

    # Crysterm's notice for *error*, with the leading space md's fields and
    # notices share.
    private def error_notice(error : Exception) : String
      " #{Crysterm::Widget::MainWindow.handler_error_message(error)}"
    end

    # The mouse field's icon: the registry's mouse glyph at the terminal's
    # tier — the pictograph where the terminal is known to render it, else
    # the letter `M`.
    private def mouse_icon : String
      @main.glyph_str Crysterm::Glyphs::Role::IconMouse
    end

    # The document's name as the status bar shows it, with its state.
    private def name_text : String
      name = @source.name || "[No Name]"
      streaming? ? "#{name} (streaming)" : name
    end

    # The caret's line and column while editing; while reading, the
    # viewer's position the way vi reports it (`All`, `Top`, `Bot`, or a
    # percentage).
    private def position_text : String
      if @editor.focused?
        Crysterm::Widget::CursorPositionLabel.text_for @editor
      else
        Crysterm::Widget::ScrollPositionLabel.text_for @viewer
      end
    end

    # Line count, word count and whether the text uses CRLF line endings,
    # recomputed only after the text changed.
    private def measure : {Int32, Int32, Bool}
      @measured ||= begin
        text = markdown
        lines = text.count('\n')
        lines += 1 unless text.empty? || text.ends_with?('\n')
        # Runs of non-whitespace, counted in one pass with nothing allocated.
        words = 0
        in_word = false
        text.each_char do |c|
          if c.whitespace?
            in_word = false
          elsif !in_word
            in_word = true
            words += 1
          end
        end
        {lines, words, text.includes?("\r\n")}
      end
    end

    # Forgets the cached measurements; the next refresh recomputes them.
    private def text_changed : Nil
      @measured = nil
    end

    # Shows *text* in place of the name field for a while (a save result, a
    # warning); the name comes back when the notice clears, or a newer
    # notice replaces it.
    private def notice(text : String) : Nil
      @main.status_bar.show_message " #{text}", NOTICE_TIMEOUT
    end
  end
end
