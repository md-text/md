require "./spec_helper"
require "file_utils"

DOC = "# Title\n\nSome *text*.\n\n## Section\n\nMore.\n"

# An App built on a stream, as the CLI builds one for standard input (the
# chunks come through `#receive`), asked to open on *line*.
private def with_streaming_app(line : Int32, &)
  window = headless_window
  begin
    yield Md::App.new(Md::Source.new(stdin: true), stream: IO::Memory.new(""), view: true, window: window, line: line)
  ensure
    window.destroy
  end
end

describe Md::App do
  it "opens an empty editor for a new document" do
    with_app do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.editor.focused?.should be_true
      app.markdown.should eq ""
      app.title.should eq "[No Name] • MD"
      window.repaint
    end
  end

  it "opens a file in view mode" do
    with_app Md::Source.new(path: "doc.md"), text: DOC, view: true do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.viewer.focused?.should be_true
      app.markdown.should eq DOC
      app.title.should eq "doc.md • MD"
      app.viewer.document.plain_text.should contain "Some text."
      window.repaint
      window.dump.to_s.should contain "Title"
    end
  end

  it "colors the viewer by the window's stylesheet, like the other panes" do
    with_app Md::Source.new(path: "doc.md"), text: "# Title\n\n`code`\n", view: true do |app, window|
      window.stylesheet = <<-CSS
        Widget { background-color: #eff0f1; color: #31363b; }
        TextEdit::heading { color: #1f5fbf; }
        TextEdit::code { color: #a3400a; }
        CSS
      window.repaint
      heading = window.cell_rows[app.viewer.atop][app.viewer.aleft + 1]
      heading.char.should eq 'i'
      Crysterm::Attr.unpack_color(Crysterm::Attr.fg(heading.attr)).should eq 0x1f5fbf
      Crysterm::Attr.unpack_color(Crysterm::Attr.bg(heading.attr)).should eq 0xeff0f1
      code = window.cell_rows[app.viewer.atop + 2][app.viewer.aleft]
      code.char.should eq 'c'
      Crysterm::Attr.unpack_color(Crysterm::Attr.fg(code.attr)).should eq 0xa3400a
      Crysterm::Attr.unpack_color(Crysterm::Attr.bg(code.attr)).should eq Crysterm::ContentPalette.code_bg_for(0xeff0f1)
      # The document stores no colors; the view supplies them.
      app.viewer.document.blocks[0].fragments[0].format.fg.should be_nil

      window.stylesheet = <<-CSS
        Widget { background-color: #1d2023; color: #eff0f1; }
        TextEdit::heading { color: #86b5ff; }
        CSS
      window.repaint
      Crysterm::Attr.unpack_color(Crysterm::Attr.fg(heading.attr)).should eq 0x86b5ff
      Crysterm::Attr.unpack_color(Crysterm::Attr.bg(heading.attr)).should eq 0x1d2023
    end
  end

  it "opens a named file that does not exist yet in the editor" do
    with_app Md::Source.new(path: "new.md") do |app|
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.title.should eq "new.md • MD"
    end
  end

  it "re-renders the viewer from the editor as it is edited" do
    with_app do |app, window|
      app.show_pane Md::App::Pane::Viewer
      app.editor.insert_text "# Edited\n\nHello"
      app.markdown.should eq "# Edited\n\nHello"
      app.viewer.document.plain_text.should contain "Hello"
      app.toc.nodes.map(&.text).should eq ["Edited"]
      window.repaint
      window.dump.to_s.should contain "Hello"
    end
  end

  it "renders a hidden viewer when it is shown" do
    with_app do |app|
      app.editor.insert_text "# Later"
      app.viewer.document.plain_text.should_not contain "Later"
      app.show_pane Md::App::Pane::Toc
      app.viewer.document.plain_text.should contain "Later"
      app.toc.nodes.map(&.text).should eq ["Later"]
    end
  end

  it "streams a document into the viewer and the editor on demand" do
    with_app Md::Source.new(stdin: true), view: true do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.viewer.follow_tail?.should be_false
      app.stream IO::Memory.new("")
      app.viewer.follow_tail?.should be_true
      app.receive "# Stream\n"
      app.receive "\nline one\n"
      app.receive "line two"
      app.finish_stream
      app.markdown.should eq "# Stream\n\nline one\nline two"
      app.viewer.document.plain_text.should contain "line two"
      app.editor.value.should eq ""
      app.show_pane Md::App::Pane::Editor
      app.editor.value.should eq "# Stream\n\nline one\nline two"
      app.receive "\nline three\n"
      app.editor.value.should end_with "line three\n"
      window.repaint
      window.dump.to_s.should contain "line three"
    end
  end

  it "opens a stream on the line asked for once the viewer has it, or at the stream's end" do
    with_streaming_app line: 4 do |app|
      app.receive "# One\n"
      app.receive "\n"
      app.receive "two\n"
      app.receive "# Four\n"
      app.viewer.cursor_position.should eq 0 # the line is in, but held back until its blank line
      app.editor.value.should eq ""
      app.receive "\n"
      doc = app.viewer.document
      landed = doc.block_at(app.viewer.cursor_position).index
      doc.blocks[landed].text.should eq "Four"
      app.editor.value.should eq "# One\n\ntwo\n# Four\n\n" # brought up to date for the jump
      app.editor.text_cursor.block_number.should eq 3
      app.viewer.follow_tail?.should be_false # staying on the line, not the tail
      app.receive "six\n"
      app.editor.value.should end_with "six\n" # and following the stream since
      doc.block_at(app.viewer.cursor_position).index.should eq landed
    end
    # A line the editor has but the viewer not yet (a paragraph still open)
    # waits too, or the viewer would land on the block above and stay there.
    with_streaming_app line: 3 do |app|
      app.receive "# One\n\ntwo\n# Four\n"
      app.viewer.cursor_position.should eq 0
      app.receive "\n"
      doc = app.viewer.document
      doc.blocks[doc.block_at(app.viewer.cursor_position).index].text.should eq "two"
      app.editor.text_cursor.block_number.should eq 2
    end
    # A line the stream never reaches, or one counting from the end, waits
    # for the end.
    with_streaming_app line: 0 do |app|
      app.receive "a\n\nb\n\nc"
      app.viewer.cursor_position.should eq 0
      app.finish_stream
      doc = app.viewer.document
      doc.blocks[doc.block_at(app.viewer.cursor_position).index].text.should eq "c"
      app.editor.text_cursor.block_number.should eq 4
    end
  end

  it "shows, focuses and hides panes with the pane toggles" do
    with_app do |app|
      app.toggle_pane Md::App::Pane::Viewer
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
      app.viewer.focused?.should be_true
      app.toggle_pane Md::App::Pane::Viewer # focused: hides it
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.editor.focused?.should be_true
      app.toggle_pane Md::App::Pane::Editor # the last pane stays
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.toggle_pane Md::App::Pane::Toc
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Toc]
    end
  end

  it "tears down with every pane shown and the editor focused" do
    # Destroying the panes in layout order (editor, viewer, outline) used to
    # rewind focus from the viewer to the outline, whose focus-in refreshes
    # the status bar, and that refresh asked the detached viewer for its
    # geometry. Crysterm now releases focus before tearing a window down;
    # this keeps the arrangement that failed: the outline before the viewer
    # in the focus history, and the viewer focused when the window goes.
    with_app text: DOC do |app, window|
      app.toggle_pane Md::App::Pane::Editor
      app.toggle_pane Md::App::Pane::Toc
      app.viewer.focus
      app.visible_panes.size.should eq 3
      app.viewer.focused?.should be_true
      window.destroy
    end
  end

  it "reports an internal error in the status bar and goes on" do
    with_app text: DOC do |app, window|
      app.internal_error RuntimeError.new("boom")
      window.repaint
      # The notice takes the name field's place; the other fields stay.
      row = window.dump.to_s.lines[31][1..-2]
      row.should start_with " Internal error: boom"
      row.should_not contain "[No Name]"
      row.should contain "INS"
      app.main.status_bar.clear_message
      window.repaint
      window.dump.to_s.lines[31].should contain "[No Name]"
      app.markdown.should eq DOC
    end
  end

  it "saves to the named file, and asks for a name without one" do
    path = File.tempname("md-spec", ".md")
    begin
      with_app Md::Source.new(path: path) do |app|
        app.editor.insert_text "saved text"
        app.save.should be_true
        File.read(path).should eq "saved text"
      end
    ensure
      File.delete? path
    end
    with_app do |app, window|
      app.save.should be_false
      app.main.status_bar.prompting?.should be_true
      window.repaint
      window.dump.to_s.lines[31][1..-2].should start_with "Save as: "
    end
  end

  it "saves as a new name from the prompt, with the current name filled in" do
    path = File.tempname("md-spec", ".md")
    other = path.sub(".md", "-copy.md")
    begin
      with_app Md::Source.new(path: path) do |app, window|
        app.editor.insert_text "copied"
        app.save_as_prompt
        window.repaint
        field = app.main.status_bar.line_prompt.field
        field.value.should eq path
        field.focused?.should be_true
        field.value = other
        field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Enter)
        File.read(other).should eq "copied"
        File.exists?(path).should be_false
        app.source.path.should eq other
        app.title.should eq "#{other} • MD"
        app.main.status_bar.prompting?.should be_false
        app.editor.focused?.should be_true
        File.read_lines(other) # a second save goes straight to the new name
        app.editor.insert_text "!"
        app.save.should be_true
        File.read(other).should eq "copied!"
      end
    ensure
      File.delete? path
      File.delete? other
      File.delete? "#{other}~" # the second save backed the first up
    end
  end

  it "keeps the focused pane on Escape, with no divider to leave" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      window.repaint
      app.viewer.focused?.should be_true
      press(window, Tput::Key::Escape).accepted?.should be_false
      window.focused.should eq app.viewer # not rewound to nothing
      app.show_pane(Md::App::Pane::Editor).focus
      press(window, Tput::Key::Escape)
      window.focused.should eq app.editor # nor to the pane focused before
    end
  end

  it "keeps the application keys quiet while a prompt is open" do
    with_app do |app, window|
      app.save_as_prompt
      window.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::F2)
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.main.status_bar.line_prompt.cancel
      window.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::F2)
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
    end
  end
end

# The texts of the bar's shown fields in layout order: the name, then the
# permanent fields (Vi Mode's mode field only while it is on).
private def status_texts(app)
  bar = app.main.status_bar
  (bar.normal_widgets + bar.permanent_widgets).select(&.visible?).map { |field| field.as(Crysterm::Widget::Label | Crysterm::Widget::ToolButton).text }
end

describe "Md::App status bar" do
  it "describes the document in its fields" do
    with_app Md::Source.new(path: "doc.md"), text: DOC, view: true do |app, window|
      window.repaint
      bar = app.main.status_bar
      # The name is the bar's one normal field (it gives way to a notice);
      # the rest are permanent.
      bar.normal_widgets.size.should eq 1
      bar.permanent_widgets.size.should eq 7
      texts = status_texts app
      texts[0].should eq " doc.md"
      texts[1].should eq "All" # the whole document fits the viewer
      texts[2].should eq "7 lines, 7 words"
      texts[3].should eq "UTF-8 LF"
      texts[4].should eq ""
      texts[5].should eq "INS"
      texts[6].should eq "M=a"
      row = window.dump.to_s.lines[31][1..-2]
      row.should start_with " doc.md"
      row.should contain "7 lines, 7 words"
      row.should contain "INS"
      row.rstrip.should end_with "M=a"
    end
  end

  it "follows the caret, the modified flag and the overwrite mode while editing" do
    with_app do |app|
      app.editor.insert_text "ab\ncd"
      texts = -> { status_texts app }
      texts.call[0].should eq " [No Name]"
      texts.call[1].should eq "Ln 2, Col 3"
      texts.call[2].should eq "2 lines, 2 words"
      texts.call[4].should eq "✎ modified"
      app.editor.overwrite_mode = true
      texts.call[5].should eq "OVR"
      app.editor.cursor_pos = 1
      app.editor._listener Crysterm::Event::KeyPress.new('X')
      app.markdown.should eq "aX\ncd"
      texts.call[1].should eq "Ln 1, Col 3"
    end
  end

  it "cycles the mouse mode like vi's mouse= values and applies it to the terminal" do
    with_app Md::Source.new(path: "doc.md"), text: DOC, view: true do |app, window|
      button = app.main.status_bar.permanent_widgets.last.as(Crysterm::Widget::ToolButton)
      app.mouse_mode.should eq Md::App::MouseMode::All
      app.cycle_mouse_mode.should eq Md::App::MouseMode::Normal
      button.text.should eq "M=n"
      window.mouse_enabled?.should be_true # reading in the viewer
      app.show_pane(Md::App::Pane::Editor).focus
      window.mouse_enabled?.should be_false # editing: not in `n`
      app.cycle_mouse_mode.should eq Md::App::MouseMode::Insert
      window.mouse_enabled?.should be_true
      button.text.should eq "M=i"
      app.cycle_mouse_mode.should eq Md::App::MouseMode::Off
      window.mouse_enabled?.should be_false
      button.text.should eq "M="
      app.cycle_mouse_mode.should eq Md::App::MouseMode::All
      window.mouse_enabled?.should be_true
    end
  end

  it "shows a streaming marker, and asks for a name when saving a stream" do
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream IO::Memory.new("")
      app.receive "# One\n"
      name = app.main.status_bar.normal_widgets.first.as(Crysterm::Widget::Label)
      name.text.should eq " stdin (streaming)"
      app.finish_stream
      name.text.should eq " stdin"
      app.save.should be_false # no name: the prompt opens instead
      app.main.status_bar.prompting?.should be_true
    end
  end

  it "counts a streamed document chunk by chunk, a word or a line ending split between chunks once" do
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream IO::Memory.new("")
      size = app.main.status_bar.permanent_widgets[2].as(Crysterm::Widget::Label)
      encoding = app.main.status_bar.permanent_widgets[3].as(Crysterm::Widget::Label)
      app.receive "one two\r"
      size.text.should eq "1 line, 2 words"
      encoding.text.should eq "UTF-8 LF"
      app.receive "\nthr"
      size.text.should eq "2 lines, 3 words"
      encoding.text.should eq "UTF-8 CRLF"
      app.receive "ee four\n"
      size.text.should eq "2 lines, 4 words"
      app.finish_stream
      size.text.should eq "2 lines, 4 words"
      app.show_pane Md::App::Pane::Editor # the editor's text, measured afresh, says the same
      doc = app.editor.document
      app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.size)
      app.editor.insert_text "five"
      size.text.should eq "3 lines, 5 words"
    end
  end
