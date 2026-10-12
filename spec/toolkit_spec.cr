require "./spec_helper"

# View → Color Depth, View → Terminal Links and Options → No Animations:
# Crysterm's own options in the menus, kept with the other settings.

private def submenu(app, index, text) : Array(Crysterm::Action)
  menu(app, index).actions.find!(&.text.==(text)).menu || [] of Crysterm::Action
end

describe "Md::App toolkit options" do
  it "offers the color depths, the current one checked, and applies a pick to the window" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      entries = submenu(app, 3, "Co&lor Depth")
      # Auto names the depth Crysterm detects here, by that depth's own label.
      detected = entries[0].text
      detected.should match /\A&Auto \((Monochrome|8 Colors|16 Colors|256 Colors|True Color|\d+ Colors)\)\z/
      entries.map(&.text).skip(1).should eq ["&Monochrome", "&8 Colors", "1&6 Colors", "&256 Colors", "&True Color"]
      entries.map(&.checked?).should eq [true, false, false, false, false, false]
      entries[3].trigger
      app.color_depth.should eq Crysterm::ColorDepth::Ansi
      Crysterm::Config.colors_depth.should eq Crysterm::ColorDepth::Ansi
      window.color_count.should eq 16
      entries.map(&.checked?).should eq [false, false, false, true, false, false]
      app.color_depth = Crysterm::ColorDepth::TrueColor
      window.color_count.should eq 0x1000000
      entries[5].checked?.should be_true
      # The detection, not the pick: View's AboutToShow brings it up to date.
      menu(app, 3).emit Crysterm::Event::AboutToShow
      entries[0].text.should eq detected
    end
  ensure
    Crysterm::Config.reset "colors.depth"
  end

  it "offers the hyperlink policies and tells the window" do
    with_app do |app, window|
      entries = submenu(app, 3, "Terminal Lin&ks")
      entries.map(&.text).should eq ["&Auto (No)", "Al&ways", "&Never", "", "Double-click to &Open"]
      entries[0, 3].map(&.checked?).should eq [true, false, false]
      app.viewer.links_enabled?.should be_true
      entries[2].trigger
      app.hyperlinks.should eq Crysterm::AutoToggle::Off
      Crysterm::Config.render_hyperlinks.should eq Crysterm::AutoToggle::Off
      window.hyperlinks.should eq Crysterm::AutoToggle::Off
      window.hyperlinks?.should be_false
      app.viewer.links_enabled?.should be_false # Never: no links in the viewer at all
      entries[1].trigger
      window.hyperlinks?.should be_true # forced on, headless or not
      app.viewer.links_enabled?.should be_true
    end
  ensure
    Crysterm::Config.reset "render.hyperlinks"
  end

  it "starts without links under a configured Never, and follows a link on a double click when asked" do
    with_config %(render:\n  hyperlinks: "off"\nmd:\n  link_double_click: true\n) do
      with_app Md::Source.new(path: "doc.md"), text: "See [the site](https://example.com).\n", view: true, config: true do |app|
        app.viewer.links_enabled?.should be_false
        app.viewer.double_click_links?.should be_true
      end
    end
    with_app Md::Source.new(path: "doc.md"), text: "See [the site](https://example.com).\n", view: true do |app|
      opened = [] of String
      app.url_opener = ->(url : String) { opened << url; nil }
      toggle = submenu(app, 3, "Terminal Lin&ks").last
      toggle.checked?.should be_false
      app.viewer.double_click_links?.should be_false
      toggle.trigger
      app.link_double_click?.should be_true
      app.viewer.double_click_links?.should be_true
      app.link_double_click = false
      toggle.checked?.should be_false
      app.viewer.double_click_links?.should be_false
    end
  end

  it "toggles reduced motion" do
    with_app do |app|
      entry = menu(app, 4).actions.find!(&.text.==("No An&imations"))
      entry.checked?.should be_false
      entry.trigger
      app.reduced_motion?.should be_true
      Crysterm::Config.render_reduced_motion.should be_true
      app.reduced_motion = false
      entry.checked?.should be_false
      Crysterm::Config.render_reduced_motion.should be_false
    end
  ensure
    Crysterm::Config.reset "render.reduced_motion"
  end

  it "starts from the configured values and keeps the picks with the settings" do
    with_config %(colors:\n  depth: ansi\nrender:\n  hyperlinks: "off"\n  reduced_motion: true\nmedia:\n  backend: glyph\n) do |path|
      with_app config: true do |app, window|
        app.color_depth.should eq Crysterm::ColorDepth::Ansi
        window.color_count.should eq 16
        app.hyperlinks.should eq Crysterm::AutoToggle::Off
        app.reduced_motion?.should be_true
        app.media_backend.should eq Crysterm::Widget::Media::Backend::Glyph
        Md::Config.dirty?.should be_false
        app.color_depth = Crysterm::ColorDepth::Xterm256
        app.media_backend = Crysterm::Widget::Media::Backend::Ansi
        app.link_double_click = true
        app.save_config
      end
      file = config_file(path)
      file["md"]["link_double_click"].as_bool.should be_true
      file["colors"]["depth"].as_s.should eq "Xterm256"
      file["render"]["hyperlinks"].as_s.should eq "Off" # as Crysterm spells it
      file["render"]["reduced_motion"].as_bool.should be_true
      file["media"]["backend"].as_s.should eq "Ansi"
    end
  end
end
