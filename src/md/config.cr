require "crysterm"
require "yaml"

# The Edit, Format, View and Options menu choices as configuration options, in Crysterm's
# registry (`Crysterm::Config`, which is the Superconf shard): each is a
# `md.<name>` key in the config file, an `MD_<NAME>` environment variable, a
# `--md-<name>` command-line option and a typed accessor
# (`Crysterm::Config.md_sync_cursor`), beside Crysterm's own options — the
# theme (`colors.theme`) and the media backend (`media.backend`) are two the
# menus also offer. The registration is the one place a choice is declared;
# `Md::Config` below loads and saves them, and the `App` keeps its menu
# entries in step with them (`app_config.cr`).
#
# Watch File and Overwrite Mode are not here: the first is per run, as
# `--watch` is, the second is the editor's state.
module Superconf
  # Edit.
  option "md.vi_mode", false, env: "MD_VI_MODE",
    description: "Edit → Vi Mode (Neovim): edit the editor's text as in Neovim, by an embedded nvim; the function keys and Alt combinations stay md's"
  # Format.
  option "md.soft_wrap", true, env: "MD_SOFT_WRAP",
    description: "Format → Soft Wrap: fold a long line at the editor's edge instead of scrolling sideways"
  option "md.hard_wrap", false, env: "MD_HARD_WRAP",
    description: "Format → Hard Wrap: break a line being typed at the text width (80 columns without one)"
  option "md.text_width", 0, env: "MD_TEXT_WIDTH",
    description: "Format → Text Width: the most columns the text is laid out in, in both panes; 0 is the pane's width",
    validate: ->(n : Int32) { n >= 0 }
  # View.
  option "md.sync_cursor", false, env: "MD_SYNC_CURSOR",
    description: "View → Sync Cursor: keep the editor's and the viewer's carets on the same place in the document"
  option "md.highlight_line", false, env: "MD_HIGHLIGHT_LINE",
    description: "View → Highlight Line: tint the caret's row in both panes"
  option "md.line_numbers", false, env: "MD_LINE_NUMBERS",
    description: "View → Line Numbers → Editor: number the editor's source lines in a gutter"
  option "md.viewer_line_numbers", false, env: "MD_VIEWER_LINE_NUMBERS",
    description: "View → Line Numbers → Viewer: number the viewer's rendered rows in a gutter, from 1, apart from the source lines"
  option "md.center_text", true, env: "MD_CENTER_TEXT",
    description: "View → Center Document: center a capped text column in a wider pane rather than keep it at the left"
  option "md.horizontal_ruler", false, env: "MD_HORIZONTAL_RULER",
    description: "View → Rulers → Horizontal: a column ruler along the top of each pane"
  option "md.vertical_ruler", false, env: "MD_VERTICAL_RULER",
    description: "View → Rulers → Vertical: a row ruler down the left of each pane"
  option "md.guides", false, env: "MD_GUIDES",
    description: "View → Guides: guide lines at the text's edges, and wherever one is pulled off the column ruler"
  option "md.bars", true, env: "MD_BARS",
    description: "View → Menu and Status Bars: show the menu bar and the status bar (F4 hides and shows them together)"
  option "md.images", true, env: "MD_IMAGES",
    description: "View → Images: draw the document's images in the viewer with the Media Backend, above the row with the picture glyph and the alt text"
  option "md.link_double_click", false, env: "MD_LINK_DOUBLE_CLICK",
    description: "View → Terminal Links → Double-click to Open: follow a link in the viewer on a double click rather than a single one"
  option "md.dialog_style", Md::App::DialogStyle::LinePrompt, env: "MD_DIALOG_STYLE",
    description: "View → Dialog Style: how a question is asked, in place of the status bar (line_prompt) or in a dialog (modal)"
  option "md.tooltips", Md::App::Tooltips::StatusBar, env: "MD_TOOLTIPS",
    description: "View → Tooltips: where a menu entry's description shows while it is highlighted — in the status bar (status_bar), in a popup beside the entry after a moment (popup), or nowhere (off)"
  # Options.
  option "md.vi_config", false, env: "MD_VI_CONFIG",
    description: "Options → Vi Mode: Use Neovim Config: start Vi Mode's nvim with your own config and plugins rather than --clean"
  option "md.confirm_discard", true, env: "MD_CONFIRM_DISCARD",
    description: "Options → Ask Before Discarding Changes: ask what to do with unsaved changes before they would be lost"
  option "md.autosave", true, env: "MD_AUTOSAVE",
    description: "Options → Auto-Save: write unsaved edits to a recovery file every 30 seconds"
  option "md.backup_file", true, env: "MD_BACKUP_FILE",
    description: "Options → Keep a Backup File: keep a file's previous contents as FILE~ at the session's first save of it"
  option "md.mouse_mode", Md::App::MouseMode::All, env: "MD_MOUSE_MODE",
    description: "Options → Mouse: when the mouse serves md, after vi's mouse option (all|normal|insert|off); off leaves it to the terminal"
  option "md.clipboard_mode", Md::App::ClipboardMode::Terminal, env: "MD_CLIPBOARD_MODE",
    description: "Options → Clipboard: where a copy goes and a paste comes from (terminal|command|internal)"
  option "md.resizable_panes", true, env: "MD_RESIZABLE_PANES",
    description: "Options → Resizable Panes: let the dividers between the panes move"
  # The panes.
  option "md.pane_sizes", "", env: "MD_PANE_SIZES",
    description: "The widths in columns of the editor, the viewer and the table of contents, comma-separated (0 for a pane never resized), as the dividers left them; recorded when md quits"

  # md is the registry's application: its config file is the registry's
  # default one (`default_config_path`), which the toolkit's help names;
  # Crysterm's own file (`~/.config/crysterm/config.yml`) is read before it
  # (`Md::Config.configure`). The environment variables keep Crysterm's
  # `CRYSTERM_` prefix, as a toolkit's do (Qt's `QT_*`), while md's options
  # name their own `MD_*` variables above.
  self.app_name = "md"
