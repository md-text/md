require "./spec_helper"

# Window → Remember Positions (`window_places.cr`): the store of spawned
# windows' frames, by launcher and window number, and the hooks Window → New
# and a window's end use. The displays are stubbed; nothing runs osascript.

private SCREEN = {0, 0, 1920, 1080}

# Runs the block with a store in a scratch file as the shared one and
# *screens* as the displays, putting both back after.
private def with_places(screens = [SCREEN] of Md::WindowPlaces::Frame, &)
  dir = File.tempname("md-window-places")
  Dir.mkdir_p dir
  path = File.join(dir, "windows.yml")
  saved_screens = Md::WindowPlaces.screens
  saved_shared = Md::WindowPlaces.shared
  Md::WindowPlaces.screens = -> { screens.as(Array(Md::WindowPlaces::Frame)?) }
  places = Md::WindowPlaces.load(path)
  Md::WindowPlaces.shared = places
  begin
    yield places, path
  ensure
    Md::WindowPlaces.screens = saved_screens
    Md::WindowPlaces.shared = saved_shared
    FileUtils.rm_rf dir
  end
end

# An opener that records the frames it was asked to open at.
private def framing_opener(frames)
  ->(title : String, frame : Md::WindowPlaces::Frame?) do
    frames << frame
    window = headless_window
    window.title = title
    window
  end
end

private def remember_entry(app)
  menu(app, 5).actions.find! { |action| action.text == "Remember &Positions" }
end

describe Md::WindowPlaces do
  it "round-trips the store through its file" do
    with_places do |places, path|
      places.record "terminal.app", 2, {10, 20, 640, 480}
      places.record "terminal.app", 3, {700, 20, 640, 480}
      places.record "iterm2", 2, {5, 5, 300, 200}
      File.exists?(path).should be_true
      again = Md::WindowPlaces.load(path)
      again.frames("terminal.app").should eq({2 => {10, 20, 640, 480}, 3 => {700, 20, 640, 480}})
      again.frame_for("terminal.app", 3).should eq({700, 20, 640, 480})
    end
  end

  it "reads a missing or broken file as an empty store" do
    with_places do |_, path|
      Md::WindowPlaces.load(path).frames("terminal.app").should be_empty
      File.write path, "{ not: [yaml"
      Md::WindowPlaces.load(path).frames("terminal.app").should be_empty
      File.write path, "terminal.app: 7\n"
      Md::WindowPlaces.load(path).frames("terminal.app").should be_empty
    end
  end

  it "numbers new windows lowest-free from 2" do
    Md::WindowPlaces.free_number([1]).should eq 2
    Md::WindowPlaces.free_number([1, 2, 3]).should eq 4
    Md::WindowPlaces.free_number([1, 3]).should eq 2
    Md::WindowPlaces.free_number([] of Int32).should eq 2
  end

  it "offers a frame only for the launcher it was recorded under" do
    with_places do |places|
      places.record "terminal.app", 2, {10, 20, 640, 480}
      places.frame_for("terminal.app", 2).should eq({10, 20, 640, 480})
      places.frame_for("iterm2", 2).should be_nil
      places.frame_for("terminal.app", 3).should be_nil
    end
  end

  it "never records or moves the first window" do
    with_places do |places|
      places.record "terminal.app", 1, {10, 20, 640, 480}
      places.frames("terminal.app").should be_empty
      places.frame_for("terminal.app", 1).should be_nil
    end
  end

  it "drops a frame off every display, and every frame when the displays are unknown" do
    with_places([SCREEN, {1920, -200, 1280, 1024}]) do |places|
      places.record "terminal.app", 2, {2000, 0, 640, 480}   # on the second display
      places.record "terminal.app", 3, {4000, 100, 640, 480} # right of both
      places.record "terminal.app", 4, {100, 1100, 640, 480} # below the first
      places.frame_for("terminal.app", 2).should eq({2000, 0, 640, 480})
      places.frame_for("terminal.app", 3).should be_nil
      places.frame_for("terminal.app", 4).should be_nil
      Md::WindowPlaces.screens = -> { nil.as(Array(Md::WindowPlaces::Frame)?) }
      places.frame_for("terminal.app", 2).should be_nil
    end
  end

  it "keeps a frame whose title strip is on a display" do
    Md::WindowPlaces.on_screen?({-300, 10, 400, 300}, [SCREEN]).should be_true
    Md::WindowPlaces.on_screen?({100, -10, 400, 300}, [SCREEN]).should be_true
    Md::WindowPlaces.on_screen?({100, -30, 400, 300}, [SCREEN]).should be_false
  end
end

describe "Md::App Remember Positions" do
  it "passes the remembered frame to the opener and numbers the window" do
    with_places do |places|
      application = Crysterm::Application.new
      with_app Md::Source.new(path: "doc.md"), text: "# Doc\n", view: true do |app, window|
        application.add window
        app.window_place_refusal = nil
        launcher = Crysterm::Terminal.resolve_launcher(nil).try(&.name) || "terminal.app"
        places.record launcher, 2, {10, 20, 640, 480}
        frames = [] of Md::WindowPlaces::Frame?
        app.window_opener = framing_opener(frames)
        app.remember_window_positions = true
        app.window_number.should eq 1
        other = app.new_window || fail("no window was opened")
        begin
          other.window_number.should eq 2
          if Crysterm::Terminal.resolve_launcher(nil)
            frames.should eq [{10, 20, 640, 480}]
          end
        ensure
          other.window.destroy
        end
      end
    end
  end

  it "neither uses nor records a frame with the option off" do
    with_places do |places, path|
      application = Crysterm::Application.new
      with_app Md::Source.new(path: "doc.md"), text: "# Doc\n", view: true do |app, window|
        application.add window
        app.window_place_refusal = nil
        launcher = Crysterm::Terminal.resolve_launcher(nil).try(&.name) || "terminal.app"
        places.record launcher, 2, {10, 20, 640, 480}
        File.delete path
        frames = [] of Md::WindowPlaces::Frame?
        app.window_opener = framing_opener(frames)
        app.remember_window_positions?.should be_false
        other = app.new_window || fail("no window was opened")
        begin
          frames.should eq [nil] of Md::WindowPlaces::Frame?
          other.close_window
        ensure
          other.window.destroy
        end
        File.exists?(path).should be_false
      end
    end
  end

  it "disables the entry with the reason where windows cannot be placed" do
    with_app Md::Source.new(path: "doc.md"), text: "# Doc\n", view: true do |app|
      app.window_place_refusal = "kitty cannot place its windows"
      entry = remember_entry(app)
      entry.enabled?.should be_false
      entry.status_tip.to_s.should contain "Unavailable here: kitty cannot place its windows"
      app.window_place_refusal = nil
      entry.enabled?.should be_true
      entry.status_tip.to_s.should_not contain "Unavailable"
      entry.checked?.should be_false
      entry.trigger
      app.remember_window_positions?.should be_true
    end
  end
end
