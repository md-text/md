require "./spec_helper"
require "../src/md/history"
require "file_utils"

# Runs the block with `XDG_STATE_HOME` set to *value* (unset for nil) and
# restores whatever it was before.
private def with_xdg_state_home(value : String?, &)
  previous = ENV["XDG_STATE_HOME"]?
  if value
    ENV["XDG_STATE_HOME"] = value
  else
    ENV.delete("XDG_STATE_HOME")
  end
  yield
ensure
  if previous
    ENV["XDG_STATE_HOME"] = previous
  else
    ENV.delete("XDG_STATE_HOME")
  end
end

# Runs the block with a fresh, empty directory under `Dir.tempdir` and
# removes it afterwards.
private def with_tempdir(&)
  dir = File.tempname("md-history", "", dir: Dir.tempdir)
  Dir.mkdir_p(dir)
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

describe Md::History do
  describe ".default_path" do
    it "lives under XDG_STATE_HOME when it is set" do
      with_xdg_state_home("/tmp/xdg-state") do
        Md::History.default_path.should eq "/tmp/xdg-state/md/history.json"
      end
    end

    it "falls back to ~/.local/state" do
      with_xdg_state_home(nil) do
        Md::History.default_path.should eq Path.home.join(".local", "state", "md", "history.json").to_s
      end
    end
  end

  describe ".load" do
    it "is empty for a missing file" do
      with_tempdir do |dir|
        history = Md::History.load(File.join(dir, "history.json"))
        history.recent.should be_empty
        history.dirty?.should be_false
        history.path.should eq File.join(dir, "history.json")
      end
    end

    it "is empty for a malformed file" do
      with_tempdir do |dir|
        path = File.join(dir, "history.json")
        File.write(path, "{\"version\": 1, \"recent\": [{\"path\": 3")
        Md::History.load(path).recent.should be_empty
        File.write(path, "[1, 2, 3]")
        Md::History.load(path).recent.should be_empty
        File.write(path, "{\"version\": 1, \"recent\": [{\"path\": \"/a\", \"line\": 1, \"column\": 1, \"viewing\": true, \"at\": \"yesterday\"}]}")
        Md::History.load(path).recent.should be_empty
      end
    end

    it "is empty for another version" do
      with_tempdir do |dir|
        path = File.join(dir, "history.json")
        File.write(path, "{\"version\": 2, \"recent\": [{\"path\": \"/a.md\", \"line\": 1, \"column\": 1, \"viewing\": true, \"at\": \"2026-01-01T00:00:00Z\"}]}")
        Md::History.load(path).recent.should be_empty
      end
    end

    it "keeps a non-absolute path from the file as it is" do
      with_tempdir do |dir|
        path = File.join(dir, "history.json")
        File.write(path, "{\"version\": 1, \"recent\": [{\"path\": \"notes.md\", \"line\": 2, \"column\": 3, \"viewing\": false, \"at\": \"2026-01-01T00:00:00Z\"}]}")
        Md::History.load(path).recent.map(&.path).should eq ["notes.md"]
      end
    end
  end

  describe "#touch" do
    it "puts the newest first, makes paths absolute and caps at MAX" do
      history = Md::History.new("unused.json")
      (1..Md::History::MAX + 5).each do |i|
        history.touch("file#{i}.md", i, 1, viewing: true)
      end
      recent = history.recent
      recent.size.should eq Md::History::MAX
      recent.first.path.should eq File.expand_path("file#{Md::History::MAX + 5}.md")
      recent.last.path.should eq File.expand_path("file6.md")
      recent.all?(&.path.starts_with?('/')).should be_true
      history.dirty?.should be_true
    end

    it "updates an existing path and moves it to the front" do
      history = Md::History.new("unused.json")
      history.touch("a.md", 1, 1, viewing: true, at: Time.utc(2026, 1, 1))
      history.touch("b.md", 1, 1, viewing: true, at: Time.utc(2026, 1, 2))
      entry = history.touch("./a.md", 7, 3, viewing: false, at: Time.utc(2026, 1, 3))
      entry.path.should eq File.expand_path("a.md")
      entry.line.should eq 7
      entry.column.should eq 3
      entry.viewing.should be_false
      entry.at.should eq Time.utc(2026, 1, 3)
      history.recent.map(&.path).should eq [File.expand_path("a.md"), File.expand_path("b.md")]
    end
  end

  describe "#entry" do
    it "finds a file by any spelling of its path" do
      history = Md::History.new("unused.json")
      history.touch(File.expand_path("docs/readme.md"), 4, 2, viewing: true)
      found = history.entry("./docs/../docs/readme.md")
      found.should_not be_nil
      found.try(&.line).should eq 4
      history.entry("docs/other.md").should be_nil
    end
  end

  describe "#clear" do
    it "forgets every file and says how many there were" do
      history = Md::History.new("unused.json")
      history.clear.should eq 0
      history.dirty?.should be_false
      history.touch("a.md", 1, 1, viewing: true)
      history.touch("b.md", 1, 1, viewing: true)
      history.clear.should eq 2
      history.recent.should be_empty
      history.dirty?.should be_true
    end
  end

  describe "#forget" do
    it "drops the file and says whether it was there" do
      history = Md::History.new("unused.json")
      history.touch("a.md", 1, 1, viewing: true)
      history.forget("./a.md").should be_true
      history.recent.should be_empty
      history.forget("a.md").should be_false
    end
  end

  describe "#save" do
    it "round-trips through the file" do
      with_tempdir do |dir|
        path = File.join(dir, "state", "md", "history.json")
        history = Md::History.new(path)
        history.touch("a.md", 3, 4, viewing: true, at: Time.utc(2026, 5, 6, 7, 8, 9))
        history.touch("b.md", 10, 1, viewing: false, at: Time.utc(2026, 5, 7))
        history.save.should be_true
        history.dirty?.should be_false

        loaded = Md::History.load(path)
        loaded.recent.should eq history.recent
        loaded.dirty?.should be_false
        Dir.children(dir).should eq ["state"]
        Dir.children(File.dirname(path)).should eq ["history.json"]

        json = JSON.parse(File.read(path))
        json["version"].should eq 1
        json["recent"][0]["path"].should eq File.expand_path("b.md")
        json["recent"][1]["at"].should eq "2026-05-06T07:08:09Z"
      end
    end

    it "returns false for an unwritable location" do
      with_tempdir do |dir|
        file = File.join(dir, "not-a-dir")
        File.write(file, "")
        history = Md::History.new(File.join(file, "md", "history.json"))
        history.touch("a.md", 1, 1, viewing: true)
        history.save.should be_false
        history.dirty?.should be_true
      end
    end
  end
end
