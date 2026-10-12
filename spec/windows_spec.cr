require "./spec_helper"

# The Window menu (`app_windows.cr`): more md windows in one process, on
# headless windows a stubbed opener hands out, under one shared
# `Crysterm::Application`.

# An opener that records the headless windows it handed out.
private def recording_opener(opened)
  ->(title : String) do
    window = headless_window
    window.title = title
    opened << window
    window
  end
end

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
      window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "", "doc.md"]
      window_menu(app).actions[0].enabled?.should be_true
      window_menu(app).actions[3].checked?.should be_true
      window_menu(app).actions.map(&.shortcut_text).should eq ["Ctrl+N", "Ctrl+W", "", ""]

      other = app.new_window || fail("no window was opened")
      begin
        other.window.should be opened.first
        other.window.title.should eq "doc.md • MD"
        # Joined to the running application, on screen and reading input.
        other.window.application.should be application
        application.windows.should eq [window, other.window]
        other.window.screen.listening?.should be_true
        # The same document, as it stands here, in the same pane.
        other.source.path.should eq app.source.path
        other.markdown.should eq app.markdown
        other.visible_panes.should eq [Md::App::Pane::Viewer]
        # Both windows list both, each with its own checked.
        window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "", "doc.md", "doc.md"]
        window_menu(app).actions[3..].map(&.checked?).should eq [true, false]
        window_menu(other).actions[3..].map(&.checked?).should eq [false, true]
        # Independent: an edit in one is not in the other.
        other.editor.insert_text "More"
        app.markdown.should_not contain "More"
        other.editor.document.modified = false # so the close below has nothing to ask

        # Closing the other closes it alone, and the lists follow.
        other.close_window
        other.window.destroyed?.should be_true
        window.destroyed?.should be_false
        application.windows.should eq [window]
        window_menu(app).actions.map(&.text).should eq ["&New", "&Close Current", "", "doc.md"]
        Md::App.instances.should contain app
        Md::App.instances.should_not contain other
      ensure
        other.window.destroy
      end
    end
  end

  it "opens the new window on unsaved text as unsaved, so its own guard asks too" do
    with_app Md::Source.new(path: "doc.md"), text: "A\n", view: true do |app|
      app.window_opener = recording_opener([] of Crysterm::Window)
      app.editor.cursor_position = 0 # a load leaves the caret at the end
      app.editor.insert_text "changed "
      other = app.new_window || fail("no window was opened")
      begin
        other.markdown.should eq "changed A\n"
        other.editor.document.modified?.should be_true
        other.main.status_bar.permanent_widgets[4].as(Crysterm::Widget::Label).text.should eq "✎ modified"
        other.close_window
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
        window_menu(app).actions[4].trigger
        notice(app).should contain "a.md is in another terminal window"
        window_menu(app).actions[3..].map(&.checked?).should eq [true, false] # the checks stay with each window's own
        window_menu(app).actions[3].trigger                                   # this one: nothing to do
        window_menu(app).actions[3..].map(&.checked?).should eq [true, false]
      ensure
        other.window.destroy
      end
    end
  end
end
