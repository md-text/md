require "./spec_helper"

# A file deleted since it was left — on the trail, next after a closed
# document, or in File → Open Recent — is not reopened as a new, empty
# document under its name: md says "No such file" and goes on.

describe "Md::App reopening a file gone from disk" do
  it "spends a Previous File place in a deleted file, with a notice" do
    gone = tempfile "# Gone\n"
    here = tempfile "# Here\n"
    begin
      with_app Md::Source.new(path: gone), text: "# Gone\n", view: true do |app|
        app.open_file(here).should be_true
        File.delete gone
        app.previous_file.should be_true
        notice(app).should contain "No such file: #{gone}"
        app.source.path.should eq here # stayed
        app.markdown.should eq "# Here\n"
        app.previous_file_available?.should be_false # the place is spent
        question(app).should eq ""                   # nothing to ask about
      end
    ensure
      File.delete? gone
      File.delete? here
    end
  end

  it "skips a deleted next file on File → Close" do
    first = tempfile "# First\n"
    second = tempfile "# Second\n"
    begin
      with_app Md::Source.new(path: first), text: "# First\n", view: true do |app|
        app.open_file(second).should be_true
        app.previous_file.should be_true # back on first; second is ahead
        File.delete second
        app.close_document
        app.source.path.should be_nil # the blank document, not an empty "second"
        File.exists?(second).should be_false
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  it "takes a deleted file off File → Open Recent instead of opening it empty" do
    gone = tempfile "# Gone\n"
    here = tempfile "# Here\n"
    history = Md::History.new(File.tempname("md-spec-history", ".json"))
    begin
      with_app Md::Source.new(path: gone), text: "# Gone\n", view: true, history: history do |app|
        app.open_file(here).should be_true
        File.delete gone
        recent = app.main.menu_bar.menus[0].actions[1]
        entry = (recent.menu || [] of Crysterm::Action).find!(&.text.includes?(File.basename(gone)))
        entry.trigger
        notice(app).should contain "No such file: #{gone}"
        app.source.path.should eq here
        history.recent.map(&.path).should_not contain gone
        (recent.menu || [] of Crysterm::Action).map(&.text).none?(&.includes?(File.basename(gone))).should be_true
      end
    ensure
      File.delete? gone
      File.delete? here
    end
  end
end
