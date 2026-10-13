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

# *text* after Format → Rewrap → Document to *width* columns.
private def rewrapped(text, width = 20)
  result = ""
  with_app text: text, view: false do |app|
    app.text_width = width
    app.rewrap_document
    result = app.markdown
  end
  result
end

describe "Md::App editing, Rewrap" do
  it "breaks no line where the next would start a list item, a heading, a quote, a fence or a setext underline" do
    rewrapped("aaaa bbbb cccc dddd - eeee\n").should eq "aaaa bbbb cccc\ndddd - eeee\n"
    rewrapped("aaaa bbbb cccc dddd 1. eeee\n").should eq "aaaa bbbb cccc\ndddd 1. eeee\n"
    rewrapped("aaaa bbbb cccc dddd # eeee\n").should eq "aaaa bbbb cccc\ndddd # eeee\n"
    rewrapped("aaaa bbbb cccc dddd > eeee\n").should eq "aaaa bbbb cccc\ndddd > eeee\n"
    rewrapped("aaaa bbbb cccc dddd ```\n").should eq "aaaa bbbb cccc\ndddd ```\n"
    rewrapped("aaaa bbbb cccc dddd ===\n").should eq "aaaa bbbb cccc\ndddd ===\n"
    rewrapped("- aaaa bbbb cccc dd + eeee\n").should eq "- aaaa bbbb cccc\n  dd + eeee\n"
  end

  it "breaks no line after a backslash, which would end it in a hard break" do
    rewrapped("aaaa bbbb cccc ddd\\ eeee\n").should eq "aaaa bbbb cccc\nddd\\ eeee\n"
    rewrapped("aaaa bbbb cccc dd\\\\ eeee\n").should eq "aaaa bbbb cccc dd\\\\\neeee\n"
  end
end

describe "Md::App editing, Rewrap and hard breaks" do
  it "keeps a hard line break, two spaces or a backslash, where it is, the words after it flowing on" do
    rewrapped("aaaa bbbb  \ncccc\ndddd\n").should eq "aaaa bbbb  \ncccc dddd\n"
    rewrapped("aaaa\\\nbbbb cccc dddd eeee ffff\n").should eq "aaaa\\\nbbbb cccc dddd eeee\nffff\n"
    rewrapped("- aaaa  \n  bbbb\n  cccc\n").should eq "- aaaa  \n  bbbb cccc\n"
    rewrapped("> aaaa  \n> bbbb\n> cccc\n").should eq "> aaaa  \n> bbbb cccc\n"
  end
end

describe "Md::App editing, Rewrap and list items" do
  it "keeps a space after a marker whose text is on the lines below" do
    rewrapped("-\n  aaaa\n  bbbb\n").should eq "- aaaa bbbb\n"
    rewrapped("1.\n   aaaa\n").should eq "1. aaaa\n"
  end
end

describe "Md::App editing, Rewrap and what is no paragraph" do
  it "leaves link reference definitions one to a line" do
    rewrapped("[a]: /x\n[b]: /y 'Title'\ntext\n").should eq "[a]: /x\n[b]: /y 'Title'\ntext\n"
    rewrapped("aaaa\n[b]: /y\n").should eq "aaaa\n[b]: /y\n"
  end

  it "joins no text to an empty item unless indented to the item's content" do
    rewrapped("- \naaaa\n").should eq "- \naaaa\n"
    rewrapped("> 1. \n> aaaa\n").should eq "> 1. \n> aaaa\n"
    rewrapped("- \n  aaaa\n").should eq "- aaaa\n"
  end
end

describe "Md::App editing, Hard Wrap" do
  it "starts no carried line with Markdown of its own, nor one a word being typed could become" do
    {"- x", "# x", "> x", "12. x"}.each do |typed|
      with_app text: "aaaa bbbb cccc dddd\n", view: false do |app, window|
        app.hard_wrap = true
        app.text_width = 20
        place app, 0, 19
        " #{typed}".each_char { |char| press window, char }
        app.markdown.should eq "aaaa bbbb cccc\ndddd #{typed}\n"
      end
    end
  end
end
