require "./spec_helper"
require "file_utils"

# Runs the block with `XDG_STATE_HOME` and `XDG_CACHE_HOME` pointing at
# fresh directories, so the history, the recovery files and the log file
# land there, and removes them afterwards. Yields the recovery files'
# directory, the cache directory and the history file's path.
private def with_xdg_dirs(&)
  previous = {ENV["XDG_STATE_HOME"]?, ENV["XDG_CACHE_HOME"]?}
  root = File.tempname("md-spec-caches")
  state = File.join(root, "state")
  cache = File.join(root, "cache")
  Dir.mkdir_p state
  Dir.mkdir_p cache
  ENV["XDG_STATE_HOME"] = state
  ENV["XDG_CACHE_HOME"] = cache
  yield File.join(state, "md", "autosave"), File.join(cache, "md"), File.join(state, "md", "history.json")
ensure
  {"XDG_STATE_HOME", "XDG_CACHE_HOME"}.each_with_index do |name, i|
    if value = previous.try &.[i]
      ENV[name] = value
    else
      ENV.delete name
    end
  end
  FileUtils.rm_rf root if root
end

describe "Md::App clear caches" do
  it "empties the history, the recovery files and the cache directory, and says what went" do
    with_xdg_dirs do |autosave_dir, cache_dir, history_path|
      Md::App.cache_dir.should eq cache_dir
      Md::App.autosave_dir.should eq autosave_dir
      Dir.mkdir_p autosave_dir
      Dir.mkdir_p cache_dir
      File.write File.join(autosave_dir, "unnamed-20260101-120000-1.md"), "lost\n"
      File.write File.join(autosave_dir, "%2Fhome%2Fu%2Fa.md"), "lost\n"
      File.write File.join(cache_dir, "md.log"), "old log\n"
      history = Md::History.new(history_path)
      history.touch "a.md", 1, 1, true
      history.touch "b.md", 2, 1, true
      history.save.should be_true
      Crysterm::Config.md_soft_wrap = false
      path = tempfile "text\n"
      begin
        with_app Md::Source.new(path: path), text: "text\n", view: true, history: history do |app|
          app.autosave_interval = 30.milliseconds
          recent = menu(app, 0).actions[1]
          recent.enabled?.should be_true
          app.show_pane(Md::App::Pane::Editor).focus
          app.editor.insert_text "edited "
          own = app.recovery_path
          settle { File.exists? own }

          app.clear_caches.should eq({2, 3})
          notice(app).should eq " Cleared 2 recent files, 3 recovery files"
          history.recent.should be_empty
          Md::History.load(history_path).recent.should be_empty # written at once
          Dir.children(autosave_dir).should be_empty
          Dir.children(cache_dir).should be_empty
          recent.enabled?.should be_false
          app.soft_wrap?.should be_false # the config is not a cache
          settle { File.exists? own }    # the document's own copy comes back
          app.finish_autosave

          app.clear_caches.should eq({0, 0})
          notice(app).should eq " Cleared 0 recent files, 0 recovery files"
        end
      ensure
        Crysterm::Config.reset "md.soft_wrap"
        File.delete? path
      end
    end
  end

  it "asks first from Options → Clear Caches…, and clears nothing on no" do
    with_xdg_dirs do |autosave_dir, _, history_path|
      Dir.mkdir_p autosave_dir
      File.write File.join(autosave_dir, "unnamed-20260101-120000-1.md"), "lost\n"
      history = Md::History.new(history_path)
      history.touch "a.md", 1, 1, true
      with_app history: history do |app|
        entry = menu(app, 4).actions.find!(&.text.==("Clea&r Caches…"))
        entry.trigger
        question(app).should eq "Clear the recent files (1), positions, and recovery files (1)? (y)es, (n)o: "
        answer app, 'n'
        history.recent.size.should eq 1
        Dir.children(autosave_dir).size.should eq 1
        entry.trigger
        answer app, 'y'
        history.recent.should be_empty
        Dir.children(autosave_dir).should be_empty
        notice(app).should eq " Cleared 1 recent file, 1 recovery file"
      end
    end
  end

  it "empties the log file Crysterm writes instead of removing it, and runs without a history" do
    with_xdg_dirs do |_, cache_dir, _|
      Dir.mkdir_p cache_dir
      log = File.join(cache_dir, "md.log")
      File.write log, "lines\n"
      File.write File.join(cache_dir, "other"), "x"
      previous = Crysterm::Config.log_file
      Crysterm::Config.set "log.file", log
      begin
        with_app do |app|
          app.history.should be_nil
          app.clear_caches.should eq({0, 0})
          File.read(log).should eq ""
          Dir.children(cache_dir).should eq ["md.log"]
        end
      ensure
        Crysterm::Config.set "log.file", previous
      end
    end
  end
end
