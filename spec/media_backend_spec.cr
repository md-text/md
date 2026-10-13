require "./spec_helper"

alias Backend = Crysterm::Widget::Media::Backend

# An App on a document, Crysterm's `media.backend` option put back to its
# default afterwards: the option is one global for every window, and a pick
# from the menu sets it.
private def with_media_app(&)
  with_app Md::Source.new(path: "doc.md"), text: "# Title\n\nSome text.\n", view: true do |app, window|
    yield app, window
  end
ensure
  Crysterm::Config.reset "media.backend"
end

# The View → Media Backend submenu, separators included.
private def media_menu(app) : Array(Crysterm::Action)
  menu(app, 3).actions.find!(&.text.==("Media &Backend")).menu || [] of Crysterm::Action
end

# Its "Change for 5s" entry.
private def trial_entry(app) : Crysterm::Action
  media_menu(app).first
end

# Its backend entries, `Md::App::MEDIA_BACKENDS`' order, without the
# separators and the trial entry.
private def backend_entries(app) : Array(Crysterm::Action)
  media_menu(app).reject(&.separator?)[1..]
end

# The entry for *backend*.
private def entry(app, backend : Backend) : Crysterm::Action
  backend_entries(app)[Md::App::MEDIA_BACKENDS.index!(backend)]
end

# The entries' checks with only *backend*'s set.
private def checked_for(backend : Backend) : Array(Bool)
  Md::App::MEDIA_BACKENDS.map(&.==(backend))
end

