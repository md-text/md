require "json"

module Md
  # The recently opened files and where the user was in each, kept across
  # runs (like vim's viminfo or less's history) for the File → Open Recent
  # menu and for landing on the remembered position when a file is reopened.
  #
  # The list lives in a small JSON file; every method tolerates a missing or
  # broken file so that history never gets in the way of opening a document.
  #
  # A file is known by its canonical key (`Documents.key_for`, Qt's
  # `QFileInfo::canonicalFilePath`, which Qt Creator's recent files use
  # too), so a file opened through a symlink and through its real path —
  # or by another case of its name on a case-insensitive volume — is one
  # entry with one position. The entry shows the path as the user last
  # opened it.
  class History
    # One remembered file: its absolute *path* as last opened (what File →
    # Open Recent shows and opens), the 1-based caret *line* and *column* in
    # the Markdown source, whether the *viewing* pane (rather than the
    # editor) was focused, when it was last touched (UTC), and the file's
    # canonical *key* (`Documents.key_for`) — nil only in a file written
    # before keys were kept, which `History` fills in as it loads.
    record Entry,
      path : String,
      line : Int32,
      column : Int32,
      viewing : Bool,
      at : Time,
      key : String? = nil do
      include JSON::Serializable

      # The key the entry is matched by: the one recorded, or else the
      # path's own.
      def canonical : String
        key || Documents.key_for(path)
      end
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

    # A history kept at *path* holding *entries*, most recent first. An
    # entry without a key (a file written before keys were kept) gets its
    # path's, and entries that turn out to be one file merge, the most
    # recently touched winning; the history is then dirty, so the next save
    # writes the file migrated.
    def initialize(@path : String, entries = [] of Entry)
      @entries = History.merge(entries)
      @dirty = @entries.size != entries.size || entries.any?(&.key.nil?)
    end

    # *entries* with a key each, one per key: the most recently touched entry
    # of a key stays, in its place among the others (most recent first).
    protected def self.merge(entries : Array(Entry)) : Array(Entry)
      keyed = entries.map { |entry| entry.key ? entry : entry.copy_with(key: entry.canonical) }
      latest = {} of String => Int32
      keyed.each_with_index do |entry, index|
        held = latest[entry.canonical]?
        latest[entry.canonical] = index if held.nil? || entry.at > keyed[held].at
      end
      latest.values.sort!.map { |index| keyed[index] }
    end

    # The remembered files, most recent first.
    def recent : Array(Entry)
      @entries.dup
    end

    # The entry for *path*, reached by any path to the same file — another
    # spelling, a symlink, another case on a case-insensitive volume — or
    # nil when it was never opened (or has been forgotten).
    def entry(path : String) : Entry?
      key, absolute = Documents.key_for(path), File.expand_path(path)
      @entries.find { |entry| same?(entry, key, absolute) }
    end

    # Records that *path* was open at *line*/*column* with the *viewing* pane
    # focused, moving it to the front and letting the oldest entry fall off
    # beyond `MAX`. The file's entry is found by its key, so the same file
    # reached through another path is one entry, which now shows *path*
    # (made absolute), the way it was opened this time.
    def touch(path : String, line : Int32, column : Int32, viewing : Bool, at : Time = Time.utc) : Entry
      absolute = File.expand_path(path)
      entry = Entry.new(absolute, line, column, viewing, at, Documents.key_for(absolute))
      @entries.reject! { |other| same?(other, entry.canonical, absolute) }
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
      key, absolute = Documents.key_for(path), File.expand_path(path)
      before = @entries.size
      @entries.reject! { |entry| same?(entry, key, absolute) }
      removed = @entries.size != before
      @dirty = true if removed
      removed
    end

    # Whether *entry* is the file of *key*, or was opened as *absolute* (a
    # file gone since, whose key, now its directory's, may no longer be the
    # one recorded).
    private def same?(entry : Entry, key : String, absolute : String) : Bool
      entry.canonical == key || entry.path == absolute
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
