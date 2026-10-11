require "./spec_helper"

# View → Follow cursor: the editor's and the viewer's carets follow each
# other, matched by source line (`TextBlock#source_line`).

FOLLOW_DOC = "# Title\n\nSome *text*\nwraps here.\n\n```\ncode\n```\n\n## Section\n\nMore.\n"

# Editor position of (1-based) *line*, plus *col*.
private def at(app, line, col = 0)
  app.editor.document.block_position(line - 1) + col
end

# Viewer position of the block whose text is *text*, plus *col*.
private def shown(app, text, col = 0)
  doc = app.viewer.document
  i = (0...doc.block_count).find! { |k| doc.blocks[k].text == text }
  doc.block_position(i) + col
end

describe "Md::App follow cursor" do
  it "maps editor positions to the rendered block and back" do
    with_app Md::Source.new, text: FOLLOW_DOC, view: false do |app|
      app.show_pane Md::App::Pane::Viewer
      app.viewer_position(at(app, 1)).should eq shown(app, "Title")
      app.viewer_position(at(app, 1, 2)).should eq shown(app, "Title", 2)
      # The soft-wrapped paragraph is one block; its second source line
      # carries over by offset from the first.
      app.viewer_position(at(app, 3)).should eq shown(app, "Some text wraps here.")
      app.viewer_position(at(app, 4, 3)).should eq shown(app, "Some text wraps here.", 3 + "Some *text*\n".size)
      # A fence line renders nothing: the block above it.
      app.viewer_position(at(app, 6)).should eq shown(app, "Some text wraps here.", "Some text wraps here.".size)
      app.viewer_position(at(app, 7, 2)).should eq shown(app, "code", 2)
      app.viewer_position(at(app, 12)).should eq shown(app, "More.")

      app.editor_position(shown(app, "Title")).should eq at(app, 1)
      app.editor_position(shown(app, "Some text wraps here.", 2)).should eq at(app, 3, 2)
      app.editor_position(shown(app, "code", 3)).should eq at(app, 7, 3)
      app.editor_position(shown(app, "More.", 5)).should eq at(app, 12, 5)
    end
  end

  it "keeps the other pane's caret on the focused pane's place, when following" do
    with_app Md::Source.new, text: FOLLOW_DOC, view: false do |app|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.follow_cursor?.should be_false
      app.editor.cursor_position = at(app, 12)
      app.viewer.cursor_position.should eq 0 # off: nothing follows

      app.follow_cursor = true # on: aligned at once, from the focused pane
      app.viewer.cursor_position.should eq shown(app, "More.")
      app.editor.cursor_position = at(app, 7, 1)
      app.viewer.cursor_position.should eq shown(app, "code", 1)

      app.viewer.focus # the viewer leads now
      app.viewer.cursor_position = shown(app, "Title", 3)
      app.editor.cursor_position.should eq at(app, 1, 3)

      app.follow_cursor = false
      app.viewer.cursor_position = shown(app, "More.")
      app.editor.cursor_position.should eq at(app, 1, 3)
    end
  end

  it "re-places the viewer's caret after an edit re-rendered it" do
    with_app Md::Source.new, text: FOLLOW_DOC, view: false do |app|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.follow_cursor = true
      app.editor.cursor_position = at(app, 12, 5)
      app.editor.insert_text "!"
      app.viewer.document.plain_text.should contain "More.!"
      app.viewer.cursor_position.should eq shown(app, "More.!", 6)
    end
  end

  it "scrolls the following pane into view, and is a View menu toggle" do
    long = (1..60).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"
    with_app Md::Source.new, text: long, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      window.repaint
      follow = menu(app, 3).actions[5]
      follow.text.should eq "&Follow cursor"
      follow.checked?.should be_false
      follow.trigger
      app.follow_cursor?.should be_true
      app.editor.cursor_position = at(app, 99)
      window.repaint
      app.viewer.scroll_position.should be > 0
      window.dump.to_s.should contain "Paragraph 50"
      app.follow_cursor = false
      follow.checked?.should be_false
    end
  end

  it "puts the following pane's caret on the same viewport row as the leading pane's" do
    long = (1..60).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"
    with_app Md::Source.new, text: long, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.follow_cursor = true
      window.repaint
      # Scroll the editor so its caret sits mid-viewport, then move within
      # the viewport: the viewer's caret row follows the editor's, not just
      # into view.
      app.editor.cursor_position = at(app, 79)
      window.repaint
      app.editor.scroll_to 70
      app.editor.cursor_position = at(app, 81)
      window.repaint
      editor_row = app.editor.cursor_row - app.editor.scroll_position
      editor_row.should be > 2
      (app.viewer.cursor_row - app.viewer.scroll_position).should eq editor_row

      # And the other way round.
      app.viewer.focus
      app.viewer.scroll_to 20
      app.viewer.cursor_position = shown(app, "Paragraph 20")
      window.repaint
      viewer_row = app.viewer.cursor_row - app.viewer.scroll_position
      viewer_row.should be > 2
      (app.editor.cursor_row - app.editor.scroll_position).should eq viewer_row
    end
  end
end

describe "Md::App table of contents" do
  it "jumps both the viewer and the editor to the activated heading, following or not" do
    long = (1..40).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n\n## Late heading\n\n" +
           (1..40).map { |i| "After #{i}" }.join("\n\n") + "\n"
    with_app Md::Source.new, text: long, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.show_pane(Md::App::Pane::Toc).focus
      window.repaint
      app.follow_cursor?.should be_false
      app.toc.nodes.map(&.text).should eq ["Late heading"]
      app.toc.current_index = 0
      app.toc.activate_current
      app.viewer.cursor_position.should eq shown(app, "Late heading")
      app.editor.cursor_position.should eq at(app, 81)
      window.repaint
      # The heading tops both panes' viewports, as a browser lands a fragment.
      (app.viewer.cursor_row - app.viewer.scroll_position).should eq 0
      (app.editor.cursor_row - app.editor.scroll_position).should eq 0
      window.dump.to_s.should contain "## Late heading"

      # The jump moved the viewer's caret like any other move: a caret-line
      # highlight follows it to the heading.
      heading_bg = -> { Crysterm::Attr.bg(window.cell_rows[app.viewer.atop][app.viewer.aleft].attr) }
      plain = heading_bg.call
      app.viewer.cursor_position = 0
      app.highlight_line = true
      app.toc.current_index = 0
      app.toc.activate_current
      window.repaint
      app.viewer.cursor_viewport_row.should eq 0 # the caret, and so the tint, on the heading's row
      heading_bg.call.should_not eq plain
      app.highlight_line = false

      # The same through the viewer's own link activation, with the editor hidden.
      app.hide_pane Md::App::Pane::Editor
      app.editor.cursor_position = 0
      app.jump_to "#late-heading"
      app.editor.cursor_position.should eq 0
    end
  end
end
