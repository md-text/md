require "./spec_helper"

# The Window menu (`app_windows.cr`): more md windows in one process, on
# headless windows a stubbed opener hands out, under one shared
# `Crysterm::Application`.

private def window_menu(app)
  menu(app, 5)
end

describe "Md::App windows" do
  it "lists the open windows, this one checked, and opens a new one on the document" do
    application = Crysterm::Application.new
    with_app Md::Source.new(path: "doc.md"), text: "# Doc\n\nText.\n", view: true do |app, window|
      application.add window
      opened = [] of Crysterm::Window
      app.window_opener = recording_opener(opened)
      window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "&Linking", "Remember &Positions", "", "doc.md"]
      window_menu(app).actions[0].enabled?.should be_true
      window_menu(app).actions[5].checked?.should be_true
      window_menu(app).actions.map(&.shortcut_text).should eq ["Ctrl+N", "Ctrl+W", "", "", "", ""]

      other = app.new_window || fail("no window was opened")
      begin
        other.window.should be opened.first
        other.window.title.should eq "doc.md:2 • MD"
        window.title.should eq "doc.md:1 • MD"
        # Joined to the running application, on screen and reading input.
        other.window.application.should be application
        application.windows.should eq [window, other.window]
        other.window.screen.listening?.should be_true
        # The same document, in the same pane.
        other.document.should be app.document
        other.editor.document.should be app.editor.document
        other.visible_panes.should eq [Md::App::Pane::Viewer]
        # Both windows list both, numbered, each with its own checked.
        window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "&Linking", "Remember &Positions", "", "doc.md:1", "doc.md:2"]
        window_menu(app).actions[5..].map(&.checked?).should eq [true, false]
        window_menu(other).actions[5..].map(&.checked?).should eq [false, true]
        # One text: an edit in one is in the other.
        other.editor.insert_text "More"
        app.markdown.should contain "More"

        # Closing the other closes it alone, without asking: the document
        # lives on here; the lists and the title follow.
        other.close_window
        other.window.destroyed?.should be_true
        window.destroyed?.should be_false
        application.windows.should eq [window]
        window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "&Linking", "Remember &Positions", "", "doc.md"]
        window.title.should eq "doc.md • MD"
        Md::App.instances.should contain app
        Md::App.instances.should_not contain other
      ensure
        other.window.destroy
      end
    end
  end

  it "shows an & in a document's name as it is, not as a mnemonic" do
    with_app Md::Source.new(path: "Q&A.md"), text: "# Q\n", view: true do |app|
      entry = window_menu(app).actions[5]
      entry.text.should eq "Q&&A.md"
      entry.mnemonic.should be_nil
      Crysterm::Mnemonic.parse(entry.text)[0].should eq "Q&A.md"
    end
  end

  it "renames this window in every window's list when the document changes" do
    with_app Md::Source.new(path: "doc.md"), text: "# Doc\n", view: true do |app|
      app.window_opener = recording_opener([] of Crysterm::Window)
      other = app.new_window || fail("no window was opened")
      saved = File.tempname("md-spec-windows", ".md")
      begin
        app.save_as(saved).should be_true
        names = ["#{File.basename(saved)}:1", "#{File.basename(saved)}:2"]
        window_menu(app).actions[5..].map(&.text).should eq names
        settle { other.window.title == "#{names[1]} • MD" }
        window_menu(other).actions[5..].map(&.text).should eq names
        other.close_window
      ensure
        other.window.destroy
        File.delete? saved
      end
    end
  end

  it "shares the unsaved state, and only the last window on the document asks" do
    with_app Md::Source.new(path: "doc.md"), text: "A\n", view: true do |app, window|
      app.window_opener = recording_opener([] of Crysterm::Window)
      app.editor.cursor_position = 0
      app.editor.insert_text "changed "
      other = app.new_window || fail("no window was opened")
      begin
        other.markdown.should eq "changed A\n"
        other.editor.document.modified?.should be_true
        other.main.status_bar.permanent_widgets[4].as(Crysterm::Widget::Label).text.should eq "✎ modified"
        app.close_window # another window shows the document: nothing to ask
        window.destroyed?.should be_true
        other.close_window # the last: asks
        question(other).should start_with "Save changes to"
        answer other, 'n'
        other.window.destroyed?.should be_true
      ensure
        other.window.destroy
      end
    end
  end

  it "closes the window after the unsaved-changes question, from Ctrl-W outside the editor" do
    with_app Md::Source.new(path: "doc.md") do |app, window|
      app.editor.insert_text "unsaved"
      app.show_pane(Md::App::Pane::Viewer).focus
      press(window, Tput::Key::CtrlW).accepted?.should be_true
      question(app).should start_with "Save changes to"
      window.destroyed?.should be_false
      answer app, 'c' # Cancel keeps it
      window.destroyed?.should be_false
      app.close_window
      answer app, 'n'
      window.destroyed?.should be_true
    end
  end

  it "disables Window → New where none can be opened, and the key says why" do
    with_app do |app, window|
      app.window_refusal = "no terminal emulator found"
      window_menu(app).actions[0].enabled?.should be_false
      app.show_pane(Md::App::Pane::Viewer).focus
      press(window, Tput::Key::CtrlN).accepted?.should be_true
      notice(app).should contain "Cannot open a window: no terminal emulator found"
      app.new_window.should be_nil
      # An opener that works anywhere enables the entry.
      app.window_opener = recording_opener([] of Crysterm::Window)
      window_menu(app).actions[0].enabled?.should be_true
      app.window_refusal.should be_nil
    end
  end

  it "reports an opener that fails instead of raising" do
    with_app do |app|
      app.window_opener = ->(_title : String) : Crysterm::Window { raise "Timed out waiting for the kitty window to start" }
      app.new_window.should be_nil
      notice(app).should contain "Cannot open a window: Timed out waiting for the kitty window"
    end
  end

  it "quits by closing every window, each through its own guard" do
    application = Crysterm::Application.new
    with_app Md::Source.new(path: "a.md"), text: "A\n", view: true do |app, window|
      application.add window
      app.window_opener = recording_opener([] of Crysterm::Window)
      other = app.new_window || fail("no window was opened")
      begin
        other.editor.insert_text "changed"
        app.quit
        # The clean window went; the one with changes asks and stays.
        window.destroyed?.should be_true
        other.window.destroyed?.should be_false
        question(other).should start_with "Save changes to"
        answer other, 'n'
        other.window.destroyed?.should be_true
        application.windows.should be_empty
      ensure
        other.window.destroy
      end
    end
  end

  it "picks another window from the menu, with a notice when it is in another terminal" do
    with_app Md::Source.new(path: "a.md"), text: "A\n", view: true do |app, _|
      app.window_opener = recording_opener([] of Crysterm::Window)
      other = app.new_window || fail("no window was opened")
      begin
        window_menu(app).actions[6].trigger
        notice(app).should contain "a.md:2 is in another terminal window"
        window_menu(app).actions[5..].map(&.checked?).should eq [true, false] # the checks stay with each window's own
        window_menu(app).actions[5].trigger                                   # this one: nothing to do
        window_menu(app).actions[5..].map(&.checked?).should eq [true, false]
      ensure
        other.window.destroy
      end
    end
  end
end
