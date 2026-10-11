require "./spec_helper"
require "file_utils"

DOC = "# Title\n\nSome *text*.\n\n## Section\n\nMore.\n"

describe Md::App do
  it "opens an empty editor for a new document" do
    with_app do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.editor.focused?.should be_true
      app.markdown.should eq ""
      app.title.should eq "md"
      window.repaint
    end
  end

  it "opens a file in view mode" do
    with_app Md::Source.new(path: "doc.md"), text: DOC, view: true do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.viewer.focused?.should be_true
      app.markdown.should eq DOC
      app.title.should eq "md - doc.md"
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
      app.title.should eq "md - new.md"
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
        app.title.should eq "md - #{other}"
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

  it "keeps the application keys quiet while a prompt is open" do
    with_app do |app, window|
      app.save_as_prompt
      window.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::F3)
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.main.status_bar.line_prompt.cancel
      window.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::F3)
      app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
    end
  end
end

# The texts of the bar's fields in layout order: the name, then the
# permanent fields.
private def status_texts(app)
  bar = app.main.status_bar
  (bar.normal_widgets + bar.permanent_widgets).map { |field| field.as(Crysterm::Widget::Label | Crysterm::Widget::ToolButton).text }
end

describe "Md::App status bar" do
  it "describes the document in its fields" do
    with_app Md::Source.new(path: "doc.md"), text: DOC, view: true do |app, window|
      window.repaint
      bar = app.main.status_bar
      # The name is the bar's one normal field (it gives way to a notice);
      # the rest are permanent.
      bar.normal_widgets.size.should eq 1
      bar.permanent_widgets.size.should eq 6
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
end

describe "Md::App menus" do
  it "has File, Edit, View and Options menus" do
    with_app do |app|
      app.main.menu_bar.menus.size.should eq 5
      menu(app, 0).actions.map(&.text).should eq ["&Open…", "Open &Recent", "&Reload", "", "&Save", "Save &As…", "", "&Quit"]
      menu(app, 0).actions[1].enabled?.should be_false # no history, nothing recent
      menu(app, 1).actions.map(&.text).should eq ["&Copy", "Copy as &Markdown", "", "&Find…", "Find &Next", "Find &Previous", "&Replace…", "Clear &Highlight", "", "&Go to Line…", "Nex&t Heading", "Pre&vious Heading", "", "&Back", "For&ward"]
      menu(app, 2).actions.map(&.text).should eq ["&Bold", "&Italic", "&Code", "", "&Toggle Task", "I&ndent", "&Outdent", "", "&Promote Heading", "&Demote Heading"]
      menu(app, 3).actions.map(&.text).should eq ["&Editor", "&Viewer", "&Table of contents", "&Resize panes", "", "&Follow cursor", "&Highlight line", "Line &numbers", "", "&Soft wrap", "Te&xt width", "&Center text", "", "&Watch file"]
      menu(app, 4).actions.map(&.text).should eq ["&Overwrite mode", "&Ask before discarding changes", "A&uto-save", "&Keep a backup file", "&Mouse", "&Theme", "&Clipboard"]
    end
  end

  it "names the keys that open the menu bar at its right end" do
    with_app do |_, window|
      window.repaint
      row = window.dump.to_s.lines[2]
      row.should match /\| File  Edit  Format  View  Options +Menu = F10 \/ Alt\+F \|$/
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
      toc.text.should eq "&Table of contents"
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
      modes.map(&.text).should eq ["M=&a (always)", "M=&n (while reading)", "M=&i (while editing)", "M= (&never)"]
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

describe "Md::App settings" do
  it "applies the stored choices and records changes, saving them at exit" do
    dir = File.tempname("md-spec-settings")
    Dir.mkdir_p dir
    path = File.join(dir, "settings.json")
    begin
      File.write path, <<-JSON
        {"version": 1, "settings": {"follow_cursor": true, "highlight_line": true,
         "confirm_discard": false, "mouse_mode": "insert", "line_numbers": true,
         "pane_sizes": [40, 60, 20]}}
        JSON
      settings = Md::Settings.load(path)
      with_app Md::Source.new(path: "doc.md"), text: DOC, view: true, settings: settings do |app, window|
        app.settings.should be settings
        app.follow_cursor?.should be_true
        app.highlight_line?.should be_true
        app.editor.highlight_current_line?.should be_true
        app.viewer.highlight_current_line?.should be_true
        app.confirm_discard?.should be_false
        app.mouse_mode.should eq Md::App::MouseMode::Insert
        window.mouse_enabled?.should be_false # reading in the viewer: not in `i`
        app.editor.line_numbers?.should be_true
        follow, highlight = menu(app, 3).actions[5, 2]
        follow.checked?.should be_true
        highlight.checked?.should be_true
        settings.dirty?.should be_false # applying is not a change

        follow.trigger
        app.follow_cursor?.should be_false
        app.cycle_mouse_mode.should eq Md::App::MouseMode::Off
        app.confirm_discard = true
        app.editor.line_numbers = false
        settings.dirty?.should be_true
        app.save_settings
        settings.dirty?.should be_false
      end

      reloaded = Md::Settings.load(path)
      reloaded.follow_cursor?.should be_false
      reloaded.highlight_line?.should be_true
      reloaded.confirm_discard?.should be_true
      reloaded.mouse_mode.should eq Md::App::MouseMode::Off
      reloaded.line_numbers?.should be_false
      reloaded.pane_sizes.should eq [40, 60, 20]
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "keeps the defaults for choices never made, and runs without a store" do
    with_app settings: Md::Settings.new("unused.json") do |app|
      app.follow_cursor?.should be_false
      app.highlight_line?.should be_false
      app.confirm_discard?.should be_true
      app.mouse_mode.should eq Md::App::MouseMode::All
      app.settings.try(&.dirty?).should be_false
    end
    with_app do |app|
      app.settings.should be_nil
      app.follow_cursor = true
      app.save_settings
    end
  end
end
