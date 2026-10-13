require "./spec_helper"

# Runs the block with md's cache directory in a scratch `XDG_CACHE_HOME`,
# where Help → Manual writes the manual.
private def with_cache_home(&)
  dir = File.tempname("md-spec-cache")
  previous = ENV["XDG_CACHE_HOME"]?
  ENV["XDG_CACHE_HOME"] = dir
  begin
    yield dir
  ensure
    previous ? (ENV["XDG_CACHE_HOME"] = previous) : ENV.delete("XDG_CACHE_HOME")
    FileUtils.rm_rf dir
  end
end

describe "Help menu" do
  it "is last on the bar, after Window, with Manual and About" do
    with_app do |app, _window|
      menus = app.main.menu_bar.menus
      app.main.menu_bar.mnemonics.last(2).should eq ['n', 'p']
      menus.last.actions.map(&.text).should eq ["&Manual", "&About md"]
    end
  end

  it "About names md's version, author and website in the status bar" do
    with_app do |app, _window|
      app.main.menu_bar.menus.last.actions[1].trigger
      notice(app).should contain Md::VERSION
      notice(app).should contain "Davor Ocelic"
      notice(app).should contain "https://github.com/md-text/md"
    end
  end

  it "Manual opens MANUAL.md as the document" do
    with_cache_home do
      with_app do |app, _window|
        app.main.menu_bar.menus.last.actions[0].trigger
        app.source.path.should eq Md::App.manual_path
        app.markdown.should start_with "# md manual\n"
        app.markdown.should contain "\n## Usage\n"
        app.markdown.should contain "\n### Help\n"
        app.markdown.should_not contain "## Installation"
        app.markdown.should_not contain "## Development"
        app.markdown.should_not contain "[![CI]"
        app.markdown.should_not contain "**Status:**"
      end
    end
  end
end
