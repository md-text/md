module Md
  class App
    # Two safety nets for the text in the editor, after emacs' two: a backup
    # of the file as it was before md first wrote it in this session
    # (`make-backup-files`, the `file~` beside the file) and an auto-save of
    # the unsaved edits to a recovery file (`auto-save-mode`, the `#file#`).
    # Both are checkable entries in the Options menu — Keep a Backup File,
    # Auto-Save — on by default and kept across runs (`app_config.cr`).
    #
    # The backup is made on the first save to an existing file, once per
    # file per session, so it holds what was on disk when the session took
    # the file up, not merely the previous save: the file is copied to
    # `FILE~` beside it before the write. A backup that cannot be written is
    # named in the save's notice; the save goes ahead regardless.
    #
    # Auto-save writes the document to a recovery file, never to the file
    # itself: the file is written when the user says so, the distinction
    # vim's swap file and emacs' auto-save file both draw. A timer ticks
    # every `AUTOSAVE_INTERVAL` (`#autosave_interval`, which specs shorten),
    # and a tick that finds the document modified and edited since the last
    # auto-save writes it. The recovery files live under
    # `$XDG_STATE_HOME/md/autosave/` (`~/.local/state/md/autosave/`) rather
    # than beside the file, so a project directory is not littered. A named
    # document's is its absolute path with `/` escaped as `%2F` (and `%` as
    # `%25`, so the name reads back to the path): `/home/u/notes.md`
    # recovers from `%2Fhome%2Fu%2Fnotes.md`. A document without a name — a
    # new one, or standard input, which md edits like anything else —
    # recovers from `unnamed-<date>-<time>-<pid>.md` (`-2`, `-3`… added
    # for another window's taken in the same second). A save makes the
    # recovery file redundant and removes it, as does a clean exit, so what
    # is left in the directory after a crash or a kill is just what was
    # lost. Opening a file whose recovery file is newer than the file gets a
    # notice naming the copy; recovering it is opening or copying the copy
    # (File → Open… takes its path). The writes are atomic — a temporary
    # file renamed into place — and a failure is a notice, once, never an
    # error into the app: the net must not be what trips it.

    # One net per document, whatever the windows on it (`Document`): one
    # timer, on the document's host window, one recovery file, one backup;
    # the settings are each window's (the config makes them one for the
    # process), the host's counting for the timer.

    # How often the text is looked at for unsaved edits to auto-save.
    AUTOSAVE_INTERVAL = 30.seconds

    # Options → Auto-Save and Options → Keep a Backup File. Reactive
    # properties, so the menu entries bind to them.
    @autosave : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @backup_file : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @autosave_interval : Time::Span = AUTOSAVE_INTERVAL

    # The recovery files' directory: `$XDG_STATE_HOME/md/autosave`.
    def self.autosave_dir : String
      File.join History.state_dir, "autosave"
    end

    # The name a recovery file for *path* has in `.autosave_dir`: the
    # absolute path, percent-escaped so it is one file name.
    def self.recovery_name(path : String) : String
      File.expand_path(path).gsub('%', "%25").gsub('/', "%2F")
    end

    def autosave? : Bool
      @autosave.value
    end

    # Turns auto-saving on or off (Options → Auto-Save); the timer follows
    # (the property's change handler, in `#wire_autosave`).
    def autosave=(value : Bool) : Bool
      @autosave.value = value
    end

    def backup_file? : Bool
      @backup_file.value
    end

    # Turns the backup on or off (Options → Keep a Backup File).
    def backup_file=(value : Bool) : Bool
      @backup_file.value = value
    end

    def autosave_interval : Time::Span
      @autosave_interval
    end

    # Changes how often the text is looked at; a running timer is restarted
    # on the new interval.
    def autosave_interval=(span : Time::Span) : Time::Span
      @autosave_interval = span
      @document.setup_autosave if @document.autosaving?
      span
    end

    # The recovery file the document at hand would be written to
    # (`Document#recovery_path`).
    def recovery_path : String
      @document.recovery_path
    end

    # Wires the net, once the panes and the settings are in place: the
    # setting starts and stops the document's timer — started again now on
    # the settings read, when this window hosts it, as the attach started it
    # on the defaults — and a leftover recovery file for a document just
    # read is noticed (a window joining a document another window shows has
    # heard of it there).
    private def wire_autosave : Nil
      @autosave.on_change { @document.setup_autosave }
      @document.setup_autosave if @document.host.same?(self)
      @document.check_recovery.try { |found| notice found } if last_view?
    end
  end
end
