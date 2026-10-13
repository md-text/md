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
end
