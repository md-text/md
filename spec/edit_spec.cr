require "./spec_helper"

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
    with_app text: "- one\n1. first\n- [x] done\n  * sub\n> 2) quoted\n", view: false do |app, window|
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
    with_app text: "- one two\n", view: false do |app, window|
      place app, 0, 5
      press window, Tput::Key::Enter
      app.markdown.should eq "- one\n- two\n"
      app.editor.cursor_position.should eq 8
    end
  end

  it "ends the list on Enter on an empty item, keeping the quote" do
    with_app text: "- one\n  - \n> - \n", view: false do |app, window|
      place app, 1, 4
      press(window, Tput::Key::Enter).accepted?.should be_true
      app.markdown.should eq "- one\n\n> - \n"
      place app, 2, 4
      press window, Tput::Key::Enter
      app.markdown.should eq "- one\n\n> \n"
    end
  end

  it "ends the list on two Enters in a row — a bullet, a task or a number — and a third is a plain newline" do
    with_app text: "- one\n\n- [x] done\n\n3. third\n", view: false do |app, window|
      place app, 0, 5
      press window, Tput::Key::Enter # continues
      app.markdown.lines[1].should eq "- "
      press(window, Tput::Key::Enter).accepted?.should be_true # the empty item ends the list
      app.markdown.should eq "- one\n\n\n- [x] done\n\n3. third\n"
      app.editor.cursor_position.should eq 6
      press window, Tput::Key::Enter # a plain newline, the editor's own
      app.markdown.should eq "- one\n\n\n\n- [x] done\n\n3. third\n"

      place app, 4, 10
      press window, Tput::Key::Enter
      app.markdown.lines[5].should eq "- [ ] " # the box still there
      press window, Tput::Key::Enter
      app.markdown.lines[5].should eq ""
      press window, Tput::Key::Enter
      app.markdown.lines[5, 2].should eq ["", ""]

      place app, 8, 8
      press window, Tput::Key::Enter
      app.markdown.lines[9].should eq "4. "
      press window, Tput::Key::Enter
      app.markdown.lines[9].should eq ""
      press window, Tput::Key::Enter
      app.markdown.should end_with "3. third\n\n\n"
      app.editor.undo.should be_true # each step one undo step
      app.markdown.should end_with "3. third\n\n"
    end
  end

  it "leaves Enter to the editor off a list item, or with the caret inside the marker" do
    with_app text: "text\n- one\n", view: false do |app, window|
      place app, 0, 4
      press window, Tput::Key::Enter
      app.markdown.should eq "text\n\n- one\n"
      place app, 2, 0
      press window, Tput::Key::Enter
      app.markdown.should eq "text\n\n\n- one\n"
    end
  end

  it "indents and outdents a list item with Tab and Shift-Tab, by the item above's content offset" do
    with_app text: "- a\n- b\n1. step\n- detail\n", view: false do |app, window|
      place app, 1, 2
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "- a\n  - b\n1. step\n- detail\n"
      app.editor.cursor_position.should eq 8
      # An item cannot nest deeper than one level under the item above.
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "- a\n  - b\n1. step\n- detail\n"
      notice(app).should contain "Already nested"
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
      notice(app).should contain "Not indented"
      # The first item has nothing above to nest under: indenting it would
      # change nothing in the rendering, so it stays.
      place app, 0, 2
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
      notice(app).should contain "No list item above"
      # A bullet under an ordered item goes under its content, three in.
      place app, 3, 0
      press window, Tput::Key::Tab
      app.markdown.should eq "- a\n- b\n1. step\n   - detail\n"
      press window, Tput::Key::ShiftTab
      app.markdown.should eq "- a\n- b\n1. step\n- detail\n"
    end
  end

  it "indents every line of a selection by the same amount, in one undo step" do
    with_app text: "- top\n- a\n  continued\n\n- b\n", view: false do |app, window|
      select_text app, 6, app.editor.document.size
      press window, Tput::Key::Tab
      app.markdown.should eq "- top\n  - a\n    continued\n\n  - b\n"
      app.editor.undo.should be_true
      app.markdown.should eq "- top\n- a\n  continued\n\n- b\n"
      app.indent_lines(-1).should be_false # at the margin already: nothing to do
      app.markdown.should eq "- top\n- a\n  continued\n\n- b\n"
    end
  end

  it "indents any other line by four spaces with Tab and outdents it with Shift-Tab, staying in the editor" do
    with_app text: "text\n\tcode\n> quoted\n", view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      place app, 0, 2
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "    text\n\tcode\n> quoted\n"
      app.editor.cursor_position.should eq 6
      app.editor.focused?.should be_true
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "text\n\tcode\n> quoted\n"
      # At the margin: nothing comes off, and the key still stays put.
      press(window, Tput::Key::ShiftTab).accepted?.should be_true
      app.markdown.should eq "text\n\tcode\n> quoted\n"
      app.editor.focused?.should be_true
      # A leading tab is one unit; a quoted line indents after its marker.
      place app, 1, 3
      press window, Tput::Key::ShiftTab
      app.markdown.should eq "text\ncode\n> quoted\n"
      place app, 2, 3
      press window, Tput::Key::Tab
      app.markdown.should eq "text\ncode\n>     quoted\n"
      # A selection of plain lines moves together, in one undo step.
      select_text app, 0, app.editor.document.size
      press window, Tput::Key::Tab
      app.markdown.should eq "    text\n    code\n>         quoted\n"
      app.editor.undo.should be_true
      app.markdown.should eq "text\ncode\n>     quoted\n"
    end
  end

  it "leaves the space after a quote marker alone when outdenting: it is the marker's, not indentation" do
    with_app text: "> quoted\n>   indented\n", view: false do |app|
      place app, 0, 3
      app.indent_lines(-1).should be_false
      app.markdown.should eq "> quoted\n>   indented\n"
      place app, 1, 3
      app.indent_lines(-1).should be_true
      app.markdown.should eq "> quoted\n> indented\n"
    end
    with_app text: "> - item\n>   - sub\n", view: false do |app|
      place app, 0, 4
      app.indent_lines(-1).should be_false
      notice(app).should contain "Not indented"
      place app, 1, 6
      app.indent_lines(-1).should be_true
      app.markdown.should eq "> - item\n> - sub\n"
    end
  end

  it "shows Tab and Shift+Tab on Format → Indent and Outdent, keys that are theirs in the editor alone" do
    with_app text: "text\n", view: false do |app, window|
      indent = menu(app, 3).actions.find!(&.text.==("I&ndent"))
      outdent = menu(app, 3).actions.find!(&.text.==("&Outdent"))
      indent.shortcut_text.should eq "Tab"
      outdent.shortcut_text.should eq "Shift+Tab"
      indent.shortcut_context.widget?.should be_true
      app.editor.actions.should eq [indent, outdent]
      # Outside the editor, Tab cycles the focus as before, indenting
      # nothing (the viewer has it for its links first).
      app.show_pane(Md::App::Pane::Toc).focus
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "text\n"
      app.toc.focused?.should be_false
      app.show_pane(Md::App::Pane::Viewer).focus
      press(window, Tput::Key::Tab).accepted?.should be_true
      app.markdown.should eq "text\n"
      # The entry itself indents from any pane, through the editor.
      app.viewer.focus
      indent.trigger
      app.markdown.should eq "    text\n"
      outdent.trigger
      app.markdown.should eq "text\n"
    end
  end

  it "gives a list item a task box and takes it off, ticks and unticks it, and makes a line of text an item" do
    with_app text: "- item\ntext\n", view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      place app, 0, 3
      app.toggle_task_box.should be_true
      app.markdown.should eq "- [ ] item\ntext\n"
      press(window, Tput::Key::AltX).accepted?.should be_true # Toggle Task Checkbox
      app.markdown.should eq "- [x] item\ntext\n"
      app.viewer.document.blocks[0].block_format.checked?.should be_true # the viewer followed
      app.check_task.should be_true
      app.markdown.should eq "- [ ] item\ntext\n"
      app.toggle_task_box.should be_true # the box off again
      app.markdown.should eq "- item\ntext\n"
      app.check_task.should be_true # no box yet: a ticked one
      app.markdown.should eq "- [x] item\ntext\n"
      app.toggle_task_box.should be_true
      app.markdown.should eq "- item\ntext\n"
      app.editor.undo.should be_true # each one step
      app.markdown.should eq "- [x] item\ntext\n"
      place app, 1, 0
      app.toggle_task_box.should be_true
      app.markdown.should eq "- [x] item\n- [ ] text\n"
      app.editor.undo.should be_true # the item and its box, one step
      app.markdown.should eq "- [x] item\ntext\n"
      place app, 1, 0
      app.check_task.should be_true
      app.markdown.should eq "- [x] item\n- [x] text\n"
    end
  end

  it "makes the lines of text a selection holds items with boxes, in a quote too, and says so where there is none" do
    with_app text: "> one\n> two\n\n# Heading\n\n```\ncode\n```\n", view: false do |app|
      select_text app, 0, app.editor.document.block_position(2)
      app.toggle_task_box.should be_true
      app.markdown.should eq "> - [ ] one\n> - [ ] two\n\n# Heading\n\n```\ncode\n```\n"
      {3, 6}.each do |line| # a heading, a code block's line
        place app, line, 1
        app.check_task.should be_false
        notice(app).should contain "Not a list item or a line of text"
      end
      app.markdown.should eq "> - [ ] one\n> - [ ] two\n\n# Heading\n\n```\ncode\n```\n"
    end
  end

  it "takes the box a line of text starts with for the box of the item made of it" do
    with_app text: "[x] done\n[ ] todo\n[x] kept\n", view: false do |app|
      place app, 0, 2
      app.check_task.should be_true # ticked, not flipped to [ ]
      app.markdown.should eq "- [x] done\n[ ] todo\n[x] kept\n"
      place app, 1, 2
      app.check_task.should be_true
      app.markdown.should eq "- [x] done\n- [x] todo\n[x] kept\n"
      place app, 2, 2
      app.toggle_task_box.should be_true # kept, not taken off
      app.markdown.should eq "- [x] done\n- [x] todo\n- [x] kept\n"
    end
  end

  it "leaves a line of code that looks like a list item alone" do
    with_app text: "```\n- not an item\n```\n", view: false do |app|
      place app, 1, 3
      app.toggle_task_box.should be_false
      app.check_task.should be_false
      app.markdown.should eq "```\n- not an item\n```\n"
    end
  end

  it "shows on the Task entry whether the caret's item is a task, as the menu opens, and flips it" do
    with_app text: "- [ ] task\n- item\ntext\n\n# Heading\n", view: false do |app|
      insert = menu(app, 2)
      task = insert.actions.find! { |a| a.text == "As a &Task" }
      task.checkable?.should be_true
      toggle = insert.actions.find! { |a| a.text == "Toggle Task Chec&kbox" }
      toggle.shortcut_text.should eq "Alt+X"
      place app, 0, 2
      insert.emit Crysterm::Event::AboutToShow
      task.checked?.should be_true
      place app, 1, 2
      insert.emit Crysterm::Event::AboutToShow
      task.checked?.should be_false
      task.trigger # picking the entry: checked, and the box with it
      task.checked?.should be_true
      app.markdown.should eq "- [ ] task\n- [ ] item\ntext\n\n# Heading\n"
      place app, 2, 0
      insert.emit Crysterm::Event::AboutToShow
      task.checked?.should be_false # no item
      # A line of text: made an item, with a box.
      task.trigger
      task.checked?.should be_true
      app.markdown.should eq "- [ ] task\n- [ ] item\n- [ ] text\n\n# Heading\n"
      place app, 4, 2 # nothing to make a task of
      insert.emit Crysterm::Event::AboutToShow
      task.trigger
      task.checked?.should be_false # nothing to flip: the check stays off
      notice(app).should contain "Not a list item"
    end
  end

  it "reads the Task entry's state from the viewer's caret while reading, without showing the editor" do
    with_app Md::Source.new(path: "doc.md"), text: "- [x] task\n- item\n", view: true do |app|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      insert = menu(app, 2)
      task = insert.actions.find! { |a| a.text == "As a &Task" }
      plain = app.viewer.document.plain_text
      app.viewer.text_cursor = Crysterm::TextCursor.new(app.viewer.document, plain.index!("item"))
      insert.emit Crysterm::Event::AboutToShow
      task.checked?.should be_false
      app.viewer.text_cursor = Crysterm::TextCursor.new(app.viewer.document, plain.index!("task"))
      insert.emit Crysterm::Event::AboutToShow
      task.checked?.should be_true
      app.visible_panes.should eq [Md::App::Pane::Viewer] # opening a menu edits nothing
    end
  end

  it "boxes and checks every list item of a selection, each as it is, in one undo step" do
    with_app text: "- a\n- [x] b\ntext\n- [ ] c\n", view: false do |app|
      select_text app, 0, app.editor.document.size
      app.toggle_task_box.should be_true
      app.markdown.should eq "- [ ] a\n- b\ntext\n- c\n"
      app.check_task.should be_true
      app.markdown.should eq "- [x] a\n- [x] b\ntext\n- [x] c\n"
      app.editor.undo.should be_true
      app.markdown.should eq "- [ ] a\n- b\ntext\n- c\n"
      app.editor.undo.should be_true
      app.markdown.should eq "- a\n- [x] b\ntext\n- [ ] c\n"
    end
  end

  it "wraps the word at the caret in bold, italic and code, and unwraps it again" do
    with_app text: "some word here\n", view: false do |app, window|
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
    with_app text: "some __word__ here, _it_\n", view: false do |app|
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

  it "takes a marker on one end of the selection alone as text to wrap, not as wrapping to undo" do
    with_app text: "a `code here\n", view: false do |app|
      select_text app, 2, 7 # "`code"
      app.toggle_code.should be_true
      app.markdown.should eq "a ``code` here\n"
      app.editor.selected_text.should eq "`code"
    end
  end

  it "keeps spaces at the selection's ends outside the markers, which must hug the text" do
    with_app text: "a word  here\n", view: false do |app|
      select_text app, 1, 8 # " word  "
      app.toggle_bold.should be_true
      app.markdown.should eq "a **word**  here\n"
      app.editor.selected_text.should eq "word"
      app.toggle_bold.should be_true
      app.markdown.should eq "a word  here\n"
    end
  end

  it "takes the markers off text selected with spaces beside them, rather than adding more" do
    with_app text: "a **word** here\n", view: false do |app|
      select_text app, 2, 11 # "**word** "
      app.toggle_bold.should be_true
      app.markdown.should eq "a word here\n"
      app.editor.selected_text.should eq "word"
    end
  end

  it "inserts the pair with the caret between when there is nothing to wrap" do
    with_app do |app|
      app.toggle_bold.should be_true
      app.markdown.should eq "****"
      app.editor.cursor_position.should eq 2
    end
  end

  it "puts the caret's paragraph in a fenced code block, and takes the fences off again from anywhere in it" do
    with_app text: "Intro.\n\nputs 1\nputs 2\n\nAfter.\n", view: false do |app|
      place app, 3, 2
      app.toggle_code_block.should be_true
      app.markdown.should eq "Intro.\n\n```\nputs 1\nputs 2\n```\n\nAfter.\n"
      app.editor.cursor_position.should eq app.editor.document.block_position(4) + 2 # still in "puts 2"
      # The opening fence.
      place app, 2, 0
      app.toggle_code_block.should be_true
      app.markdown.should eq "Intro.\n\nputs 1\nputs 2\n\nAfter.\n"
      app.toggle_code_block
      place app, 3, 4 # a line of the code
      app.toggle_code_block
      app.markdown.should eq "Intro.\n\nputs 1\nputs 2\n\nAfter.\n"
      app.editor.document.undo
      app.markdown.should eq "Intro.\n\n```\nputs 1\nputs 2\n```\n\nAfter.\n"
    end
  end

  it "fences the selection's lines with their quote markers, and drops an empty block on a blank line" do
    with_app text: "> a\n> b\n> c\n\nend\n", view: false do |app|
      doc = app.editor.document
      select_text app, doc.block_position(1), doc.block_position(2) + 1
      app.toggle_code_block.should be_true
      app.markdown.should eq "> a\n> ```\n> b\n> c\n> ```\n\nend\n"
      app.editor.text_cursor.selected_text.should eq "> b\n>"
      place app, 5, 0
      app.toggle_code_block.should be_true
      app.markdown.should eq "> a\n> ```\n> b\n> c\n> ```\n```\n\n```\nend\n"
      app.editor.cursor_position.should eq doc.block_position(6)
    end
  end

  it "takes the opening fence alone off a block left open, and leaves a fence inside code alone" do
    with_app text: "````\n```\ncode\n````\n", view: false do |app|
      place app, 1, 0 # a fence shown inside the block's code
      app.toggle_code_block
      app.markdown.should eq "```\ncode\n"
      place app, 1, 2 # in a block open to the end
      app.toggle_code_block
      app.markdown.should eq "code\n"
      app.editor.cursor_position.should eq 2
    end
  end

  it "fences a paragraph after a block an outdent ended, leaving that block alone" do
    with_app text: "- item\n  ```\n  code\n\nafter\n", view: false do |app|
      place app, 4, 2 # past the list item, which ended the block in it
      app.toggle_code_block.should be_true
      app.markdown.should eq "- item\n  ```\n  code\n\n```\nafter\n```\n"
    end
  end

  it "fences the caret's paragraph without the heading above it or a fenced block below it" do
    with_app text: "## Install\nmake\nmake install\n```\nold\n```\n", view: false do |app|
      place app, 1, 0
      app.toggle_code_block.should be_true
      app.markdown.should eq "## Install\n```\nmake\nmake install\n```\n```\nold\n```\n"
    end
  end

  it "keeps a whole-line selection on its lines when fencing them" do
    with_app text: "a\nb\nc\n", view: false do |app|
      doc = app.editor.document
      select_text app, 0, doc.block_position(2) # "a\nb\n", up to c's start
      app.toggle_code_block.should be_true
      app.markdown.should eq "```\na\nb\n```\nc\n"
      app.editor.text_cursor.selected_text.should eq "a\nb\n```\n"
    end
  end

  it "takes the fences off a block opened on the line that outdented a list item's block" do
    with_app text: "- item\n  ```\n  code\n```\nmore\n```\n", view: false do |app|
      place app, 4, 2 # in the block the outdented fence opens
      app.toggle_code_block.should be_true
      app.markdown.should eq "- item\n  ```\n  code\nmore\n"
    end
  end

  it "takes off an empty fenced block that ends the document" do
    with_app text: "x\n```\n```", view: false do |app|
      place app, 2, 1
      app.toggle_code_block.should be_true
      app.markdown.should eq "x"
      app.editor.cursor_position.should eq 1
    end
  end

  it "takes a ``` that a paragraph's text runs on to, four columns in, for text, not a fence" do
    with_app text: "text\n    ```\nmore\n", view: false do |app|
      place app, 1, 5
      app.toggle_code_block.should be_true
      app.markdown.should eq "```\ntext\n    ```\nmore\n```\n"
    end
  end

  it "promotes and demotes the heading on the caret's line" do
    with_app text: "## Title\n> ## quoted\n###### deep\n", view: false do |app, window|
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

  it "promotes and demotes the heading of the caret's section from anywhere in its text, keeping the caret" do
    with_app text: "Preface.\n\n## Title\n\nBody text.\n\n```\n# not a heading\n```\n\nMore.\n", view: false do |app|
      doc = app.editor.document
      place app, 10, 2 # "More.", below a code block with a # line in it
      app.demote_heading.should be_true
      app.markdown.lines[2].should eq "### Title"
      app.markdown.lines[7].should eq "# not a heading"
      app.editor.cursor_position.should eq doc.block_position(10) + 2
      place app, 4, 5
      app.promote_heading.should be_true
      app.promote_heading.should be_true
      app.markdown.lines[2].should eq "# Title"
      app.editor.cursor_position.should eq doc.block_position(4) + 5
      app.editor.text_cursor.block.text.should eq "Body text."
      place app, 0, 3 # before the first heading: the line itself
      app.promote_heading.should be_false
      notice(app).should contain "Not a heading"
      app.demote_heading.should be_true
      app.markdown.lines[0].should eq "# Preface."
      app.editor.cursor_position.should eq 5
    end
  end

  it "shifts a setext heading from its section, making it an ATX one" do
    text = "# Top\n\nSetext Title\n---\n\nBody text.\n"
    with_app text: text, view: false do |app|
      doc = app.editor.document
      place app, 5, 4 # in the section under the --- heading, not the # one
      app.demote_heading.should be_true
      app.markdown.should eq "# Top\n\n### Setext Title\n\nBody text.\n"
      app.editor.cursor_position.should eq doc.block_position(4) + 4
      app.editor.text_cursor.block.text.should eq "Body text."
    end
    with_app text: text, view: false do |app|
      place app, 3, 1 # on the underline
      app.promote_heading.should be_true
      app.markdown.should eq "# Top\n\n# Setext Title\n\nBody text.\n"
    end
    # A === heading's lines joined; promoted, it loses the underline.
    with_app text: "> Two\n> lines\n> ===\ntext\n", view: false do |app|
      place app, 0, 2
      app.demote_heading.should be_true
      app.markdown.should eq "> ## Two lines\ntext\n"
    end
    with_app text: "Title\n===\n\ntext\n", view: false do |app|
      place app, 3, 0
      app.promote_heading.should be_true
      app.markdown.should eq "Title\n\ntext\n"
    end
  end

  it "takes a --- after a blank line, a list item or in code for no setext underline" do
    {"# Top\n\nText\n\n---\n\nmore\n",
     "# Top\n\n- item\n---\nmore\n",
     "# Top\n\n```\nText\n---\n```\nmore\n"}.each do |text|
      with_app text: text, view: false do |app|
        place app, app.editor.document.block_count - 2, 0
        app.demote_heading.should be_true
        app.markdown.should eq text.sub("# Top", "## Top")
      end
    end
  end

  it "leaves a line of code before the first heading alone" do
    with_app text: "```\nmake\n```\n", view: false do |app|
      place app, 1, 2
      app.demote_heading.should be_false
      notice(app).should contain "Not a heading"
      app.markdown.should eq "```\nmake\n```\n"
    end
  end

  it "formats from the viewer at the source of its caret, showing the editor" do
    with_app text: "some word here\n", view: true do |app|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.viewer.text_cursor = Crysterm::TextCursor.new(app.viewer.document, 6)
      app.toggle_bold.should be_true
      app.markdown.should eq "some **word** here\n"
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
    end
  end
end
