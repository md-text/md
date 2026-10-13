require "./spec_helper"
require "file_utils"

# File → Open Recent, in every window: the windows share the history.
private def recent_files(app)
  (app.main.menu_bar.menus[0].actions[1].menu || [] of Crysterm::Action).map(&.text)
end

describe "File → Open Recent across windows" do
  it "lists a file opened in one window, and the list cleared, in the other's menu too" do
    dir = File.tempname("md-spec-recent-windows")
    Dir.mkdir_p dir
    doc = File.join(dir, "doc.md")
    other = File.join(dir, "other.md")
    File.write doc, "# Doc\n"
    File.write other, "# Other\n"
    history = Md::History.new(File.join(dir, "history.json"))
    application = Crysterm::Application.new
    begin
      with_app Md::Source.new(path: doc), text: "# Doc\n", view: true, history: history do |a, window|
        application.add window
        a.window_opener = recording_opener
        b = a.new_window || fail("no window was opened")
        begin
          a.open_file other
          recent_files(a).should eq [other, doc]
          recent_files(b).should eq [other, doc]
          a.clear_caches
          recent_files(b).should be_empty
          b.main.menu_bar.menus[0].actions[1].enabled?.should be_false
        ensure
          b.window.destroy
        end
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end
