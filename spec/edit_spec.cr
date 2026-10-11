require "./spec_helper"

private def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

# The editor shown and focused, holding *text*, unless *view* asks for the
# viewer (the editor hidden), as opening a file does.
private def with_app(text = "", view = false, &)
  window = headless_window
  begin
    yield Md::App.new(Md::Source.new, text: text, view: view, window: window), window
  ensure
    window.destroy
  end
end

# Presses a key the way the terminal delivers it, and returns the event so
# a spec can see whether it was taken.
private def press(window, key : Tput::Key) : Crysterm::Event::KeyPress
  e = Crysterm::Event::KeyPress.new('\0', key)
  window.emit Crysterm::Event::KeyPress, e
  e
end

private def notice(app)
  app.main.status_bar.message
end

# Puts the editor's caret at *column* of *line*, both 0-based.
private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

# Selects the editor's text between document positions *from* and *to*.
private def select_text(app, from, to)
  app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, from, to)
end

describe "Md::App editing" do
  it "continues a list item on Enter: the same marker, the number raised, the task box emptied" do
    with_app "- one\n1. first\n- [x] done\n  * sub\n> 2) quoted\n" do |app, window|
      place app, 0, 5
      press(window, Tput::Key::Enter).accepted?.should be_true
      app.markdown.should eq "- one\n- \n1. first\n- [x] done\n  * sub\n> 2) quoted\n"
      app.editor.cursor_position.should eq 8
      place app, 2, 8
      press window, Tput::Key::Enter
      app.markdown.lines[3].should eq "2. "
      place app, 4, 10
      press window, Tput::Key::Enter
      app.markdown.lines[5].should eq "- [ ] "
      place app, 6, 7
      press window, Tput::Key::Enter
      app.markdown.lines[7].should eq "  * "
      place app, 8, 11
      press window, Tput::Key::Enter
      app.markdown.lines[9].should eq "> 3) "
      app.editor.document.modified?.should be_true
    end
  end

  it "starts the new item with the text after the caret" do
    with_app "- one two\n" do |app, window|
      place app, 0, 5
      press window, Tput::Key::Enter
      app.markdown.should eq "- one\n- two\n"
      app.editor.cursor_position.should eq 8
    end
  end

  it "ends the list on Enter on an empty item, keeping the quote" do
    with_app "- one\n  - \n> - \n" do |app, window|
      place app, 1, 4
      press(window, Tput::Key::Enter).accepted?.should be_true
      app.markdown.should eq "- one\n\n> - \n"
      place app, 2, 4
      press window, Tput::Key::Enter
      app.markdown.should eq "- one\n\n> \n"
    end
  end

  it "leaves Enter to the editor off a list item, or with the caret inside the marker" do
    with_app "text\n- one\n" do |app, window|
      place app, 0, 4
      press window, Tput::Key::Enter
      app.markdown.should eq "text\n\n- one\n"
      place app, 2, 0
      press window, Tput::Key::Enter
      app.markdown.should eq "text\n\n\n- one\n"
    end
  end

  it "indents and outdents a list item with Tab and Shift-Tab, by the item above's content offset" do
    with_app "- a\n- b\n1. step\n- detail\n" do |app, window|
      place app, 1, 2
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "- a\n  - b\n1. step\n- detail\n"
      app.editor.cursor_position.should eq 8
      # An item cannot nest deeper than one level under the item above.
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "- a\n  - b\n1. step\n- detail\n"
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
      # A bullet under an ordered item goes under its content, three in.
      place app, 3, 0
      press window, Tput::Key::Tab
      app.markdown.should eq "- a\n- b\n1. step\n   - detail\n"
      press window, Tput::Key::ShiftTab
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
    end
  end

  it "indents every line of a selection by the same amount, in one undo step" do
    with_app "- a\n  continued\n\n- b\n" do |app, window|
      select_text app, 0, app.editor.document.size
      press window, Tput::Key::Tab
      app.markdown.should eq "  - a\n    continued\n\n  - b\n"
      app.editor.undo.should be_true
      app.markdown.should eq "- a\n  continued\n\n- b\n"
      app.indent_list(-1).should be_true # at the margin already: taken, nothing to do
      app.markdown.should eq "- a\n  continued\n\n- b\n"
    end
  end

  it "lets Tab move focus off a list item" do
    with_app "text\n" do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      press window, Tput::Key::Tab
      app.markdown.should eq "text\n"
      app.viewer.focused?.should be_true
    end
  end

  it "toggles a list item's task box, and says so off a list" do
    with_app "- item\ntext\n" do |app, window|
      app.show_pane Md::App::Pane::Viewer
      place app, 0, 3
      app.toggle_task.should be_true
      app.markdown.should eq "- [ ] item\ntext\n"
      press(window, Tput::Key::AltX).accepted?.should be_true
      app.markdown.should eq "- [x] item\ntext\n"
      app.viewer.document.blocks[0].block_format.checked?.should be_true # the viewer followed
      app.toggle_task.should be_true
      app.markdown.should eq "- [ ] item\ntext\n"
      place app, 1, 0
      app.toggle_task.should be_false
      notice(app).should contain "Not a list item"
      app.markdown.should eq "- [ ] item\ntext\n"
    end
  end

  it "wraps the word at the caret in bold, italic and code, and unwraps it again" do
    with_app "some word here\n" do |app, window|
      place app, 0, 7
      press(window, Tput::Key::CtrlB).accepted?.should be_true
      app.markdown.should eq "some **word** here\n"
      app.editor.selected_text.should eq "word"
      app.toggle_bold.should be_true
      app.markdown.should eq "some word here\n"
      app.editor.selected_text.should eq "word"
      app.toggle_italic
      app.markdown.should eq "some *word* here\n"
      app.toggle_bold
      app.markdown.should eq "some ***word*** here\n"
      app.toggle_italic
      app.markdown.should eq "some **word** here\n"
      app.toggle_bold
      app.markdown.should eq "some word here\n"
      app.toggle_code
      app.markdown.should eq "some `word` here\n"
      app.toggle_code
      app.markdown.should eq "some word here\n"
    end
  end

  it "wraps the selection, finds the markers around a word, and takes underscores too" do
    with_app "some __word__ here, _it_\n" do |app|
      select_text app, 0, 4
      app.toggle_code
      app.markdown.should eq "`some` __word__ here, _it_\n"
      app.editor.selected_text.should eq "some"
      select_text app, 1, 5
      app.toggle_code
      app.markdown.should eq "some __word__ here, _it_\n"
      place app, 0, 9
      app.toggle_bold
      app.markdown.should eq "some word here, _it_\n"
      place app, 0, 17
      app.toggle_italic
      app.markdown.should eq "some word here, it\n"
    end
  end

  it "inserts the pair with the caret between when there is nothing to wrap" do
    with_app do |app|
      app.toggle_bold.should be_true
      app.markdown.should eq "****"
      app.editor.cursor_position.should eq 2
    end
  end

  it "promotes and demotes the heading on the caret's line" do
    with_app "## Title\n> ## quoted\n###### deep\n" do |app, window|
      place app, 0, 3
      press(window, Tput::Key::CtrlUp).accepted?.should be_true
      app.markdown.lines[0].should eq "# Title"
      app.promote_heading.should be_true
      app.markdown.lines[0].should eq "Title"
      app.promote_heading.should be_false
      notice(app).should contain "Not a heading"
      press(window, Tput::Key::CtrlDown).accepted?.should be_true
      app.markdown.lines[0].should eq "# Title"
      place app, 1, 0
      app.promote_heading
      app.markdown.lines[1].should eq "> # quoted"
      place app, 2, 0
      app.demote_heading.should be_false
      notice(app).should contain "No heading level below 6"
      app.markdown.lines[2].should eq "###### deep"
    end
  end

  it "formats from the viewer at the source of its caret, showing the editor" do
    with_app "some word here\n", view: true do |app|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.viewer.text_cursor = Crysterm::TextCursor.new(app.viewer.document, 6)
      app.toggle_bold.should be_true
      app.markdown.should eq "some **word** here\n"
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
    end
  end
end
