require "./spec_helper"
require "file_utils"

# View → Soft Wrap, Text Width and Center Text: the editor's wrap mode, a
# cap on the text's width and the capped column's placement, through
# Crysterm's `wrap_content`, `line_wrap_column` and
# `line_wrap_column_alignment`.

# One paragraph some 270 columns long on one source line, then a short one.
LONG_DOC = (1..40).map { |i| "word#{i}" }.join(" ") + "\n\nshort\n"

# The row *row* of *pane*, as painted.
private def pane_row(window, pane, row)
  cells = window.cell_rows[pane.atop + row]
  String.build { |io| (pane.aleft...pane.aleft + pane.awidth).each { |x| io << cells[x].char } }
end

describe "Md::App text layout" do
  it "soft wraps the editor by default and lets long lines run off when turned off" do
    with_app Md::Source.new, text: LONG_DOC, view: false do |app, window|
      app.soft_wrap?.should be_true
      app.editor.wrap_content?.should be_true
      window.repaint
      end_of_line = app.editor.document.block_position(1) - 1
      app.editor.cursor_position = end_of_line
      window.repaint
      app.editor.cursor_viewport_row.should be > 0 # folded over several rows
      app.editor.show_horizontal_scrollbar?.should be_false

      wrap = menu(app, 3).actions.find!(&.text.==("&Soft Wrap"))
      wrap.text.should eq "&Soft Wrap"
      wrap.checked?.should be_true
      wrap.shortcut_text.should eq "Alt+W"
      wrap.trigger
      app.soft_wrap?.should be_false
      app.editor.wrap_content?.should be_false
      window.repaint
      app.editor.cursor_viewport_row.should eq 0 # one row, scrolled sideways
      app.editor.show_horizontal_scrollbar?.should be_true
      pane_row(window, app.editor, 2).strip.should eq "short"

      app.soft_wrap = true
      wrap.checked?.should be_true
      app.editor.wrap_content?.should be_true
    end
  end

  it "caps the viewer's text at the chosen width, centered, from the View menu" do
    with_app Md::Source.new(path: "doc.md"), text: LONG_DOC, view: true do |app, window|
      app.text_width.should eq 0
      app.center_text?.should be_true
      window.repaint
      pane_row(window, app.viewer, 0).rstrip.size.should be > 90

      widths = menu(app, 3).actions.find!(&.text.==("Te&xt Width"))
      widths.text.should eq "Te&xt Width"
      entries = widths.menu.should_not be_nil
      entries.map(&.text).should eq ["&Unlimited", "&72 Columns", "&80 Columns", "&100 Columns", "1&20 Columns"]
      entries[0].checked?.should be_true
      entries[1].trigger
      app.text_width.should eq 72
      entries[1].checked?.should be_true
      entries[0].checked?.should be_false
      app.viewer.line_wrap_column.should eq 72
      app.editor.line_wrap_column.should eq 72
      app.viewer.line_wrap_column_alignment.should eq Tput::AlignFlag::HCenter

      app.text_width = 40
      window.repaint
      # 99 text columns (one is the caret's), 40 of text: 29 blank on the
      # left, then the text, no row wider than the cap.
      app.viewer.ileft.should eq 29
      row = pane_row(window, app.viewer, 0)
      row[0, 29].strip.should be_empty
      row[29].should eq 'w'
      row[29, 40].rstrip.size.should be <= 40
      row[69..].strip.should be_empty
      pane_row(window, app.viewer, 1)[29].should eq 'w'
      app.viewer.position_at(app.viewer.aleft + 29, app.viewer.atop).should eq 0

      center = menu(app, 3).actions.find!(&.text.==("&Center Text"))
      center.text.should eq "&Center Text"
      center.checked?.should be_true
      center.trigger
      app.center_text?.should be_false
      app.viewer.line_wrap_column_alignment.should eq Tput::AlignFlag::Left
      window.repaint
      app.viewer.ileft.should eq 0
      pane_row(window, app.viewer, 0)[0].should eq 'w'
      pane_row(window, app.viewer, 0)[40..].strip.should be_empty

      app.text_width = 0
      window.repaint
      pane_row(window, app.viewer, 0).rstrip.size.should be > 90
    end
  end

  it "keeps the panes aligned under Sync Cursor with a text width set" do
    with_app Md::Source.new, text: LONG_DOC, view: false do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.focus
      app.sync_cursor = true
      app.text_width = 40
      window.repaint
      app.editor.cursor_position = app.editor.document.block_position(2)
      window.repaint
      app.viewer.cursor_viewport_row.should eq app.editor.cursor_viewport_row
      pane_row(window, app.viewer, app.viewer.cursor_viewport_row).strip.should eq "short"
    end
  end

  it "keeps the three choices across runs" do
    dir = File.tempname("md-spec-wrap-settings")
    Dir.mkdir_p dir
    path = File.join(dir, "settings.json")
    begin
      File.write path, <<-JSON
        {"version": 1, "settings": {"soft_wrap": false, "text_width": 80, "center_text": false}}
        JSON
      settings = Md::Settings.load(path)
      with_app Md::Source.new(path: "doc.md"), text: LONG_DOC, view: true, settings: settings do |app|
        app.soft_wrap?.should be_false
        app.editor.wrap_content?.should be_false
        app.text_width.should eq 80
        app.center_text?.should be_false
        app.viewer.line_wrap_column.should eq 80
        app.viewer.line_wrap_column_alignment.should eq Tput::AlignFlag::Left
        settings.dirty?.should be_false

        app.text_width = 100
        app.center_text = true
        settings.dirty?.should be_true
        app.save_settings
      end

      reloaded = Md::Settings.load(path)
      reloaded.soft_wrap?.should be_false
      reloaded.text_width.should eq 100
      reloaded.center_text?.should be_true
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "has the panes' own defaults without a store" do
    with_app settings: Md::Settings.new("unused.json") do |app|
      app.soft_wrap?.should be_true
      app.text_width.should eq 0
      app.center_text?.should be_true
      app.settings.try(&.dirty?).should be_false
    end
  end
end
