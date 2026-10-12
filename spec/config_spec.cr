require "./spec_helper"

# `Md::Config`: the View and Options choices as options in Crysterm's
# registry, loaded from the config file, the environment and the command
# line, kept in the file, and reachable from the Options menu.

describe Md::Config do
  describe ".path" do
    it "is Superconf's default for md, under XDG_CONFIG_HOME" do
      with_config do |path|
        path.should eq File.join(ENV["XDG_CONFIG_HOME"], "md", "config.yml")
        Md::Config.path.should eq path
        Superconf.app_name.should eq "md"
      end
    end
  end

  describe "the options" do
    it "registers every View and Options choice with an md. key, an MD_ variable and a --md- flag" do
      keys = Md::Config.options.map(&.key)
      keys.should contain "md.sync_cursor"
      keys.should contain "md.mouse_mode"
      keys.should contain "md.pane_sizes"
      option = Crysterm::Config["md.text_width"]
      option.cli.should eq "--md-text-width"
      Superconf.env_name(option).should eq "MD_TEXT_WIDTH"
      option.description.should start_with "Format → Text Width"
      Crysterm::Config.md_text_width.should eq 0
      Md::Config.flags.should contain "--no-md-sync-cursor"
      Md::Config.help.should contain "--md-dialog-style=VALUE"
      Md::Config.help.should contain "~/.config/md/config.yml"
    end

    it "takes the file, then the environment and the command line over it" do
      with_config "md:\n  text_width: 80\n  vertical_ruler: true\ncolors:\n  theme: light\n", argv: ["--md-text-width=100", "--no-md-vertical-ruler"] do
        Crysterm::Config.md_text_width.should eq 100
        Crysterm::Config.md_vertical_ruler.should be_false
        Crysterm::Config.colors_theme.should eq Crysterm::CSS::Theme::Choice::Light
        Crysterm::Config["md.text_width"].source.should eq Superconf::Source::CommandLine
        Crysterm::Config["colors.theme"].source.should eq Superconf::Source::ConfigFile
      end
      Crysterm::Config.md_text_width.should eq 0 # reset afterwards
      Crysterm::Config.colors_theme.should eq Crysterm::CSS::Theme::Choice::Terminal
    end

    it "reads Crysterm's own file first, below md's, and leaves its values to it" do
      with_config "md:\n  text_width: 80\n" do |path|
        toolkit = Md::Config.toolkit_path
        toolkit.should eq File.join(ENV["XDG_CONFIG_HOME"], "crysterm", "config.yml")
        Dir.mkdir_p File.dirname(toolkit)
        File.write toolkit, "colors:\n  theme: light\nmd:\n  text_width: 60\n"
        Md::Config.configure file: path, argv: [] of String
        Crysterm::Config.colors_theme.should eq Crysterm::CSS::Theme::Choice::Light
        Crysterm::Config.md_text_width.should eq 80 # md's file wins
        Md::Config.dirty?.should be_false
        Md::Config.save.should be_true
        file = config_file(path)
        file["md"]["text_width"].as_i.should eq 80
        file["colors"]?.should be_nil
      end
    end

    it "refuses a broken file, naming it" do
      error = expect_raises(Md::Error, /cannot parse config file/) { with_config("md: [\n") { } }
      (error.message || "").should contain "config.yml"
    end

    it "refuses a file it cannot read, naming it, and starts on none at all" do
      with_config do |path|
        Md::Config.configure file: path, argv: [] of String # no file: the defaults
        Dir.mkdir_p path
        error = expect_raises(Md::Error, /cannot read config file/) do
          Md::Config.configure file: path, argv: [] of String
        end
        (error.message || "").should contain path
      end
    end

    it "refuses a value that does not fit its option" do
      expect_raises(Md::Error, /md.text_width/) do
        with_config("md:\n  text_width: wide\n") { }
      end
      expect_raises(Md::Error, /md.text_width/) do
        with_config("md:\n  text_width: -3\n") { }
      end
    end
  end

  describe ".save" do
    it "writes the picks of the run and the file's own entries, and nothing at its default" do
      with_config "md:\n  vertical_ruler: true\n" do |path|
        Crysterm::Config.md_sync_cursor = true # a pick
        Md::Config.dirty?.should be_true
        Md::Config.save.should be_true
        Md::Config.dirty?.should be_false
        text = File.read(path)
        text.should start_with "# md's settings"
        file = config_file(path)
        file["md"]["vertical_ruler"].as_bool.should be_true # the file's own entry
        file["md"]["sync_cursor"].as_bool.should be_true    # the pick
        file["md"]["guides"]?.should be_nil                 # a default
        file["colors"]?.should be_nil
      end
    end

    it "carries over an entry a variable or a flag outranked, and entries it does not know" do
      yaml = <<-YAML
        md:
          text_width: 80
          future_choice: "yes"
        colors:
          theme: light
        someday:
          option: 7
        YAML
      with_config yaml, argv: ["--md-text-width=100", "--colors-theme=dark"] do |path|
        Crysterm::Config.md_text_width.should eq 100
        Md::Config.save.should be_true
        file = config_file(path)
        file["md"]["text_width"].as_i.should eq 80 # the flag's 100 is for this run
        file["md"]["future_choice"].as_s.should eq "yes"
        file["colors"]["theme"].as_s.should eq "light"
        file["someday"]["option"].as_i.should eq 7
        File.read(path).should contain %(future_choice: "yes") # a string stays a string
      end
    end

    it "leaves what Crysterm's own file set, and a changed default, out of the file" do
      with_config do |path|
        # A default changed by the program (`Crysterm.default_log_file` at
        # every start) is not a pick: nothing to write, nothing dirty.
        Superconf.set "md.text_width", 72, Superconf::Source::Default
        Crysterm::Config.md_text_width.should eq 72
        Md::Config.dirty?.should be_false
        # Crysterm's file is read before md's options exist; its values
        # arrive at file precedence from another origin.
        Superconf.load_yaml "colors: {theme: light}", "config file /elsewhere/crysterm/config.yml"
        Crysterm::Config.colors_theme.should eq Crysterm::CSS::Theme::Choice::Light
        Md::Config.save.should be_true

        file = config_file(path)
        file["colors"]?.should be_nil
        file["md"]?.try(&.["text_width"]?).should be_nil
        Crysterm::Config.md_guides = true # a pick still counts
        Md::Config.dirty?.should be_true
      end
    end

    it "writes elsewhere on request, keeping the config file's own dirty state" do
      with_config do |path|
        Crysterm::Config.md_guides = true
        other = File.join(File.dirname(path), "elsewhere.yml")
        Md::Config.save(other).should be_true
        config_file(other)["md"]["guides"].as_bool.should be_true
        Md::Config.dirty?.should be_true
        File.exists?(path).should be_false
      end
    end

    it "returns false instead of raising when the file cannot be written" do
      with_config do |path|
        blocker = File.join(File.dirname(path), "blocker")
        Dir.mkdir_p File.dirname(blocker)
        File.write blocker, "" # a file where the directory would go
        Md::Config.save(File.join(blocker, "config.yml")).should be_false
      end
    end
  end

  describe ".load_file" do
    it "applies a file now, over what a flag set, as picks" do
      with_config nil, argv: ["--md-text-width=100"] do |path|
        other = File.join(File.dirname(path), "other.yml")
        File.write other, "md:\n  text_width: 72\n  center_text: false\n"
        Md::Config.load_file other
        Crysterm::Config.md_text_width.should eq 72
        Crysterm::Config.md_center_text.should be_false
        Crysterm::Config["md.text_width"].source.should eq Superconf::Source::Runtime
        Md::Config.save
        config_file(path)["md"]["text_width"].as_i.should eq 72
        expect_raises(Md::Error, /cannot read config file .*missing\.yml/) { Md::Config.load_file File.join(File.dirname(path), "missing.yml") }
      end
    end
  end
