module Md
  class App
    # The questions md asks — a file name to open or save as, a pattern and
    # its replacement, a line number, what to do with unsaved changes — and
    # the two ways it asks them, View → Dialog Style (`DialogStyle`): in
    # place of the status bar, the way vi's command line replaces its
    # status line (Crysterm's `LinePrompt`, through `StatusBar#prompt`),
    # the default; or in a modal dialog in the middle of the window
    # (Crysterm's `InputDialog` and `MessageBox`, Qt's
    # `QInputDialog::getText` and `QMessageBox`). Every question goes
    # through `#ask_text` or `#ask_choice`, which pick the style, so a
    # caller asks the same way whichever is on; the choice is kept across
    # runs with the other settings.
    #
    # A line prompt takes a line of text with `Tab` completing file names,
    # `Up` recalling earlier answers, `Enter` answering and `Escape` (or
    # `Backspace` on an empty line) giving up. A choice — Save, Don't save
    # or Cancel — is a line prompt answered by one key, its label naming
    # the keys: `Save changes to notes.md? (y)es, (n)o, (c)ancel: `; a key
    # answers at once, as the Replace question's do, and `Enter` on an
    # empty line, like `Escape`, is no answer, which the caller takes as
    # the cancelling choice. The Replace question itself (`y`/`n`/`a`/`q`
    # at each match, `app_search.cr`) is a line prompt in both styles: it
    # is asked once per match, and a dialog at every match would be in the
    # way of the stepping it drives.
    #
    # Both styles answer through a callback. The blocking `Window#prompt`
    # and `Window#ask` are not used: they block the fiber that calls them,
    # which from a menu entry or a key is the render fiber.
    enum DialogStyle
      # A dialog in the middle of the window.
      Modal
      # A prompt in place of the status bar.
      LinePrompt
    end

    # A choice offered by `#ask_choice`: the dialog's button label and the
    # line prompt's form of it with the answering key in parentheses,
    # `{"Save", "(y)es"}`.
    alias Choice = {String, String}

    # A reactive property, so the View → Dialog Style entries bind to it
    # (`#build_menus`); `#dialog_style` and `#dialog_style=` are its plain
    # face.
    @dialog_style : Crysterm::Reactive::Property(DialogStyle) = Crysterm::Reactive::Property.new(DialogStyle::LinePrompt)
    # The single-key handler on the prompt's field while a choice question
    # is up there, and the choice it took.
    @choice_key : EventHandler::Subscription?
    @choice_answer : Int32?

    def dialog_style : DialogStyle
      @dialog_style.value
    end

    # Picks how questions are asked (View → Dialog Style); a question
    # already up stays as it is.
    def dialog_style=(style : DialogStyle) : DialogStyle
      @dialog_style.value = style
    end

    # Asks for a line of text and delivers it to *callback*, or nil when
    # the question was given up. *label* is the prompt's, as vi spells
    # them (`Open: `, `/`, `:`); *question* is the dialog's text, by
    # default the label itself (`Open:`), for the labels that read as one.
    # The field starts at *value*.
    def ask_text(label : String, value : String = "", question : String? = nil, &callback : String? ->) : Nil
      case @dialog_style.value
      in .line_prompt? then status_prompt(label, value, &callback)
      in .modal?       then read_in_dialog(question || label.strip, value, &callback)
      end
    end

    # Asks *question* with *choices* to pick from and delivers the index of
    # the one picked to *callback*, or nil when the question was dismissed
    # (`Escape`; at a prompt, an empty `Enter` or an answer that is none of
    # the keys).
    def ask_choice(question : String, choices : Array(Choice), &callback : Int32? ->) : Nil
      case @dialog_style.value
      in .line_prompt? then choose_in_prompt(question, choices.map(&.[1]), &callback)
      in .modal?       then choose_in_dialog(question, choices.map(&.[0]), &callback)
      end
    end

    # The text question as an `InputDialog`, centered and sized to
    # *question* like `InputDialog.read` makes it. The dialog goes once it
    # has finished with itself (it repaints as the answer is delivered),
    # and the callback runs then, on a clean slate — it may open the next
    # question, or quit.
    private def read_in_dialog(question : String, value : String, &callback : String? ->) : Nil
      geometry = Crysterm::Mixin::OkCancelDialog.presenter_geometry(@window, question)
      dialog = Crysterm::Widget::InputDialog.new(**geometry)
      dialog.open(question, value) do |answer|
        @window.post do
          dialog.destroy
          callback.call answer
        end
      end
    end

    # The choice question as a `MessageBox` with a button per choice;
    # `Escape` dismisses it. Likewise destroyed before the callback runs.
    private def choose_in_dialog(question : String, labels : Array(String), &callback : Int32? ->) : Nil
      geometry = Crysterm::Mixin::OkCancelDialog.presenter_geometry(@window, question)
      box = Crysterm::Widget::MessageBox.new(**geometry)
      box.open(question, labels) do |index|
        @window.post do
          box.destroy
          callback.call index
        end
      end
    end

    # The prompt in place of the status bar. With the bars hidden (`F4`,
    # `#bars?`) the status bar is shown for the question and hidden again
    # once it is answered or given up (`#wire_prompt_bar`), the way an
    # editor's command line appears over a full-screen view. The bar is
    # shown after the prompt opens: opening cancels a question still up,
    # whose end would hide the bar again.
    private def status_prompt(label : String, value : String, &callback : String? ->) : Nil
      @main.status_bar.prompt(label, value, &callback)
      @main.status_bar.show unless @bars.value
    end

    # Hides the status bar again after a prompt that showed it (from
    # `#build_status`): the prompt's end comes before its callback, so a
    # question that asks another shows the bar again at once.
    private def wire_prompt_bar : Nil
      prompt = @main.status_bar.line_prompt
      conceal = -> { @main.status_bar.hide unless @bars.value }
      prompt.on(Crysterm::Event::Submitted) { conceal.call }
      prompt.on(Crysterm::Event::Cancelled) { conceal.call }
    end

    # The choice question in place of the status bar, answered by one key:
    # the prompt's field takes the key as text, and a handler registered
    # after the prompt's own listener — so it runs once the key is in —
    # hands it over, submitting an empty answer (which the field's Up/Down
    # history skips), as the Replace question does (`#ask_replace`). An
    # answer typed out and entered counts by its first letter.
    private def choose_in_prompt(question : String, forms : Array(String), &callback : Int32? ->) : Nil
      keys = forms.map { |form| form[form.index!('(') + 1].downcase }
      prompt = @main.status_bar.line_prompt
      status_prompt("#{question} #{forms.join(", ")}: ", "") do |text|
        @choice_key.try &.off
        @choice_key = nil
        answer = @choice_answer
        @choice_answer = nil
        if answer.nil? && text && (first = text.strip.downcase[0]?)
          answer = keys.index(first)
        end
        callback.call answer
      end
      field = prompt.field
      @choice_key = field.on(Crysterm::Event::KeyPress) do |e|
        next if e.key || !(index = keys.index(e.char.downcase))
        @choice_answer = index
        field.value = ""
        field.submit
      end
    end

    private def dialog_style_label(style : DialogStyle) : String
      case style
      in .modal?       then "&Modal Dialogs"
      in .line_prompt? then "&Line Prompts"
      end
    end
  end
end
