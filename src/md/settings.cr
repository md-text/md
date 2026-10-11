require "json"

module Md
  # The user's choices kept across runs — the View and Options menu settings
  # and the pane sizes today, a theme and the like tomorrow — the way Qt's `QSettings` keeps
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

    # The settings md keeps today, each a typed pair of accessors over its
    # key — `sync_cursor?`/`sync_cursor=` for a `Bool`, `theme`/`theme=`
    # for anything else — so a caller reads a choice by name and type. A
    # setting without a stored value reads as nil, so the caller's own
    # default stands and is not spelled twice. An enum is stored by its
    # member's name (`"insert"`, `"dark"`) and reads as nil once md no longer
    # knows the name.
    private macro setting(name, type)
      def {{ name.id }}{{ (type.stringify == "Bool" ? "?" : "").id }} : {{ type }}?
        get? {{ name.id.stringify }}, {{ type }}
      end

      def {{ name.id }}=(value : {{ type }}) : Nil
        set {{ name.id.stringify }}, value
      end
    end

    # View → Sync Cursor, Highlight Line, Line Numbers, Soft Wrap, Text
    # Width (in columns; 0 is no cap) and Center Text.
    setting sync_cursor, Bool
    setting highlight_line, Bool
    setting line_numbers, Bool
    setting soft_wrap, Bool
    setting text_width, Int32
    setting center_text, Bool
    # Options → Ask Before Discarding Changes, Auto-Save, Keep a Backup File,
    # Mouse, Theme (as `--colors-theme` spells it) and Clipboard.
    setting confirm_discard, Bool
    setting autosave, Bool
    setting backup_file, Bool
    setting mouse_mode, App::MouseMode
    setting theme, App::Theme
    setting clipboard_mode, App::ClipboardMode
    # The panes' widths in cells as the splitter wants them
    # (`App#pane_sizes`): `[editor, viewer, toc]`, 0 for a pane never resized.
    setting pane_sizes, Array(Int32)

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
