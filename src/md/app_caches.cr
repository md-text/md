require "file_utils"

module Md
  class App
    # Options → Clear Caches…: what md keeps for itself between runs, as
    # opposed to the user's choices (`Settings`, which stay) — the history
    # of recent files and positions (`History`, File → Open Recent), the
    # auto-save recovery files (`App.autosave_dir`) and the cache
    # directory (`App.cache_dir`), where Crysterm's log goes while md runs
    # (`CLI.log_to_file`) — emptied in one go, after a question. Qt-world
    # applications offer "Clear Recent Files" or "Clear History"; this one
    # goes further, so it says so, with an ellipsis, and asks first
    # (`#ask_choice`, `app_dialogs.cr`).
    #
    # The current document's recovery file goes with the others: it is
    # written again at the next auto-save tick while the document is
    # modified, so nothing is lost that is not in the editor. The log file
    # is emptied rather than removed, since Crysterm holds it open (in
    # append mode, so later lines land in the emptied file); anything else
    # in the cache directory is removed. Only md's own directories are
    # touched: a log sent elsewhere (`CRYSTERM_LOG_FILE`) is left alone,
    # and so is the history of a run that keeps none (specs).

    # md's cache directory, `$XDG_CACHE_HOME/md` (`~/.cache/md`): the log
    # file's home, as `Crysterm.default_log_file` places it.
    def self.cache_dir : String
      cache = ENV["XDG_CACHE_HOME"]?.presence || Path.home.join(".cache").to_s
      Path[cache].join("md").to_s
    end

    # Options → Clear Caches…: asks, then clears (`#clear_caches`).
    def clear_caches_prompt : Nil
      ask_choice("Clear the recent files, positions and recovery files?", [{"Clear", "(y)es"}, {"Cancel", "(n)o"}]) do |index|
        clear_caches if index == 0
      end
    end

    # Clears the caches (see the class comment), refreshes File → Open
    # Recent and says what went: "Cleared 12 recent files, 3 recovery
    # files". Returns the two counts. The history is written at once, so
    # a run that ends badly does not bring the list back.
    def clear_caches : {Int32, Int32}
      recent = 0
      if history = @history
        recent = history.clear
        history.save
      end
      recovery = remove_entries App.autosave_dir
      # The document's own copy went with the rest: forgotten here, so it
      # is written afresh, which the next tick does, finding the document
      # edited since its last write.
      drop_recovery
      @autosave_dirty = true
      remove_entries App.cache_dir, empty: Crysterm::Config.log_file
      refresh_recent_menu
      notice "Cleared #{recent} recent file#{"s" unless recent == 1}, #{recovery} recovery file#{"s" unless recovery == 1}"
      {recent, recovery}
    end

    # Removes what is in *dir*, if it exists, and returns how many entries
    # went; the file named by *empty* is emptied instead of removed. Each
    # entry is tried on its own: one that will not go does not stop the
    # rest, and is not counted.
    private def remove_entries(dir : String, empty : String? = nil) : Int32
      return 0 unless Dir.exists? dir
      count = 0
      Dir.each_child(dir) do |child|
        path = File.join(dir, child)
        begin
          if path == empty
            File.write path, ""
          else
            FileUtils.rm_rf path
          end
          count += 1
        rescue IO::Error
          # Left for the next time.
        end
      end
      count
    rescue IO::Error
      count || 0
    end
  end
end