describe "Md::App media backend" do
  it "offers Crysterm's media backends in the View menu after Theme and Images, Auto checked" do
    with_media_app do |app|
      app.media_backend.should eq Backend::Auto
      texts = menu(app, 3).actions.map(&.text)
      texts[texts.index!("The&me") + 1, 2].should eq ["&Images", "Media &Backend"]

      entries = media_menu(app)
      entries[0].text.should eq "Change for &5s"
      entries[0].checkable?.should be_true
      entries[0].checked?.should be_false
      entries[1].separator?.should be_true
      # Auto names what it detects here, by the entry's own label.
      entries[2].text.should match /\A&Auto \((Sub-Cell Glyphs|ANSI, One Cell per Pixel|Kitty Graphics|iTerm2 Inline Images|Sixel)\)\z/
      entries[3].text.should eq "Non&e"
      entries[4].separator?.should be_true # Auto and None, then the cell grid
      backends = backend_entries(app)
      backends.size.should eq Backend.values.size
      backends.map(&.text).skip(2).should eq [
        "A&NSI, One Cell per Pixel", "ANSI, &True Color", "ANSI, 25&6 Colors", "ANSI, &16 Colors", "ANSI, &8 Colors",
        "Sub-Cell &Glyphs", "Solid &Blocks", "Unicode &Half Blocks", "Unicode &Quadrants",
        "Unicode Se&xtants", "Unicode &Octants", "Braille &Dots", "ASCII &Contours",
        "&Sixel", "&ReGIS", "&Kitty Graphics", "&iTerm2 Inline Images", "Tektronix 401&4",
        "&w3mimgdisplay Overlay", "Überzug Overla&y",
      ]
      # Each mnemonic once in the submenu.
      letters = entries.reject(&.separator?).compact_map(&.mnemonic)
      letters.size.should eq entries.count { |entry| !entry.separator? }
      letters.uniq.size.should eq letters.size
      # The groups are separated: the cell grid, the terminal's graphics, the overlays.
      entries.count(&.separator?).should eq 4
      entries[entries.index!(entry(app, Backend::Sixel)) - 1].separator?.should be_true
      entries[entries.index!(entry(app, Backend::Overlay)) - 1].separator?.should be_true
      backends.map(&.checked?).should eq checked_for(Backend::Auto)
    end
  end

  it "disables the backends this terminal cannot drive, Auto and None never" do
    with_media_app do |app, window|
      entry(app, Backend::Auto).enabled?.should be_true
      entry(app, Backend::None).enabled?.should be_true
      entry(app, Backend::Ansi).enabled?.should be_true
      entry(app, Backend::GlyphAscii).enabled?.should be_true
      entry(app, Backend::Regis).enabled?.should be_false # nothing detects them
      entry(app, Backend::Tek).enabled?.should be_false
      Md::App::MEDIA_BACKENDS.each do |backend|
        entry(app, backend).enabled?.should eq backend.available?(window.tput)
      end
    end
  end

  it "sets the backend and Crysterm's option from a pick, exactly the picked one checked" do
    with_media_app do |app|
      entry(app, Backend::AnsiC256).trigger
      app.media_backend.should eq Backend::AnsiC256
      Crysterm::Config.media_backend.should eq Backend::AnsiC256
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::AnsiC256)
      notice(app).should contain "ANSI, 256 colors"
      notice(app).should_not contain "for 5s"
      entry(app, Backend::AnsiC256).trigger # re-picking keeps it
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::AnsiC256)
      app.media_trial_running?.should be_false

      entry(app, Backend::Auto).trigger
      app.media_backend.should eq Backend::Auto
      Crysterm::Config.media_backend.should eq Backend::Auto
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::Auto)
    end
  end

  it "follows the setter as it follows the menu" do
    with_media_app do |app|
      app.media_backend = Backend::GlyphHalf
      Crysterm::Config.media_backend.should eq Backend::GlyphHalf
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::GlyphHalf)
    end
  end

  it "tries a backend for a while under Change for 5s, then goes back" do
    with_media_app do |app|
      app.media_trial_span = 50.milliseconds
      trial_entry(app).trigger
      app.media_trial?.should be_true
      trial_entry(app).checked?.should be_true

      entry(app, Backend::AnsiC16).trigger
      app.media_backend.should eq Backend::AnsiC16
      Crysterm::Config.media_backend.should eq Backend::AnsiC16
      app.media_trial_running?.should be_true
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::AnsiC16)
      notice(app).should contain "ANSI, 16 colors for 50ms, then back to Auto"

      settle { app.media_backend == Backend::Auto }
      Crysterm::Config.media_backend.should eq Backend::Auto
      app.media_trial_running?.should be_false
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::Auto)
      notice(app).should contain "back to Auto"
      app.media_trial?.should be_true # the check stays for the next pick
    end
  end

  it "restarts the time on another pick during a trial and still returns to the original" do
    with_media_app do |app|
      app.media_backend = Backend::Ansi # the backend in force before the trial
      app.media_trial_span = 80.milliseconds
      app.media_trial = true
      entry(app, Backend::AnsiC8).trigger
      sleep 40.milliseconds
      entry(app, Backend::GlyphAscii).trigger
      app.media_backend.should eq Backend::GlyphAscii
      sleep 60.milliseconds # the first pick's time is up; the second's is not
      app.media_backend.should eq Backend::GlyphAscii
      settle { app.media_backend == Backend::Ansi }
      Crysterm::Config.media_backend.should eq Backend::Ansi
    end
  end

  it "ends the trial when the backend it would return to is picked" do
    with_media_app do |app|
      app.media_trial_span = 50.milliseconds
      app.media_trial = true
      entry(app, Backend::AnsiC8).trigger
      app.media_trial_running?.should be_true
      entry(app, Backend::Auto).trigger
      app.media_trial_running?.should be_false
      app.media_backend.should eq Backend::Auto
      sleep 80.milliseconds
      app.media_backend.should eq Backend::Auto
    end
  end

  it "keeps the tried backend and cancels the return when Change for 5s is unchecked during a trial" do
    with_media_app do |app|
      app.media_trial_span = 50.milliseconds
      app.media_trial = true
      entry(app, Backend::AnsiC8).trigger
      app.media_trial_running?.should be_true
      trial_entry(app).trigger
      app.media_trial?.should be_false
      app.media_trial_running?.should be_false
      sleep 80.milliseconds
      app.media_backend.should eq Backend::AnsiC8
      Crysterm::Config.media_backend.should eq Backend::AnsiC8
    end
  end

  it "starts from the backend Crysterm's config names for the run" do
    Crysterm::Config.media_backend = Backend::Kitty # --media-backend kitty
    with_media_app do |app|
      app.media_backend.should eq Backend::Kitty
      backend_entries(app).map(&.checked?).should eq checked_for(Backend::Kitty)
    end
  end

  it "rebuilds a background image for the picked backend" do
    with_media_app do |app, window|
      app.viewer.style.background_image = "#{__DIR__}/../lib/crysterm/data/image/matterhorn.png"
      window.repaint
      first = app.viewer.background_media.should_not be_nil
      entry(app, Backend::AnsiC16).trigger
      window.repaint
      app.viewer.background_media.should be_a(Crysterm::Widget::Media::Ascii::C16)
      app.viewer.background_media.should_not be(first)
    end
  end
end
