require "./spec_helper"

# Options → Tooltips: every menu entry's description, shown in the status bar
# while the entry is highlighted (the default), in a popup beside the entry
# after a moment, or nowhere; kept across runs.

# Every non-separator action of *actions* and their submenus, at any depth.
private def walk(actions : Array(Crysterm::Action), into = [] of Crysterm::Action) : Array(Crysterm::Action)
  actions.each do |action|
    next if action.separator?
    into << action
    action.menu.try { |sub| walk sub, into }
  end
  into
end

private def visible_tool_tip(window) : Crysterm::Widget::ToolTip?
  window.children.select(Crysterm::Widget::ToolTip).find(&.visible?)
end

# Opens the View menu with its first entry highlighted, the keyboard way.
private def open_view(app, window)
  app.main.menu_bar.open_menu 3
  window.repaint
  menu(app, 3).select_first_action
  menu(app, 3)
end

describe "Md::App tooltips" do
  it "shows the highlighted entry's description in the status bar by default, and clears it as the highlight leaves" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.tooltips.should eq Md::App::Tooltips::StatusBar
      app.main.status_tips?.should be_true
      view = open_view(app, window)
      first = view.actions.first
      notice(app).should eq first.status_tip
      notice(app).should eq " Show the Markdown source editor, or hide it; F1 shows and focuses it"
      press window, Tput::Key::Down
      notice(app).should eq view.actions[1].status_tip
      press window, Tput::Key::Escape
      view.visible?.should be_false
      notice(app).should eq ""
      window.repaint
      visible_tool_tip(window).should be_nil
    end
  end

  it "derives a setting's description from its option, written once" do
    with_app do |app|
      view = menu(app, 3)
      sync = view.actions.find!(&.text.==("S&ync Cursor"))
      sync.status_tip.should eq " Keep the editor's and the viewer's carets on the same place in the document"
      sync.tool_tip.should eq "Keep the editor's and the viewer's carets on the same place in the document"
      tooltips = menu(app, 4).actions.find!(&.text.==("&Tooltips"))
      tooltips.tool_tip.should eq Crysterm::Config["md.tooltips"].description.split(": ", 2).last.sub(/\A./, &.upcase)
      (tooltips.menu || fail("Tooltips has no submenu")).map(&.text).should eq ["In &Status Bar", "As a &Popup", "&Never"]
    end
  end

  it "gives every entry of every menu and submenu a description" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true, history: Md::History.new(tempfile(nil)) do |app|
      app.main.menu_bar.menus.size.should eq 6
      all = app.main.menu_bar.menus.flat_map { |bar_menu| walk bar_menu.actions }
      all.size.should be > 100
      all.each do |action|
        text = action.tool_tip || fail("#{action.text} has no description")
        text.empty?.should be_false
        text.should_not eq action.text # a tooltip repeating the label is not shown
        action.status_tip.should eq " #{text}"
        action.whats_this.should eq text
      end
    end
  end

  it "pops the description up beside the entry after a moment as a Popup, and hides it as the highlight moves" do
    Crysterm::Config.set "tool_tip.delay", 20.milliseconds
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.tooltips = Md::App::Tooltips::Popup
      app.main.status_tips?.should be_false
      app.main.menu_bar.menus.all?(&.tool_tips_visible?).should be_true
      view = open_view(app, window)
      notice(app).should eq "" # the status bar keeps the document's name
      settle { visible_tool_tip(window) }
      tip = visible_tool_tip(window) || fail("no tooltip is up")
      tip.content.should eq " #{view.actions.first.tool_tip}"
      window.repaint
      (tip.aleft + tip.awidth).should be <= window.awidth # a long one is kept on screen
      press window, Tput::Key::Down
      visible_tool_tip(window).should be_nil
      settle { visible_tool_tip(window) }
      press window, Tput::Key::Escape
      visible_tool_tip(window).should be_nil
      # Beside the row, right of the menu, where it fits (Crysterm places it
      # as it does a submenu).
      app.main.menu_bar.open_menu 1
      window.repaint
      edit = menu(app, 1)
      edit.select_last_action # Previous Heading, a short description
      settle { visible_tool_tip(window) }
      tip = visible_tool_tip(window) || fail("no tooltip is up")
      window.repaint
      lp = edit.lpos || fail("the Edit menu has no position")
      tip.aleft.should be >= lp.xl
      tip.atop.should eq lp.yi + edit.itop + edit.current_index
      app.main.menu_bar.close
      visible_tool_tip(window).should be_nil
      # The submenus, built on each open, inherit the choice.
      app.main.menu_bar.open_menu 4
      window.repaint
      options = menu(app, 4)
      options.select_first_action
      until options.selected_action.try(&.text) == "&Mouse"
        options.handle_key_press Crysterm::Event::KeyPress.new('\0', Tput::Key::Down)
      end
      options.handle_key_press Crysterm::Event::KeyPress.new('\0', Tput::Key::Right)
      (options.@submenu_open || fail("the Mouse submenu did not open")).tool_tips_visible?.should be_true
      settle { visible_tool_tip(window) }
      (visible_tool_tip(window) || fail("no tooltip is up")).content.should eq " The mouse serves md always"
      app.main.menu_bar.close
    end
  ensure
    Crysterm::Config.reset "tool_tip.delay"
  end

  it "shows neither when Never, and F1 still shows the description beside the entry" do
    Crysterm::Config.set "tool_tip.delay", 20.milliseconds
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.tooltips = Md::App::Tooltips::Off
      app.main.status_tips?.should be_false
      app.main.menu_bar.menus.none?(&.tool_tips_visible?).should be_true
      view = open_view(app, window)
      notice(app).should eq ""
      sleep 80.milliseconds
      visible_tool_tip(window).should be_nil
      press(window, Tput::Key::F1).accepted?.should be_true
      (visible_tool_tip(window) || fail("no tooltip is up")).content.should eq " #{view.actions.first.whats_this}"
      press window, Tput::Key::Down
      visible_tool_tip(window).should be_nil
      app.tooltips = Md::App::Tooltips::StatusBar
      notice(app).should eq "" # the bar follows the next highlight, not this one
      press window, Tput::Key::Down
      notice(app).should eq view.actions[2].status_tip
      app.main.menu_bar.close
    end
  ensure
    Crysterm::Config.reset "tool_tip.delay"
  end

  it "starts from the configured choice and keeps a pick with the settings" do
    with_config %(md:\n  tooltips: popup\n) do |path|
      with_app config: true do |app|
        app.tooltips.should eq Md::App::Tooltips::Popup
        app.main.status_tips?.should be_false
        app.main.menu_bar.menus.all?(&.tool_tips_visible?).should be_true
        entries = menu(app, 4).actions.find!(&.text.==("&Tooltips")).menu || fail("Tooltips has no submenu")
        entries.map(&.checked?).should eq [false, true, false]
        entries[2].trigger
        app.tooltips.should eq Md::App::Tooltips::Off
        Crysterm::Config.md_tooltips.should eq Md::App::Tooltips::Off
        app.save_config
      end
      config_file(path)["md"]["tooltips"].as_s.should eq "Off"
    end
  end
end
