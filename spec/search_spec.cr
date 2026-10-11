require "./spec_helper"

SEARCH_DOC = <<-MD
  # Alpha

  The needle is here, and a Needle there.

  ## Beta

  No match in this paragraph.

  ## Gamma

  A last needle.
  MD

describe "Md::App search" do
  it "finds forward from the caret, wraps around with a notice, and reports a miss" do
    with_app Md::Source.new(path: "doc.md"), text: SEARCH_DOC, view: true do |app, window|
      window.repaint
      viewer = app.viewer
      plain = viewer.document.plain_text
      app.search("needle").should be_true
      viewer.selected_text.should eq "needle"
      viewer.cursor_position.should eq plain.index!("needle") + "needle".size
      app.find_next.should be_true
      viewer.selected_text.should eq "Needle" # smartcase: a lowercase pattern ignores case
      app.find_next.should be_true
      viewer.selected_text.should eq "needle"
      viewer.text_cursor.selection_start.should eq plain.rindex("needle")
      app.find_next.should be_true # wraps
      viewer.text_cursor.selection_start.should eq plain.index("needle")
      notice(app).should contain "Search hit BOTTOM"
      app.find_next(reverse: true).should be_true # back over the wrap
      viewer.text_cursor.selection_start.should eq plain.rindex("needle")
      notice(app).should contain "Search hit TOP"

      app.search("Needle").should be_true # an uppercase letter: exact case
      viewer.selected_text.should eq "Needle"
      app.find_next.should be_true
      viewer.selected_text.should eq "Needle"

      app.search("absent").should be_false
      notice(app).should contain "Pattern not found: absent"
    end
  end

  it "takes a regular expression, or the text literally when it is not one" do
    with_app Md::Source.new(path: "doc.md"), text: SEARCH_DOC, view: true do |app|
      app.search("ne+dle th").should be_true
      app.viewer.selected_text.should eq "Needle th"
      app.search("(").should be_false # an unbalanced paren is literal text
      app.search("[").should be_false
    end
  end

  it "underlines every match, follows the text as it changes, and clears from the Edit menu" do
    with_app Md::Source.new, text: SEARCH_DOC, view: false do |app, _|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.search("needle").should be_true
      app.search_pane.should eq Md::App::Pane::Editor
      app.editor.extra_selections.size.should eq 3
      app.editor.extra_selections.all?(&.format.attributes.underline?).should be_true
      app.viewer.extra_selections.size.should eq 3
      # Past the match the search selected (typing would replace it).
      app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, app.editor.document.size)
      app.editor.insert_text "\n\nAnother needle."
      app.editor.extra_selections.size.should eq 4
      app.viewer.extra_selections.size.should eq 4
      clear = app.main.menu_bar.menus[1].actions.find! { |a| a.text == "Clear Search &Highlights" }
      clear.trigger
      app.editor.extra_selections.should be_empty
      app.viewer.extra_selections.should be_empty
      app.search_pattern.should eq "needle" # `n` still works
      app.find_next.should be_true
    end
  end

  it "keeps the viewer's own overlays when it highlights" do
    with_app Md::Source.new(path: "doc.md"), text: "See [a link](#beta).\n\n## Beta\n", view: true do |app|
      app.viewer.text_cursor = Crysterm::TextCursor.new(app.viewer.document, 0)
      own = app.viewer.extra_selections.dup
      app.search("beta")
      (app.viewer.extra_selections.size - own.size).should eq 1
      app.clear_search
      app.viewer.extra_selections.should eq own
      app.search_pattern.should be_nil
      app.find_next.should be_false
      notice(app).should contain "No previous search"
    end
  end

  it "has the pager's keys in the viewer and the prompt in place of the status bar" do
    with_app Md::Source.new(path: "doc.md"), text: SEARCH_DOC, view: true do |app, window|
      press window, '/'
      app.main.status_bar.prompting?.should be_true
      answer app, "gamma"
      app.main.status_bar.prompting?.should be_false
      app.viewer.selected_text.should eq "Gamma"
      press window, '?'
      answer app, "alpha"
      app.search_backward?.should be_true
      app.viewer.selected_text.should eq "Alpha"
      press window, 'N'                          # against the search's direction: forward
      app.viewer.selected_text.should eq "Alpha" # the only one, wrapped
      press window, Tput::Key::CtrlF
      answer app, "needle"
      app.search_backward?.should be_false
      press window, 'n'
      app.viewer.selected_text.should eq "Needle"
      press window, Tput::Key::AltG
      app.viewer.selected_text.should eq "needle"
    end
  end

  it "leaves the pager's letters to the editor" do
    with_app do |app, window|
      app.editor.focus
      app.editor._listener Crysterm::Event::KeyPress.new('/')
      app.markdown.should eq "/"
      app.main.status_bar.prompting?.should be_false
      press window, Tput::Key::CtrlF # the editor's search key
      app.main.status_bar.prompting?.should be_true
      app.main.status_bar.line_prompt.cancel
    end
  end
end

describe "Md::App go to line and headings" do
  it "puts both panes on a source line, clamped, counting from the end for zero and negatives" do
    with_app Md::Source.new, text: SEARCH_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      window.repaint
      app.go_to_line 9
      app.editor.text_cursor.block_number.should eq 8
      app.viewer.document.plain_text[app.viewer.cursor_position, 5].should eq "Gamma"
      app.go_to_line 99
      app.editor.text_cursor.block_number.should eq app.editor.document.block_count - 1
      app.go_to_line 0
      app.editor.text_cursor.block_number.should eq app.editor.document.block_count - 1
      app.go_to_line -1
      app.editor.text_cursor.block_number.should eq app.editor.document.block_count - 2
      app.go_to_line 3, 5
      app.editor.text_cursor.block_number.should eq 2
      app.editor.text_cursor.column_number.should eq 4
      app.go_to_line 3, 500 # the column is clamped to the line
      app.editor.text_cursor.column_number.should eq app.editor.document.blocks[2].size
    end
  end

  it "asks for the line with `:` in the viewer and refuses what is not a number" do
    with_app Md::Source.new(path: "doc.md"), text: SEARCH_DOC, view: true do |app, window|
      press window, ':'
      answer app, "5"
      app.viewer.document.plain_text[app.viewer.cursor_position, 4].should eq "Beta"
      press window, Tput::Key::CtrlL
      answer app, "five"
      notice(app).should contain "Not a line number: five"
    end
  end

  it "jumps between headings in both panes" do
    with_app Md::Source.new, text: SEARCH_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.viewer.focus
      window.repaint
      plain = app.viewer.document.plain_text
      press window, ']'
      app.viewer.cursor_position.should eq plain.index("Beta")
      app.editor.text_cursor.block_number.should eq 4
      press window, ']'
      app.viewer.cursor_position.should eq plain.index("Gamma")
      press window, ']'
      app.viewer.cursor_position.should eq plain.index("Gamma") # none below
      notice(app).should contain "No heading below"
      press window, '['
      app.viewer.cursor_position.should eq plain.index("Beta")
      press window, Tput::Key::AltUp
      app.viewer.cursor_position.should eq plain.index("Alpha")
      app.jump_heading(-1).should be_false
      press window, Tput::Key::AltDown
      app.viewer.cursor_position.should eq plain.index("Beta")

      # From the editor, relative to the editor's caret.
      app.editor.focus
      app.editor.cursor_position = app.editor.document.block_position(8) # the Gamma line
      app.jump_heading(-1).should be_true
      app.viewer.cursor_position.should eq plain.index("Beta")
      app.editor.text_cursor.block_number.should eq 4
    end
  end
end
