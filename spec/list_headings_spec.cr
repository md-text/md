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

# The levels of the headings markd finds in *text*, in order.
private def markd_levels(text)
  Markd.to_html(text).scan(/<h(\d)>/).map(&.[1].to_i)
end

describe "Md::App headings in list items" do
  it "finds ATX and setext headings in list items as markd does" do
    {
      "- ## Title"                    => [{0, 0, 2}],
      "- # Foo\n- Bar\n  ---\n  baz"  => [{0, 0, 1}, {1, 2, 2}], # CommonMark example 300
      "* # One\n+ ### Three"          => [{0, 0, 1}, {1, 1, 3}],
      "1. # T\n2) ## U"               => [{0, 0, 1}, {1, 1, 2}],
      "-  # x"                        => [{0, 0, 1}],
      "- > # quoted"                  => [{0, 0, 1}],
      "> - ## T"                      => [{0, 0, 2}],
      "- item\n  ---"                 => [{0, 1, 2}],
      "- item\n  ==="                 => [{0, 1, 1}],
      "1. item\n   ---"               => [{0, 1, 2}],
      "- a\n  b\n  ---"               => [{0, 2, 2}],
      "- a\nb\n  ---"                 => [{0, 2, 2}], # a lazy line is the paragraph's
      "- a\n- b\n  ---"               => [{1, 2, 2}],
      "- a\n  - b\n    ---"           => [{1, 2, 2}],
      "- - a\n    ---"                => [{0, 1, 2}],
      "- a\n\n  - b\n\n  c\n  ---"    => [{4, 5, 2}],
      "> - a\n>   ---"                => [{0, 1, 2}],
      "- a\n     ---"                 => [{0, 1, 2}],
      "- # T\n  ---"                  => [{0, 0, 1}],
      "-\n  ## T"                     => [{1, 1, 2}],
      "- a\n  ## b"                   => [{1, 1, 2}],
      "- item\n---"                   => [] of {Int32, Int32, Int32}, # the list, then a rule
      "- item\n==="                   => [] of {Int32, Int32, Int32}, # text run on lazily
      "- a\n--"                       => [] of {Int32, Int32, Int32},
      "1. a\n  ---"                   => [] of {Int32, Int32, Int32}, # short of the content
      "- a\n      ---"                => [] of {Int32, Int32, Int32}, # four columns past it
      "- a\n  - b\n  ---"             => [] of {Int32, Int32, Int32}, # the outer item's rule
      "- a\n  > q\n\n  b\n---"        => [] of {Int32, Int32, Int32},
      "- ---"                         => [] of {Int32, Int32, Int32}, # one rule, no list
      "- ***"                         => [] of {Int32, Int32, Int32}, # a rule in the item
      "- * * *\n  ---"                => [] of {Int32, Int32, Int32},
      "* ---"                         => [] of {Int32, Int32, Int32},
      "1. ---"                        => [] of {Int32, Int32, Int32},
      "- [ ] ## T"                    => [] of {Int32, Int32, Int32}, # a task box is text
      "-     # code"                  => [] of {Int32, Int32, Int32},
      "- ```\n  # x\n  ```"           => [] of {Int32, Int32, Int32},
      "- a\n  ```\n  x\n  ---\n  ```" => [] of {Int32, Int32, Int32},
      "- a\n\n      x\n      ---"     => [] of {Int32, Int32, Int32},
      "> a\nb\n> ---"                 => [] of {Int32, Int32, Int32},
    }.each do |text, expected|
      found = headings_of(text)
      found.should eq(expected), "#{text.inspect}: #{found}"
      found.map(&.[2]).should eq(markd_levels(text)), "#{text.inspect} against markd"
    end
  end

  it "promotes and demotes an ATX heading in an item, keeping the marker and the caret" do
    with_app text: "# Top\n\n- one\n  - ## Title\n1. # First\n", view: false do |app|
      doc = app.editor.document
      place app, 3, 9 # "Ti|tle"
      app.demote_heading.should be_true
      app.markdown.lines[3].should eq "  - ### Title"
      app.editor.cursor_position.should eq doc.block_position(3) + 10
      app.promote_heading.should be_true
      app.promote_heading.should be_true
      app.markdown.lines[3].should eq "  - # Title"
      app.editor.cursor_position.should eq doc.block_position(3) + 8
      app.promote_heading.should be_true
      app.markdown.lines[3].should eq "  - Title"
      app.markdown.lines[0].should eq "# Top"
      place app, 4, 6
      app.promote_heading.should be_true
      app.markdown.lines[4].should eq "1. First"
      app.editor.cursor_position.should eq doc.block_position(4) + 4
    end
  end

  it "makes a setext heading in an item an ATX one after the marker" do
    with_app text: "# Top\n\n- item\n  ---\n\n  body\n", view: false do |app|
      doc = app.editor.document
      place app, 5, 3 # in the item's section
      app.demote_heading.should be_true
      app.markdown.should eq "# Top\n\n- ### item\n\n  body\n"
      app.editor.cursor_position.should eq doc.block_position(4) + 3
      app.promote_heading.should be_true
      app.markdown.should eq "# Top\n\n- ## item\n\n  body\n"
    end
    with_app text: "> 1. Two\n>    lines\n>    ===\n", view: false do |app|
      place app, 1, 6
      app.demote_heading.should be_true
      app.markdown.should eq "> 1. ## Two lines\n"
      app.editor.cursor_position.should eq 13
    end
    with_app text: "- a\nlazy\n  ===\n", view: false do |app|
      place app, 0, 2
      app.promote_heading.should be_true
      app.markdown.should eq "- a\nlazy\n"
    end
  end

  it "takes no list item's text over a rule for a heading" do
    {"# Top\n\n- item\n---\nmore\n",
     "# Top\n\n* ---\nmore\n",
     "# Top\n\n- a\n  - b\n  ---\nmore\n"}.each do |text|
      with_app text: text, view: false do |app|
        place app, app.editor.document.block_count - 2, 0
        app.demote_heading.should be_true
        app.markdown.should eq text.sub("# Top", "## Top")
      end
    end
  end

  it "jumps between headings in list items" do
    text = "# Top\n\n- ## In item\n\n  text\n\n- Setext\n  ---\n\n  more\n"
    with_app Md::Source.new, text: text, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.viewer.focus
      window.repaint
      plain = app.viewer.document.plain_text
      app.jump_heading(1).should be_true
      app.viewer.cursor_position.should eq plain.index("In item")
      app.editor.text_cursor.block_number.should eq 2
      app.jump_heading(1).should be_true
      app.viewer.cursor_position.should eq plain.index("Setext")
      app.editor.text_cursor.block_number.should eq 6
      app.jump_heading(1).should be_false
      app.jump_heading(-1).should be_true
      app.viewer.cursor_position.should eq plain.index("In item")
    end
  end

  it "takes a heading in an item for a line not to break or refill" do
    Md::App.unbreakable_line?("- ## A heading").should be_true
    Md::App.unbreakable_line?("  1. # A heading").should be_true
    Md::App.unbreakable_line?("- [ ] ## A task").should be_false
    Md::App.unbreakable_line?("- item").should be_false
  end
end
