require "json"

module Md
  # The recently opened files and where the user was in each, kept across
  # runs (like vim's viminfo or less's history) for the File → Open Recent
  # menu and for landing on the remembered position when a file is reopened.
  #
  # The list lives in a small JSON file; every method tolerates a missing or
  # broken file so that history never gets in the way of opening a document.
  class History
    # One remembered file: its absolute *path*, the 1-based caret *line* and
    # *column* in the Markdown source, whether the *viewing* pane (rather than
    # the editor) was focused, and when it was last touched (UTC).
    record Entry,
      path : String,
      line : Int32,
      column : Int32,
      viewing : Bool,
      at : Time do
      include JSON::Serializable
    end

    # How many files are remembered; older ones fall off the end.
    MAX = 20

    # The on-disk format; a file with another `version` is ignored so that an
    # incompatible future layout starts afresh instead of half-loading.
    VERSION = 1

    # The file as stored: a version stamp around the list.
    private struct Document
      include JSON::Serializable

      getter version : Int32
      getter recent : Array(Entry)

      def initialize(@version, @recent)
      end
    end

    getter path : String

    # md's state directory, `$XDG_STATE_HOME/md`, which by the XDG spec
    # defaults to `~/.local/state/md`: for what the program writes rather
    # than the user — the history, and the auto-save recovery files
    # (`App.autosave_dir`).
    def self.state_dir : String
      state = ENV["XDG_STATE_HOME"]?.presence || Path.home.join(".local", "state").to_s
      Path[state].join("md").to_s
    end

    # `$XDG_STATE_HOME/md/history.json` (`~/.local/state/md/history.json`);
    # state, not config, because it is written by the program rather than
    # the user.
    def self.default_path : String
      File.join state_dir, "history.json"
    end

    # Loads the history kept at *path*. A missing, unreadable or malformed
    # file yields an empty history rather than an error: losing the recent
    # list is a nuisance, failing to start would be a bug.
    def self.load(path : String = default_path) : History
      document = Document.from_json(File.read(path))
      entries = document.version == VERSION ? document.recent : [] of Entry
      new(path, entries)
    rescue IO::Error | JSON::Error | Time::Format::Error
      new(path)
    end

    def initialize(@path : String, @entries = [] of Entry)
      @dirty = false
    end

    # The remembered files, most recent first.
    def recent : Array(Entry)
      @entries.dup
    end

    # The entry for *path*, spelled any way that expands to the same absolute
    # path, or nil when it was never opened (or has been forgotten).
    def entry(path : String) : Entry?
      absolute = File.expand_path(path)
      @entries.find { |entry| entry.path == absolute }
    end

    # Records that *path* was open at *line*/*column* with the *viewing* pane
    # focused, moving it to the front and letting the oldest entry fall off
    # beyond `MAX`. The path is made absolute so the same file reached from
    # different directories is one entry.
    def touch(path : String, line : Int32, column : Int32, viewing : Bool, at : Time = Time.utc) : Entry
      entry = Entry.new(File.expand_path(path), line, column, viewing, at)
      @entries.reject! { |other| other.path == entry.path }
      @entries.unshift(entry)
      @entries.pop(@entries.size - MAX) if @entries.size > MAX
      @dirty = true
      entry
    end

    # Forgets every file (Options → Clear Caches…). Returns how many there
    # were; forgetting none changes nothing.
    def clear : Int32
      count = @entries.size
      return 0 if count == 0
      @entries.clear
      @dirty = true
      count
    end

    # Drops *path* from the list, for a file that is gone or that the user
    # removed from the menu. Returns whether it was there.
    def forget(path : String) : Bool
      absolute = File.expand_path(path)
      before = @entries.size
      @entries.reject! { |entry| entry.path == absolute }
      removed = @entries.size != before
      @dirty = true if removed
      removed
    end

    # Writes the list to `path`, creating the directory as needed. The file
    # is written whole (`SaveFile`) so a crash mid-write leaves the previous
    # history intact. Returns false instead of raising when the directory
    # cannot be made or the file cannot be written: history is not worth an
    # error dialog.
    def save : Bool
      Dir.mkdir_p(File.dirname(@path))
      SaveFile.write(@path, Document.new(VERSION, @entries).to_pretty_json)
      @dirty = false
      true
    rescue IO::Error
      false
    end

    # Whether anything changed since the history was loaded or last saved,
    # so a caller can skip the write on a quiet exit.
    def dirty? : Bool
      @dirty
    end
  end
end
