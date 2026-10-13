require "./spec_helper"

# `Md::DocumentLock`: the mark an md process leaves on a file it has open,
# and the notice another md gives on finding it (`Md::Documents`).

# Runs the block with locking on (`Md::Documents.locking?`, as the CLI
# turns it on) and `XDG_STATE_HOME` pointing at a fresh directory, so the
# locks go to a scratch `locks` directory, which it yields.
private def with_lock_dir(&)
  dir = File.tempname("md-spec-locks")
  previous = ENV["XDG_STATE_HOME"]?
  ENV["XDG_STATE_HOME"] = dir
  Md::Documents.locking = true
  begin
    yield Md::DocumentLock.dir
  ensure
    Md::Documents.locking = false
    if previous
      ENV["XDG_STATE_HOME"] = previous
    else
      ENV.delete "XDG_STATE_HOME"
    end
    FileUtils.rm_rf dir
  end
end

# The lock file of *path*'s key in *dir*.
private def lock_file(dir : String, path : String) : String
  File.join dir, Md::App.recovery_name(Md::Documents.key_for(path))
end

# Writes a lock on *path* as the process *pid* on *host*, running *app*,
# would: by default the program *pid* runs, as its own lock would say.
private def write_lock(dir : String, path : String, pid : Int64, host = Md::DocumentLock.host_name, app = Md::DocumentLock.process_name(pid) || "md")
  Dir.mkdir_p dir
  File.write lock_file(dir, path), "#{pid}\n#{app}\n#{host}\n2026-01-01T00:00:00Z\n"
end

# A pid no process has: one that has just ended.
private def dead_pid : Int64
  process = Process.new("true")
  process.wait
  process.pid
end

describe Md::DocumentLock do
  it "writes the pid, the application, the host and the time, and goes on unlock" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_true
        lock.locked?.should be_true
        info = Md::DocumentLock.read(lock.path) || fail("no lock")
        info.pid.should eq Process.pid
        info.app.should eq Md::DocumentLock.app_name
        info.host.should eq Md::DocumentLock.host_name
        info.at.should_not be_nil
        lock.path.should eq lock_file(dir, path)
        Dir.children(dir).should eq [File.basename(lock.path)]
        lock.unlock
        File.exists?(lock.path).should be_false
      ensure
        File.delete? path
      end
    end
  end

  it "is stale when its pid is another program's now" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        # The parent process lives, but runs no program called md-elsewhere:
        # the pid was reused (after a reboot, say), and the lock is replaced.
        write_lock dir, path, Process.ppid, app: "md-elsewhere"
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_true
        lock.holder.should be_nil
        Md::DocumentLock.read(lock.path).try(&.pid).should eq Process.pid
        lock.unlock
      ensure
        File.delete? path
      end
    end
  end

  it "is held by another live process and names it" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        write_lock dir, path, Process.ppid
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_false
        lock.holder.try(&.pid).should eq Process.ppid
        lock.holder.try(&.holder).should eq "pid #{Process.ppid}"
        lock.unlock
        Md::DocumentLock.read(lock_file(dir, path)).try(&.pid).should eq Process.ppid
      ensure
        File.delete? path
      end
    end
  end

  it "replaces a stale lock, whose process is gone" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        write_lock dir, path, dead_pid
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_true
        lock.holder.should be_nil
        Md::DocumentLock.read(lock.path).try(&.pid).should eq Process.pid
        lock.unlock
      ensure
        File.delete? path
      end
    end
  end

  it "counts another host's lock as held" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        write_lock dir, path, dead_pid, host: "elsewhere.example"
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_false
        lock.holder.try(&.holder).should eq "pid #{lock.holder.try(&.pid)} on elsewhere.example"
      ensure
        File.delete? path
      end
    end
  end

  it "replaces something that is not a lock" do
    with_lock_dir do |dir|
      path = tempfile "a"
      begin
        Dir.mkdir_p dir
        File.write lock_file(dir, path), "garbage"
        lock = Md::DocumentLock.new(Md::Documents.key_for(path))
        lock.try_lock.should be_true
        lock.unlock
      ensure
        File.delete? path
      end
    end
  end
