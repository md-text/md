require "crysterm"
require "option_parser"
require "./source"

module Md
  # Command-line front end: parses arguments and starts the application.
  module CLI
    # Runs the program with the given arguments and returns the process exit
    # status. `stdout`/`stderr` are injectable so that specs can capture them.
    def self.run(args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
      # Set by the option handlers when the program should exit without
      # starting the application (after `--version`, `--help` or a usage error).
      status : Int32? = nil
      positional = [] of String
      help = false
      verbose = false
      # md's own usage text, captured before the Crysterm toolkit flags are
      # registered below so that they never appear in help or usage errors.
      help_text : String? = nil

      parser = OptionParser.new
      parser.banner = <<-BANNER
        Usage: md [options] [FILE | -]

        Views and edits Markdown. With no FILE, opens an empty editor; with a
        FILE, views it (a FILE that does not exist yet opens in the editor).
        With `-`, or with no FILE and content on standard input, views the
        document as it streams in.

        Keys: F2 editor, F3 viewer, F4 table of contents (show/focus, or hide
        when focused), Tab next pane, Ctrl-S save, Ctrl-Q quit.

        Options:
        BANNER

      parser.on("-V", "--version", "Print the version and exit") do
        stdout.puts "md #{VERSION}"
        status ||= 0
      end
      parser.on("-h", "--help", "Show this help and exit") do
        help = true
        status ||= 0
      end
      parser.on("-v", "--verbose", "Be more verbose (with --help: also list the\nCrysterm toolkit options)") do
        verbose = true
      end
      parser.invalid_option do |flag|
        stderr.puts "md: unknown option: #{flag}"
        stderr.puts(help_text || parser)
        status = 2
      end
      parser.unknown_args do |rest, after_dashes|
        # Unknown options have already been reported by `invalid_option`; what
        # remains are the positional arguments (`-` included).
        positional = rest + after_dashes
      end

      help_text = parser.to_s

      # Crysterm reads its toolkit options (--colors-theme, --colors-stylesheet,
      # ...) straight from ARGV before this parser runs, without consuming
      # them; this parser gets the arguments with them taken out, so they are
      # neither reported as unknown nor mistaken for a file. md's own flags
      # take precedence over a toolkit flag of the same name.
      own_flags = Set{"-V", "--version", "-h", "--help", "-v", "--verbose"}
      parser.parse Crysterm.strip_toolkit_args(args, except: own_flags)

      if help
        stdout.puts help_text
        if verbose
          stdout.puts
          stdout.puts Crysterm.toolkit_options_help(except: own_flags)
        end
      end

      if exit_status = status
        return exit_status
      end

      source = Source.resolve(positional, STDIN.tty?)
      log_to_file
      launch(source).run
    rescue ex : ArgumentError
      stderr.puts "md: #{ex.message}"
      stderr.puts(help_text || parser)
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
    # that does not exist yet, or unnamed).
    private def self.launch(source : Source) : App
      if source.stdin?
        App.new source, stream: STDIN
      elsif (path = source.path) && File.exists?(path)
        text = begin
          File.read path
        rescue ex : IO::Error
          raise Error.new("cannot read #{path}: #{ex.message}")
        end
        App.new source, text: text, view: true
      else
        App.new source
      end
    end
  end
end
