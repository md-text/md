require "./spec_helper"

# `Md::Document`'s watcher (Options → Watch File) and the document's own
# writes of its file.

describe "Md::Document watching its file" do
  it "takes its own save for no change on disk, though edits followed it before the watcher looked" do
    path = tempfile "text\n"
    begin
      with_app Md::Source.new(path: path), text: "text\n", view: false do |app|
        app.watch_interval = 20.milliseconds
        app.watch_file = true
        app.editor.cursor_position = 0
        app.editor.insert_text "saved "
        app.save.should be_true
        app.editor.insert_text "typed on " # before the watcher's next look
        sleep 120.milliseconds
        notice(app).should_not contain "changed on disk"
        app.markdown.should eq "saved typed on text\n"
        # A change by another program is still told.
        File.write path, "theirs\n"
        settle { notice(app).includes? "changed on disk; unsaved changes kept" }
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end
end
