require "crysterm"
require "option_parser"
require "./source"
require "./export"
require "./manual"

module Md
  # Command-line front end: parses arguments and starts the application.
  module CLI
    # One command-line option: its flags, the name of its argument if it
    # takes one (and the values it accepts, when they are a fixed set) and
    # its description. `OPTIONS` is the one place these live: the parser,
    # the man page and the shell completions (`Manual`) are all built from
    # it, so they cannot drift apart. Descriptions carry their own line
    # breaks, which `--help` prints as they are; the generators join them.
    record Option,
      long : String,
      description : String,
      short : String? = nil,
      argument : String? = nil,
      values : Array(String)? = nil do
      # The flag as `OptionParser` registers it: `--line N`.
      def long_spec : String
        (arg = argument) ? "#{long} #{arg}" : long
      end

      # Likewise for the short flag: `-l N`.
      def short_spec : String?
        return unless s = short
        (arg = argument) ? "#{s} #{arg}" : s
      end

      # The description on one line.
      def text : String
        description.gsub('\n', ' ')
      end
    end

    OPTIONS = [
      Option.new("--version", "Print the version and exit", short: "-V"),
      Option.new("--help", "Show this help and exit", short: "-h"),
      Option.new("--verbose", "Be more verbose (with --help, also list the\nCrysterm toolkit options)", short: "-v"),
      Option.new("--watch", "Reload FILE as it changes on disk (View → Watch File)", short: "-w"),
      Option.new("--line", "Open on source line N, like +N (past the end,\nthe last line), instead of the remembered position", short: "-l", argument: "N"),
      Option.new("--view", "Open the viewer, even on a new FILE"),
      Option.new("--edit", "Open the editor, even on an existing FILE"),
      Option.new("--export", "Print FILE (or standard input) rendered as html\nor text, and exit", argument: "FORMAT", values: Export::FORMATS.to_a),
      Option.new("--to", "The same as --export (pandoc's spelling)", argument: "FORMAT", values: Export::FORMATS.to_a),
      Option.new("--generate", "Print the man page or a shell completion\nscript (man, bash, zsh, fish) and exit", argument: "WHAT", values: Manual::KINDS.to_a),
    ]

    # What the command line asked for; the option handlers fill it in
    # (`.parse`).
    class Options
      # The arguments that are not options: the file, or `-`.
      getter positional = [] of String
      property? help = false
      property? version = false
      property? verbose = false
      property? watch = false
      # The source line to open on (`+N`, `--line N`); without one, the
      # position remembered for the file is restored.
      property line : Int32?
      # `--view` (true) or `--edit` (false); without either, the `Source`
      # decides the pane.
      property view : Bool?
      # `--export FORMAT`: render to standard output instead of opening a
      # window (`Export`).
      property export : String?
      # `--generate WHAT`: print the man page or a completion script
      # (`Manual`) instead of opening a window.
      property generate : String?

      # Records *option*, given with *value* (empty for a flag): what each
      # entry of `OPTIONS` means. A value that does not fit is a usage error.
      def take(option : Option, value : String) : Nil
        case option.long
        when "--version"        then @version = true
        when "--help"           then @help = true
        when "--verbose"        then @verbose = true
        when "--watch"          then @watch = true
        when "--line"           then @line = CLI.line_number(value)
        when "--view"           then @view = pane_choice(true)
        when "--edit"           then @view = pane_choice(false)
        when "--export", "--to" then @export = Export.format(value)
        when "--generate"       then @generate = Manual.kind(value)
        else                         raise "no handler for #{option.long}"
        end
      end

      # The pane *view* asks for, unless the other one was already asked
      # for: `--view --edit` is a usage error, not a last-wins.
      private def pane_choice(view : Bool) : Bool
        raise ArgumentError.new("--view and --edit cannot be combined") if @view == !view
        view
      end
    end

    # The flags md itself owns. Crysterm's toolkit options (--colors-theme,
    # --colors-stylesheet, ...) are read from the arguments as given, by
    # `Config.configure` once the parser is done; `.parse` takes them out of
    # what it parses so they are neither reported as unknown nor mistaken
    # for a file, keeping these, which take precedence over a toolkit flag
    # of the same name.
    OWN_FLAGS = OPTIONS.flat_map { |option| [option.long, option.short].compact }.to_set

    # Runs the program with the given arguments and returns the process exit
    # status. `stdout`/`stderr`/`stdin` are injectable so that specs can
    # capture and feed them, and so is the *window* the app is built on (by
    # default a new one, on the terminal).
    def self.run(args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR, stdin : IO = STDIN, window : Crysterm::Window? = nil) : Int32
      run(args, stdout, stderr, stdin, window, &.run)
    end

    # The same, with the app, once built, handed to the block to run, which
    # returns the exit status: for a spec, in place of `App#run`'s loop on
    # the terminal. What the block raises escapes the app, as from `App#run`.
    def self.run(args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR, stdin : IO = STDIN, window : Crysterm::Window? = nil, & : App -> Int32) : Int32
      # A usage error is one of the command line's: once the window is built,
      # an `ArgumentError` is the app's own and is reported as such below.
      app = begin
        options = parse(args)
        stdout.puts "md #{VERSION}" if options.version?
        if options.help?
          stdout.puts help
          if options.verbose?
            # The settings first, as md's own, then the toolkit's without them.
            stdout.puts
            stdout.puts Config.help
            stdout.puts
            stdout.puts Crysterm.toolkit_options_help(except: OWN_FLAGS + Config.flags.to_set)
          end
        end
        return 0 if options.help? || options.version?
        if kind = options.generate
          stdout << Manual.generate(kind)
          return 0
        end
        if format = options.export
          return export(options.positional, format, stdin, stdout)
        end

        source = Source.resolve(options.positional, stdin.tty?)
        # Crysterm's config file and md's, the MD_*/CRYSTERM_* variables and
        # the toolkit and settings flags among *args*: for the window about to
        # open, so a `--help` or an `--export` reads none of it. A
        # `--crysterm-dump-config` prints every option and exits here; a value
        # that fits no option is an `Error`, reported below.
        Config.configure argv: args
        log_to_file
        launch(source, options, stdin, window)
      rescue ex : ArgumentError | OptionParser::Exception
        stderr.puts "md: #{ex.message}"
        stderr.puts help
        return 2
      end
      yield app
    rescue ex : Error
      stderr.puts "md: #{ex.message}"
      1
    rescue ex
      # An error that escaped the app: Crysterm restores the terminal before
      # `exec` raises it, so the report lands on the shell screen.
      stderr.puts "md: internal error: #{ex.inspect_with_backtrace}"
      1
    end

    # Parses *args* into `Options`. A usage error — an unknown option, a
    # value that is not a line number, `--view` together with `--edit` —
    # raises `ArgumentError`; a missing value raises
    # `OptionParser::MissingOption`.
    def self.parse(args : Array(String)) : Options
      options = Options.new
      build_parser(options).parse Crysterm.strip_toolkit_args(args, except: OWN_FLAGS)
      options
    end

    # md's own usage text: the banner and its options, never the Crysterm
    # toolkit's (those are listed by `--help --verbose`).
    def self.help : String
      build_parser(Options.new).to_s
    end

    # The option parser over `OPTIONS`, its handlers writing into *options*.
    private def self.build_parser(options : Options) : OptionParser
      parser = OptionParser.new
      parser.banner = <<-BANNER
        Usage: md [options] [+N] [FILE | -]

        Views and edits Markdown. With no FILE, opens an empty editor; with a
        FILE, views it (a FILE that does not exist yet opens in the editor).
        With `-`, or with no FILE and content on standard input, views the
        document as it streams in.

        Keys: F1 editor, F2 viewer, F3 table of contents (show/focus, or hide
        when focused), F4 menu and status bars, Tab next pane (outside the
        editor), Ctrl-O open, Ctrl-S save, Ctrl-F find, Ctrl-L go to line,
        Ctrl-Q quit; F10 or Alt-F for the menus.

        Options:
        BANNER

      OPTIONS.each do |option|
        handler = ->(value : String) { options.take(option, value) }
        if short = option.short_spec
          parser.on(short, option.long_spec, option.description, &handler)
        else
          parser.on(option.long_spec, option.description, &handler)
        end
      end
      parser.invalid_option { |flag| raise ArgumentError.new("unknown option: #{flag}") }
      parser.unknown_args do |rest, after_dashes|
        # What remains are the positional arguments (`-` included) and the
        # `+N` of pagers and editors (`less +N`, `vim +N`), which
        # `OptionParser` does not know as an option; a bare `+` is the end
        # of the document, as in vim. A file whose name starts with `+`
        # goes after `--`.
        rest.each do |arg|
          if arg.starts_with?('+')
            options.line = arg == "+" ? 0 : line_number(arg)
          else
            options.positional << arg
          end
        end
        options.positional.concat after_dashes
      end
      parser
    end

    # *value* as a line number, or a usage error.
    protected def self.line_number(value : String) : Int32
      value.to_i? || raise ArgumentError.new("not a line number: #{value}")
    end

    # Prints the document rendered as *format* (`Export`) on *stdout* and
    # returns the exit status. No FILE means standard input, terminal or
    # not, as it does for any filter; nothing of the window's — the log
    # file, the history — is touched.
    private def self.export(positional : Array(String), format : String, stdin : IO, stdout : IO) : Int32
      source = Source.resolve(positional, false)
      text = (path = source.path) ? read_file(path) : stdin.gets_to_end
      stdout << Export.render(Source.decode(text), format)
      0
    end

    # The contents of *path*, or an `Error` naming it.
    private def self.read_file(path : String) : String
      File.read path
    rescue ex : IO::Error
      raise Error.new("cannot read #{path}: #{Md.error_text(ex)}")
    end

    # Where Crysterm's log goes while md runs: `$XDG_CACHE_HOME/md/md.log`
    # (`~/.cache/md/md.log`), unless the user set Crysterm's `log.file`
    # (`CRYSTERM_LOG_FILE`) or the directory cannot be created. Standard
    # error is the screen while md runs, so a logged backtrace would land
    # over the UI.
    private def self.log_to_file : Nil
      Crysterm.default_log_file "md"
    end

    # Builds the application for *source*: a stream from standard input, an
    # existing file in view mode, or an empty editor (named after a file
    # that does not exist yet, or unnamed) — unless `--view` or `--edit`
    # said which pane. The history of recent files and positions comes
    # along, and the Edit, Format, View and Options choices are linked to the
    # configuration (`Config`, loaded by `.run`) and kept in its file;
    # `--watch` follows the file from the start, `--line` opens on that
    # line. The app is built on *window* when there is one.
    private def self.launch(source : Source, options : Options, stdin : IO, window : Crysterm::Window?) : App
      history = History.load
      view = options.view
      line = options.line
      if source.stdin?
        App.new source, stream: stdin, view: view.nil? ? true : view, window: window, history: history, config: true, line: line
      elsif (path = source.path) && File.exists?(path)
        App.new source, text: read_file(path), view: view.nil? ? true : view, window: window, history: history, config: true, watch: options.watch?, line: line
      else
        App.new source, view: view || false, window: window, history: history, config: true, watch: options.watch?, line: line
      end
    end
  end
end
