require "spec"
require "file_utils"

# End-to-end checks of md's windows in a real terminal: `bin/md` runs in a
# private tmux server, Window → New opens a tmux window in the same md
# process (Crysterm's multiplexer launcher), and the panes are read back
# with `capture-pane`. tmux forwards focus reports (`focus-events on`), so a
# window in the background is told it is unfocused, as Terminal.app,
# iTerm2 or Ghostty tell it — what the headless specs cannot show: a window
# that stopped painting while unfocused, keys that never reach md, a quit
# that closes windows before its question is answered.
#
# Run with `make e2e`, which builds `bin/md` first; skipped without tmux.

# A tmux server of its own, with md started in its first window.
private class Session
  SOCKET = "md-e2e-#{Process.pid}"

  getter dir : String

  def initialize(text : String, config : String? = nil)
    @dir = File.tempname("md-e2e")
    Dir.mkdir_p File.join(@dir, "config", "md")
    Dir.mkdir_p File.join(@dir, "state")
    File.write File.join(@dir, "config", "md", "config.yml"), config if config
    File.write file, text
    md = File.expand_path("../bin/md", __DIR__)
    env = "XDG_STATE_HOME=#{@dir}/state XDG_CONFIG_HOME=#{@dir}/config XDG_CACHE_HOME=#{@dir}/cache"
    tmux "new-session", "-d", "-s", "e2e", "-x", "100", "-y", "30", "env #{env} #{md} --edit #{file}"
    tmux "set", "-g", "focus-events", "on"
    # A client attached on a terminal of its own (`script` makes one): tmux
    # tells panes of focus only through one, as a user's terminal would.
    @client = Process.new("script", ["-q", "/dev/null", "tmux", "-L", SOCKET, "attach", "-t", "e2e"],
      input: Process::Redirect::Pipe, output: Process::Redirect::Close, error: Process::Redirect::Close)
    settle { capture(0).includes?("File") && !tmux("list-clients").empty? }
  end

  # The document md edits.
  def file : String
    File.join @dir, "doc.md"
  end

  # Runs tmux on this session's server; returns what it printed.
  def tmux(*args : String) : String
    output = IO::Memory.new
    Process.run("tmux", ["-L", SOCKET] + args.to_a, output: output, error: Process::Redirect::Close)
    output.to_s
  end

  # Presses *keys* (tmux key names) in window *index*.
  def keys(index : Int32, *keys : String) : Nil
    tmux "send-keys", "-t", "e2e:#{index}", *keys
  end

  # Makes window *index* tmux's current one: the others are told they are
  # unfocused.
  def select(index : Int32) : Nil
    tmux "select-window", "-t", "e2e:#{index}"
  end

  # The text shown in window *index*.
  def capture(index : Int32) : String
    tmux "capture-pane", "-p", "-t", "e2e:#{index}"
  end

  # The status bar of window *index*: its last line.
  def status(index : Int32) : String
    capture(index).lines.last? || ""
  end

  # The windows open, by index.
  def windows : Array(Int32)
    tmux("list-windows", "-F", "\#{window_index}").lines.compact_map(&.to_i?)
  end

  # Opens a second md window (Window → New from window 0) and waits for it.
  def new_window : Nil
    keys 0, "C-n"
    settle { windows.size == 2 && capture(1).includes?("File") }
  end

  # Waits for the condition, polling, for up to *timeout*.
  def settle(timeout = 5.seconds, &) : Nil
    deadline = Time.instant + timeout
    until yield
      raise "the condition was not met within #{timeout}" if Time.instant > deadline
      sleep 50.milliseconds
    end
  end

  def close : Nil
    tmux "kill-server"
    @client.terminate rescue nil
    @client.wait
    FileUtils.rm_rf @dir
  end
end

private def with_session(text = "# Title\n\none\ntwo\nthree\nfour\nfive\n", config : String? = nil, &)
  session = Session.new(text, config)
  begin
    yield session
  ensure
    session.close
  end
end

describe "md windows in a real terminal" do
  unless Process.find_executable("tmux") && File.exists?(File.expand_path("../bin/md", __DIR__))
    pending "needs tmux and bin/md (make e2e builds it)"
    next
  end

  it "shows an edit made in one window in the other, also while the other is unfocused" do
    with_session do |session|
      session.new_window
      session.select 1 # window 0 is in the background, told it is unfocused
      session.keys 1, "X", "Y", "Z"
      session.settle { session.capture(1).includes?("XYZ# Title") }
      session.settle { session.capture(0).includes?("XYZ# Title") } # painted without a click
    end
  end

  it "mirrors the caret in linked windows" do
    with_session(config: "md:\n  window_link: \"Linked\"\n") do |session|
      session.new_window
      session.select 1
      session.keys 1, "Down", "Down", "Down"
      session.settle { session.status(1).includes?("Ln 4,") }
      session.settle { session.status(0).includes?("Ln 4,") }
    end
  end

  it "closes nothing until the quit question is answered" do
    with_session do |session|
      session.new_window
      session.select 1
      session.keys 1, "X"
      session.keys 1, "C-q"
      session.settle { session.status(1).includes?("Save changes to") }
      session.windows.should eq [0, 1]
      session.capture(0).should contain "X# Title" # the first window is still there
      session.keys 1, "c"
      session.settle { !session.status(1).includes?("Save changes to") }
      session.windows.should eq [0, 1]
      session.keys 1, "C-q"
      session.settle { session.status(1).includes?("Save changes to") }
      session.keys 1, "n"
      session.settle { session.tmux("list-sessions").empty? } # md ended, and tmux with it
      File.read(session.file).should_not contain "X"
    end
  end
end
