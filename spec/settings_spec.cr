require "./spec_helper"
require "file_utils"

# Runs the block with `XDG_CONFIG_HOME` set to *value* (unset for nil) and
# restores whatever it was before.
private def with_xdg_config_home(value : String?, &)
  previous = ENV["XDG_CONFIG_HOME"]?
  if value
    ENV["XDG_CONFIG_HOME"] = value
  else
    ENV.delete("XDG_CONFIG_HOME")
  end
  yield
ensure
  if previous
    ENV["XDG_CONFIG_HOME"] = previous
  else
    ENV.delete("XDG_CONFIG_HOME")
  end
end

# Runs the block with a fresh, empty directory under `Dir.tempdir` and
# removes it afterwards.
private def with_tempdir(&)
  dir = File.tempname("md-settings", "", dir: Dir.tempdir)
  Dir.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

describe Md::Settings do
  describe ".default_path" do
    it "lives under XDG_CONFIG_HOME when it is set" do
      with_xdg_config_home("/tmp/xdg-config") do
        Md::Settings.default_path.should eq "/tmp/xdg-config/md/settings.json"
      end
    end

    it "falls back to ~/.config" do
      with_xdg_config_home(nil) do
        Md::Settings.default_path.should eq Path.home.join(".config", "md", "settings.json").to_s
      end
    end
  end

  describe ".load" do
    it "is empty for a missing file" do
      with_tempdir do |dir|
        settings = Md::Settings.load(File.join(dir, "settings.json"))
        settings.keys.should be_empty
        settings.dirty?.should be_false
        settings.path.should eq File.join(dir, "settings.json")
        settings.sync_cursor?.should be_nil
        settings.mouse_mode.should be_nil
      end
    end

    it "is empty for a malformed file" do
      with_tempdir do |dir|
        path = File.join(dir, "settings.json")
        File.write(path, "{\"version\": 1, \"settings\": {\"sync_cursor\": tr")
        Md::Settings.load(path).keys.should be_empty
        File.write(path, "[1, 2, 3]")
        Md::Settings.load(path).keys.should be_empty
        File.write(path, "{\"version\": 1, \"settings\": [true]}")
        Md::Settings.load(path).keys.should be_empty
      end
    end

    it "is empty for another version" do
      with_tempdir do |dir|
        path = File.join(dir, "settings.json")
        File.write(path, "{\"version\": 2, \"settings\": {\"sync_cursor\": true}}")
        Md::Settings.load(path).sync_cursor?.should be_nil
      end
    end
  end

  describe "#get" do
    it "reads a stored value as the default's type, or the default" do
      settings = Md::Settings.new("unused.json")
      settings.get("wrap_width", 80).should eq 80
      settings.set "wrap_width", 100
      settings.get("wrap_width", 80).should eq 100
      settings.get?("wrap_width", Int32).should eq 100
      settings.set "pane_sizes", [30, 70]
      settings.get("pane_sizes", [] of Int32).should eq [30, 70]
      settings.set "theme", "dark"
      settings.get("theme", "light").should eq "dark"
      settings.set "mouse_mode", Md::App::MouseMode::Insert
      settings.get("mouse_mode", Md::App::MouseMode::All).should eq Md::App::MouseMode::Insert
      settings.set "line_numbers", false
      settings.get("line_numbers", true).should be_false
      settings.get?("line_numbers", Bool).should be_false
    end

    it "falls back to the default for a value of another type" do
      settings = Md::Settings.new("unused.json")
      settings.set "wrap_width", "wide"
      settings.get("wrap_width", 80).should eq 80
      settings.get?("wrap_width", Int32).should be_nil
      settings.set "mouse_mode", "trackball"
      settings.get("mouse_mode", Md::App::MouseMode::All).should eq Md::App::MouseMode::All
      settings.mouse_mode.should be_nil
    end
  end

  describe "#set" do
    it "marks the settings dirty only for a change" do
      settings = Md::Settings.new("unused.json")
      settings.set "sync_cursor", true
      settings.dirty?.should be_true
      settings.has_key?("sync_cursor").should be_true
      settings.has_key?("highlight_line").should be_false

      fresh = Md::Settings.new("unused.json", {"sync_cursor" => JSON::Any.new(true)})
      fresh.set "sync_cursor", true
      fresh.dirty?.should be_false
      fresh.set "sync_cursor", false
      fresh.dirty?.should be_true
    end
  end

  describe "#remove" do
    it "forgets a key and says whether it was set" do
      settings = Md::Settings.new("unused.json")
      settings.set "theme", "dark"
      settings.remove("theme").should be_true
      settings.get?("theme", String).should be_nil
      settings.remove("theme").should be_false
    end
  end

  describe "#save" do
    it "round-trips every setting through the file" do
      with_tempdir do |dir|
        path = File.join(dir, "config", "md", "settings.json")
        settings = Md::Settings.new(path)
        settings.sync_cursor = true
        settings.highlight_line = true
        settings.confirm_discard = false
        settings.mouse_mode = Md::App::MouseMode::Normal
        settings.save.should be_true
        settings.dirty?.should be_false

        loaded = Md::Settings.load(path)
        loaded.sync_cursor?.should be_true
        loaded.highlight_line?.should be_true
        loaded.confirm_discard?.should be_false
        loaded.mouse_mode.should eq Md::App::MouseMode::Normal
        loaded.dirty?.should be_false
        Dir.children(dir).should eq ["config"]
        Dir.children(File.dirname(path)).should eq ["settings.json"]

        json = JSON.parse(File.read(path))
        json["version"].should eq 1
        json["settings"]["mouse_mode"].should eq "normal"
        json["settings"]["confirm_discard"].should be_false
      end
    end

    it "keeps keys it does not know" do
      with_tempdir do |dir|
        path = File.join(dir, "settings.json")
        File.write(path, "{\"version\": 1, \"settings\": {\"sync_cursor\": false, \"pane_sizes\": [40, 60], \"theme\": {\"name\": \"dusk\"}}}")
        settings = Md::Settings.load(path)
        settings.keys.sort!.should eq ["pane_sizes", "sync_cursor", "theme"]
        settings.sync_cursor = true
        settings.save.should be_true

        json = JSON.parse(File.read(path))
        json["settings"]["sync_cursor"].should be_true
        json["settings"]["pane_sizes"].should eq [40, 60]
        json["settings"]["theme"]["name"].should eq "dusk"
      end
    end

    it "returns false for an unwritable location" do
      with_tempdir do |dir|
        file = File.join(dir, "not-a-dir")
        File.write(file, "")
        settings = Md::Settings.new(File.join(file, "md", "settings.json"))
        settings.sync_cursor = true
        settings.save.should be_false
        settings.dirty?.should be_true
      end
    end
  end
end
