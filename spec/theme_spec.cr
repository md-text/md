require "./spec_helper"
require "file_utils"

# A headless window: in-memory IO, fixed size, no terminal involved. Its
# creation installs Crysterm's config theme (`terminal`, with nothing probed
# here); the theme is one global for every window, so each spec puts back
# the one it found.
private def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

private def with_app(settings = nil, &)
  window = headless_window
  saved = Crysterm::CSS.theme
  begin
    yield Md::App.new(Md::Source.new(path: "doc.md"), text: "# Title\n\nSome text.\n", view: true, window: window, settings: settings), window
  ensure
    Crysterm::CSS.theme = saved
    window.destroy
  end
end

# The Options → Theme entries.
private def theme_entries(app) : Array(Crysterm::Action)
  options = app.main.menu_bar.menus[4]
  submenu = options.actions.find! { |action| action.text == "&Theme" }
  submenu.menu || [] of Crysterm::Action
end

# The background the viewer's first cell is painted with.
private def viewer_bg(app, window) : Int32
  window.repaint
  cell = window.cell_rows[app.viewer.atop][app.viewer.aleft]
  Crysterm::Attr.unpack_color(Crysterm::Attr.bg(cell.attr))
end

describe "Md::App theme" do
  it "offers Crysterm's built-in themes in the Options menu, the current one checked" do
    with_app do |app|
      app.theme.should eq Md::App::Theme::Terminal
      entries = theme_entries(app)
      entries.map(&.text).should eq ["&Terminal (its own colors)", "&Dark", "&Light"]
      entries.map(&.checked?).should eq [true, false, false]
      entries[1].trigger
      app.theme.should eq Md::App::Theme::Dark
      Crysterm::CSS.theme.try(&.name).should eq "dark"
      entries.map(&.checked?).should eq [false, true, false]
      entries[1].trigger # re-picking the checked theme keeps it
      entries.map(&.checked?).should eq [false, true, false]
    end
  end

  it "repaints the window in the picked theme" do
    with_app do |app, window|
      theme_entries(app)[1].trigger
      dark = viewer_bg(app, window)
      dark.should eq Crysterm::CSS::Theme.dark.primaries["surface"]
      theme_entries(app)[2].trigger
      light = viewer_bg(app, window)
      light.should eq Crysterm::CSS::Theme.light.primaries["surface"]
      Crysterm::Colors.luminance(dark).should be < Crysterm::Colors.luminance(light)
    end
  end

  it "keeps an author stylesheet over whichever theme is picked" do
    with_app do |app, window|
      window.stylesheet = "TextBrowser { background-color: #123456; }"
      viewer_bg(app, window).should eq 0x123456
      theme_entries(app)[1].trigger
      viewer_bg(app, window).should eq 0x123456
      Crysterm::CSS.theme.try(&.name).should eq "dark"
    end
  end

  it "cycles the themes from the keyboard" do
    with_app do |app|
      app.cycle_theme.should eq Md::App::Theme::Dark
      app.cycle_theme.should eq Md::App::Theme::Light
      app.cycle_theme.should eq Md::App::Theme::Terminal
      Crysterm::CSS.theme.try(&.name).should eq "terminal"
    end
  end

  it "restores the stored theme at start and records the picked one" do
    dir = File.tempname("md-spec-theme")
    Dir.mkdir_p dir
    path = File.join(dir, "settings.json")
    begin
      File.write path, %({"version": 1, "settings": {"theme": "light"}})
      settings = Md::Settings.load(path)
      with_app settings do |app, window|
        app.theme.should eq Md::App::Theme::Light
        Crysterm::CSS.theme.try(&.name).should eq "light"
        theme_entries(app).map(&.checked?).should eq [false, false, true]
        viewer_bg(app, window).should eq Crysterm::CSS::Theme.light.primaries["surface"]
        settings.dirty?.should be_false # applying is not a change

        theme_entries(app)[1].trigger
        settings.dirty?.should be_true
        app.save_settings
      end
      Md::Settings.load(path).theme.should eq Md::App::Theme::Dark
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "lets --colors-theme win for the run without recording it" do
    Crysterm::Config.colors_theme = Md::App::Theme::Dark
    settings = Md::Settings.new("unused.json", {"theme" => JSON::Any.new("light")})
    with_app settings do |app|
      app.theme.should eq Md::App::Theme::Dark
      settings.dirty?.should be_false
      theme_entries(app).map(&.checked?).should eq [false, true, false]

      theme_entries(app)[2].trigger # a pick from the menu is recorded as ever
      settings.theme.should eq Md::App::Theme::Light
    end
  ensure
    Crysterm::Config.colors_theme = Md::App::Theme::Terminal
  end
end
