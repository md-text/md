require "./spec_helper"

# A question is answered the way View → Dialog Style says: at the status
# bar's prompt (the default), or in a modal dialog in the middle of the
# window. The same question is asked both ways here.

DIALOG_DOC = (1..9).map { |i| "Line #{i}" }.join("\n\n") + "\n"

# The modal input dialog's field given up with Escape.
private def escape_dialog(window)
  dialog = input_dialog(window) || fail("no input dialog is up")
  dialog.line_edit.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Escape)
end

describe "Md::App dialog style" do
  it "asks at the prompt by default, offers the styles under View → Dialog Style, and keeps the choice" do
    with_config do
      with_app config: true do |app|
        app.dialog_style.should eq Md::App::DialogStyle::LinePrompt
        styles = menu(app, 3).actions.find!(&.text.==("&Dialog Style")).menu || [] of Crysterm::Action
        styles.map(&.text).should eq ["&Modal Dialogs", "&Line Prompts"]
        styles.map(&.checked?).should eq [false, true]
        styles[0].trigger
        app.dialog_style.should eq Md::App::DialogStyle::Modal
        styles.map(&.checked?).should eq [true, false]
        Crysterm::Config.md_dialog_style.should eq Md::App::DialogStyle::Modal
      end
      with_app config: true do |app|
        app.dialog_style.should eq Md::App::DialogStyle::Modal
      end
    end
  end

  it "asks for a line of text at the prompt, or in an input dialog" do
    with_app Md::Source.new(path: "doc.md"), text: DIALOG_DOC, view: true do |app, window|
      app.go_to_line_prompt
      question(app).should eq ":"
      input_dialog(window).should be_nil
      answer app, "3"
      app.editor.text_cursor.block_number.should eq 2

      app.dialog_style = Md::App::DialogStyle::Modal
      app.go_to_line_prompt
      app.main.status_bar.prompting?.should be_false
      input_dialog(window).should_not be_nil
      window.repaint
      window.dump.to_s.should contain "Go to line:"
      answer_dialog window, "5"
      settle { app.editor.text_cursor.block_number == 4 }
      settle { input_dialog(window).nil? } # the dialog is gone once answered
      # Escape gives the question up.
      app.go_to_line_prompt
      escape_dialog window
      settle { input_dialog(window).nil? }
      app.editor.text_cursor.block_number.should eq 4
      # A label that is not a question gets one of its own; a plain label
      # is the question.
      app.search_prompt backward: true
      window.repaint
      window.dump.to_s.should contain "Find backward:"
      escape_dialog window
      settle { input_dialog(window).nil? }
      app.open_prompt
      window.repaint
      window.dump.to_s.should contain "Open:"
      escape_dialog window
      settle { input_dialog(window).nil? }
    end
  end

  it "asks the unsaved-changes question at the prompt, or in a message box" do
    path = File.tempname("md-spec", ".md")
    begin
      with_app Md::Source.new(path: path) do |app, window|
        app.editor.insert_text "unsaved"
        ran = 0
        app.confirm_discard { ran += 1 }
        question(app).should eq "Save changes to #{path}? (y)es, (n)o, (c)ancel: "
        choice(window, "Save").should be_nil
        answer app, 'Y' # case does not matter
        ran.should eq 1
        File.read(path).should eq "unsaved"

        app.dialog_style = Md::App::DialogStyle::Modal
        app.editor.insert_text " more"
        app.confirm_discard { ran += 1 }
        app.main.status_bar.prompting?.should be_false
        choice(window, "Don't save").should_not be_nil
        choose window, "Cancel"
        settle { choice(window, "Cancel").nil? }
        ran.should eq 1
        app.confirm_discard { ran += 1 }
        choose window, "Save"
        settle { ran == 2 }
        File.read(path).should eq "unsaved more"
      end
    ensure
      File.delete? path
    end
  end

  it "keeps the application keys quiet while a dialog is up, as it does for a prompt" do
    with_app Md::Source.new(path: "doc.md"), text: DIALOG_DOC, view: true do |app, window|
      app.dialog_style = Md::App::DialogStyle::Modal
      app.asking?.should be_false
      app.editor.insert_text "unsaved"
      app.confirm_discard { }
      app.asking?.should be_true
      # A letter the box's buttons leave to the window: `q` would quit over
      # the question, `F1` show the editor under it. The `q` is taken, so
      # Crysterm's default quit key, which it is too, stands down.
      press(window, 'q').accepted?.should be_true
      window.destroyed?.should be_false
      press window, Tput::Key::F1
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      choose window, "Cancel"
      settle { !app.asking? }
      press(window, Tput::Key::F1).accepted?.should be_true
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
    end
  end
end
