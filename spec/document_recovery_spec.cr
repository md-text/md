require "./spec_helper"
require "file_utils"

# `Md::Document`'s recovery file following the modified state.

describe "Md::Document recovery file" do
  it "goes when an undo takes the document back to its saved text" do
    previous = ENV["XDG_STATE_HOME"]?
    state = File.tempname("md-spec-state")
    ENV["XDG_STATE_HOME"] = state
    path = tempfile "text\n"
    begin
      with_app Md::Source.new(path: path), text: "text\n", view: false do |app|
        app.autosave_interval = 30.milliseconds
        app.editor.cursor_position = 0
        app.editor.insert_text "edited "
        copy = app.recovery_path
        settle { File.exists? copy }
        app.document.text.undo
        app.document.text.modified?.should be_false
        File.exists?(copy).should be_false # nothing unsaved for it to keep
        sleep 100.milliseconds
        File.exists?(copy).should be_false # nor is it written again
        app.document.text.redo
        settle { File.exists? copy }
        File.read(copy).should eq "edited text\n"
      end
    ensure
      previous ? (ENV["XDG_STATE_HOME"] = previous) : ENV.delete("XDG_STATE_HOME")
      FileUtils.rm_rf state
      File.delete? path
    end
  end

  it "does not offer an unnamed copy of an md still running as one left behind" do
    previous = ENV["XDG_STATE_HOME"]?
    state = File.tempname("md-spec-state")
    ENV["XDG_STATE_HOME"] = state
    dir = Md::App.autosave_dir
    begin
      Dir.mkdir_p dir
      # This process's own unnamed document's net, and a second one's.
      File.write File.join(dir, "unnamed-20260101-120000-#{Process.pid}.md"), "mine\n"
      File.write File.join(dir, "unnamed-20260101-120000-#{Process.pid}-2.md"), "mine too\n"
      with_app do |app|
        notice(app).should be_empty
      end
      ended = Process.new("true")
      ended.wait
      File.write File.join(dir, "unnamed-20260101-120001-#{ended.pid}.md"), "lost\n"
      with_app do |app|
        notice(app).should eq " Recovered copy exists in #{dir}"
      end
    ensure
      previous ? (ENV["XDG_STATE_HOME"] = previous) : ENV.delete("XDG_STATE_HOME")
      FileUtils.rm_rf state
    end
  end
end
