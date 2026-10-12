require "./spec_helper"

# Ctrl-Home and Ctrl-End go to the start and the end of the document, in
# the editor and in the viewer (Crysterm's text edits, as Qt's
# `MoveToStartOfDocument`/`MoveToEndOfDocument`), and with View → Sync
# Cursor the other pane follows.

DOCUMENT_KEYS_DOC = (1..60).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"

describe "Md::App Ctrl-Home and Ctrl-End" do
  it "move the editor's caret to the start and the end, the viewer following" do
    with_app Md::Source.new, text: DOCUMENT_KEYS_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.sync_cursor = true
      app.editor.cursor_position = app.editor.document.block_position(40)

      press(window, Tput::Key::CtrlEnd).accepted?.should be_true
      app.editor.cursor_position.should eq app.editor.document.plain_text.size
      app.viewer.cursor_position.should eq app.viewer_position(app.editor.cursor_position)
      app.viewer.cursor_position.should be > 0

      press(window, Tput::Key::CtrlHome).accepted?.should be_true
      app.editor.cursor_position.should eq 0
      app.viewer.cursor_position.should eq 0
    end
  end

  it "move the viewer's caret to the start and the end, the editor following" do
    with_app Md::Source.new, text: DOCUMENT_KEYS_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.viewer.focus
      app.sync_cursor = true

      press(window, Tput::Key::CtrlEnd).accepted?.should be_true
      app.viewer.cursor_position.should eq app.viewer.document.plain_text.size
      app.editor.cursor_position.should eq app.editor_position(app.viewer.cursor_position)
      app.editor.cursor_position.should be > app.editor.document.block_position(100)

      press(window, Tput::Key::CtrlHome).accepted?.should be_true
      app.viewer.cursor_position.should eq 0
      app.editor.cursor_position.should eq 0
    end
  end
end
