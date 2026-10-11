require "./spec_helper"
require "file_utils"

# The panes in their splitter (`app_panes.cr`): dividers between the shown
# panes, resizing by divider and by key, and the sizes kept in the settings.

private def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

private def with_app(source = Md::Source.new, text = "", view = !text.empty?, settings = nil, &)
  window = headless_window
  begin
    yield Md::App.new(source, text: text, view: view, window: window, settings: settings), window
  ensure
    window.destroy
  end
end

private def key(window, key : Tput::Key)
  window.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', key)
end

private def show_all(app)
  app.show_pane Md::App::Pane::Editor
  app.show_pane Md::App::Pane::Viewer
  app.show_pane Md::App::Pane::Toc
end

PANES_DOC = "# Title\n\nSome text.\n\n## Section\n\nMore.\n"

describe "Md::App panes" do
  it "lays the shown panes out in a splitter, the editor and viewer sharing the width beside the outline" do
    with_app text: PANES_DOC do |app, window|
      show_all app
      window.repaint
      splitter = app.splitter
      splitter.panes.should eq [app.editor, app.viewer, app.toc]
      splitter.dividers.size.should eq 2
      splitter.dividers.map(&.visible?).should eq [true, true]
      splitter.sizes.should eq [34, 34, Md::App::TOC_WIDTH]
      app.editor.width.should eq 34
      app.toc.width.should eq Md::App::TOC_WIDTH
      splitter.dividers.map(&.aleft).should eq [34, 69] # drawn between the panes
      app.viewer.aleft.should eq 35
      app.toc.aleft.should eq 70
    end
  end

  it "hides a hidden pane's divider and gives its width to the others" do
    with_app text: PANES_DOC do |app, window|
      show_all app
      app.hide_pane Md::App::Pane::Toc
      app.splitter.sizes.should eq [49, 50, 0]
      app.splitter.dividers.map(&.visible?).should eq [true, false]
      window.repaint
      app.viewer.width.should eq 50
      app.splitter.dividers[0].aleft.should eq 49
      app.viewer.aleft.should eq 50

      app.hide_pane Md::App::Pane::Viewer
      app.splitter.sizes.should eq [100, 0, 0]
      app.splitter.dividers.map(&.visible?).should eq [false, false]

      app.show_pane Md::App::Pane::Toc # back at its width
      app.splitter.sizes.should eq [69, 0, Md::App::TOC_WIDTH]
      app.splitter.dividers.map(&.visible?).should eq [true, false]
    end
  end

  it "resizes by moving a divider, and keeps the proportions when the terminal changes size" do
    with_app text: PANES_DOC do |app, window|
      show_all app
      app.splitter.dividers[0].position = 20
      app.splitter.sizes.should eq [20, 48, Md::App::TOC_WIDTH]
      app.splitter.dividers[1].position = 80
      app.splitter.sizes.should eq [20, 59, 19]
      app.pane_sizes.should eq [20, 59, 19]

      window.width = 160
      window.repaint
      app.splitter.sizes.should eq [35, 104, 19] # the outline keeps its cells
      app.pane_sizes.should eq [20, 59, 19]
    end
  end

  it "moves a divider from the keyboard through View → Resize panes" do
    with_app text: PANES_DOC do |app, window|
      show_all app
      app.editor.focus
      resize = menu_actions(app)[3]
      resize.text.should eq "&Resize panes"
      resize.shortcut_text.should eq "Alt+R"
      resize.trigger
      divider = app.splitter.dividers[0]
      divider.focused?.should be_true
      divider.position.should eq 34
      divider.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Right)
      divider.position.should eq 35
      app.splitter.sizes.should eq [35, 33, Md::App::TOC_WIDTH]
      divider.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Left)
      app.splitter.sizes.should eq [34, 34, Md::App::TOC_WIDTH]

      key window, Tput::Key::Escape # back to the pane at the divider's left
      app.editor.focused?.should be_true

      # From the last pane, the divider at its left; Enter returns too.
      app.toc.focus
      app.resize_panes
      app.splitter.dividers[1].focused?.should be_true
      key window, Tput::Key::Enter
      app.viewer.focused?.should be_true

      # Tab cycles the panes, never the dividers.
      app.editor.focus
      window.focus_next
      app.viewer.focused?.should be_true

      # One pane shown: nothing to resize.
      app.hide_pane Md::App::Pane::Toc
      app.hide_pane Md::App::Pane::Editor
      app.resize_panes
      app.viewer.focused?.should be_true
    end
  end

  it "keeps the pane sizes in the settings and restores them" do
    dir = File.tempname("md-spec-panes")
    Dir.mkdir_p dir
    path = File.join(dir, "settings.json")
    begin
      File.write path, %({"version": 1, "settings": {"pane_sizes": [20, 40, 25]}})
      settings = Md::Settings.load(path)
      with_app text: PANES_DOC, settings: settings do |app|
        show_all app
        app.pane_sizes.should eq [20, 40, 25]
        app.splitter.sizes.should eq [24, 49, 25] # the same proportions, the outline as set
        settings.dirty?.should be_false
        app.splitter.dividers[0].position = 30
        app.save_settings
        settings.dirty?.should be_false
      end

      reloaded = Md::Settings.load(path)
      reloaded.pane_sizes.should eq [30, 43, 25]
      with_app text: PANES_DOC, settings: reloaded do |app|
        show_all app
        app.splitter.sizes.should eq [30, 43, 25]
      end

      # A value that is not one width per pane is left alone.
      File.write path, %({"version": 1, "settings": {"pane_sizes": [40, 60]}})
      with_app text: PANES_DOC, settings: Md::Settings.load(path) do |app|
        app.pane_sizes.should eq [0, 0, Md::App::TOC_WIDTH]
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end

# The View menu's entries.
private def menu_actions(app)
  app.main.menu_bar.menus[3].actions
end