end

describe "Two md processes on one file" do
  it "tells a window opening a file another live md has open" do
    with_lock_dir do |dir|
      path = tempfile "# A\n"
      begin
        write_lock dir, path, Process.ppid
        with_app Md::Source.new(path: path), text: "# A\n" do |app|
          settle { notice(app).includes?("open in another md") }
          notice(app).should eq " #{File.basename(path)} is open in another md (pid #{Process.ppid}); saving here overwrites its changes"
          Md::Documents.lock_holder(app.document).try(&.pid).should eq Process.ppid
        end
        # The other md's lock stays.
        Md::DocumentLock.read(lock_file(dir, path)).try(&.pid).should eq Process.ppid
      ensure
        File.delete? path
      end
    end
  end

  it "tells a window opening the file from File -> Open" do
    with_lock_dir do |dir|
      path = tempfile "# A\n"
      begin
        write_lock dir, path, Process.ppid
        with_app do |app|
          app.open_file(path).should be_true
          settle { notice(app).includes?("open in another md") }
        end
      ensure
        File.delete? path
      end
    end
  end

  it "replaces a dead md's lock without a word" do
    with_lock_dir do |dir|
      path = tempfile "# A\n"
      begin
        write_lock dir, path, dead_pid
        with_app Md::Source.new(path: path), text: "# A\n" do |app|
          Md::Documents.lock_holder(app.document).should be_nil
          Md::DocumentLock.read(lock_file(dir, path)).try(&.pid).should eq Process.pid
          notice(app).should_not contain "another md"
        end
      ensure
        File.delete? path
      end
    end
  end

  it "keeps the lock while a window shows the file and drops it when the last leaves" do
    with_lock_dir do |dir|
      path = tempfile "# A\n"
      application = Crysterm::Application.new
      begin
        with_app Md::Source.new(path: path), text: "# A\n" do |a, window|
          application.add window
          a.window_opener = recording_opener
          File.exists?(lock_file(dir, path)).should be_true
          b = a.new_window || fail("no window was opened")
          b.window.destroy
          File.exists?(lock_file(dir, path)).should be_true
        end
        File.exists?(lock_file(dir, path)).should be_false
        Md::Documents.all.should be_empty
      ensure
        File.delete? path
      end
    end
  end

  it "leaves no lock while locking is off, as for a spec or an embedder" do
    with_lock_dir do |dir|
      Md::Documents.locking = false
      path = tempfile "# A\n"
      begin
        with_app Md::Source.new(path: path), text: "# A\n" do
          Dir.exists?(dir).should be_false
        end
      ensure
        File.delete? path
      end
    end
  end

  it "moves the lock with Save As, and tells when the new name is another md's" do
    with_lock_dir do |dir|
      path = tempfile "# A\n"
      other = tempfile nil
      taken = tempfile nil
      begin
        write_lock dir, taken, Process.ppid
        with_app Md::Source.new(path: path), text: "# A\n" do |app|
          app.save_as(other).should be_true
          File.exists?(lock_file(dir, path)).should be_false
          Md::DocumentLock.read(lock_file(dir, other)).try(&.pid).should eq Process.pid

          app.save_as(taken).should be_true
          File.exists?(lock_file(dir, other)).should be_false
          settle { notice(app).includes?("open in another md") }
          Md::DocumentLock.read(lock_file(dir, taken)).try(&.pid).should eq Process.ppid
        end
      ensure
        {path, other, taken}.each { |file| File.delete? file }
        {path, other, taken}.each { |file| File.delete? "#{file}~" }
      end
    end
  end

  it "locks a new document's file once Save As names it" do
    with_lock_dir do |dir|
      path = tempfile nil
      begin
        with_app do |app|
          Dir.exists?(dir).should be_false
          app.save_as(path).should be_true
          Md::DocumentLock.read(lock_file(dir, path)).try(&.pid).should eq Process.pid
        end
        File.exists?(lock_file(dir, path)).should be_false
      ensure
        File.delete? path
      end
    end
  end
end
