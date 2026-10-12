require "./spec_helper"

# View → Line Numbers → Editor and Viewer: Crysterm's line-number gutter
# (`AbstractScrollArea#line_numbers`) on each pane on its own — the editor's
# numbering the source lines, the viewer's the rendered rows from 1, apart
# from the source; kept across runs.

# A paragraph that wraps in the viewer, then a short one.
LN_DOC = (1..30).map { |i| "word#{i}" }.join(" ") + "\n\nshort\n"

# The row *row* of *pane*, as painted.
private def pane_row(window, pane, row)
  cells = window.cell_rows[pane.atop + row]
  String.build { |io| (pane.aleft...pane.aleft + pane.awidth).each { |x| io << cells[x].char } }
end

describe "Md::App line numbers" do
  it "is a View submenu, an entry for each pane, the viewer's numbering the rendered rows" do
    with_app Md::Source.new(path: "doc.md"), text: LN_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.line_numbers?.should be_false
      app.viewer_line_numbers?.should be_false
      editor_entry, viewer_entry = menu(app, 3).actions.find!(&.text.==("Line &Numbers")).menu || fail("Line Numbers has no submenu")
      editor_entry.text.should eq "&Editor"
      viewer_entry.text.should eq "&Viewer"

      viewer_entry.trigger
      app.viewer_line_numbers?.should be_true
      viewer_entry.checked?.should be_true
      app.viewer.line_numbers?.should be_true
      app.editor.line_numbers?.should be_false
      window.repaint
      # The paragraph wraps over several rows, each numbered; the blank row
      # after it too, then "short" — the rendered rows, not the source's
      # line 3.
      rows = (0...app.viewer.aheight).map { |row| pane_row(window, app.viewer, row) }
      rows[0][0, 5].should eq " 1 wo"
      rows[1][0, 2].should eq " 2"
      short = rows.index!(&.includes?("short"))
      short.should be > 2
      rows[short][0, 8].should eq "#{(short + 1).to_s.rjust(2)} short"
      pane_row(window, app.editor, 0)[0, 2].should eq "wo"

      editor_entry.trigger
      app.editor.line_numbers?.should be_true
      window.repaint
      pane_row(window, app.editor, 0)[0, 5].should eq " 1 wo"

      app.run_command("viewer-line-numbers").should be_true
      app.viewer_line_numbers?.should be_false
      app.viewer.line_numbers?.should be_false
      app.editor.line_numbers?.should be_true
      window.repaint
      pane_row(window, app.viewer, 0)[0, 2].should eq "wo"
    end
  end

  it "keeps the viewer's choice across runs, off by default" do
    with_config "md:\n  viewer_line_numbers: true\n" do |path|
      with_app Md::Source.new(path: "doc.md"), text: LN_DOC, view: true, config: true do |app, _window|
        app.viewer_line_numbers?.should be_true
        app.viewer.line_numbers?.should be_true
        app.editor.line_numbers?.should be_false
        app.viewer.line_numbers = false
        app.viewer_line_numbers?.should be_false
        app.save_config
      end
      config_file(path)["md"]["viewer_line_numbers"].as_bool.should be_false
    end
  end
end
