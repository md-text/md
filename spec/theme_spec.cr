require "./spec_helper"
require "file_utils"

# An App on a document the viewer shows, so a pane's background is on
# screen to read; the theme is one global for every window (creating one
# installs Crysterm's config theme), so each spec puts back the one it
# found.
private def with_theme_app(settings = nil, &)
  saved = Crysterm::CSS.theme
  with_app Md::Source.new(path: "doc.md"), text: "# Title\n\nSome text.\n", view: true, settings: settings do |app, window|
    yield app, window
  end
ensure
  Crysterm::CSS.theme = saved
end

# The View → Theme entries.
private def theme_entries(app) : Array(Crysterm::Action)
  view = app.main.menu_bar.menus[3]
  submenu = view.actions.find! { |action| action.text == "The&me" }
  submenu.menu || [] of Crysterm::Action
end

# The entries' checks with only the one at *index* set.
private def checked_at(index : Int32) : Array(Bool)
  Md::App::THEMES.map_with_index { |_, i| i == index }
end

# The background the viewer's first cell is painted with.
private def viewer_bg(app, window) : Int32
  window.repaint
  cell = window.cell_rows[app.viewer.atop][app.viewer.aleft]
  Crysterm::Attr.unpack_color(Crysterm::Attr.bg(cell.attr))
end

# The background a cell inside the editor's text is painted with.
private def editor_bg(app, window) : Int32
  window.repaint
  cell = window.cell_rows[app.editor.atop + 1][app.editor.aleft + 2]
  Crysterm::Attr.unpack_color(Crysterm::Attr.bg(cell.attr))
end

describe "Md::App theme" do
  it "offers Crysterm's built-in themes in the View menu, the current one checked" do
    with_theme_app do |app|
      app.theme.should eq Md::App::Theme::Terminal
      entries = theme_entries(app)
      entries.map(&.text).should eq [
        "&Terminal (Its Own Colors)", "&Dark", "&Light",
        "&Breeze Dark", "Breeze L&ight", "&QDarkStyle Dark", "QDarkStyle Li&ght", "Qt &Modern Dark",
      ]
      entries.map(&.checked?).should eq checked_at(0)
      entries[1].trigger
      app.theme.should eq Md::App::Theme::Dark
      Crysterm::CSS.theme.try(&.name).should eq "dark"
      entries.map(&.checked?).should eq checked_at(1)
      entries[1].trigger # re-picking the checked theme keeps it
      entries.map(&.checked?).should eq checked_at(1)
    end
  end

  it "repaints the window in the picked theme" do
    with_theme_app do |app, window|
      theme_entries(app)[1].trigger
      dark = viewer_bg(app, window)
      dark.should eq Crysterm::CSS::Theme.dark.primaries["surface"]
      theme_entries(app)[2].trigger
      light = viewer_bg(app, window)
      light.should eq Crysterm::CSS::Theme.light.primaries["surface"]
      Crysterm::Colors.luminance(dark).should be < Crysterm::Colors.luminance(light)
    end
  end

  it "repaints the window in a Qt theme's colors, from the sheet embedded in Crysterm" do
    with_theme_app do |app, window|
      theme_entries(app)[3].trigger
      app.theme.should eq Md::App::Theme::BreezeDark
      Crysterm::CSS.theme.try(&.name).should eq "breeze-dark"
      viewer_bg(app, window).should eq 0x1d2023 # Breeze's QTextEdit background
      editor_bg(app, window).should eq 0x1d2023 # and its QPlainTextEdit's
      theme_entries(app)[4].trigger
      Crysterm::CSS.theme.try(&.name).should eq "breeze-light"
      Crysterm::Colors.luminance(viewer_bg(app, window)).should be > 0.5
      theme_entries(app).map(&.checked?).should eq checked_at(4)
    end
  end

  it "keeps an author stylesheet over whichever theme is picked" do
    with_theme_app do |app, window|
      window.stylesheet = "TextBrowser { background-color: #123456; }"
      viewer_bg(app, window).should eq 0x123456
      theme_entries(app)[1].trigger
      viewer_bg(app, window).should eq 0x123456
      Crysterm::CSS.theme.try(&.name).should eq "dark"
      theme_entries(app)[5].trigger
      viewer_bg(app, window).should eq 0x123456
      Crysterm::CSS.theme.try(&.name).should eq "qdarkstyle-dark"
    end
  end

  it "paints the editor the same whether or not it has the focus" do
    # An editor that changed shade with the focus read as dimmed whenever
    # the user worked in the viewer or the table of contents, which keep
    # theirs; the theme keeps a multi-line editor one color, as Qt keeps a
    # QPlainTextEdit's base color (its spec is Crysterm's).
    with_theme_app do |app, window|
      app.show_pane(Md::App::Pane::Editor).focus
      app.editor.focused?.should be_true
      focused = editor_bg(app, window)
      app.viewer.focus
      app.editor.focused?.should be_false
      editor_bg(app, window).should eq focused
    end
  end

  it "cycles the themes from the keyboard, the Qt ones among them" do
    with_theme_app do |app|
      app.cycle_theme.should eq Md::App::Theme::Dark
      app.cycle_theme.should eq Md::App::Theme::Light
      app.cycle_theme.should eq Md::App::Theme::BreezeDark
      app.cycle_theme.should eq Md::App::Theme::BreezeLight
      app.cycle_theme.should eq Md::App::Theme::QdarkstyleDark
      app.cycle_theme.should eq Md::App::Theme::QdarkstyleLight
      app.cycle_theme.should eq Md::App::Theme::QtmodernDark
      Crysterm::CSS.theme.try(&.name).should eq "qtmodern-dark"
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
      with_theme_app settings do |app, window|
        app.theme.should eq Md::App::Theme::Light
        Crysterm::CSS.theme.try(&.name).should eq "light"
        theme_entries(app).map(&.checked?).should eq checked_at(2)
        viewer_bg(app, window).should eq Crysterm::CSS::Theme.light.primaries["surface"]
        settings.dirty?.should be_false # applying is not a change

        theme_entries(app)[3].trigger
        settings.dirty?.should be_true
        app.save_settings
      end
      stored = Md::Settings.load(path)
      stored.theme.should eq Md::App::Theme::BreezeDark
      stored.get?("theme", String).should eq "breeze_dark" # as --colors-theme spells it, by Crystal's enum names
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "lets --colors-theme win for the run without recording it" do
    Crysterm::Config.colors_theme = Md::App::Theme::Dark
    settings = Md::Settings.new("unused.json", {"theme" => JSON::Any.new("light")})
    with_theme_app settings do |app|
      app.theme.should eq Md::App::Theme::Dark
      settings.dirty?.should be_false
      theme_entries(app).map(&.checked?).should eq checked_at(1)

      theme_entries(app)[2].trigger # a pick from the menu is recorded as ever
      settings.theme.should eq Md::App::Theme::Light
    end
  ensure
    Crysterm::Config.colors_theme = Md::App::Theme::Terminal
  end
end
