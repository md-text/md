require "./spec_helper"

private def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

private def with_app(source = Md::Source.new, text = "", view = !text.empty?, &)
  window = headless_window
  begin
    yield Md::App.new(source, text: text, view: view, window: window), window
  ensure
    window.destroy
  end
end

# Presses a key the way the terminal delivers it, and returns the event so
# a spec can see who took it.
private def press(window, key : Tput::Key) : Crysterm::Event::KeyPress
  e = Crysterm::Event::KeyPress.new('\0', key)
  window.emit Crysterm::Event::KeyPress, e
  e
end

private def press(window, char : Char) : Crysterm::Event::KeyPress
  e = Crysterm::Event::KeyPress.new(char)
  window.emit Crysterm::Event::KeyPress, e
  e
end

private def answer(app, text)
  field = app.main.status_bar.line_prompt.field
  field.value = text
  field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Enter)
end

private def notice(app)
  app.main.status_bar.message
end

# The status bar's row as painted: the prompt's label and field while a
# question is open.
private def status_row(window)
  window.repaint
  window.dump.to_s.lines[31][1..-2]
end

# The bar's menus in add order: File, Edit, View, Options.
private def menu(app, index)
  app.main.menu_bar.menus[index]
end

# The dialog's button labelled *text*, if the dialog is up.
private def choice(window, text)
  window.descendants.select(Crysterm::Widget::Button).find { |b| b.text == text && b.visible? }
end

SHORTCUT_DOC = <<-MD
  # Alpha

  A needle here.

  ## Beta

  Another needle.
  MD

