require "./spec_helper"

# Window → Linking → Linked (`md.window_link`, `ViewLink`): the windows on a
# document mirror each other, as the panes of one window.

LONG = (1..80).map { |number| "Line #{number} of the document." }.join('\n') + "\n"
# One paragraph a line, so the viewer has a block per source line.
PARAGRAPHS = (1..80).map { |number| "Line #{number} of the document." }.join("\n\n") + "\n"

private def window_menu(app)
  menu(app, 5)
end

# An opener of headless windows *width* by *height* cells, smaller than
# the first window's.
private def sized_opener(width, height)
  ->(title : String) do
    window = Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: width, height: height
    window.title = title
    window
  end
end

describe "Md::App linked windows" do
  it "registers md.window_link and offers it in Window → Linking" do
    Md::Config.options.map(&.key).should contain "md.window_link"
    with_app do |app|
      app.window_link.should eq Md::App::WindowLink::Separate
      window_menu(app).actions.map(&.text)[0, 3].should eq ["&New", "&Close Current", "&Linking"]
      entries = window_menu(app).actions[2].menu || fail("no submenu")
      entries.map(&.text).should eq ["&Separate Views", "&Linked (Mirrored)"]
      entries.map(&.name).should eq ["window-link-separate", "window-link-linked"]
      entries[0].checked?.should be_true
      app.run_command "window-link-linked"
      app.window_link.should eq Md::App::WindowLink::Linked
      Md::Documents.window_link.should eq Md::App::WindowLink::Linked
      entries[1].checked?.should be_true
    ensure
      Md::Documents.link_windows Md::App::WindowLink::Separate
    end
  end

  it "mirrors the editor caret and selection to the other window" do
    with_two_windows(text: LONG, view: false, linked: true) do |a, b|
      b.link.should be a.link
      a.editor.focus
      press a.window, Tput::Key::Down
      a.editor.text_cursor = Crysterm::TextCursor.new(a.document.text, 40, 50)
      settle { b.editor.cursor_position == 50 }
      b.editor.text_cursor.anchor.should eq 40
    end
  end

  it "mirrors scrolling: the same first line in windows of different heights" do
    with_two_windows(text: LONG, view: false, linked: true, opener: sized_opener(100, 20)) do |a, b|
      b.window.repaint
      a.editor.focus
      press a.window, Tput::Key::PageDown
      press a.window, Tput::Key::PageDown
      a.window.repaint
      top = a.editor.top_position
      top.should be > 0
      settle { b.editor.top_position == top }
    end
  end

  it "mirrors the viewer position, mapped through the source when the widths differ" do
    text = "# Title\n\n| a | b |\n|---|---|\n| one | two |\n\n" + LONG
    with_two_windows(text: text, linked: true, opener: sized_opener(60, 30)) do |a, b|
      b.window.repaint
      a.viewer.focus
      press a.window, Tput::Key::Down
      a.viewer.text_cursor = Crysterm::TextCursor.new(a.viewer.document, a.viewer_position(a.document.text.block_position(30)))
      a.window.repaint
      settle { b.editor_position(b.viewer.cursor_position) == a.editor_position(a.viewer.cursor_position) }
    end
  end

  it "with Sync Cursor, a move in A's editor moves B's viewer when B shows only the viewer" do
    with_two_windows(text: PARAGRAPHS, view: false, linked: true) do |a, b|
      b.show_pane(Md::App::Pane::Viewer).focus
      b.hide_pane Md::App::Pane::Editor
      a.sync_cursor = true
      a.editor.focus
      press a.window, Tput::Key::Down
      a.go_to_line 79
      a.window.repaint
      line = ->(app : Md::App) { app.viewer.document.block_at(app.viewer.cursor_position).index }
      settle { b.sync_cursor? && b.viewer.document.blocks[line.call(b)].text.starts_with?("Line 40 ") }
    end
  end

  it "shares the search: n in B finds the next match of A's pattern" do
    with_two_windows(text: LONG, view: false, linked: true) do |a, b|
      a.editor.focus
      press a.window, Tput::Key::Down
      a.editor.cursor_position = 0
      a.search("Line 7 ").should be_true
      a.window.repaint
      settle { b.search_pattern == "Line 7 " }
      b.editor.focus
      press b.window, Tput::Key::Down # B leads now
      b.find_next.should be_true
      b.editor.text_cursor.block_number.should eq 6
    end
  end

  it "shares the trail and moves the group together on Open, Previous File and File → Close" do
    first = tempfile "# First\n"
    second = tempfile "# Second\n"
    begin
      with_two_windows(Md::Source.new(path: first), "# First\n", linked: true) do |a, b|
        a.open_file(second).should be_true
        b.source.path.should eq second
        b.document.should be a.document
        b.previous_file_available?.should be_true
        b.previous_file.should be_true
        a.source.path.should eq first
        b.source.path.should eq first
        a.next_file_available?.should be_true
        a.close_document
        a.source.path.should eq second
        b.source.path.should eq second
        b.link.should be a.link
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  it "asks before the group leaves a modified document, which no window keeps" do
    other = tempfile "# Other\n"
    begin
      with_two_windows(linked: true) do |a, b|
        a.editor.insert_text "x"
        b.open_dropped(other).should be_true
        question(b).should start_with "Save changes to"
        answer b, 'n'
        a.source.path.should eq other
      end
    ensure
      File.delete? other
    end
  end

  it "makes the most recently used window the leader on linking, the others adopting its state" do
    with_two_windows(text: LONG, view: false) do |a, b|
      b.editor.cursor_position = 0
      a.editor.focus
      press a.window, Tput::Key::Down
      a.editor.cursor_position = 100
      press b.window, Tput::Key::Down
      b.editor.cursor_position = 200
      Md::Documents.link_windows Md::App::WindowLink::Linked
      a.window_link.should eq Md::App::WindowLink::Linked
      (a.link || fail("not linked")).leader.should be b
      b.window.repaint
      settle { a.editor.cursor_position == 200 }
      settle { notice(a).includes? "are linked" }
    end
  end

  it "leaves each window where it is on separating, with its own copy of the trail" do
    first = tempfile "# First\n"
    second = tempfile "# Second\n"
    begin
      with_two_windows(Md::Source.new(path: first), "# First\n", linked: true) do |a, b|
        a.open_file(second)
        a.trail.should be b.trail
        b.window_link = Md::App::WindowLink::Separate
        a.window_link.should eq Md::App::WindowLink::Separate
        a.link.should be_nil
        a.trail.should_not be b.trail
        a.trail.back.should eq b.trail.back
        b.previous_file.should be_true
        b.source.path.should eq first
        a.source.path.should eq second # alone now
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  it "mirrors a window opened with Ctrl-N at once, and hands leadership on when the leader closes" do
    with_two_windows(text: LONG, view: false, linked: true) do |a, b|
      (a.link || fail("not linked")).views.should eq [a, b]
      press b.window, Tput::Key::Down
      (b.link || fail("not linked")).leader.should be b
      b.window.close
      (a.link || fail("not linked")).leader.should be a
      (a.link || fail("not linked")).views.should eq [a]
    end
  end

  it "applies one mirror per follower for one key" do
    with_two_windows(text: LONG, view: false, linked: true) do |a, b|
      a.editor.focus
      a.window.repaint
      b.window.repaint
      a.editor.text_cursor = Crysterm::TextCursor.new(a.document.text, 0)
      a.window.repaint
      settle { b.editor.cursor_position == 0 }
      count = 0
      b.editor.on(Crysterm::Event::CursorPositionChanged) { count += 1 }
      press a.window, Tput::Key::Down
      a.window.repaint
      settle { count >= 1 }
      sleep 50.milliseconds
      count.should eq 1
    end
  end

  it "starts linked from the config" do
    with_config("md:\n  window_link: linked\n") do
      with_app config: true do |app|
        app.window_link.should eq Md::App::WindowLink::Linked
        Md::Documents.window_link.should eq Md::App::WindowLink::Linked
      end
    end
  ensure
    Md::Documents.link_windows Md::App::WindowLink::Separate
  end
end