end

module Md
  # md's configuration: the options above and Crysterm's, loaded at start and
  # kept in the config file, the way `QSettings` keeps an application's
  # choices — except that the file is one every option can be given in, and
  # the same options take an environment variable and a command-line flag.
  #
  # The file is `$XDG_CONFIG_HOME/md/config.yml` (`~/.config/md/config.yml`),
  # YAML with one mapping per option group, as `--crysterm-dump-config` prints
  # it; a JSON file reads too. Precedence, low to high: Crysterm's own file
  # (`~/.config/crysterm/config.yml`, for every program built on it), md's
  # file, the environment, the command line, then what is picked while md
  # runs — all read by `.configure`, since Crysterm's own reading of them as
  # it loads is turned off (`src/bin/md.cr`): it would run before md's options
  # exist and before an error could be reported as anything but a backtrace. A
  # pick from a menu is recorded at once in the option (`App`'s properties
  # are linked to the options, `app_config.cr`); the file is written when md
  # quits, if anything changed, and by Options → Save Config.
  #
  # What the file gets (`.save`): every option picked during the run, every
  # option the file itself had set, and — carried over as they were — the
  # file's entries an environment variable or a command-line flag outranked
  # this run (`--colors-theme dark` wins for the run, the stored theme stays
  # stored) and the entries md does not know (an older md keeps a newer one's
  # settings). Nothing else: an option Crysterm's file, a variable or a flag
  # set is theirs to keep setting, and a default stays a default, so a change
  # of default in a later version reaches a user who never chose otherwise.
  #
  # Options → Load Config… (`.load_file`) applies a file now, at the
  # precedence of a pick: its values replace what a variable or a flag set,
  # as the user asked for them, and are recorded as picks.
  module Config
    # The Crysterm options md's menus offer — the theme, the media backend,
    # the color depth, the terminal links, reduced motion (No Animations) and detachable
    # menus — which `.reset` puts back with the `md.*` options (specs).
    CRYSTERM_KEYS = ["colors.theme", "media.backend", "colors.depth", "render.hyperlinks", "render.reduced_motion", "menu.tear_off"]

    # Whether any option changed since the last load at start or save to
    # the config file, so a quiet exit skips the write.
    class_getter? dirty : Bool = false

    # What md's config file said when it was loaded, by dotted key: the
    # scalars, carried over by `.save` where the option they name is
    # outranked for this run or unknown.
    @@document = {} of String => YAML::Any

    # Whether the options are watched for `dirty?` yet.
    @@watching = false

    # The config file: `$XDG_CONFIG_HOME/md/config.yml`, by the XDG spec
    # `~/.config/md/config.yml` when the variable is unset — Superconf's own
    # default, md being the registry's application.
    def self.path : String
      Superconf.default_config_path
    end

    # Crysterm's own config file, `$XDG_CONFIG_HOME/crysterm/config.yml`
    # (`~/.config/crysterm/config.yml`): the one every program built on
    # Crysterm reads, below its own.
    def self.toolkit_path : String
      Superconf.default_config_path "crysterm"
    end

    # Loads the configuration for the run, lowest precedence first: Crysterm's
    # own file (`.toolkit_path`) when it exists, *file* (`.path` by default)
    # when it exists, then the environment, then *argv*. A
    # `--crysterm-dump-config` among *argv* prints every option, md's
    # included, and exits. A file that cannot be read or parsed, or a value
    # that does not fit its option — in a file, a variable or a flag — is an
    # `Error` saying which (Superconf names the source): md does not start on
    # a broken configuration, it says what is wrong.
    def self.configure(file : String = path, argv : Array(String) = ARGV) : Nil
      @@document.clear
      toolkit = toolkit_path
      Superconf.load_file toolkit if File.exists?(toolkit)
      # md's file is read and parsed once: Superconf applies the document
      # at file precedence, under the name `Superconf.load_file` gives a
      # file, and the same document is kept as the file's own entries, for
      # `.save`.
      origin = "config file #{file}"
      if text = read(file)
        document = Superconf.parse_yaml text, origin
        Superconf.load_yaml document, origin
        @@document = flatten(document)
      end
      Crysterm.configure!("", argv: argv)
      # Superconf stamps a file's values "config file PATH (KEY)"; with no
      # file of md's, nothing matches, Crysterm's own file's values included.
      @@origin = text ? "#{origin} (" : ""
      watch
      @@dirty = false
    rescue ex : Superconf::Error
      raise Error.new(ex.message)
    end

    # The text of the config file *file*, or nil when there is none; a file
    # that is there but cannot be read (a directory, no permission) is an
    # `Error` naming it, as `Superconf.load_file` names it.
    private def self.read(file : String) : String?
      File.read file
    rescue File::NotFoundError
      nil
    rescue ex : IO::Error
      raise Error.new("cannot read config file #{file}: #{ex.message}")
    end

    # What Superconf stamps on a value from the file `.configure` loaded, up
    # to the key: empty when there was no file.
    @@origin = ""

    # Applies *file* now (Options → Load Config…), at the precedence of a
    # pick: see the module comment. Raises `Error` for a file that cannot
    # be read or parsed, or a value that does not fit.
    def self.load_file(file : String) : Nil
      Superconf.load_file file, Superconf::Source::Runtime
    rescue ex : Superconf::Error
      raise Error.new(ex.message)
    end

    # Writes the settings to *file* (`.path` by default; see the module
    # comment for what goes in), creating the directory as needed. The text
    # is written beside the file and renamed over it, so a crash mid-write
    # leaves the previous file intact. Returns false instead of raising when
    # the directory cannot be made or the file not written: at exit there is
    # no one left to tell, and the menu entry gives a notice.
    def self.save(file : String = path) : Bool
      text = render
      Dir.mkdir_p File.dirname(file)
      temp = "#{file}.#{Process.pid}.tmp"
      begin
        File.write temp, text
        File.rename temp, file
      rescue IO::Error
        File.delete? temp
        return false
      end
      @@dirty = false if file == path
      true
    rescue IO::Error
      false
    end

    # The settings as the file holds them: a comment saying where they come
    # from, then the options by group, keys sorted, each value emitted as
    # Superconf dumps it (a string or an enum quoted, so `yes` or `123` reads
    # back as the text it is), or as the file had it for an entry carried
    # over.
    def self.render : String
      values = {} of String => Superconf::AbstractOption | YAML::Any
      @@document.each do |key, any|
        option = Superconf[key]?
        values[key] = any if option.nil? || option.source.env? || option.source.command_line?
      end
      Superconf.each do |option|
        next if option.alias_target
        values[option.key] = option if saved?(option)
      end
      String.build do |io|
        io << "# md's settings: the Edit, Format, View and Options menu choices, written when md quits\n"
        io << "# and by Options → Save Config. Each entry is also a --<group>-<name>\n"
        io << "# option and an MD_* or CRYSTERM_* variable; md --help --verbose lists them.\n"
        io << YAML.build { |yaml| emit values, yaml }
      end
    end

    # Puts every `md.*` option and the Crysterm options the menus offer back
    # to its default and forgets the loaded file, for a spec to start clean.
    def self.reset : Nil
      Superconf.each { |option| Superconf.reset option.key if option.key.starts_with?("md.") }
      CRYSTERM_KEYS.each { |key| Superconf.reset key }
      @@document.clear
      @@origin = ""
      @@dirty = false
    end

    # The `md.*` options, in registration order — the settings section of
    # the help and the man page.
    def self.options : Array(Superconf::AbstractOption)
      found = [] of Superconf::AbstractOption
      Superconf.each { |option| found << option if option.key.starts_with?("md.") }
      found
    end

    # The settings listed as `OptionParser` prints options, for `--help
    # --verbose`: each `md.*` option's flag (a boolean's `--no-` negation
    # too) with its description and default, under a banner saying where
    # else it can be set.
    def self.help : String
      banner = <<-BANNER
        Settings: the Edit, Format, View and Options menu choices. Each can also be set in
        #{path.sub(Path.home.to_s, "~")} or by an MD_* environment variable; a pick in
        a menu is kept there (Options → Save Config).
        BANNER
      Crysterm.options_help banner, options
    end

    # The flags `.help` lists, which the toolkit's list leaves out.
    def self.flags : Array(String)
      options.flat_map { |option| option.bool? ? [option.cli, option.cli.sub("--", "--no-")] : [option.cli] }
    end

    # Whether *option* is written by `.save` as it is now: picked during the
    # run, or set by md's own file.
    private def self.saved?(option : Superconf::AbstractOption) : Bool
      case option.source
      in .runtime?                        then true
      in .config_file?                    then !@@origin.empty? && option.origin.starts_with?(@@origin)
      in .default?, .env?, .command_line? then false
      end
    end

    # Hears every option, for `dirty?`; once. A change at default precedence
    # is a change of default (`Superconf.set_default`: Crysterm's log file at
    # every start), not a pick, and `.save` writes no default: not dirt.
    private def self.watch : Nil
      return if @@watching
      @@watching = true
      Superconf.each do |option|
        next if option.alias_target
        option.on_change { @@dirty = true unless option.source.default? }
      end
    end

    # The scalars of a parsed config *document* by dotted key, nested
    # mappings flattened as Superconf reads them (`screen: {glyphs: ascii}`
    # is `screen.glyphs`).
    private def self.flatten(document : YAML::Any, prefix : String = "", into = {} of String => YAML::Any) : Hash(String, YAML::Any)
      if hash = document.as_h?
        hash.each do |key, value|
          name = key.as_s? || key.raw.to_s
          flatten value, prefix.empty? ? name : "#{prefix}.#{name}", into
        end
      elsif !prefix.empty?
        into[prefix] = document
      end
      into
    end

    # Emits *values* grouped by the key's first segment, as Superconf dumps
    # them: a key without a dot at the top, a group whose name a top-level key
    # takes flat.
    private def self.emit(values : Hash(String, Superconf::AbstractOption | YAML::Any), yaml : YAML::Builder) : Nil
      keys = values.keys.sort!
      top, dotted = keys.partition { |key| !key.includes?('.') }
      yaml.mapping do
        top.each do |key|
          yaml.scalar key
          emit_value values[key], yaml
        end
        dotted.group_by(&.split('.', 2).first).each do |group, members|
          if top.includes?(group)
            members.each do |key|
              yaml.scalar key
              emit_value values[key], yaml
            end
          else
            yaml.scalar group
            yaml.mapping do
              members.each do |key|
                yaml.scalar key.split('.', 2)[1]
                emit_value values[key], yaml
              end
            end
          end
        end
      end
    end

    private def self.emit_value(value : Superconf::AbstractOption | YAML::Any, yaml : YAML::Builder) : Nil
      case value
      in Superconf::AbstractOption then value.emit_yaml yaml
      in YAML::Any                 then emit_any value, yaml
      end
    end

    # Emits an entry carried over from the loaded file as it was: a string
    # quoted, as Superconf quotes one, so `yes` stays the text it was.
    private def self.emit_any(any : YAML::Any, yaml : YAML::Builder) : Nil
      case raw = any.raw
      when Hash
        yaml.mapping do
          raw.each do |key, value|
            emit_any key, yaml
            emit_any value, yaml
          end
        end
      when Array  then yaml.sequence { raw.each { |value| emit_any value, yaml } }
      when String then yaml.scalar raw, style: YAML::ScalarStyle::DOUBLE_QUOTED
      when Nil    then yaml.scalar "null"
      else             yaml.scalar raw.to_s
      end
    end
  end
end
