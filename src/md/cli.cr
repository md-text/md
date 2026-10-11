require "crysterm"
require "option_parser"
require "./source"
require "./export"

module Md
  # Command-line front end: parses arguments and starts the application.
  module CLI
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
    end

    # The flags md itself owns. Crysterm reads its toolkit options
    # (--colors-theme, --colors-stylesheet, ...) straight from ARGV before
    # the parser runs, without consuming them; `.parse` takes them out of
    # the arguments so they are neither reported as unknown nor mistaken
    # for a file, keeping these, which take precedence over a toolkit flag
    # of the same name.
    OWN_FLAGS = Set{"-V", "--version", "-h", "--help", "-v", "--verbose", "-w", "--watch",
                    "-l", "--line", "--view", "--edit", "--export", "--to"}

    # Runs the program with the given arguments and returns the process exit
    # status. `stdout`/`stderr`/`stdin` are injectable so that specs can
    # capture and feed them.
    def self.run(args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR, stdin : IO = STDIN) : Int32
      options = parse(args)
      stdout.puts "md #{VERSION}" if options.version?
      if options.help?
        stdout.puts help
        if options.verbose?
          stdout.puts
          stdout.puts Crysterm.toolkit_options_help(except: OWN_FLAGS)
        end
      end
      return 0 if options.help? || options.version?
      if format = options.export
        return export(options.positional, format, stdin, stdout)
      end

      source = Source.resolve(options.positional, stdin.tty?)
      log_to_file
      launch(source, options, stdin).run
    rescue ex : ArgumentError | OptionParser::Exception
      stderr.puts "md: #{ex.message}"
      stderr.puts help
      2
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

    # The option parser, its handlers writing into *options*.
    private def self.build_parser(options : Options) : OptionParser
      parser = OptionParser.new
      parser.banner = <<-BANNER
        Usage: md [options] [+N] [FILE | -]

        Views and edits Markdown. With no FILE, opens an empty editor; with a
        FILE, views it (a FILE that does not exist yet opens in the editor).
        With `-`, or with no FILE and content on standard input, views the
        document as it streams in.

        Keys: F2 editor, F3 viewer, F4 table of contents (show/focus, or hide
        when focused), Tab next pane, Ctrl-O open, Ctrl-S save, Ctrl-F find,
        Ctrl-L go to line, Ctrl-Q quit; F10 or Alt-F for the menus.

        Options:
        BANNER

      parser.on("-V", "--version", "Print the version and exit") { options.version = true }
      parser.on("-h", "--help", "Show this help and exit") { options.help = true }
      parser.on("-v", "--verbose", "Be more verbose (with --help: also list the\nCrysterm toolkit options)") { options.verbose = true }
      parser.on("-w", "--watch", "Reload FILE as it changes on disk (View → Watch file)") { options.watch = true }
      parser.on("-l N", "--line N", "Open on source line N, like +N (past the end:\nthe last line); otherwise the remembered position") do |value|
        options.line = line_number(value)
      end
      parser.on("--view", "Open the viewer, even on a new FILE") { options.view = pane_choice(options, true) }
      parser.on("--edit", "Open the editor, even on an existing FILE") { options.view = pane_choice(options, false) }
      parser.on("--export FORMAT", "Print FILE (or standard input) rendered as html\nor text, and exit") { |value| options.export = Export.format(value) }
      parser.on("--to FORMAT", "The same as --export (pandoc's spelling)") { |value| options.export = Export.format(value) }
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

    # The pane *view* asks for, unless *options* already asked for the other
    # one: `--view --edit` is a usage error, not a last-wins.
    private def self.pane_choice(options : Options, view : Bool) : Bool
      raise ArgumentError.new("--view and --edit cannot be combined") if options.view == !view
      view
    end

    # *value* as a line number, or a usage error.
    private def self.line_number(value : String) : Int32
      value.to_i? || raise ArgumentError.new("not a line number: #{value}")
    end

    # Prints the document rendered as *format* (`Export`) on *stdout* and
    # returns the exit status. No FILE means standard input, terminal or
    # not, as it does for any filter; nothing of the window's — the log
    # file, the history — is touched.
    private def self.export(positional : Array(String), format : String, stdin : IO, stdout : IO) : Int32
      source = Source.resolve(positional, false)
      text = (path = source.path) ? read_file(path) : stdin.gets_to_end
      stdout << Export.render(text, format)
      0
    end

    # The contents of *path*, or an `Error` naming it.
    private def self.read_file(path : String) : String
      File.read path
    rescue ex : IO::Error
      raise Error.new("cannot read #{path}: #{ex.message}")
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
    # along with the settings; `--watch` follows the file from the start, `--line` opens on
    # that line.
    private def self.launch(source : Source, options : Options, stdin : IO) : App
      history = History.load
      settings = Settings.load
      view = options.view
      line = options.line
      if source.stdin?
        App.new source, stream: stdin, view: view.nil? ? true : view, history: history, settings: settings, line: line
      elsif (path = source.path) && File.exists?(path)
        App.new source, text: read_file(path), view: view.nil? ? true : view, history: history, settings: settings, watch: options.watch?, line: line
      else
        App.new source, view: view || false, history: history, settings: settings, watch: options.watch?, line: line
      end
    end
  end
end
