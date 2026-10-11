require "./spec_helper"

# View → Highlight Line: Crysterm's `highlight_current_line` on both panes,
# tinting the caret's row as it moves.

# Background of the cell at the top-left of *pane*'s row *row*.
private def row_bg(window, pane, row)
  Crysterm::Attr.bg(window.cell_rows[pane.atop + row][pane.aleft].attr)
end

HL_DOC = (1..5).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"

describe "Md::App highlight line" do
  it "tints the caret's row in a pane, following the caret, from the View menu" do
    with_app Md::Source.new, text: HL_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      window.repaint
      plain = row_bg(window, app.editor, 0)
      row_bg(window, app.editor, 2).should eq plain

      highlight = menu(app, 3).actions[7]
      highlight.text.should eq "&Highlight Line"
      highlight.checked?.should be_false
      highlight.trigger
      app.highlight_line?.should be_true
      app.editor.highlight_current_line?.should be_true
      app.viewer.highlight_current_line?.should be_true
      app.editor.extra_selections.should be_empty

      app.editor.cursor_position = app.editor.document.block_position(2) # third line
      window.repaint
      row_bg(window, app.editor, 2).should_not eq plain
      row_bg(window, app.editor, 0).should eq plain
      Crysterm::Attr.bg(window.cell_rows[app.editor.atop + 2][app.editor.aleft + app.editor.awidth - 2].attr).should eq row_bg(window, app.editor, 2)

      app.editor.cursor_position = 0
      window.repaint
      row_bg(window, app.editor, 2).should eq plain
      row_bg(window, app.editor, 0).should_not eq plain

      app.highlight_line = false
      highlight.checked?.should be_false
      app.editor.highlight_current_line?.should be_false
      app.viewer.highlight_current_line?.should be_false
      window.repaint
      row_bg(window, app.editor, 0).should eq plain
    end
  end

  it "shows the same place tinted in both panes with Sync Cursor" do
    with_app Md::Source.new, text: HL_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.sync_cursor = true
      app.highlight_line = true
      window.repaint
      viewer_plain = row_bg(window, app.viewer, 1)
      app.editor.cursor_position = app.editor.document.block_position(4) # "Paragraph 3"
      window.repaint
      editor_row = app.editor.cursor_row - app.editor.scroll_position
      viewer_row = app.viewer.cursor_row - app.viewer.scroll_position
      viewer_row.should eq editor_row
      row_bg(window, app.viewer, viewer_row).should_not eq viewer_plain
      row_bg(window, app.viewer, viewer_row + 1).should eq viewer_plain
      window.cell_rows[app.viewer.atop + viewer_row][app.viewer.aleft].char.should eq 'P'
    end
  end
end
