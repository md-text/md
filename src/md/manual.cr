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
      {"F1, F2, F3", "Show and focus the editor, the viewer or the table of contents; hide it when it is already focused (the last pane stays)."},
      {"F4", "Hide the menu bar and the status bar, or show them again (View -> Menu and Status Bars); the entries' keys keep working while they are hidden."},
      {"Tab, Shift-Tab", "Outside the editor, focus the next or the previous shown pane (in the viewer, Tab first cycles the links); in the editor, indent and outdent the caret's line or the selected lines (Format -> Indent, Outdent): a list item by the list's rules, any other line by four spaces. F1, F2 and F3 or the mouse leave the editor."},
      {"Enter", "In the table of contents, jump the viewer to the selected heading; in the viewer, follow the focused link."},
      {"Space, Enter", "In the viewer, read on by a page or by a line."},
      {"Insert", "Toggle the editor between inserting and overwriting."},
      {"F5", "Cycle the mouse mode (a: always, n: while reading, i: while editing, off), after vi's 'set mouse='."},
      {"F6", "Cycle the theme: terminal, dark, light and the five Qt themes (View -> Theme)."},
      {"Ctrl-Z", "Outside the editor, suspend md to the shell (fg resumes); in the editor, undo."},
      {"F10, Alt-F, Alt-E, Alt-M, Alt-V, Alt-O, Alt-N, Alt-P", "Open the menu bar, or the File, Edit, Format, View, Options, Window and Help menus."},
      {"Ctrl-Home, Ctrl-End", "Go to the start and the end of the document, in the editor and in the viewer."},
      {"Ctrl-O", "Open a file (asks for the name, with completion)."},
      {"Ctrl-R", "Reload the file from disk."},
      {"Ctrl-S", "Save; without a file name yet, ask for one."},
      {"Ctrl-C", "Copy the selection, or with nothing selected the current block (the line, in the editor); Edit -> Copy as Markdown copies the block's source."},
      {"Ctrl-V", "Paste the clipboard into the editor at the caret; outside the editor, at the source of the viewer's caret. Edit -> Paste Special pastes from the terminal's clipboard, the paste command, md's own buffer or the editor's kill ring."},
      {"Ctrl-F, /, ?", "Search; `/' and `?' outside the editor, `?' backward."},
      {"Ctrl-G, Alt-G, n, N", "Next and previous match (n and N outside the editor)."},
      {"Alt-H", "Replace: asks for the pattern and the replacement, then about each match (Edit -> Replace)."},
      {"Ctrl-L", "Go to a source line (asks for the number; Edit -> Go to Line)."},
      {":, Alt-K", "The command line: a command's name runs it, Tab completing it, and a number goes to that source line (`:' outside the editor; Edit -> Run Command)."},
      {"Alt-Down, Alt-Up, ], [", "Jump to the next and the previous heading (] and [ outside the editor)."},
      {"Backspace, Alt-Left, Alt-Right", "Back to the file you were in before the last link or open, where you left it (Backspace outside the editor; File -> Previous File), and on to the next again (File -> Next File)."},
      {"Alt-R", "Resize the panes from the keyboard (when View -> Resizable Panes is on): Left and Right move the divider next to the pane, Enter or Escape return."},
      {"Alt-W", "Soft Wrap in the editor on and off."},
      {"Enter", "In the editor, on a list item: continue the list; on an empty item, end it."},
      {"Ctrl-B, Alt-I, Alt-C", "Bold, italic and code around the selection or the word at the caret, or off again."},
      {"Alt-X", "Tick or untick a list item's task box, or give it a ticked one (Format -> Toggle Task; Format -> Task, a check entry, adds and removes the box)."},
      {"Ctrl-Up, Ctrl-Down", "Promote or demote the heading on the caret's line."},
      {"Alt-Q", "Refill the paragraph at the caret, or the selected paragraphs, to the wrap column (the text width, or 80); Format -> Rewrap -> Document refills every paragraph."},
      {"Ctrl-N", "Open another md window on this document, in a new terminal window (Window -> New)."},
      {"Ctrl-W", "Outside the editor, close this window, asking first when its changes are unsaved; closing the last window quits (Window -> Close Current)."},
      {"Ctrl-Q, q", "Quit, closing every window (q anywhere but in the editor); each window asks first when its changes are unsaved."},
    ]

    # The README, read when the binary is built: the user's manual Help →
    # Manual shows (`.markdown`).
    README = {{ read_file("#{__DIR__}/../../README.md") }}

    # The manual as Markdown, for Help → Manual: the README's opening
    # paragraphs and its Usage chapter, the parts about using md; the
    # project's status, its badges and the chapters on installing, building
    # and developing it are left out. One text with the README, so the two
    # never disagree.
    def self.markdown : String
      String.build do |io|
        # Before the first chapter: the opening, without the status note and
        # the badges.
        opening = true
        keep = true
        README.each_line(chomp: false) do |line|
          if line.starts_with?("## ")
            opening = false
            keep = line.starts_with?("## Usage")
          end
          next if opening && (line.starts_with?('>') || line.starts_with?("[!["))
          io << line if keep
        end
      end.gsub(/\n{3,}/, "\n\n")
    end

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
          The View and Options menu choices are options too, listed under
          SETTINGS below. Crysterm, the toolkit md is built on, takes options of
          its own (\fB\-\-colors\-theme\fR, \fB\-\-colors\-stylesheet\fR,
          \fB\-\-log\-file\fR and more) on the same command line, each also
          settable in \fI~/.config/md/config.yml\fR, in
          \fI~/.config/crysterm/config.yml\fR or by a \fBCRYSTERM_*\fR environment
          variable; \fBmd \-\-help \-\-verbose\fR lists them.
          ROFF
        io << '\n'
        io << ".SH SETTINGS\n"
        io << <<-'ROFF'
          The choices made in the View and Options menus are kept across runs in
          \fI~/.config/md/config.yml\fR (see FILES), and each is an option of
          Crysterm's configuration registry: a key in that file, an environment
          variable and a command-line option, the later winning, with a pick in a
          menu recorded at once. A value given on the command line or in the
          environment is for that run and is not written to the file. A boolean
          option is switched off with its \fB\-\-no\-\fR form
          (\fB\-\-no\-md\-soft\-wrap\fR). The theme is Crysterm's own
          \fBcolors.theme\fR (\fB\-\-colors\-theme\fR, \fBCRYSTERM_COLORS_THEME\fR).
          ROFF
        io << '\n'
        Config.options.each do |option|
          io << ".TP\n"
          flag = option.bool? ? roff_flag(option.cli, nil) : roff_flag(option.cli, "VALUE")
          io << flag << " (\\fB" << roff(Superconf.env_name(option)) << "\\fR, \\fI" << roff(option.key) << "\\fR)\n"
          default = option.default_string.presence || "\"\""
          io << wrap(roff("#{option.description}. Default: #{default}.")) << '\n'
        end
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
          .I $XDG_CONFIG_HOME/md/config.yml
          The View and Options choices and the pane sizes, kept across runs
          (\fI~/.config/md/config.yml\fR by default): YAML with one mapping per
          option group, \fBmd\fR for md's own settings and Crysterm's groups for
          its options, written when md quits if anything changed and by Options
          \-> Save Config. Entries md does not know are kept.
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
          Crysterm's configuration for every program built on it: the theme, the
          stylesheet, the mouse and keyboard settings. md's own file wins over it.
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
        # A setting's value is free text (`--md-mouse-mode off`): no completion.
        Config.options.each do |option|
          next if option.bool?
          io << "    #{option.cli}) return ;;\n"
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
        Config.options.each do |option|
          arg = option.bool? ? "" : ":value:"
          io << "  '" << option.cli << '[' << zsh_text(option.description) << ']' << arg << "' \\\n"
          io << "  '" << option.cli.sub("--", "--no-") << "[Disable " << zsh_text(option.key) << "]' \\\n" if option.bool?
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
        Config.options.each do |option|
          io << "complete -c md -l " << option.cli[2..]
          io << " -x" unless option.bool?
          io << " -d '" << option.description.gsub("'", "\\'") << "'\n"
          io << "complete -c md -l no-" << option.cli[2..] << " -d 'Disable " << option.key << "'\n" if option.bool?
        end
      end
    end

    # Every flag, short and long, in table order, then the settings' flags
    # (`Config.flags`).
    private def self.all_flags : Array(String)
      CLI::OPTIONS.flat_map { |option| [option.short, option.long].compact } + Config.flags
    end

    # *text* for roff: its backslashes and hyphens escaped (a hyphen in roff
    # is a typographic one), the arrow of the menu paths as roff draws it,
    # and a leading dot or quote kept from being read as a request.
    private def self.roff(text : String) : String
      guard text.gsub('\\', "\\\\").gsub('-', "\\-").gsub('→', "\\(->")
    end

    # *line* kept from being read as a roff request: one starting with a dot
    # or a quote gets the zero-width `\&` first.
    private def self.guard(line : String) : String
      line.starts_with?('.') || line.starts_with?('\'') ? "\\&#{line}" : line
    end

    # *text* on lines of at most *width* characters (roff joins them back
    # into a paragraph; a long source line is a style warning to `mandoc`).
    # Every line is guarded: a word such as `'set` landing first on a line
    # would otherwise start a request and vanish with the rest of the line.
    # Public for the spec that pins this.
    def self.wrap(text : String, width : Int32 = 80) : String
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
      lines.join('\n') { |wrapped| guard(wrapped) }
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