end

describe "Md::App menus" do
  it "has File, Edit, Format, View, Options, Window and Help menus" do
    with_app do |app|
      app.main.menu_bar.menus.size.should eq 7
      menu(app, 0).actions.map(&.text).should eq ["&Open…", "Open &Recent", "Reloa&d", "&Close", "", "&Previous File", "&Next File", "", "&Save", "Save &As…", "", "&Quit"]
      menu(app, 0).actions[1].enabled?.should be_false # no history, nothing recent
      menu(app, 4).actions.map(&.text).should eq ["&Overwrite Mode", "&Ask Before Discarding Changes", "A&uto-Save", "&Keep a Backup File", "&Mouse", "&Clipboard", "Resi&zable Panes", "No An&imations", "D&etachable Menus", "Vi Mode: Use &Neovim Config", "", "&Load Config…", "&Save Config", "Sa&ve Config As…", "", "Clea&r Caches…"]
      menu(app, 2).actions.map(&.text).should eq ["&Bold", "&Italic", "&Code", "Code B&lock", "", "I&ndent", "&Outdent", "", "As a &Task", "Toggle Task Chec&kbox", "", "&Promote Heading", "&Demote Heading", "", "&Soft Wrap", "&Hard Wrap", "Te&xt Width", "Re&wrap (to 80 Columns)"]
      menu(app, 3).actions.map(&.text).should contain "The&me" # with the other appearance choices
    end
  end

  it "gives each entry of a menu or a submenu its own mnemonic" do
    with_app do |app|
      check = uninitialized Proc(String, Array(Crysterm::Action), Nil)
      check = ->(name : String, actions : Array(Crysterm::Action)) do
        letters = actions.reject(&.separator?).compact_map(&.mnemonic)
        {name, letters.tally.select { |_, count| count > 1 }.keys}.should eq({name, [] of Char})
        actions.each { |action| action.menu.try { |sub| check.call "#{name} → #{action.text}", sub } }
        nil
      end
      app.main.menu_bar.menus.each { |menu| check.call menu.title, menu.actions }
    end
  end

  it "names the keys that open the menu bar at its right end" do
    with_app do |_, window|
      window.repaint
      row = window.dump.to_s.lines[2]
      row.should match /\| File  Edit  Format  View  Options  Window  Help +Menu = F10 \/ Alt\+F \|$/
    end
  end

  it "shows and hides panes from the View menu, mirroring their state" do
    with_app do |app|
      editor, viewer, toc = menu(app, 3).actions[0, 3]
      editor.checked?.should be_true
      viewer.checked?.should be_false
      viewer.trigger
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
      viewer.checked?.should be_true
      app.hide_pane Md::App::Pane::Viewer
      viewer.checked?.should be_false
      editor.trigger # the last pane stays, and so does its check
      app.visible_panes.should eq [Md::App::Pane::Editor]
      editor.checked?.should be_true
      toc.text.should eq "&Table of Contents"
    end
  end

  it "sets the overwrite and mouse modes from the Options menu, in step with the status bar" do
    with_app do |app|
      overwrite, confirm = menu(app, 4).actions[0, 2]
      mouse = menu(app, 4).actions[4]
      confirm.checked?.should be_true
      confirm.trigger
      app.confirm_discard?.should be_false
      overwrite.trigger
      app.editor.overwrite_mode?.should be_true
      app.editor.overwrite_mode = false
      overwrite.checked?.should be_false

      modes = mouse.menu || [] of Crysterm::Action
      modes.map(&.text).should eq ["M=&a (Always)", "M=&n (While Reading)", "M=&i (While Editing)", "M= (Ne&ver)"]
      modes.map(&.checked?).should eq [true, false, false, false]
      modes[2].trigger
      app.mouse_mode.should eq Md::App::MouseMode::Insert
      modes.map(&.checked?).should eq [false, false, true, false]
      app.cycle_mouse_mode # from the status bar / F5
      app.mouse_mode.should eq Md::App::MouseMode::Off
      modes.map(&.checked?).should eq [false, false, false, true]
      modes[3].trigger # re-picking the checked mode keeps it
      modes.map(&.checked?).should eq [false, false, false, true]
    end
  end
