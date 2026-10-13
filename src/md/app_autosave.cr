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

    # How often the editor is looked at for unsaved edits to auto-save.
    AUTOSAVE_INTERVAL = 30.seconds

    # Options → Auto-Save and Options → Keep a Backup File. Reactive
    # properties, so the menu entries bind to them.
    @autosave : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @backup_file : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    @autosave_timer : Crysterm::Timer?
    @autosave_interval : Time::Span = AUTOSAVE_INTERVAL
    # Set by every user edit, cleared by every auto-save: the timer writes
    # only when there is something new to write.
    @autosave_dirty = false
    # The recovery file on disk for the document at hand, so a save, a change
    # of document or the exit can remove it; nil while there is none.
    @recovery_path : String?
    # Whether the last auto-save failed, so the notice is given once rather
    # than every interval.
    @autosave_failed = false
    # The files backed up this session.
    @backed_up = Set(String).new

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

    # Changes how often the editor is looked at; a running timer is restarted
    # on the new interval.
    def autosave_interval=(span : Time::Span) : Time::Span
      @autosave_interval = span
      setup_autosave if @autosave_timer
      span
    end

    # The recovery file the document at hand would be written to.
    def recovery_path : String
      @recovery_path ||= File.join(App.autosave_dir, recovery_name)
    end

    # Wires the net, once the panes and the settings are in place: edits
    # mark the document for the next tick, the setting starts and stops the
    # timer, a leftover recovery file for the document is noticed, and the
    # timer goes with the window.
    private def wire_autosave : Nil
      @editor.on(Crysterm::Event::TextChanged) { @autosave_dirty = true unless @loading }
      @autosave.on_change { setup_autosave }
      @main.on(Crysterm::Event::Destroy) { stop_autosave }
      setup_autosave
      check_recovery
    end

    # Starts the timer, or takes it down: run when the setting or the
    # interval changes. The tick is posted to the render fiber, where the
    # editor is read (as `Crysterm::FileWatcher` delivers its events); a
    # tick still queued when its timer is stopped or replaced is dropped
    # there, so nothing is written after `#finish_autosave`.
    private def setup_autosave : Nil
      stop_autosave
      return unless @autosave.value
      timer = Crysterm::Timer.new @autosave_interval, immediate: false
      timer.on_tick { @window.post { autosave_tick if @autosave_timer.same?(timer) } }
      @autosave_timer = timer.start
    end

    private def stop_autosave : Nil
      @autosave_timer.try &.stop
      @autosave_timer = nil
    end

    # The timer's look at the editor: unsaved edits since the last look are
    # written to the recovery file.
    private def autosave_tick : Nil
      return unless @autosave.value && @autosave_dirty && @editor.document.modified?
      write_recovery
    end

    # Writes the document to its recovery file, beside its final name and
    # renamed over it, so a crash mid-write leaves the previous copy intact.
    private def write_recovery : Nil
      path = recovery_path
      Dir.mkdir_p File.dirname(path)
      temp = "#{path}.#{Process.pid}.tmp"
      begin
        File.write temp, markdown
        File.rename temp, path
      rescue ex : IO::Error
        File.delete? temp
        raise ex
      end
      @autosave_dirty = false
      @autosave_failed = false
    rescue ex : IO::Error
      notice "Cannot auto-save to #{path}: #{ex.message}" unless @autosave_failed
      @autosave_failed = true
    end

    # The document is on disk as the user wants it (a save): the recovery
    # file has nothing to add and goes.
    private def autosave_settled : Nil
      @autosave_dirty = false
      drop_recovery
    end

    # Removes the document's recovery file, if one was written: the document
    # is saved, left for another, or the session ends cleanly. Another
    # window on the same file with unsaved edits of its own keeps the file
    # for them, and writes them at its next tick, over what this one wrote.
    private def drop_recovery : Nil
      if path = @recovery_path
        sharing = App.instances.select { |app| !app.same?(self) && app.@recovery_path == path && app.editor.document.modified? }
        if sharing.empty?
          File.delete? path
        else
          sharing.each &.mark_for_autosave
        end
      end
      @recovery_path = nil
    rescue IO::Error
      # A recovery file that will not go is still only a copy.
    end

    # Makes the next tick write the document, whose recovery file another
    # window on the same file has written over (`#drop_recovery`).
    protected def mark_for_autosave : Nil
      @autosave_dirty = true
    end

    # The exit's part: the timer stops and the recovery file goes, the
    # session having ended the way the user meant it to (`#run`).
    def finish_autosave : Nil
      stop_autosave
      drop_recovery
    end

    # Copies *path* to `path~` before the first save of the session writes
    # it, when the option is on and there is a file to keep. Returns what
    # went wrong, for the save's notice, or nil.
    private def backup(path : String) : String?
      return if !@backup_file.value || @backed_up.includes?(path) || !File.exists?(path)
      @backed_up << path
      File.copy path, "#{path}~"
      nil
    rescue ex : IO::Error
      "backup #{path}~ failed: #{ex.message}"
    end

    # A notice when a recovery file for the document is newer than the
    # document's file (or the file is not there): a session ended badly and
    # the copy holds its edits. For a new document without a name, the
    # directory is looked at for unnamed copies left behind.
    private def check_recovery : Nil
      if path = @source.path
        copy = File.join(App.autosave_dir, App.recovery_name(path))
        return unless info = File.info?(copy)
        return if (file = File.info?(path)) && file.modification_time >= info.modification_time
        notice "Recovered copy from #{recovery_time info} exists: #{copy}"
      elsif !@source.stdin?
        copies = Dir.glob(File.join(App.autosave_dir, "unnamed-*.md")).sort!
        return if copies.empty?
        notice "#{copies.size == 1 ? "Recovered copy exists" : "#{copies.size} recovered copies exist"} in #{App.autosave_dir}"
      end
    rescue IO::Error
      # A directory that cannot be read has no copies to offer.
    end

    private def recovery_time(info : File::Info) : String
      info.modification_time.to_local.to_s("%Y-%m-%d %H:%M")
    end

    # The document's recovery file name: the escaped path of a named
    # document, or a name of its own for one without.
    private def recovery_name : String
      if path = @source.path
        App.recovery_name path
      else
        # Another window's unnamed document may have taken the name in the
        # same second: a number tells the two apart.
        base = "unnamed-#{Time.local.to_s("%Y%m%d-%H%M%S")}-#{Process.pid}"
        name = "#{base}.md"
        n = 1
        while App.instances.any? { |app| !app.same?(self) && app.@recovery_path.try { |taken| File.basename(taken) == name } }
          name = "#{base}-#{n += 1}.md"
        end
        name
      end
    end
  end
end
