require "./spec_helper"

# A menu entry md disables — File → Previous File and Next File with no file
# to go to — driven with the mouse as a terminal reports it: greyed out
# (Crysterm's disabled menu rows), dead to a click, and not left the File
# menu's current entry once the menu is closed.

private def mouse(window, action : Tput::Mouse::Action, x, y, button = Tput::Mouse::Button::Left)
  window.dispatch_mouse Tput::Mouse::Event.new(action, button, x, y, source: :test)
end

# A click at (*x*, *y*): the pointer arrives first, as a terminal reports it.
private def click_at(window, x, y)
  mouse window, Tput::Mouse::Action::Move, x, y, Tput::Mouse::Button::None
  mouse window, Tput::Mouse::Action::Down, x, y
  mouse window, Tput::Mouse::Action::Up, x, y, Tput::Mouse::Button::None
  window.repaint
end

# The row of *menu* whose label, tags left out, starts with *text*.
private def row(menu, text)
  menu.item_boxes.find! { |b| b.content.gsub(/\{[^}]*\}/, "").starts_with? text }
end

private def fg_at(window, x, y)
  Crysterm::Attr.unpack_color Crysterm::Attr.fg(window.cell_rows[y][x].attr)
end

private def bg_at(window, x, y)
  Crysterm::Attr.unpack_color Crysterm::Attr.bg(window.cell_rows[y][x].attr)
end

# Clicks the File menu's title on the bar.
private def click_file(app, window)
  bar = app.main.menu_bar
  click_at window, bar.aleft + 1, bar.atop
end

describe "Md::App disabled menu entries" do
  it "draws File → Previous File and Next File greyed out with no file to go to" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.theme = Md::App::Theme::Dark # the theme is global; the Terminal one draws every row in the default colors
      window.repaint
      click_file app, window
      file = menu(app, 0)
      file.visible?.should be_true
      file.actions.find!(&.text.==("&Previous File")).enabled?.should be_false
      file.actions.find!(&.text.==("&Next File")).enabled?.should be_false
      save = row(file, "Save ")
      enabled = fg_at(window, save.aleft + 1, save.atop)
      {"Previous File", "Next File"}.each do |text|
        box = row(file, text)
        fg_at(window, box.aleft, box.atop).should_not eq enabled # the underlined letter
        fg_at(window, box.aleft + 1, box.atop).should_not eq enabled
      end
    end
  end

  it "opens the File menu again with no entry highlighted after Previous File was clicked to no effect" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      window.repaint
      click_file app, window
      file = menu(app, 0)
      box = row(file, "Previous File")
      plain = bg_at(window, box.aleft + 1, box.atop)
      click_at window, box.aleft + 2, box.atop
      file.visible?.should be_true
      file.selected_action.try(&.text).should eq "&Previous File"
      press window, Tput::Key::Escape
      window.repaint
      file.visible?.should be_false
      click_file app, window
      file.visible?.should be_true
      bg_at(window, box.aleft + 1, box.atop).should eq plain
      file.selected_action.try(&.text).should eq "&Open…"
    end
  end
end