end

describe "Md::App config" do
  it "applies the configured choices and records changes, saving them at exit" do
    yaml = <<-YAML
      md:
        sync_cursor: true
        highlight_line: true
        confirm_discard: false
        mouse_mode: insert
        line_numbers: true
        pane_sizes: "40,60,20"
      YAML
    with_config yaml do |path|
      with_app Md::Source.new(path: "doc.md"), text: DOC, view: true, config: true do |app, window|
        app.config?.should be_true
        app.sync_cursor?.should be_true
        app.highlight_line?.should be_true
        app.editor.highlight_current_line?.should be_true
        app.viewer.highlight_current_line?.should be_true
        app.confirm_discard?.should be_false
        app.mouse_mode.should eq Md::App::MouseMode::Insert
        window.mouse_enabled?.should be_false # reading in the viewer: not in `i`
        app.editor.line_numbers?.should be_true
        app.pane_sizes.should eq [40, 60, 20]
        follow, highlight = menu(app, 3).actions.select { |a| a.text.in?("S&ync Cursor", "&Highlight Line") }
        follow.checked?.should be_true
        highlight.checked?.should be_true
        Md::Config.dirty?.should be_false # applying is not a change

        follow.trigger
        app.sync_cursor?.should be_false
        Crysterm::Config.md_sync_cursor.should be_false # recorded at once
        app.cycle_mouse_mode.should eq Md::App::MouseMode::Off
        app.confirm_discard = true
        app.editor.line_numbers = false
        app.line_numbers?.should be_false
        Md::Config.dirty?.should be_true
        app.save_config
        Md::Config.dirty?.should be_false
      end

      file = config_file(path)["md"]
      file["sync_cursor"].as_bool.should be_false
      file["highlight_line"].as_bool.should be_true
      file["confirm_discard"].as_bool.should be_true
      file["mouse_mode"].as_s.should eq "Off"
      file["line_numbers"].as_bool.should be_false
      file["pane_sizes"].as_s.should eq "40,60,20"
    end
  end

  it "keeps the defaults for choices never made, and runs without the config" do
    with_config do
      with_app config: true do |app|
        app.sync_cursor?.should be_false
        app.highlight_line?.should be_false
        app.confirm_discard?.should be_true
        app.mouse_mode.should eq Md::App::MouseMode::All
        Md::Config.dirty?.should be_false
      end
    end
    with_app do |app|
      app.config?.should be_false
      app.sync_cursor = true
      Crysterm::Config.md_sync_cursor.should be_false # a spec's pick stays its own
      app.save_config
    end
  end
end
