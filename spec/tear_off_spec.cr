require "./spec_helper"

# Options → Detachable Menus: Crysterm's tear-off menus (`menu.tear_off`) from
# md's menus — the grab strip on the View menu, a copy torn off it whose
# entries work on md, closed by its mark; the bars going and the window
# closing with a torn-off menu up; kept across runs.

private alias Menu = Crysterm::Widget::Menu

private def handle_of(menu)
  menu.children.select(Menu::TearOffHandle).first?
end

# A mouse report at the window's (*x*, *y*), as the terminal delivers it.
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

# Tears the View menu off by a drag of its strip and returns the copy.
private def tear_off_view(app, window) : Menu
  app.main.menu_bar.open_menu 3
  window.repaint
  handle = handle_of(menu(app, 3)) || fail("the View menu shows no tear-off strip")
  x, y = handle.aleft, handle.atop
  mouse window, Tput::Mouse::Action::Move, x, y, Tput::Mouse::Button::None
  mouse window, Tput::Mouse::Action::Down, x, y
  mouse window, Tput::Mouse::Action::Move, x + 8, y + 4
  mouse window, Tput::Mouse::Action::Up, x + 8, y + 4, Tput::Mouse::Button::None
  window.repaint
  Menu.torn_off_menus(window).first? || fail("no menu was torn off")
end

# Clicks the row of *menu* whose entry is *text*.
private def click_row(window, menu, text)
  i = menu.actions.index! { |a| a.text == text }
  click_at window, menu.aleft + menu.ileft + 1, menu.atop + menu.itop + i
end

describe "Md::App detachable menus" do
  it "toggles the option from the Options entry" do
    with_app do |app|
      entry = menu(app, 4).actions.find!(&.text.==("D&etachable Menus"))
      entry.checked?.should be_false
      app.tear_off_menus?.should be_false
      menu(app, 3).tear_off_enabled?.should be_false
      entry.trigger
      app.tear_off_menus?.should be_true
      Crysterm::Config.menu_tear_off.should be_true
      menu(app, 3).tear_off_enabled?.should be_true
      app.tear_off_menus = false
      entry.checked?.should be_false
      Crysterm::Config.menu_tear_off.should be_false
    end
  ensure
    Crysterm::Config.reset "menu.tear_off"
  end

  it "shows the strip on the View menu, tears a working copy off it, and closes it by its mark" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.main.menu_bar.open_menu 3
      window.repaint
      handle_of(menu(app, 3)).should be_nil
      app.main.menu_bar.close
      app.tear_off_menus = true
      torn = tear_off_view(app, window)
      torn.actions.map(&.text).should eq menu(app, 3).actions.map(&.text)
      menu(app, 3).visible?.should be_false # the chain went down as on a leaf activation
      app.main.menu_bar.open_index.should be_nil

      app.sync_cursor?.should be_false
      click_row window, torn, "S&ync Cursor"
      app.sync_cursor?.should be_true
      torn.actions.find!(&.text.==("S&ync Cursor")).checked?.should be_true
      menu(app, 3).actions.find!(&.text.==("S&ync Cursor")).checked?.should be_true # the same action
      torn.visible?.should be_true
      click_row window, torn, "S&ync Cursor"
      app.sync_cursor?.should be_false

      close = torn.children.find { |child| child.content == "⊠" } || fail("the torn-off menu shows no close mark")
      click_at window, close.aleft, close.atop
      Menu.torn_off_menus(window).should be_empty
    end
  ensure
    Crysterm::Config.reset "menu.tear_off"
  end

  it "survives the bars going and the window closing with a torn-off menu up" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.tear_off_menus = true
      torn = tear_off_view(app, window)
      press(window, Tput::Key::F4).accepted?.should be_true
      app.bars?.should be_false
      window.repaint
      torn.visible?.should be_true
      press(window, Tput::Key::F4)
      window.repaint
      Menu.torn_off_menus(window).should eq [torn]
      window.destroy
    end
  ensure
    Crysterm::Config.reset "menu.tear_off"
  end

  it "keeps the choice across runs" do
    with_config "menu:\n  tear_off: true\n" do |path|
      with_app config: true do |app|
        app.tear_off_menus?.should be_true
        menu(app, 3).tear_off_enabled?.should be_true
        Md::Config.dirty?.should be_false
        app.tear_off_menus = false
        Md::Config.dirty?.should be_true
        app.save_config
      end
      config_file(path)["menu"]["tear_off"].as_bool.should be_false
    end
  end
end
