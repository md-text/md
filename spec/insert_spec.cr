require "./spec_helper"

# The Insert menu: Markdown templates put in at the caret, the first
# placeholder selected.

# Puts the editor's caret at *column* of *line*, both 0-based.
private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

# The editor's selected text.
private def selected(app)
  app.editor.text_cursor.selected_text
end

# The Insert menu's entry *label*, in a submenu when *submenu* is given.
private def insert_entry(app, label, submenu = nil)
  actions = menu(app, 2).actions
  actions = actions.find!(&.text.==(submenu)).menu || fail("#{submenu} has no submenu") if submenu
  actions.find!(&.text.==(label))
end

describe "Md::App Insert menu" do
  it "puts a table of the chosen size on a blank line, its first header cell selected" do
    with_app text: "Text.\n\n", view: false do |app|
      place app, 1, 0
      insert_entry(app, "&1  2 Columns × 2 Rows", "T&able").trigger
      app.markdown.should eq "Text.\n\n| Column 1 | Column 2 |\n| -------- | -------- |\n|          |          |\n|          |          |\n"
      selected(app).should eq "Column 1"
    end
  end

  it "puts a block after the caret's paragraph, apart by blank lines, in one undo step" do
    with_app text: "One\ntwo.\n\nThree.\n", view: false do |app|
      place app, 0, 1
      app.insert_heading(2).should be_true
      app.markdown.should eq "One\ntwo.\n\n## Heading\n\nThree.\n"
      selected(app).should eq "Heading"
      app.editor.undo.should be_true
      app.markdown.should eq "One\ntwo.\n\nThree.\n"
    end
  end

  it "keeps a blank line above a block put on a blank line under text" do
    with_app text: "Text.\n", view: false do |app|
      place app, 1, 0
      insert_entry(app, "Horizontal &Rule").trigger
      app.markdown.should eq "Text.\n\n---\n" # not a setext heading under Text.
      insert_entry(app, "&Note", "Al&ert").trigger
      app.markdown.should eq "Text.\n\n---\n\n> [!NOTE]\n> Text\n"
      selected(app).should eq "Text"
    end
  end

  it "refuses a block inside a code block" do
    with_app text: "```\ncode\n```\n", view: false do |app|
      place app, 1, 2
      app.insert_table(2, 1).should be_false
      app.markdown.should eq "```\ncode\n```\n"
      notice(app).should contain "Not inside a code block"
    end
  end

  it "wraps a link or an image around the selection, or inserts one to type over" do
    with_app text: "See here.\n", view: false do |app|
      doc = app.editor.document
      app.editor.text_cursor = Crysterm::TextCursor.new(doc, 4, 8)
      insert_entry(app, "&Link").trigger
      app.markdown.should eq "See [here](url).\n"
      selected(app).should eq "url"
      place app, 0, 0
      app.insert_image.should be_true
      app.markdown.should eq "![alt text](url)See [here](url).\n"
      selected(app).should eq "alt text"
    end
  end

  it "numbers a footnote past the document's highest and defines it at the end" do
    with_app text: "One[^1].\n\n[^1]: First.\n", view: false do |app|
      place app, 0, 8
      app.insert_footnote.should be_true
      app.markdown.should eq "One[^1].[^2]\n\n[^1]: First.\n\n[^2]: Footnote\n"
      selected(app).should eq "Footnote"
    end
  end

  it "asks for a custom table size, offering the last one asked for" do
    with_app text: "", view: false do |app|
      insert_entry(app, "&Custom Size…", "T&able").trigger
      app.main.status_bar.line_prompt.field.value.should eq "3x3"
      answer app, "3 × 1"
      app.markdown.should eq "| Column 1 | Column 2 | Column 3 |\n| -------- | -------- | -------- |\n|          |          |          |\n"
      app.insert_table_prompt
      app.main.status_bar.line_prompt.field.value.should eq "3x1"
      answer app, "0x9"
      notice(app).should contain "Not a table size: 0x9"
    end
  end

  it "holds the task entries, apart, with the check read as the menu opens" do
    with_app text: "- [ ] task\n", view: false do |app|
      actions = menu(app, 2).actions
      actions[-3].separator?.should be_true
      task = insert_entry(app, "As a &Task")
      place app, 0, 7
      menu(app, 2).emit Crysterm::Event::AboutToShow
      task.checked?.should be_true
      menu(app, 3).actions.map(&.text).should_not contain "As a &Task" # moved out of Format
    end
  end
end
