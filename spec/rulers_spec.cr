require "./spec_helper"
require "file_utils"

# View → Rulers: a column ruler along the top row of the editor and the
# viewer and a row ruler down their left, through Crysterm's
# `AbstractScrollArea#rulers`; kept across runs.

# One paragraph some 270 columns long on one source line, then a short one.
RULERS_DOC = (1..40).map { |i| "word#{i}" }.join(" ") + "\n\nshort\n"

# The row *row* of *pane*, as painted.
private def pane_row(window, pane, row)
  cells = window.cell_rows[pane.atop + row]
  String.build { |io| (pane.aleft...pane.aleft + pane.awidth).each { |x| io << cells[x].char } }
end

describe "Md::App rulers" do
  it "is off by default, and the View entry shows them on both panes" do
    with_app Md::Source.new(path: "doc.md"), text: RULERS_DOC, view: true do |app, window|
      app.rulers?.should be_false
      app.editor.rulers?.should be_false
      app.viewer.rulers?.should be_false
      window.repaint
      pane_row(window, app.viewer, 0)[0].should eq 'w'

      entry = menu(app, 3).actions.find!(&.text.==("R&ulers"))
      entry.checked?.should be_false
      entry.trigger
      app.rulers?.should be_true
      entry.checked?.should be_true
      app.editor.rulers?.should be_true
      app.viewer.rulers?.should be_true
      window.repaint
      # The column ruler's tape on the pane's top row, the row ruler before
      # the first text row, the text below and right of them.
      pane_row(window, app.viewer, 0)[0, 20].should eq "  ────┼───10────┼───"
      pane_row(window, app.viewer, 1)[0, 3].should eq " │w"
      app.viewer.ileft.should eq 2
      app.viewer.itop.should eq 1

      app.rulers = false
      entry.checked?.should be_false
      app.viewer.rulers?.should be_false
      window.repaint
      pane_row(window, app.viewer, 0)[0].should eq 'w'
    end
  end

  it "counts the text's columns, and sits outside the editor's line-number gutter" do
    with_app Md::Source.new, text: RULERS_DOC, view: false do |app, window|
      app.rulers = true
      app.editor.line_numbers = true
      window.repaint
      pane_row(window, app.editor, 1)[0, 6].should eq " │ 1 w"
      pane_row(window, app.editor, 0)[0, 10].should eq "     ────┼"
      app.show_pane Md::App::Pane::Viewer
      app.text_width = 40
      window.repaint
      # The viewer's tape starts where its centered text does.
      left = app.viewer.ileft
      left.should be > 2
      pane_row(window, app.viewer, 0)[left - 1].should eq ' '
      pane_row(window, app.viewer, 0)[left, 10].should eq "────┼───10"
      pane_row(window, app.viewer, 1)[left].should eq 'w'
    end
  end

  it "keeps the choice across runs" do
    with_config "md:\n  rulers: true\n" do |path|
      with_app Md::Source.new(path: "doc.md"), text: RULERS_DOC, view: true, config: true do |app|
        app.rulers?.should be_true
        app.editor.rulers?.should be_true
        app.viewer.rulers?.should be_true
        Md::Config.dirty?.should be_false
        app.rulers = false
        Md::Config.dirty?.should be_true
        app.save_config
      end
      config_file(path)["md"]["rulers"].as_bool.should be_false
    end
  end

  it "has the panes' own default without a config file" do
    with_config do
      with_app config: true do |app|
        app.rulers?.should be_false
        Md::Config.dirty?.should be_false
      end
    end
  end
end
