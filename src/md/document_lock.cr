require "socket"

module Md
  # The mark one md process leaves on a file it has open, so that another
  # md opening the file knows (Qt's `QLockFile`, Vim's swap file, Emacs's
  # `.#FILE` lock): a small file in `.dir`, named after the file's key
  # (`App.recovery_name`, as the recovery files are), holding the process's
  # pid, the application's name, the host's name and when it was taken —
  # `QLockFile`'s lines, with the time after them.
  #
  # The lock warns rather than blocks, as Qt Creator and Kate do: the
  # second md shows a notice and edits on (`Documents`). A lock is
  # created whole or not at all — written to a file of its own, then linked
  # to its name, which fails when the name is taken — so two processes
  # cannot both take it. A lock whose process is gone (a crash, a kill) is
  # stale and replaced, as `QLockFile::removeStaleLockFile` does; one taken
  # on another host is held, since whether its process lives cannot be
  # told from here.
  class DocumentLock
    # The application name written in the lock, `QLockFile`'s second line.
    APP_NAME = "md"

    # What a lock file says: the *pid* of the process holding it, its *host*
    # and *app*, and when it was taken (nil when the line is missing or
    # unreadable).
    record Info, pid : Int64, host : String, app : String, at : Time? do
      # Whether the process holding the lock may still have the file open:
      # one on this host whose pid is alive, or one on another host, which
      # cannot be looked at.
      def live? : Bool
        host != DocumentLock.host_name || Process.exists?(pid)
      end

      # Whether the lock is this process's own.
      def own? : Bool
        host == DocumentLock.host_name && pid == Process.pid
      end

      # Who holds the lock, for a notice: `pid 1234`, with `on HOST` when
      # it is another host's.
      def holder : String
        host == DocumentLock.host_name ? "pid #{pid}" : "pid #{pid} on #{host}"
      end
    end

    # The locks this process holds, by lock file, released when it exits.
    @@held = {} of String => DocumentLock

    at_exit { DocumentLock.unlock_all }

    # The locks' directory: `$XDG_STATE_HOME/md/locks`, beside the recovery
    # files' (`App.autosave_dir`).
    def self.dir : String
      File.join History.state_dir, "locks"
    end

    # This host's name, as written in the locks.
    def self.host_name : String
      @@host_name ||= System.hostname
    end

    # The canonical key of the file locked (`Documents.key_for`).
    getter key : String

    # The lock file.
    getter path : String

    # The other process's lock found by the last `#try_lock` that failed, nil
    # otherwise.
    getter holder : Info?

    # A lock on the file of *key*, kept in *dir*; not taken until
    # `#try_lock`.
    def initialize(@key : String, dir : String = DocumentLock.dir)
      @path = File.join(dir, App.recovery_name(@key))
      @locked = false
    end

    # Whether this process holds the lock.
    def locked? : Bool
      @locked
    end

    # Takes the lock unless another live process holds it
    # (`QLockFile::tryLock`), replacing a stale one. Returns whether the
    # lock is this process's now; when it is another's, `#holder` says
    # whose. A lock that cannot be written (no state directory to be had)
    # is not taken, and nobody is said to hold it.
    def try_lock : Bool
      return true if @locked
      @holder = nil
      2.times do
        if create
          @locked = true
          @@held[@path] = self
          return true
        end
        info = DocumentLock.read(@path)
        if info.try(&.own?)
          # This process's, left by a document gone without unlocking.
          File.delete? @path
        elsif info.try(&.live?)
          @holder = info
          return false
        else
          # Stale, or not a lock at all: replaced.
          File.delete? @path
        end
      end
      false
    rescue IO::Error
      false
    end

    # Gives the lock up (`QLockFile::unlock`): the file goes, if it is still
    # this process's. A lock not held is left alone.
    def unlock : Nil
      return unless @locked
      @locked = false
      @@held.delete @path
      File.delete? @path if DocumentLock.read(@path).try(&.own?)
    rescue IO::Error
    end

    # What the lock file at *path* says, or nil when there is none or it is
    # not one (`QLockFile::getLockInfo`).
    def self.read(path : String) : Info?
      lines = File.read(path).lines
      return unless lines.size >= 3 && (pid = lines[0].to_i64?) && pid > 0
      at = lines[3]?.try { |line| Time.parse_rfc3339(line) rescue nil }
      Info.new(pid, lines[2], lines[1], at)
    rescue IO::Error
    end

    # Gives up every lock the process holds: at its exit, the documents
    # having perhaps not been closed one by one.
    def self.unlock_all : Nil
      @@held.values.each &.unlock
    end

    # Writes this process's lock to `#path`, all at once: written to a file
    # of its own and linked to the name, which fails when the name is taken.
    # Returns whether the lock was created.
    private def create : Bool
      Dir.mkdir_p File.dirname(@path)
      temporary = "#{@path}.#{Process.pid}.tmp"
      File.write temporary, "#{Process.pid}\n#{APP_NAME}\n#{DocumentLock.host_name}\n#{Time.utc.to_rfc3339}\n"
      begin
        File.link temporary, @path
        true
      rescue File::AlreadyExistsError
        false
      ensure
        File.delete? temporary
      end
    end
  end
end
