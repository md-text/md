require "json"

module Md
  # The user's choices kept across runs — the View and Options menu settings
  # today, pane sizes and the like tomorrow — the way Qt's `QSettings` keeps
  # an application's: a flat map of named values behind typed accessors,
  # loaded at start, written at exit.
  #
  # The map lives in a small JSON file. Values are stored as the JSON they
  # serialize to, so a key can hold anything `to_json`/`from_json` round-trip
  # (`Bool`, numbers, strings, enums by their member name, arrays of those),
  # and `#get` asks for them back by type with a default for a key that is
  # missing or holds something else. Keys this version of md does not know
  # are carried from load to save untouched, so an older md does not shed a
  # newer one's settings. Every method tolerates a missing or broken file:
  # settings never get in the way of opening a document.
  class Settings
    # The on-disk format; a file with another `version` is ignored so that an
    # incompatible future layout starts afresh instead of half-loading. New
    # keys are not a new layout: they simply appear.
    VERSION = 1

    # The file as stored: a version stamp around the map.
    private struct Document
      include JSON::Serializable

      getter version : Int32
      getter settings : Hash(String, JSON::Any)

      def initialize(@version, @settings)
      end
    end

    getter path : String

    # `$XDG_CONFIG_HOME/md/settings.json`, which by the XDG spec defaults to
    # `~/.config/md/settings.json`; config, not state, because it holds the
    # user's choices (where `QSettings` writes on Unix too).
    def self.default_path : String
      config = ENV["XDG_CONFIG_HOME"]?.presence || Path.home.join(".config").to_s
      Path[config].join("md", "settings.json").to_s
    end

    # Loads the settings kept at *path*. A missing, unreadable or malformed
    # file yields the defaults rather than an error: losing a few choices is
    # a nuisance, failing to start would be a bug.
    def self.load(path : String = default_path) : Settings
      document = Document.from_json(File.read(path))
      values = document.version == VERSION ? document.settings : {} of String => JSON::Any
      new(path, values)
    rescue IO::Error | JSON::Error
      new(path)
    end

    def initialize(@path : String, @values = {} of String => JSON::Any)
      @dirty = false
    end

    # The value stored under *key* read as a *type*, or nil when the key is
    # unset or its value does not read as one (a `QSettings::value` that
    # came back invalid): `get?("wrap_width", Int32)`.
    def get?(key : String, type : T.class) : T? forall T
      return unless any = @values[key]?
      T.from_json(any.to_json)
    rescue JSON::ParseException
      nil
    end

    # The value stored under *key*, or *default* when there is none to read
    # (`QSettings::value` with a default). *T* is the default's type, so
    # `get("wrap_width", 80)` is an `Int32` and `get("mouse_mode",
    # MouseMode::All)` a `MouseMode`.
    def get(key : String, default : T) : T forall T
      value = get?(key, T)
      value.nil? ? default : value
    end

    # Stores *value* under *key* (`QSettings::setValue`), replacing what was
    # there; storing what is already there changes nothing, so the file is
    # not rewritten for it.
    def set(key : String, value) : Nil
      any = JSON.parse(value.to_json)
      return if @values[key]? == any
      @values[key] = any
      @dirty = true
    end

    # Whether *key* has a stored value (`QSettings::contains`).
    def has_key?(key : String) : Bool
      @values.has_key? key
    end

    # Forgets *key*, so `#get` falls back to its default again
    # (`QSettings::remove`). Returns whether it was set.
    def remove(key : String) : Bool
      return false unless @values.has_key? key
      @values.delete key
      @dirty = true
      true
    end

    # Every stored key (`QSettings::allKeys`), the unknown ones included.
    def keys : Array(String)
      @values.keys
    end

    # View → Follow cursor. The named accessors are the settings md keeps
    # today; a setting without a stored value reads as nil, so the caller's
    # own default stands and is not spelled twice.
    def follow_cursor? : Bool?
      get? "follow_cursor", Bool
    end

    def follow_cursor=(value : Bool) : Nil
      set "follow_cursor", value
    end

    # View → Highlight line.
    def highlight_line? : Bool?
      get? "highlight_line", Bool
    end

    def highlight_line=(value : Bool) : Nil
      set "highlight_line", value
    end

    # View → Line numbers.
    def line_numbers? : Bool?
      get? "line_numbers", Bool
    end

    def line_numbers=(value : Bool) : Nil
      set "line_numbers", value
    end

    # Options → Ask before discarding changes.
    def confirm_discard? : Bool?
      get? "confirm_discard", Bool
    end

    def confirm_discard=(value : Bool) : Nil
      set "confirm_discard", value
    end

    # Options → Auto-save.
    def autosave? : Bool?
      get? "autosave", Bool
    end

    def autosave=(value : Bool) : Nil
      set "autosave", value
    end

    # Options → Keep a backup file.
    def backup_file? : Bool?
      get? "backup_file", Bool
    end

    def backup_file=(value : Bool) : Nil
      set "backup_file", value
    end

    # Options → Mouse, stored by the mode's name (`"all"`, `"normal"`,
    # `"insert"`, `"off"`); a name md no longer knows reads as nil.
    def mouse_mode : App::MouseMode?
      get? "mouse_mode", App::MouseMode
    end

    def mouse_mode=(mode : App::MouseMode) : Nil
      set "mouse_mode", mode
    end

    # Options → Theme, stored by the theme's name (`"terminal"`, `"dark"`,
    # `"light"`), as `--colors-theme` spells it.
    def theme : App::Theme?
      get? "theme", App::Theme
    end

    def theme=(theme : App::Theme) : Nil
      set "theme", theme
    end

    # View → Soft wrap.
    def soft_wrap? : Bool?
      get? "soft_wrap", Bool
    end

    def soft_wrap=(value : Bool) : Nil
      set "soft_wrap", value
    end

    # View → Text width, in columns; 0 is no cap.
    def text_width : Int32?
      get? "text_width", Int32
    end

    def text_width=(value : Int32) : Nil
      set "text_width", value
    end

    # View → Center text.
    def center_text? : Bool?
      get? "center_text", Bool
    end

    def center_text=(value : Bool) : Nil
      set "center_text", value
    end

    # Writes the map to `path`, creating the directory as needed
    # (`QSettings::sync`). The file is written beside its final name and
    # renamed over it so a crash mid-write leaves the previous settings
    # intact. Returns false instead of raising when the directory cannot be
    # made or the file cannot be written: settings are not worth an error
    # dialog.
    def save : Bool
      Dir.mkdir_p(File.dirname(@path))
      temp = "#{@path}.#{Process.pid}.tmp"
      begin
        File.write(temp, Document.new(VERSION, @values).to_pretty_json)
        File.rename(temp, @path)
      rescue IO::Error
        File.delete?(temp)
        return false
      end
      @dirty = false
      true
    rescue IO::Error
      false
    end

    # Whether anything changed since the settings were loaded or last saved,
    # so a caller can skip the write on a quiet exit.
    def dirty? : Bool
      @dirty
    end
  end
end
