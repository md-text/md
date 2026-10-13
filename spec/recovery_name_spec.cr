require "./spec_helper"
require "file_utils"

describe "Md::App.recovery_name" do
  it "keeps a short path's name, which reads back to the path" do
    Md::App.recovery_name("/home/u/100%.md").should eq "%2Fhome%2Fu%2F100%25.md"
  end

  it "shortens a deep path's name to one a file system takes, distinct and the same each time" do
    deep = "/" + (["ä" * 30] * 8).join("/") + "/notes.md"
    other = deep.sub("notes.md", "other.md")
    name = Md::App.recovery_name(deep)
    name.bytesize.should be <= Md::App::RECOVERY_NAME_MAX
    name.valid_encoding?.should be_true
    name.should end_with "%2Fnotes.md"
    name.should eq Md::App.recovery_name(deep)
    name.should_not eq Md::App.recovery_name(other)
    Md::App.recovery_name(deep.sub("/notes.md", "/x/../notes.md")).should eq name
  end

  it "auto-saves a document whose path is longer than a file name may be" do
    state = File.tempname("md-spec-state")
    previous = ENV["XDG_STATE_HOME"]?
    ENV["XDG_STATE_HOME"] = state
    dir = File.tempname("md-spec-deep")
    deep = File.join([dir] + (1..6).map { |i| "directory-number-#{i}-with-a-long-name-in-it" })
    Dir.mkdir_p deep
    path = File.join(deep, "notes.md")
    File.write path, "text\n"
    begin
      with_app Md::Source.new(path: path), text: "text\n", view: true do |app|
        app.autosave_interval = 20.milliseconds
        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.cursor_position = 0
        app.editor.insert_text "edited "
        settle { File.exists? app.recovery_path }
        File.read(app.recovery_path).should eq "edited text\n"
      end
    ensure
      previous ? (ENV["XDG_STATE_HOME"] = previous) : ENV.delete("XDG_STATE_HOME")
      FileUtils.rm_rf state
      FileUtils.rm_rf dir
    end
  end
end
