require "./spec_helper"
require "file_utils"

# Runs the block with `XDG_STATE_HOME` pointing at a fresh directory, so the
# recovery files land there, and removes the directory afterwards.
private def with_state_home(&)
  previous = ENV["XDG_STATE_HOME"]?
  dir = File.tempname("md-spec-state")
  Dir.mkdir_p dir
  ENV["XDG_STATE_HOME"] = dir
  yield File.join(dir, "md", "autosave")
ensure
  if previous
    ENV["XDG_STATE_HOME"] = previous
  else
    ENV.delete "XDG_STATE_HOME"
  end
  FileUtils.rm_rf dir if dir
end

private def edit(app, text)
  app.show_pane(Md::App::Pane::Editor).focus
  app.editor.cursor_position = 0
  app.editor.insert_text text
end

describe "Md::App backup" do
  it "keeps the file's previous contents as FILE~ on the first save of the session only" do
    path = tempfile "first\n"
    begin
      with_app Md::Source.new(path: path), text: "first\n", view: true do |app|
        app.backup_file?.should be_true
        edit app, "second "
        app.save.should be_true
        File.read(path).should eq "second first\n"
        File.read("#{path}~").should eq "first\n"
        notice(app).should eq " Saved #{path}"
        edit app, "third "
        app.save.should be_true
        File.read("#{path}~").should eq "first\n"
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "makes none with the option off, nor for a file that did not exist" do
    path = tempfile "text\n"
    fresh = File.tempname("md-spec-new", ".md")
    begin
      with_app Md::Source.new(path: path), text: "text\n", view: true do |app|
        app.backup_file = false
        edit app, "x"
        app.save.should be_true
        File.exists?("#{path}~").should be_false
        app.open_file fresh
        app.backup_file = true
        app.editor.insert_text "new"
        app.save.should be_true
        File.exists?("#{fresh}~").should be_false
      end
    ensure
      File.delete? path
      File.delete? fresh
    end
  end

  it "saves anyway when the backup cannot be written, saying so" do
    path = tempfile "text\n"
    Dir.mkdir "#{path}~" # a copy cannot replace a directory
    begin
      with_app Md::Source.new(path: path), text: "text\n", view: true do |app|
        edit app, "x"
        app.save.should be_true
        File.read(path).should eq "xtext\n"
        notice(app).should start_with " Saved #{path} (backup #{path}~ failed: "
      end
    ensure
      File.delete? path
      FileUtils.rm_rf "#{path}~"
    end
  end
end

describe "Md::App auto-save" do
  it "writes a named document's edits to a recovery file after the interval, which a save or a clean exit removes" do
    with_state_home do |dir|
      path = tempfile "text\n"
      begin
        with_app Md::Source.new(path: path), text: "text\n", view: true do |app|
          app.autosave?.should be_true
          app.autosave_interval = 30.milliseconds
          sleep 100.milliseconds
          Dir.exists?(dir).should be_false # nothing modified, nothing written
          edit app, "edited "
          copy = File.join(dir, path.gsub('%', "%25").gsub('/', "%2F"))
          app.recovery_path.should eq copy
          settle { File.exists? copy }
          File.read(copy).should eq "edited text\n"
          File.read(path).should eq "text\n"                # the file is the user's to write
          Dir.children(dir).should eq [File.basename(copy)] # the temporary file is gone

          app.save.should be_true
          File.exists?(copy).should be_false
          edit app, "more "
          settle { File.exists? copy }
          app.finish_autosave
          File.exists?(copy).should be_false
          app.editor.insert_text "late"
          sleep 100.milliseconds
          File.exists?(copy).should be_false # the timer is stopped
        end
      ensure
        File.delete? path
        File.delete? "#{path}~"
      end
    end
  end

  it "gives a document without a name a recovery file of its own" do
    with_state_home do |dir|
      with_app do |app|
        app.autosave_interval = 30.milliseconds
        app.editor.insert_text "unsaved"
        settle { Dir.exists?(dir) && !Dir.children(dir).empty? }
        copies = Dir.children(dir)
        copies.size.should eq 1
        copies[0].should match /^unnamed-\d{8}-\d{6}-#{Process.pid}\.md$/
        File.read(File.join(dir, copies[0])).should eq "unsaved"
        app.finish_autosave
        Dir.children(dir).should be_empty
      end
    end
  end

  it "writes nothing while the option is off, and starts when it is turned on" do
    with_state_home do |dir|
      with_app do |app|
        app.autosave_interval = 30.milliseconds
        app.autosave = false
        app.editor.insert_text "quiet"
        sleep 100.milliseconds
        Dir.exists?(dir).should be_false
        app.autosave = true
        settle { Dir.exists?(dir) && !Dir.children(dir).empty? }
        app.finish_autosave
      end
    end
  end

  it "notices a recovery file newer than the file when the file is opened" do
    with_state_home do |dir|
      path = tempfile "on disk\n"
      other = tempfile "other\n"
      begin
        copy = File.join(dir, Md::App.recovery_name(path))
        Dir.mkdir_p dir
        File.write copy, "lost edits\n"
        ago = Time.utc - 1.hour
        File.utime ago, ago, path
        with_app Md::Source.new(path: path), text: "on disk\n", view: true do |app|
          notice(app).should eq " Recovered copy from #{File.info(copy).modification_time.to_local.to_s("%Y-%m-%d %H:%M")} exists: #{copy}"
          app.open_file other
          notice(app).should contain "Opened #{other}" # no copy for it
          app.open_file path
          notice(app).should contain "Recovered copy from"
        end
        # The copy is older than the file once the file is written again.
        File.write path, "newer\n"
        with_app Md::Source.new(path: path), text: "newer\n", view: true do |app|
          notice(app).should be_empty
        end
      ensure
        File.delete? path
        File.delete? other
      end
    end
  end

  it "mentions unnamed copies left behind to a new document" do
    with_state_home do |dir|
      Dir.mkdir_p dir
      File.write File.join(dir, "unnamed-20260101-120000-1.md"), "lost\n"
      with_app do |app|
        notice(app).should eq " Recovered copy exists in #{dir}"
      end
      File.write File.join(dir, "unnamed-20260101-120001-2.md"), "lost too\n"
      with_app do |app|
        notice(app).should eq " 2 recovered copies exist in #{dir}"
      end
      with_app Md::Source.new(stdin: true), view: true do |app|
        notice(app).should be_empty # a stream is not a new document
      end
    end
  end

  it "keeps both choices in the config, and offers them in the Options menu" do
    with_config do
      with_app config: true do |app|
        options = app.main.menu_bar.menus[4]
        autosave = options.actions.find { |a| a.text == "A&uto-Save" } || fail("no Auto-Save entry")
        backup = options.actions.find { |a| a.text == "&Keep a Backup File" } || fail("no backup entry")
        autosave.checked?.should be_true
        backup.checked?.should be_true
        autosave.trigger
        app.autosave?.should be_false
        Crysterm::Config.md_autosave.should be_false
        app.backup_file = false
        backup.checked?.should be_false
        Crysterm::Config.md_backup_file.should be_false
      end
      with_app config: true do |app|
        app.autosave?.should be_false
        app.backup_file?.should be_false
      end
    end
  end
end
