module Md
  # The manual page and the shell completions (`md --generate man|bash|
  # zsh|fish`), generated from `CLI::OPTIONS` so that an option added there
  # is in all of them with nothing else to write. The binary is their one
  # source: `make man` and `make completions` run it, and the release
  # archives carry what it printed, so nothing generated is kept in git to
  # go stale.
  module Manual
    # What `--generate` can print.
    KINDS = {"man", "bash", "zsh", "fish"}

    # When the binary was built, as seconds since the epoch: the clock at
    # compile time, or `SOURCE_DATE_EPOCH` when the build set it, as
    # reproducible builds do. The man page is dated with it.
    BUILD_EPOCH = {{ (env("SOURCE_DATE_EPOCH") || `date +%s`).strip }}.to_i64

    # The keys, as the man page lists them (the README's table, in short).
    KEYS = [
      {"F2, F3, F4", "Show and focus the editor, the viewer or the table of contents; hide it when it is already focused (the last pane stays)."},
      {"Tab, Shift-Tab", "Focus the next or the previous shown pane (in the viewer, Tab first cycles the links)."},
      {"Enter", "In the table of contents, jump the viewer to the selected heading; in the viewer, follow the focused link."},
      {"Space, Enter", "In the viewer, read on by a page or by a line."},
      {"Insert", "Toggle the editor between inserting and overwriting."},
      {"F5", "Cycle the mouse mode (a: always, n: while reading, i: while editing, off), after vi's 'set mouse='."},
      {"F6", "Cycle the theme: terminal, dark, light (Options -> Theme)."},
      {"Ctrl-Z", "Outside the editor, suspend md to the shell (fg resumes); in the editor, undo."},
      {"F10, Alt-F, Alt-E, Alt-M, Alt-V, Alt-O", "Open the menu bar, or the File, Edit, Format, View and Options menus."},
      {"Ctrl-O", "Open a file (asks for the name, with completion)."},
      {"Ctrl-R", "Reload the file from disk."},
      {"Ctrl-S", "Save; without a file name yet, ask for one."},
      {"Ctrl-C", "Copy the selection, or with nothing selected the current block (the line, in the editor); Edit -> Copy as Markdown copies the block's source."},
      {"Ctrl-V", "Paste the clipboard into the editor at the caret; outside the editor, at the source of the viewer's caret. Edit -> Paste Special pastes from the terminal's clipboard, the paste command, md's own buffer or the editor's kill ring."},
      {"Ctrl-F, /, ?", "Search; `/' and `?' outside the editor, `?' backward."},
      {"Ctrl-G, Alt-G, n, N", "Next and previous match (n and N outside the editor)."},
      {"Ctrl-L, :", "Go to a source line (`:' outside the editor)."},
      {"Alt-Down, Alt-Up, ], [", "Jump to the next and the previous heading (] and [ outside the editor)."},
      {"Backspace, Alt-Left, Alt-Right", "Back to where you were before the last link or open (Backspace outside the editor), and Forward again."},
      {"Alt-R", "Resize the panes from the keyboard: Left and Right move the divider next to the pane, Enter or Escape return."},
      {"Alt-W", "Soft Wrap in the editor on and off."},
      {"Shift-Left, Shift-Right, Shift-Up, Shift-Down, Shift-Home, Shift-End, Shift-PageUp, Shift-PageDown", "Select from the cursor, in the editor and in the viewer."},
      {"Enter, Tab, Shift-Tab", "In the editor, on a list item: continue the list (an empty item ends it), indent and outdent the item or the selected lines."},
      {"Ctrl-B, Alt-I, Alt-C", "Bold, italic and code around the selection or the word at the caret, or off again."},
      {"Alt-X", "Tick or untick a list item's task box, or give it a ticked one (Format -> Check Task; Format -> Task Box adds and removes the box)."},
      {"Ctrl-Up, Ctrl-Down", "Promote or demote the heading on the caret's line."},
      {"Alt-Q", "Refill the paragraph at the caret, or the selected paragraphs, to the wrap column (the text width, or 80)."},
      {"Ctrl-Q, q", "Quit (q anywhere but in the editor); asks first when changes are unsaved."},
    ]

    # *value* checked against `KINDS`: a usage error otherwise.
    def self.kind(value : String) : String
      return value if KINDS.includes?(value)
      raise ArgumentError.new("cannot generate #{value} (#{KINDS.join(", ")})")
    end

    # The text `--generate` *kind* prints (`.kind` checked).
    def self.generate(kind : String) : String
      case kind
      when "man"  then man
      when "bash" then bash
      when "zsh"  then zsh
      when "fish" then fish
      else             raise ArgumentError.new("cannot generate #{kind}")
      end
    end

    # The man page, `md(1)`, in the man macros.
    def self.man : String
      String.build do |io|
        io << ".TH MD 1 \"#{Time.unix(BUILD_EPOCH).to_s("%Y-%m-%d")}\" \"md #{VERSION}\" \"User Commands\"\n"
        io << ".SH NAME\n"
        io << "md \\- view and edit Markdown in the terminal\n"
        io << ".SH SYNOPSIS\n"
        io << ".B md\n[\\fIoptions\\fR] [\\fB+\\fIN\\fR] [\\fIFILE\\fR | \\fB\\-\\fR]\n.br\n"
        io << ".B md\n.B \\-\\-export\n\\fIFORMAT\\fR [\\fIFILE\\fR | \\fB\\-\\fR]\n.br\n"
        io << ".B md\n.B \\-\\-generate\n\\fIWHAT\\fR\n"
        io << ".SH DESCRIPTION\n"
        io << <<-'ROFF'
          .B md
          views and edits Markdown. Its window has three panes side by side: the
          Markdown source editor, the rendered viewer and a table of contents.
          With no \fIFILE\fR it opens an empty editor; with a \fIFILE\fR it views
          it (a \fIFILE\fR that does not exist yet opens in the editor); with
          \fB\-\fR, or with no \fIFILE\fR and content on standard input, it views
          the document as it streams in, following the tail until the reader
          scrolls up. The viewer re-renders as the source is edited, and the
          table of contents follows the document's headings.
          .PP
          \fB+\fIN\fR (or \fB\-\-line\fR \fIN\fR) opens on source line \fIN\fR in
          both panes, as in
          .BR less (1)
          and
          .BR vim (1);
          a bare \fB+\fR is the end of the document. Otherwise md opens where it
          remembers the file was last read.
          .PP
          With \fB\-\-export\fR, md prints the document rendered as \fIFORMAT\fR on
          standard output and exits without opening a window, so it works as a
          filter: \fBhtml\fR is an HTML body fragment (no document wrapper, as
          .BR pandoc (1)
          without \fB\-\-standalone\fR), \fBtext\fR is the viewer's text without its
          styling. With no \fIFILE\fR, standard input is read.
          ROFF
        io << '\n'
        io << ".SH OPTIONS\n"
        CLI::OPTIONS.each do |option|
          io << ".TP\n"
          flags = [] of String
          if short = option.short
            flags << roff_flag(short, option.argument)
          end
          flags << roff_flag(option.long, option.argument)
          io << flags.join(", ") << '\n'
          io << wrap(roff(option.text)) << '\n'
        end
        io << <<-'ROFF'
          .PP
          Crysterm, the toolkit md is built on, takes options of its own
          (\fB\-\-colors\-theme\fR, \fB\-\-colors\-stylesheet\fR, \fB\-\-log\-file\fR
          and more) on the same command line, each also settable in
          \fI~/.config/crysterm/config.yml\fR or by a \fBCRYSTERM_*\fR environment
          variable; \fBmd \-\-help \-\-verbose\fR lists them.
          ROFF
        io << '\n'
        io << ".SH KEYS\n"
        KEYS.each do |keys, action|
          io << ".TP\n.B " << roff(keys) << '\n' << wrap(roff(action)) << '\n'
        end
        io << <<-'ROFF'
          .PP
          The editor has the usual editing keys: arrows and Home/End, Shift
          with the arrows to select, Ctrl\-Z/Alt\-Z to undo and redo, Ctrl\-K/Ctrl\-Y
          to kill and yank, and the mouse to position the cursor, select and
          scroll. Searching is a pager's: the pattern is a regular expression
          when it is one and literal text otherwise, case\-insensitive unless it
          has an uppercase letter, and the search wraps around with a notice.
          .PP
          A question \- a file name, a pattern, a line number, what to do with
          unsaved changes \- is asked in place of the status bar, the way vi's
          command line replaces its status line (Tab completes file names, Up
          recalls earlier answers, Escape gives up), or in a dialog in the
          middle of the window, as View \-> Dialog Style says.
          .SH FILES
          .TP
          .I $XDG_CONFIG_HOME/md/settings.json
          The View and Options choices and the pane sizes, kept across runs
          (\fI~/.config/md/settings.json\fR by default).
          .TP
          .I $XDG_STATE_HOME/md/history.json
          The recently opened files and the position in each
          (\fI~/.local/state/md/history.json\fR by default); Options \-> Clear
          Caches empties it, the recovery files and the cache directory.
          .TP
          .I $XDG_STATE_HOME/md/autosave/
          The recovery files auto-save writes, removed on a save or a clean exit.
          .TP
          .I FILE~
          The backup of a file as it was before the session's first save of it.
          .TP
          .I $XDG_CACHE_HOME/md/md.log
          Crysterm's log while md runs: handler errors with their backtraces
          (\fI~/.cache/md/md.log\fR by default; \fBCRYSTERM_LOG_FILE\fR or
          \fB\-\-log\-file\fR name another).
          .TP
          .I ~/.config/crysterm/config.yml
          Crysterm's configuration: the theme, the stylesheet, the mouse and
          keyboard settings.
          .SH EXIT STATUS
          0 on success, 1 when a file cannot be read or md cannot start, 2 on a
          usage error.
          .SH SEE ALSO
          .BR less (1),
          .BR vim (1),
          .BR pandoc (1).
          .PP
          Crysterm: https://github.com/crystallabs/crysterm
          .br
          md: https://github.com/crystallabs/md
          ROFF
        io << '\n'
      end
    end

    # The bash completion script: options after a dash, an option's values
    # after it, files otherwise (`-o default`).
    def self.bash : String
      String.build do |io|
        io << "# bash completion for md, generated by `md --generate bash`.\n"
        io << "_md() {\n"
        io << "  local cur=${COMP_WORDS[COMP_CWORD]} prev=${COMP_WORDS[COMP_CWORD-1]}\n"
        io << "  case $prev in\n"
        CLI::OPTIONS.each do |option|
          next unless option.argument
          flags = [option.short, option.long].compact.join('|')
          if values = option.values
            io << "    #{flags}) COMPREPLY=($(compgen -W '#{values.join(' ')}' -- \"$cur\")); return ;;\n"
          else
            io << "    #{flags}) return ;;\n"
          end
        end
        io << "  esac\n"
        io << "  case $cur in\n"
        io << "    -*) COMPREPLY=($(compgen -W '#{all_flags.join(' ')}' -- \"$cur\")) ;;\n"
        io << "  esac\n"
        io << "}\n"
        io << "complete -o default -F _md md\n"
      end
    end

    # The zsh completion function, for a `site-functions` directory as `_md`.
    def self.zsh : String
      String.build do |io|
        io << "#compdef md\n"
        io << "# zsh completion for md, generated by `md --generate zsh`.\n"
        io << "_arguments -s \\\n"
        CLI::OPTIONS.each do |option|
          # A pair of flags excludes each other: `'(-V --version)'{-V,--version}'[...]'`.
          flags = [option.short, option.long].compact
          head = flags.size > 1 ? "'(#{flags.join(' ')})'{#{flags.join(',')}}'" : "'#{flags[0]}"
          arg = if (name = option.argument) && (values = option.values)
                  ":#{name.downcase}:(#{values.join(' ')})"
                elsif name = option.argument
                  ":#{name.downcase}:"
                else
                  ""
                end
          io << "  " << head << '[' << zsh_text(option.text) << ']' << arg << "' \\\n"
        end
        io << "  '1:file:_files'\n"
      end
    end

    # The fish completions.
    def self.fish : String
      String.build do |io|
        io << "# fish completion for md, generated by `md --generate fish`.\n"
        CLI::OPTIONS.each do |option|
          io << "complete -c md"
          if short = option.short
            io << " -s " << short[1..]
          end
          io << " -l " << option.long[2..]
          if values = option.values
            io << " -x -a '" << values.join(' ') << "'"
          elsif option.argument
            io << " -x"
          end
          io << " -d '" << option.text.gsub("'", "\\'") << "'\n"
        end
      end
    end

    # Every flag, short and long, in table order.
    private def self.all_flags : Array(String)
      CLI::OPTIONS.flat_map { |option| [option.short, option.long].compact }
    end

    # *text* for roff: its backslashes and hyphens escaped (a hyphen in roff
    # is a typographic one), the arrow of the menu paths as roff draws it,
    # and a leading dot or quote kept from being read as a request.
    private def self.roff(text : String) : String
      out = text.gsub('\\', "\\\\").gsub('-', "\\-").gsub('→', "\\(->")
      out.starts_with?('.') || out.starts_with?('\'') ? "\\&#{out}" : out
    end

    # *text* on lines of at most *width* characters (roff joins them back
    # into a paragraph; a long source line is a style warning to `mandoc`).
    private def self.wrap(text : String, width : Int32 = 80) : String
      lines = [] of String
      line = ""
      text.split(' ') do |word|
        if line.empty?
          line = word
        elsif line.size + 1 + word.size <= width
          line += " #{word}"
        else
          lines << line
          line = word
        end
      end
      lines << line unless line.empty?
      lines.join('\n')
    end

    # A *flag* in bold, with its *argument* in italics: `\fB\-\-line\fR \fIN\fR`.
    private def self.roff_flag(flag : String, argument : String?) : String
      bold = "\\fB#{roff(flag)}\\fR"
      argument ? "#{bold} \\fI#{argument}\\fR" : bold
    end

    # *text* inside a zsh `[description]`: its brackets, colons and quotes
    # escaped.
    private def self.zsh_text(text : String) : String
      text.gsub("'", "'\\''").gsub('[', "\\[").gsub(']', "\\]").gsub(':', "\\:")
    end
  end
end
