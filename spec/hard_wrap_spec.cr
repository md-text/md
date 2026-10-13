require "./spec_helper"
require "file_utils"

# Format → Hard Wrap: Kate's static word wrap in the editor, through Crysterm's
# `hard_wrap_column`, with the carried line continuing the Markdown it is in
# (`MarkdownEdit#hard_wrap_prefix`); and Format → Rewrap → Paragraph, the
# refill of a paragraph to the same column.

# Puts the editor's caret at *column* of *line*, both 0-based.
private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

# Types *text* into the editor, a key per character.
private def type(window, text)
  text.each_char { |char| press window, char }
end

# The Format menu's Hard Wrap entry.
private def hard_wrap_entry(app)
  menu(app, 2).actions.find! { |a| a.text == "&Hard Wrap" }
end

describe "Md::App hard wrap" do
  it "is off by default, and puts the wrap column on the editor from the View menu: 80, or the text width" do
    with_app do |app|
      app.hard_wrap?.should be_false
      app.editor.hard_wrap_column.should be_nil
      entry = hard_wrap_entry(app)
      entry.checked?.should be_false
      entry.trigger
      app.hard_wrap?.should be_true
      entry.checked?.should be_true
      app.wrap_column.should eq Md::App::HARD_WRAP_COLUMN
      app.editor.hard_wrap_column.should eq 80
      app.text_width = 72
      app.editor.hard_wrap_column.should eq 72
      app.hard_wrap = false
      app.editor.hard_wrap_column.should be_nil
      app.wrap_column.should eq 72
    end
  end

  it "breaks a typed line at the last space before the column; a list item continues with its indentation" do
    with_app text: "- aaaa bbbb cccc ddd\n", view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.hard_wrap = true
      app.text_width = 20
      place app, 0, 20
      type window, "d"
      app.markdown.should eq "- aaaa bbbb cccc\n  dddd\n"
      app.editor.cursor_position.should eq 23
      type window, " eeee ffff gggg hhh"
      app.markdown.should eq "- aaaa bbbb cccc\n  dddd eeee ffff\n  gggg hhh\n"
      app.editor.document.modified?.should be_true
      # The viewer followed the edit.
      app.viewer.document.to_plain_text.should contain "gggg hhh"
    end
  end

  it "continues a blockquote with its marker, and a quoted list item with both" do
    with_app text: "> aaaa bbbb cccc ddd\n\n> - aaaa bbbb cccc d\n", view: false do |app, window|
      app.hard_wrap = true
      app.text_width = 20
      place app, 0, 20
      type window, "d"
      app.markdown.lines[0..1].should eq ["> aaaa bbbb cccc", "> dddd"]
      place app, 3, 20
      type window, "d"
      app.markdown.lines[3..4].should eq ["> - aaaa bbbb cccc", ">   dd"]
    end
  end

  it "leaves a code block, a heading and a table row unbroken" do
    with_app text: "```\naaaa bbbb cccc dddd\n```\n# aaaa bbbb cccc ddd\n| aaaa | bbbb | ccc |\n", view: false do |app, window|
      app.hard_wrap = true
      app.text_width = 20
      place app, 1, 19
      type window, " eeee"
      app.markdown.lines[1].should eq "aaaa bbbb cccc dddd eeee"
      place app, 3, 20
      type window, "d"
      app.markdown.lines[3].should eq "# aaaa bbbb cccc dddd"
      place app, 4, 19
      type window, "c"
      app.markdown.lines[4].should eq "| aaaa | bbbb | cccc |"
    end
  end

  it "leaves an indented code block unbroken" do
    with_app text: "text\n\n    aaaa bbbb cccc dddd\n", view: false do |app, window|
      app.hard_wrap = true
      app.text_width = 20
      place app, 2, 23
      type window, "e"
      app.markdown.lines[2].should eq "    aaaa bbbb cccc dddde"
    end
  end

  it "undoes the keystroke and its wrap as one step" do
    with_app text: "aaaa bbbb cccc ddddd\n", view: false do |app, window|
      app.hard_wrap = true
      app.text_width = 20
      place app, 0, 20
      type window, "e"
      app.markdown.should eq "aaaa bbbb cccc\nddddde\n"
      app.editor.undo.should be_true
      app.markdown.should eq "aaaa bbbb cccc ddddd\n"
    end
  end

  it "keeps the choice across runs" do
    with_config "md:\n  hard_wrap: true\n" do |path|
      with_app config: true do |app|
        app.hard_wrap?.should be_true
        app.editor.hard_wrap_column.should eq 80
        app.hard_wrap = false
        app.save_config
      end
      config_file(path)["md"]["hard_wrap"].as_bool.should be_false
    end
  end
