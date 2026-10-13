require "file_utils"

module Md
  class App
    # Options → Clear Caches…: what md keeps for itself between runs, as
    # opposed to the user's choices (the config file, which stays) — the history
    # of recent files and positions (`History`, File → Open Recent), the
    # auto-save recovery files (`App.autosave_dir`), the windows'
    # remembered positions (`WindowPlaces`) and the cache
    # directory (`App.cache_dir`), where Crysterm's log goes while md runs
    # (`CLI.log_to_file`) — emptied in one go, after a question. Qt-world
    # applications offer "Clear Recent Files" or "Clear History"; this one
    # goes further, so it says so, with an ellipsis, and asks first
    # (`#ask_choice`, `app_dialogs.cr`).
    #
    # The open documents' recovery files go with the others: each is
    # written again at its next auto-save tick while its document is
    # modified, so nothing is lost that is not in an editor. The log file
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

    # Options → Clear Caches…: asks, with how many recent files, positions
    # (a recent file's place other than its start) and recovery files there
    # are — each count given, a `(0)` included — then clears (`#clear_caches`).
    def clear_caches_prompt : Nil
      entries = @history.try(&.recent) || [] of History::Entry
      positions = entries.count { |e| e.line > 1 || e.column > 1 }
      recovery = Dir.exists?(App.autosave_dir) ? Dir.children(App.autosave_dir).size : 0
      ask_choice("Clear the recent files (#{entries.size}), positions (#{positions}), and recovery files (#{recovery})?", [{"Clear", "(y)es"}, {"Cancel", "(n)o"}]) do |index|
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
      # The open documents' own copies — this window's and every other
      # window's — went with the rest: forgotten, so each is written
      # afresh, which its next tick does, finding the document edited since
      # its last write.
      Documents.all.each do |doc|
        doc.drop_recovery
        doc.mark_for_autosave
      end
      forget_window_places
      remove_entries App.cache_dir, empty: Crysterm::Config.log_file
      refresh_recent_menu
      notice "Cleared #{recent} recent file#{"s" unless recent == 1}, #{recovery} recovery file#{"s" unless recovery == 1}"
      {recent, recovery}
    end

    # Removes the windows' remembered positions (Window → Remember
    # Positions): the file, and the process's store when it is that file's.
    private def forget_window_places : Nil
      path = WindowPlaces.default_path
      File.delete? path
      WindowPlaces.shared.clear if WindowPlaces.shared.path == path
    rescue IO::Error
      # A file that will not go is left; its positions are only a nicety.
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
