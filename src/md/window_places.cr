require "yaml"

module Md
  # Where md's spawned windows were last time, kept across runs for Window →
  # Remember Positions (`md.remember_window_positions`), as a `QSettings`
  # key holding `QWidget::saveGeometry` would keep them. Off by default: the
  # window manager places a new window, as it places any other.
  #
  # Windows are known by number. The window md was started in is 1 and is
  # never moved — it is the user's own terminal, and md did not open it.
  # Each window Window → New opens takes the lowest number free from 2 while
  # it is open (`.free_number`), so the second window of this run opens
  # where the second window of the last run was closed. Frames are kept per
  # launcher (`"terminal.app"`, `"iterm2"`, `"ghostty"`): a frame from one
  # emulator means nothing to another.
  #
  # Only Crysterm can place a window and read its frame back
  # (`Crysterm::Window.open(frame:)`, `Window#frame_geometry`), and only for
  # Terminal.app and iTerm2 on macOS, through AppleScript, and Ghostty on
  # macOS, which sizes a window in whole cells; everywhere else
  # the menu entry is disabled with the reason
  # (`Crysterm::Terminal.frame_geometry_refusal`) and nothing is recorded.
  #
  # The store is `$XDG_STATE_HOME/md/windows.yml`
  # (`~/.local/state/md/windows.yml`): state the program writes, beside the
  # history. A missing or broken file is an empty store.
  class WindowPlaces
    # A frame, `{x, y, width, height}` in screen points from the top-left
    # corner of the main display (`Crysterm::Terminal::Frame`).
    alias Frame = Crysterm::Terminal::Frame

    # The file as stored: launcher name → window number → `[x, y, width,
    # height]`.
    alias Store = Hash(String, Hash(Int32, Array(Int32)))

    # The number of the window md was started in, which is never moved.
    FIRST = 1

    # The file the store is kept in.
    getter path : String

    # The displays' frames, in the frames' coordinates, or nil when they
    # cannot be listed: what `#frame_for` checks a remembered frame against,
    # so a window is not put on a display that is gone. Replaceable, so a
    # spec can stub the displays (`.desktop_screens` by default).
    class_property screens : Proc(Array(Frame)?) = -> : Array(Frame)? { desktop_screens }

    # The store every window of the process shares, loaded the first time it
    # is asked for. Replaceable, so a spec can use a scratch file.
    class_property(shared : WindowPlaces) { load }

    # `$XDG_STATE_HOME/md/windows.yml`.
    def self.default_path : String
      File.join History.state_dir, "windows.yml"
    end

    # Loads the store at *path*; a missing, unreadable or malformed file is
    # an empty store, as for the history: a lost position is a nuisance, a
    # failed start a bug.
    def self.load(path : String = default_path) : WindowPlaces
      new(path, Store.from_yaml(File.read(path)))
    rescue IO::Error | YAML::ParseException | TypeCastError
      new(path)
    end

    def initialize(@path : String, @frames = Store.new)
    end

    # The lowest window number from 2 that no open window in *taken* has:
    # the number a new window takes.
    def self.free_number(taken : Enumerable(Int32)) : Int32
      (FIRST + 1..).find! { |number| !taken.includes?(number) }
    end

    # The largest coordinate or size a frame may have, in points: past it a
    # frame is not one a display has (a store edited by hand), and its
    # AppleScript bounds (`x + width`) could overflow in Crysterm.
    MAX_COORDINATE = 1 << 20

    # The frame window *number* had when last closed under *launcher*, or nil
    # when none was recorded, it is the first window, the frame is not one a
    # display could have (`MAX_COORDINATE`), or it is on no display now
    # (`.screens`; displays that cannot be listed count as none, so a window
    # is never put where it may not be seen).
    def frame_for(launcher : String, number : Int32) : Frame?
      return if number == FIRST
      values = @frames[launcher]?.try(&.[number]?) || return
      return unless values.size == 4 && values[2] > 0 && values[3] > 0
      return unless values.all? { |value| -MAX_COORDINATE <= value <= MAX_COORDINATE }
      frame = {values[0], values[1], values[2], values[3]}
      frame if (screens = WindowPlaces.screens.call) && WindowPlaces.on_screen?(frame, screens)
    end

    # Records *frame* as window *number*'s under *launcher*, and writes the
    # store (`#save`). The first window is not recorded: it is never moved.
    def record(launcher : String, number : Int32, frame : Frame) : Nil
      return if number == FIRST
      (@frames[launcher] ||= {} of Int32 => Array(Int32))[number] = frame.to_a
      save
    end

    # The frames recorded under *launcher*, by window number (specs, and a
    # look at what is kept).
    def frames(launcher : String) : Hash(Int32, Frame)
      result = {} of Int32 => Frame
      @frames[launcher]?.try &.each do |number, values|
        result[number] = {values[0], values[1], values[2], values[3]} if values.size == 4
      end
      result
    end

    # Forgets every recorded frame (Options → Clear Caches…, which removes
    # the file); a window closing afterwards records its own afresh.
    def clear : Nil
      @frames.clear
    end

    # Writes the store to `path`, whole (`SaveFile`), making the directory
    # as needed. Returns false instead of raising: a position is not worth
    # an error, and this runs as a window closes.
    def save : Bool
      Dir.mkdir_p(File.dirname(@path))
      SaveFile.write @path, @frames.to_yaml
      true
    rescue IO::Error
      false
    end

    # Whether *frame*'s title strip — its top 20 points, where the window is
    # grabbed to move it — overlaps one of *screens*: a window there can be
    # seen and moved back. A frame on a display since removed overlaps none.
    # Summed in 64 bits: a store edited by hand to hold frames near
    # `Int32::MAX` overflows no sum, and leaves Window → New working.
    def self.on_screen?(frame : Frame, screens : Array(Frame)) : Bool
      x, y, width, _ = frame.map(&.to_i64)
      screens.any? do |screen|
        left, top, across, down = screen.map(&.to_i64)
        x < left + across && x + width > left && y < top + down && y + 20 > top
      end
    end

    # The displays' frames, from AppKit's `NSScreen.screens` through
    # JavaScript for Automation (which needs no Automation permission),
    # turned to the top-left origin AppleScript's window bounds use; nil
    # off macOS, or when `osascript` fails or gives no answer within
    # *timeout* (it is killed then): Window → New waits on it.
    def self.desktop_screens(timeout : Time::Span = 3.seconds) : Array(Frame)?
      {% if flag?(:darwin) %}
        output = IO::Memory.new
        process = Process.new("osascript", ["-l", "JavaScript", "-e", SCREENS_SCRIPT], output: output, error: Process::Redirect::Close)
        done = Channel(Process::Status).new 1
        spawn(name: "md window places: displays") { done.send process.wait }
        status = select
        when finished = done.receive then finished
        when timeout(timeout)
          process.signal Signal::KILL rescue nil
          nil
        end
        return unless status.try &.success?
        frames = output.to_s.lines.compact_map do |line|
          values = line.split(',').map(&.strip.to_i?)
          next unless values.size == 4 && values.none?(Nil)
          {values[0].not_nil!, values[1].not_nil!, values[2].not_nil!, values[3].not_nil!}
        end
        frames unless frames.empty?
      {% else %}
        nil
      {% end %}
    rescue IO::Error
      nil
    end

    # The JXA that lists the displays, one `x,y,width,height` per line. AppKit
    # puts the origin at the main display's bottom-left corner, y upward;
    # window bounds have it at the top-left, y downward.
    SCREENS_SCRIPT = <<-'JS'
      ObjC.import("AppKit");
      var screens = $.NSScreen.screens;
      var main = screens.objectAtIndex(0).frame;
      var lines = [];
      for (var i = 0; i < screens.count; i++) {
        var f = screens.objectAtIndex(i).frame;
        lines.push([f.origin.x, main.size.height - f.origin.y - f.size.height,
          f.size.width, f.size.height].map(Math.round).join(","));
      }
      lines.join("\n");
      JS
  end

  class App
    # Window → Remember Positions (`md.remember_window_positions`; see
    # `WindowPlaces`). A reactive property, so the menu entry binds to it
    # and the config keeps it (`app_config.cr`); off, nothing is recorded
    # and the window manager places every window.
    @remember_window_positions : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    def remember_window_positions? : Bool
      @remember_window_positions.value
    end

    def remember_window_positions=(value : Bool) : Bool
      @remember_window_positions.value = value
    end

    # This window's number (`WindowPlaces`): 1 for the window md was started
    # in, the lowest free from 2 for one Window → New opened.
    getter window_number : Int32 = WindowPlaces::FIRST

    protected setter window_number

    # Why windows cannot be placed here, in a sentence, or nil when they can:
    # Remember Positions' enabled state, and what its description adds
    # while disabled. Found once per process (`.window_place_refusal`), and
    # settable, so a spec can see the entry either way.
    @window_place_refusal : String?
    @remember_positions_action : Crysterm::Action?

    def window_place_refusal : String?
      @window_place_refusal
    end

    def window_place_refusal=(reason : String?) : String?
      @window_place_refusal = reason
      refresh_remember_positions
      reason
    end

    @@window_place_refusal : String?
    @@window_place_refusal_known = false

    # Crysterm's verdict on placing the windows `Window.open` opens from
    # this session (`Crysterm::Terminal.frame_geometry_refusal`), found the
    # first time it is asked for.
    def self.window_place_refusal : String?
      unless @@window_place_refusal_known
        @@window_place_refusal = Crysterm::Terminal.frame_geometry_refusal
        @@window_place_refusal_known = true
      end
      @@window_place_refusal
    end

    # The Window menu's Remember Positions entry, bound to its setting and
    # enabled as the session allows (`#build_window_menu`).
    private def add_remember_positions(menu : Crysterm::Widget::Menu) : Nil
      @window_place_refusal = App.window_place_refusal
      @remember_positions_action = add_toggle menu, "Remember &Positions", "remember-window-positions",
        @remember_window_positions, option_tip("md.remember_window_positions")
      refresh_remember_positions
    end

    # Enables Remember Positions where windows can be placed; disabled, its
    # description says why.
    private def refresh_remember_positions : Nil
      return unless action = @remember_positions_action
      text = option_tip("md.remember_window_positions")
      reason = @window_place_refusal
      action.enabled = reason.nil?
      tip action, reason ? "#{text}. Unavailable here: #{reason}" : text
    end

    # The number and the remembered frame for the window Window → New is
    # about to open: the lowest free number, and its frame from last time
    # when Remember Positions is on and windows can be placed here (nil
    # otherwise, leaving the window manager to place it).
    private def next_window_place : {Int32, WindowPlaces::Frame?}
      number = WindowPlaces.free_number(App.instances.map(&.window_number))
      return {number, nil} unless remember_window_positions? && @window_place_refusal.nil?
      launcher = Crysterm::Terminal.resolve_launcher(nil).try(&.name)
      {number, launcher.try { |name| WindowPlaces.shared.frame_for(name, number) }}
    end

    # Records where this window is, for the window with its number next time
    # (`#finish`): only for a window Window → New opened, with Remember
    # Positions on, and where the emulator can tell (one `osascript` run, at
    # close). A frame that cannot be read is let go quietly.
    private def record_window_place : Nil
      return unless remember_window_positions? && @window_number != WindowPlaces::FIRST
      launcher = @window.window.try(&.launcher).try(&.name) || return
      frame = @window.frame_geometry || return
      WindowPlaces.shared.record launcher, @window_number, frame
    rescue
      nil
    end
  end
end