describe "Md::App shortcuts" do
  it "carries the keys on the File and Edit entries and shows them in the menus" do
    with_app Md::Source.new(path: "doc.md"), text: SHORTCUT_DOC, view: true do |app, window|
      menu(app, 0).actions.map(&.shortcut_text).should eq ["Ctrl+O", "", "Ctrl+R", "", "Ctrl+S", "", "", "Ctrl+Q"]
      menu(app, 1).actions.map(&.shortcut_text).should eq ["Ctrl+C", "", "", "Ctrl+F", "Ctrl+G", "Alt+G", "", "", "Ctrl+L", "Alt+Down", "Alt+Up", "", "Alt+Left", "Alt+Right"]
      menu(app, 2).actions.map(&.shortcut_text).should eq ["Ctrl+B", "Alt+I", "Alt+C", "", "Alt+X", "", "", "", "Ctrl+Up", "Ctrl+Down"]
      # The pane entries' gesture is not the F-keys', so they name no key;
      # resizing and Soft wrap have one.
      menu(app, 3).actions.map(&.shortcut_text).should eq ["", "", "", "Alt+R", "", "", "", "", "", "Alt+W", "", "", "", ""]
      app.main.menu_bar.open_menu 0
      window.repaint
      rows = window.dump.to_s.lines
      (rows.find(&.includes?("Open…")) || fail("the File menu does not show Open…")).should contain "Ctrl+O"
      (rows.find(&.includes?("Quit")) || fail("the File menu does not show Quit")).should contain "Ctrl+Q"
      app.main.menu_bar.close
    end
  end

  it "fires the file keys from any pane" do
    with_app do |app, window|
      app.show_pane(Md::App::Pane::Viewer).focus
      press(window, Tput::Key::CtrlO).accepted?.should be_true
      status_row(window).should start_with "Open: "
      app.main.status_bar.line_prompt.cancel
      press window, Tput::Key::CtrlS # no name yet: asks for one
      status_row(window).should start_with "Save as: "
      app.main.status_bar.line_prompt.cancel
      press window, Tput::Key::CtrlR
      notice(app).should contain "No file to reload"
    end
  end

  it "fires the search and jump keys, in the editor too" do
    with_app Md::Source.new, text: SHORTCUT_DOC, view: false do |app, window|
      app.editor.focus
      press window, Tput::Key::CtrlF
      status_row(window).should start_with "/"
      answer app, "needle"
      app.editor.selected_text.should eq "needle"
      first = app.editor.cursor_position
      press window, Tput::Key::CtrlG
      app.editor.cursor_position.should be > first
      press window, Tput::Key::AltG
      app.editor.cursor_position.should eq first
      press window, Tput::Key::CtrlL
      status_row(window).should start_with ":"
      answer app, "5"
      app.editor.text_cursor.block_number.should eq 4

      app.show_pane(Md::App::Pane::Viewer).focus
      plain = app.viewer.document.plain_text
      app.viewer.cursor_position = 0
      press window, Tput::Key::AltDown
      app.viewer.cursor_position.should eq plain.index("Beta")
      press window, Tput::Key::AltUp
      app.viewer.cursor_position.should eq plain.index("Alpha")
    end
  end

  it "waits while a prompt is open" do
    with_app do |app, window|
      app.save_as_prompt
      press window, Tput::Key::CtrlO
      status_row(window).should start_with "Save as: "
      press window, Tput::Key::CtrlF
      status_row(window).should start_with "Save as: "
      press window, 'x' # the question goes on being answered
      app.main.status_bar.line_prompt.field.value.should eq "x"
      app.main.status_bar.line_prompt.cancel
      press window, Tput::Key::CtrlO
      status_row(window).should start_with "Open: "
      app.main.status_bar.line_prompt.cancel
    end
  end

  it "leaves the editor the keys it uses" do
    with_app do |app, window|
      # A probe on two of the editor's keys, in the same menu as md's entries.
      probe = Crysterm::Action.new "Probe", shortcuts: [[Tput::Key::CtrlZ], [Tput::Key::CtrlK]]
      suspended = 0
      app.suspender = -> { suspended += 1 } # outside the editor Ctrl-Z is md's suspend
      fired = 0
      probe.on(Crysterm::Event::Triggered) { fired += 1 }
      menu(app, 1) << probe
      press window, 'a'
      app.markdown.should eq "a"
      press window, Tput::Key::CtrlZ # undo
      app.markdown.should eq ""
      press window, 'b'
      press window, Tput::Key::Home
      press window, Tput::Key::CtrlK # kill to the end of the line
      app.markdown.should eq ""
      fired.should eq 0

      app.show_pane(Md::App::Pane::Viewer).focus
      press window, Tput::Key::CtrlZ
      press window, Tput::Key::CtrlK
      fired.should eq 1 # Ctrl-K; Ctrl-Z was md's own key first
      suspended.should eq 1
    end
  end

  it "asks about unsaved changes once on Ctrl+Q, the default quit key standing down" do
    with_app Md::Source.new(path: "doc.md") do |app, window|
      asked = 0
      window.on(Crysterm::Event::CloseRequest) { asked += 1 }
      app.editor.insert_text "unsaved"
      e = press window, Tput::Key::CtrlQ
      asked.should eq 1
      choice(window, "Cancel").should_not be_nil
      window.destroyed?.should be_false
      # The entry took the key, so Crysterm's own quit key does not ask again.
      e.accepted?.should be_true
      Crysterm::Application.quit_gesture?(window, e).should be_false
      choice(window, "Cancel").try &.click
    end
  end
end

describe "Md::App suspend" do
  it "suspends on Ctrl-Z outside the editor, and leaves the editor its undo" do
    with_app Md::Source.new, text: SHORTCUT_DOC, view: true do |app, window|
      suspended = 0
      app.suspender = -> { suspended += 1 }
      press(window, Tput::Key::CtrlZ).accepted?.should be_true
      suspended.should eq 1
      app.show_pane(Md::App::Pane::Toc).focus
      press window, Tput::Key::CtrlZ
      suspended.should eq 2

      app.show_pane(Md::App::Pane::Editor).focus
      app.editor.cursor_position = app.editor.document.size
      press window, 'x'
      app.editor.value.should contain "x"
      press window, Tput::Key::CtrlZ
      app.editor.value.should_not contain "x"
      suspended.should eq 2
    end
  end
end
