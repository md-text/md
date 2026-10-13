require "./spec_helper"

# Puts the editor's caret at *column* of *line*, both 0-based.
private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

# The headings md finds in *text*, as {first line, last line, level}.
private def headings_of(text)
  doc = Crysterm::TextDocument.new
  doc.plain_text = text
  Md::App.headings(doc, Md::App.code_lines(doc)).map { |heading| {heading.first, heading.last, heading.level} }
end

# The viewer's blocks for *text*: text, heading level and task box.
private def viewed(text)
  Crysterm::TextDocument.from_markdown(text).blocks.map do |b|
    bf = b.block_format
    {b.text, bf.heading_level, bf.list_format.try(&.style.checkbox?) ? bf.checked? : nil}
  end
end

# GFM (cmark-gfm, which github.com renders with) gives a task box to an item
# whose first paragraph starts with one; an underline may make that paragraph
# a setext heading, and an ATX heading's text or `##` after the box is text.
describe "Md::App task items and headings" do
  it "finds the headings in task items that the viewer shows" do
    {
      "- [ ] a\n  ---"      => {[{0, 1, 2}], [{"a", 2, false}]},
      "- [x] a\n  ==="      => {[{0, 1, 1}], [{"a", 1, true}]},
      "- [ ] a\n  b\n  ---" => {[{0, 2, 2}], [{"a b", 2, false}]},
      "- [ ] ## T"          => {[] of {Int32, Int32, Int32}, [{"## T", 0, false}]},
      "- ## [ ] a"          => {[{0, 0, 2}], [{"[ ] a", 2, nil}]},
    }.each do |text, (found, blocks)|
      headings_of(text).should eq(found), text.inspect
      viewed(text).should eq(blocks), text.inspect
    end
  end

  it "knows a task item's first line" do
    Md::App.task_lead("- [ ] a").should eq "- "
    Md::App.task_lead("> 1. [x] a").should eq "> 1. "
    Md::App.task_lead("- - [X] a").should eq "- - "
    Md::App.task_lead("- ## [ ] a").should be_nil
    Md::App.task_lead("- [ ]").should be_nil
    Md::App.task_lead("[ ] a").should be_nil
    Md::App.task_lead("- a").should be_nil
  end

  it "demotes a task line to a setext heading under it, keeping the box" do
    with_app text: "- [ ] a\n", view: false do |app|
      place app, 0, 6
      app.demote_heading.should be_true
      app.markdown.should eq "- [ ] a\n  ===\n"
      app.editor.cursor_position.should eq 6
      app.demote_heading.should be_true
      app.markdown.should eq "- [ ] a\n  ---\n"
      viewed(app.markdown).should eq [{"a", 2, false}]
      app.demote_heading.should be_false
      app.markdown.should eq "- [ ] a\n  ---\n"
      app.promote_heading.should be_true
      app.markdown.should eq "- [ ] a\n  ===\n"
      app.promote_heading.should be_true
      app.markdown.should eq "- [ ] a\n"
      app.promote_heading.should be_false
    end
  end

  it "underlines the whole paragraph, in a quote and a nested item" do
    with_app text: "> - [x] one\n>   two\n> - b\n", view: false do |app|
      place app, 0, 9
      app.demote_heading.should be_true
      app.markdown.should eq "> - [x] one\n>   two\n>   ===\n> - b\n"
      viewed(app.markdown).first.should eq({"one two", 1, true})
    end
    with_app text: "- a\n  - [ ] b\n\nc\n", view: false do |app|
      place app, 1, 9
      app.demote_heading.should be_true
      app.markdown.should eq "- a\n  - [ ] b\n    ===\n\nc\n"
      headings_of(app.markdown).should eq [{1, 2, 1}]
    end
  end

  it "moves a task heading of the caret's section, its underline kept setext" do
    with_app text: "# Top\n\n- [ ] item\n  ---\n\n  body\n", view: false do |app|
      place app, 5, 3
      app.demote_heading.should be_false
      app.markdown.should eq "# Top\n\n- [ ] item\n  ---\n\n  body\n"
      app.promote_heading.should be_true
      app.markdown.should eq "# Top\n\n- [ ] item\n  ===\n\n  body\n"
      app.promote_heading.should be_true
      app.markdown.should eq "# Top\n\n- [ ] item\n\n  body\n"
    end
  end

  it "makes an item's ATX heading setext when it takes a box" do
    with_app text: "- ## a ##\n  more\n", view: false do |app|
      place app, 0, 5
      app.toggle_task_box.should be_true
      app.markdown.should eq "- [ ] a\n  ---\n  more\n"
      viewed(app.markdown).first.should eq({"a", 2, false})
    end
    with_app text: "> 1. # a\n", view: false do |app|
      place app, 0, 7
      app.check_task.should be_true
      app.markdown.should eq "> 1. [x] a\n>    ===\n"
      headings_of(app.markdown).should eq [{0, 1, 1}]
    end
  end

  it "leaves an item's heading below level 2 without a box" do
    with_app text: "- ### a\n", view: false do |app|
      place app, 0, 6
      app.toggle_task_box.should be_false
      app.check_task.should be_false
      app.markdown.should eq "- ### a\n"
    end
    with_app text: "- ### a\n- b\n", view: false do |app|
      doc = app.editor.document
      app.editor.text_cursor = Crysterm::TextCursor.new(doc, 0, doc.block_position(1) + 1)
      app.toggle_task_box.should be_true
      app.markdown.should eq "- ### a\n- [ ] b\n"
    end
  end
end