end

describe "Md::App rewrap paragraph" do
  it "refills the caret's paragraph to the wrap column, a list item keeping its marker, the caret its place" do
    with_app text: "- aaaa bbbb\n  cccc dddd eeee ffff gggg\n\nnext para\n", view: false do |app, window|
      app.text_width = 20
      place app, 1, 8 # after "  cccc d"
      press(window, Tput::Key::AltQ).accepted?.should be_true
      app.markdown.should eq "- aaaa bbbb cccc\n  dddd eeee ffff\n  gggg\n\nnext para\n"
      app.editor.cursor_position.should eq app.editor.document.block_position(1) + 3
      app.editor.undo.should be_true
      app.markdown.should eq "- aaaa bbbb\n  cccc dddd eeee ffff gggg\n\nnext para\n"
    end
  end

  it "joins short lines, keeps a blockquote's markers and stops at a list item, a heading and a blank line" do
    with_app text: "# Title\n> aa\n> bb cc\n> dd\n- item\n\nxx\n", view: false do |app|
      app.text_width = 20
      place app, 2, 0
      app.rewrap_paragraph.should be_true
      app.markdown.should eq "# Title\n> aa bb cc dd\n- item\n\nxx\n"
      place app, 2, 2
      app.rewrap_paragraph.should be_true
      app.markdown.should eq "# Title\n> aa bb cc dd\n- item\n\nxx\n"
    end
  end

  it "refills every paragraph of a selection, leaving code blocks alone, and says so off a paragraph" do
    with_app text: "aa\nbb\n\n```\ncc\ndd\n```\n\n- ee\nff\n", view: false do |app|
      app.text_width = 20
      app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, 0, app.editor.document.size)
      app.rewrap_paragraph.should be_true
      app.markdown.should eq "aa bb\n\n```\ncc\ndd\n```\n\n- ee ff\n"
      place app, 4, 0
      app.rewrap_paragraph.should be_false
      notice(app).should contain "Not a paragraph"
      place app, 1, 0
      app.rewrap_paragraph.should be_false
    end
  end

  it "refills the whole of each paragraph a selection touches, not just its lines" do
    with_app text: "aa\nbb\ncc\n\ndd\nee\nff\n", view: false do |app|
      app.text_width = 20
      doc = app.editor.document
      # From "bb" to the middle of "ee": both paragraphs, all their lines.
      app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(1) + 1, doc.block_position(5) + 1)
      app.rewrap_paragraph.should be_true
      app.markdown.should eq "aa bb cc\n\ndd ee ff\n"
    end
  end

  it "leaves an indented code block, a fence nested in a list item and a rule alone" do
    with_app text: "para one\nline two\n\n    code here\n    more code\n\n- item\n  - sub\n\n    ```\n    fenced in\n    sub\n    ```\n\ntext\n---\nafter\nrule\n", view: false do |app|
      app.text_width = 40
      app.rewrap_document.should be_true
      app.markdown.should eq "para one line two\n\n    code here\n    more code\n\n- item\n  - sub\n\n    ```\n    fenced in\n    sub\n    ```\n\ntext\n---\nafter rule\n"
    end
  end

  it "refills every paragraph of the document as one undo step, and says so without one" do
    with_app text: "# Title\n\naa\nbb\n\n```\ncc\ndd\n```\n\n- ee\nff\n", view: false do |app|
      app.text_width = 20
      place app, 0, 0
      app.rewrap_document.should be_true
      app.markdown.should eq "# Title\n\naa bb\n\n```\ncc\ndd\n```\n\n- ee ff\n"
      app.editor.undo.should be_true
      app.markdown.should eq "# Title\n\naa\nbb\n\n```\ncc\ndd\n```\n\n- ee\nff\n"
    end
    with_app text: "# Title\n\n```\ncc\n```\n", view: false do |app|
      app.rewrap_document.should be_false
      notice(app).should contain "Not a paragraph"
    end
  end

  it "shows the Format → Rewrap entries, Paragraph with its key, the column in the label" do
    with_app do |app|
      rewrap = menu(app, 2).actions.find! { |a| a.text == "Re&wrap (to 80 Columns)" }
      entries = rewrap.menu || fail("Rewrap has no submenu")
      entries.map(&.text).should eq ["&Paragraph", "&Document"]
      entries[0].shortcut_text.should eq "Alt+Q"
      app.text_width = 72
      rewrap.text.should eq "Re&wrap (to 72 Columns)"
      app.text_width = 0 # no text width: the default column
      rewrap.text.should eq "Re&wrap (to 80 Columns)"
    end
  end
end
