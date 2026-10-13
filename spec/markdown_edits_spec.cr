require "./spec_helper"

# Corner cases of the Markdown-aware editing (`app_edit.cr`): the lines
# that only look like list items to `Enter`, and what Format → Rewrap must
# keep for the Markdown to mean what it meant.

# Puts the editor's caret at *column* of *line*, both 0-based.
private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

describe "Md::App editing, Enter" do
  it "leaves a rule, a code block's line and an item opening a fence to the editor's newline" do
    with_app text: "* * *\n```\n- foo\n```\n- ```sh\n", view: false do |app, window|
      place app, 0, 5
      press(window, Tput::Key::Enter)
      app.markdown.should eq "* * *\n\n```\n- foo\n```\n- ```sh\n"
      place app, 3, 5
      press(window, Tput::Key::Enter)
      app.markdown.should eq "* * *\n\n```\n- foo\n\n```\n- ```sh\n"
      place app, 6, 7
      press(window, Tput::Key::Enter)
      app.markdown.should eq "* * *\n\n```\n- foo\n\n```\n- ```sh\n\n"
    end
  end
end