end

describe "Md::App config menu" do
  it "links a loaded file to the menu entries and the panes" do
    with_config do |path|
      with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true, config: true do |app|
        other = File.join(File.dirname(path), "other.yml")
        File.write other, "md:\n  horizontal_ruler: true\n  vertical_ruler: true\n  text_width: 72\n  pane_sizes: \"20,40,25\"\ncolors:\n  theme: dark\n"
        app.load_config_prompt
        answer app, other
        notice(app).should eq " Loaded #{other}"
        app.horizontal_ruler?.should be_true
        app.vertical_ruler?.should be_true
        app.editor.rulers?.should be_true
        app.text_width.should eq 72
        app.pane_sizes.should eq [20, 40, 25]
        app.theme.should eq Md::App::Theme::Dark
        rulers = menu(app, 3).actions.find!(&.text.==("R&ulers")).menu || fail("no Rulers submenu")
        rulers.map(&.checked?).should eq [true, true]

        app.load_config_prompt
        answer app, File.join(File.dirname(path), "missing.yml")
        notice(app).should start_with " Cannot load #{File.join(File.dirname(path), "missing.yml")}: cannot read config file"
      end
    ensure
      Crysterm::CSS.theme = nil
    end
  end

  it "saves on request, to the config file or elsewhere" do
    with_config do |path|
      with_app config: true do |app|
        options = menu(app, 4).actions.map(&.text)
        options.should eq ["&Overwrite Mode", "&Ask Before Discarding Changes", "A&uto-Save", "&Keep a Backup File", "&Mouse", "&Clipboard", "Resi&zable Panes", "No An&imations", "D&etachable Menus", "Vi Mode: Use &Neovim Config", "", "&Load Config…", "&Save Config", "Sa&ve Config As…", "", "Clea&r Caches…"]
        app.guides = true
        menu(app, 4).actions.find!(&.text.==("&Save Config")).trigger
        notice(app).should eq " Saved #{path}"
        config_file(path)["md"]["guides"].as_bool.should be_true
        config_file(path)["md"]["pane_sizes"].as_s.should eq "0,0,#{Md::App::TOC_WIDTH}"

        other = File.join(File.dirname(path), "copy.yml")
        menu(app, 4).actions.find!(&.text.==("Sa&ve Config As…")).trigger
        answer app, other
        notice(app).should eq " Saved #{other}"
        config_file(other)["md"]["guides"].as_bool.should be_true

        app.save_config_prompt
        answer app, "" # nothing written
        notice(app).should eq " Saved #{other}"
      end
    end
  end

  it "writes the file at exit only when something changed" do
    with_config do |path|
      with_app config: true do |app|
        app.save_config # the pane sizes are recorded: a first write
      end
      File.exists?(path).should be_true
      written = File.info(path).modification_time
      with_app config: true do |app|
        app.save_config
      end
      File.info(path).modification_time.should eq written
    end
  end
end
