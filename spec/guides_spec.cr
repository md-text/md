require "./spec_helper"
require "file_utils"

# View → Guides: vertical guide lines at the text's edges on the editor and
# the viewer, through Crysterm's `AbstractScrollArea#guides_enabled`, and
# more pulled off the column ruler with the mouse; kept across runs.

# One paragraph some 270 columns long on one source line, then a short one.
GUIDES_DOC = (1..40).map { |i| "word#{i}" }.join(" ") + "\n\nshort\n"

# The row *row* of *pane*, as painted.
private def pane_row(window, pane, row)
  cells = window.cell_rows[pane.atop + row]
  String.build { |io| (pane.aleft...pane.aleft + pane.awidth).each { |x| io << cells[x].char } }
end

# A mouse report at the window's (*x*, *y*), as the terminal delivers it.
private def mouse(window, action : Tput::Mouse::Action, x, y, button = Tput::Mouse::Button::Left)
  window.dispatch_mouse Tput::Mouse::Event.new(action, button, x, y, source: :test)
end

describe "Md::App guides" do
  it "is off by default, and the View entry shows them on both panes" do
    with_app Md::Source.new(path: "doc.md"), text: GUIDES_DOC, view: true do |app|
      app.guides?.should be_false
      app.editor.guides_enabled?.should be_false
      app.viewer.guides_enabled?.should be_false

      entry = menu(app, 3).actions.find!(&.text.==("&Guides"))
      entry.checked?.should be_false
      entry.trigger
      app.guides?.should be_true
      entry.checked?.should be_true
      app.editor.guides_enabled?.should be_true
      app.viewer.guides_enabled?.should be_true

      app.guides = false
      entry.checked?.should be_false
      app.viewer.guides_enabled?.should be_false
    end
  end

  it "marks the capped column's edges in a wider pane, in blank cells only" do
    with_app Md::Source.new(path: "doc.md"), text: GUIDES_DOC, view: true do |app, window|
      app.guides = true
      app.text_width = 40
      window.repaint
      # 99 text columns, 40 of text centered: 29 blank on the left, so the
      # guides sit at columns 28 and 69, beside the text.
      app.viewer.ileft.should eq 29
      app.viewer.text_column_bounds.should eq({0, 41})
      row = pane_row(window, app.viewer, 0)
      row[28].should eq '│'
      row[29].should eq 'w'
      row[69].should eq '│'
      row[30..68].should_not contain '│'
      # The short line's row, and a blank row, carry the guides too.
      short = (0...app.viewer.aheight).find! { |index| pane_row(window, app.viewer, index).includes?("short") }
      pane_row(window, app.viewer, short)[28].should eq '│'
      pane_row(window, app.viewer, short)[69].should eq '│'
      pane_row(window, app.viewer, short + 1)[28].should eq '│'
      app.guides = false
      window.repaint
      pane_row(window, app.viewer, 0)[28].should eq ' '
    end
  end

  it "pulls a guide off the editor's ruler with the mouse" do
    with_app Md::Source.new, text: GUIDES_DOC, view: false do |app, window|
      app.rulers = true
      app.guides = true
      app.editor.focus
      app.editor.cursor_position = 0
      window.repaint
      editor = app.editor
      ruler_y = editor.atop
      text_x = editor.aleft + editor.ileft
      # Pressed on the ruler at column 10, dragged three rows down.
      mouse window, Tput::Mouse::Action::Down, text_x + 9, ruler_y
      mouse window, Tput::Mouse::Action::Move, text_x + 9, ruler_y + 3
      mouse window, Tput::Mouse::Action::Up, text_x + 9, ruler_y + 3, Tput::Mouse::Button::None
      editor.guides.should eq [10]
      editor.cursor_position.should eq 0
      window.repaint
      pane_row(window, editor, 0)[editor.ileft + 9].should eq '┬'
      # Dropped back on the ruler, it is gone; the edge guides stay.
      mouse window, Tput::Mouse::Action::Down, text_x + 9, ruler_y
      mouse window, Tput::Mouse::Action::Move, text_x + 20, ruler_y
      mouse window, Tput::Mouse::Action::Up, text_x + 20, ruler_y, Tput::Mouse::Button::None
      editor.guides.should be_empty
      editor.guide_columns.size.should eq 2
    end
  end

  it "sets the text width to the last guide of the focused pane from Format → Text Width" do
    with_app Md::Source.new(path: "doc.md"), text: GUIDES_DOC, view: true do |app|
      entry = (menu(app, 2).actions.find!(&.text.==("Te&xt Width")).menu || fail("Text Width has no submenu")).last
      entry.text.should eq "To &Last Guide"
      app.viewer.focus
      entry.trigger
      app.text_width.should eq 0
      notice(app).should contain "Guides are hidden"
      app.guides = true
      entry.trigger
      app.text_width.should eq 0
      notice(app).should contain "No guide"
      app.viewer.add_guide 30
      app.viewer.add_guide 52
      app.editor.add_guide 40
      app.text_width_to_last_guide.should be_true
      app.text_width.should eq 51 # ending just left of the viewer's rightmost
      app.viewer.line_wrap_column.should eq 51
      app.show_pane(Md::App::Pane::Editor).focus
      entry.trigger
      app.text_width.should eq 39 # the editor's, while editing
      app.editor.guides = [1]
      app.text_width_to_last_guide.should be_false
      notice(app).should contain "No room for text"
    end
  end

  it "keeps the choice across runs" do
    with_config "md:\n  guides: true\n" do |path|
      with_app Md::Source.new(path: "doc.md"), text: GUIDES_DOC, view: true, config: true do |app|
        app.guides?.should be_true
        app.editor.guides_enabled?.should be_true
        app.viewer.guides_enabled?.should be_true
        Md::Config.dirty?.should be_false
        app.guides = false
        Md::Config.dirty?.should be_true
        app.save_config
      end
      config_file(path)["md"]["guides"].as_bool.should be_false
    end
  end
end
