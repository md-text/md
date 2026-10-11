require "./spec_helper"

# Selecting with `Shift` + a movement key — arrows, `Home`/`End`,
# `PageUp`/`PageDown` — in the editor and in the viewer: the selection
# grows from the caret and shrinks back, as Qt's text edits do with
# `QTextCursor::KeepAnchor`, and is painted reversed. The viewer's caret
# selects too, as a `QTextBrowser` whose text is selectable by keyboard.

# Forty short lines, so a page is well inside the document; for the viewer
# they are paragraphs, since a soft break renders as a space.
LINES_DOC     = (1..40).map { |i| "line #{i}" }.join("\n") + "\n"
PARAGRAPH_DOC = (1..40).map { |i| "line #{i}" }.join("\n\n") + "\n"

# Presses *keys* in turn.
private def press_all(window, *keys)
  keys.each { |key| press window, key }
end

# Whether the cell at *column* of *pane*'s first row is painted reversed,
# as a selection is.
private def reversed?(window, pane, column)
  window.repaint
  cell = window.cell_rows[pane.atop][pane.aleft + pane.ileft + column]
  (Crysterm::Attr.flags(cell.attr) & Crysterm::Attr::REVERSE) != 0
end

describe "Md::App selection with Shift" do
  it "selects in the editor with Shift + arrows, Home and End, and shrinks back" do
    with_app text: LINES_DOC, view: false do |app, window|
      app.editor.focused?.should be_true
      app.editor.cursor_position = 0
      press(window, Tput::Key::ShiftRight).accepted?.should be_true
      app.editor.selected_text.should eq "l"
      reversed?(window, app.editor, 0).should be_true
      reversed?(window, app.editor, 1).should be_false
      press window, Tput::Key::ShiftEnd
      app.editor.selected_text.should eq "line 1"
      reversed?(window, app.editor, 5).should be_true
      press window, Tput::Key::ShiftDown
      app.editor.selected_text.should eq "line 1\nline 2"
      press window, Tput::Key::ShiftHome
      app.editor.selected_text.should eq "line 1\n"
      press window, Tput::Key::ShiftUp
      app.editor.selection?.should be_false
      press_all window, Tput::Key::ShiftRight, Tput::Key::ShiftRight, Tput::Key::ShiftLeft
      app.editor.selected_text.should eq "l"
      # A plain move drops the selection.
      press window, Tput::Key::Right
      app.editor.selection?.should be_false
      reversed?(window, app.editor, 0).should be_false
    end
  end

  it "selects a page at a time in the editor with Shift + PageDown and PageUp" do
    with_app text: LINES_DOC, view: false do |app, window|
      window.repaint
      app.editor.cursor_position = 0
      press(window, Tput::Key::ShiftPageDown).accepted?.should be_true
      selected = app.editor.selected_text
      selected.should start_with "line 1\nline 2\n"
      selected.lines.size.should be > 5
      press window, Tput::Key::ShiftPageUp
      app.editor.selection?.should be_false
    end
  end

  it "selects in the viewer with Shift + arrows, Home and End" do
    with_app text: PARAGRAPH_DOC, view: true do |app, window|
      window.repaint
      app.viewer.focused?.should be_true
      app.viewer.cursor_position = 0
      press(window, Tput::Key::ShiftRight).accepted?.should be_true
      app.viewer.selected_text.should eq "l"
      reversed?(window, app.viewer, 0).should be_true
      reversed?(window, app.viewer, 1).should be_false
      press window, Tput::Key::ShiftEnd
      app.viewer.selected_text.should eq "line 1"
      reversed?(window, app.viewer, 5).should be_true
      press window, Tput::Key::ShiftDown
      app.viewer.selected_text.should eq "line 1\nline 2"
      press window, Tput::Key::ShiftHome
      app.viewer.selected_text.should eq "line 1\n"
      press window, Tput::Key::ShiftUp
      app.viewer.selection?.should be_false
      press_all window, Tput::Key::ShiftRight, Tput::Key::ShiftRight, Tput::Key::ShiftLeft
      app.viewer.selected_text.should eq "l"
      press window, Tput::Key::Right
      app.viewer.selection?.should be_false
      reversed?(window, app.viewer, 0).should be_false
    end
  end

  it "selects a page at a time in the viewer with Shift + PageDown and PageUp" do
    with_app text: PARAGRAPH_DOC, view: true do |app, window|
      window.repaint
      app.viewer.cursor_position = 0
      press(window, Tput::Key::ShiftPageDown).accepted?.should be_true
      selected = app.viewer.selected_text
      selected.should start_with "line 1\nline 2\n"
      selected.lines.size.should be > 5
      press window, Tput::Key::ShiftPageUp
      app.viewer.selection?.should be_false
    end
  end

  it "copies the selection made with the keyboard" do
    with_app text: PARAGRAPH_DOC, view: true do |app, window|
      window.repaint
      app.viewer.cursor_position = 0
      press_all window, Tput::Key::ShiftEnd, Tput::Key::ShiftDown
      press(window, Tput::Key::CtrlC).accepted?.should be_true
      app.clipboard.text.should eq "line 1\nline 2"
    end
  end
end
