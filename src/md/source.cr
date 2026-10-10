module Md
  # Raised for user-facing failures (an unreadable file, no terminal to talk
  # to); `CLI` prints the message and exits non-zero.
  class Error < Exception
  end

  # Where the document comes from, as decided by the command line:
  #
  # * no argument, stdin a terminal — a new, unnamed document (`path` and
  #   `stdin?` both unset);
  # * `FILE` — that file; it need not exist yet, in which case it is a new
  #   document that `Ctrl-S` will create;
  # * `-`, or no argument with content piped on stdin — the document streams
  #   in from standard input.
  record Source, path : String? = nil, stdin : Bool = false do
    # Whether the document is read from standard input.
    def stdin? : Bool
      @stdin
    end

    # Resolves the positional *args* (at most one). *stdin_tty* says whether
    # standard input is a terminal; when it is not and no file is named, the
    # document is read from it.
    def self.resolve(args : Array(String), stdin_tty : Bool) : Source
      case args.size
      when 0
        stdin_tty ? new : new(stdin: true)
      when 1
        args[0] == "-" ? new(stdin: true) : new(path: args[0])
      else
        raise ArgumentError.new("unexpected argument: #{args[1]}")
      end
    end

    # A short name for the window title.
    def name : String?
      @path || (@stdin ? "stdin" : nil)
    end
  end
end
