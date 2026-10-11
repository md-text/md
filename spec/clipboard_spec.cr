require "./spec_helper"
require "base64"

# The clipboard is the process's, shared by every app built in the specs:
# the block gets it with a recording runner and test commands in place of
# whatever the machine has, and leaves it as it was found.
private def with_clipboard(&)
  clip = Crysterm::Application.global.clipboard
  mode, copy, paste, runner = clip.mode, clip.copy_command, clip.paste_command, clip.command_runner
  recorder = Recorder.new
  clip.command_runner = recorder.to_proc
  clip.copy_command = ["copy-cmd", "--in"]
  clip.paste_command = ["paste-cmd", "--out"]
  begin
    yield clip, recorder
  ensure
    clip.mode = mode
    clip.copy_command = copy
    clip.paste_command = paste
    clip.command_runner = runner
  end
end

# A command runner that records the commands and their input and answers
# with *output* (nil: the command failed).
private class Recorder
  getter calls = [] of {Array(String), String}
  property output : String? = ""

  def to_proc : Crysterm::Application::Clipboard::CommandRunner
    ->(argv : Array(String), input : String) do
      @calls << {argv, input}
      @output
    end
  end
end

# What the terminal was sent since *output* was last cleared.
private def sent(window)
  window.output.as(IO::Memory).to_s
end

# Puts the viewer's caret at the start of the first block whose text starts
# with *text*.
private def caret_on(app, text)
  doc = app.viewer.document
  block = doc.blocks.find(&.text.starts_with?(text)) || fail("no block starts with #{text.inspect}")
  app.viewer.text_cursor = Crysterm::TextCursor.new(doc, block.position)
  block
end

CLIP_DOC = <<-MD
  # Title

  A paragraph with *emphasis* here.

  - first item
  - second item
  ```crystal
  puts 1
  puts 2
  ```

  Last words.
  MD

describe "Md::App copying" do
  it "copies the block the viewer's caret is in, as plain text, to the terminal" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app, window|
        caret_on app, "A paragraph"
        window.output.as(IO::Memory).clear
        app.copy
        clip.text.should eq "A paragraph with emphasis here."
        sent(window).should contain Base64.strict_encode("A paragraph with emphasis here.")
        notice(app).should eq " Copied 31 characters"

        caret_on app, "second"
        app.copy
        clip.text.should eq "second item"
        notice(app).should eq " Copied 11 characters"
      end
    end
  end

  it "copies a fenced code block whole, from any of its lines" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app|
        caret_on app, "puts 2"
        app.copy
        clip.text.should eq "puts 1\nputs 2"
        notice(app).should eq " Copied 2 lines"
      end
    end
  end

  it "copies the viewer's selection when there is one" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app, window|
        block = caret_on app, "A paragraph"
        app.viewer.cursor_pos = block.position + 11
        app.viewer.selection_anchor = block.position
        window.output.as(IO::Memory).clear
        app.copy
        clip.text.should eq "A paragraph"
        sent(window).should contain Base64.strict_encode("A paragraph")
        notice(app).should eq " Copied 11 characters"
      end
    end
  end

  it "copies from the table of contents what the viewer's caret is on" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app|
        caret_on app, "Last words"
        app.show_pane(Md::App::Pane::Toc).focus
        app.copy
        clip.text.should eq "Last words."
      end
    end
  end

  it "copies the editor's selection, or the caret's line" do
    with_clipboard do |clip|
      with_app Md::Source.new, text: CLIP_DOC, view: false do |app|
        app.editor.focused?.should be_true
        line = app.editor.document.block_position(2)
        app.editor.cursor_position = line + 3
        app.copy
        clip.text.should eq "A paragraph with *emphasis* here."
        notice(app).should eq " Copied 33 characters"
        app.editor.cursor_pos = line + 11
        app.editor.selection_anchor = line
        app.copy
        clip.text.should eq "A paragraph"
        app.copy_as_markdown # the editor's text is the Markdown
        clip.text.should eq "A paragraph"
      end
    end
  end

  it "copies the current block's Markdown source" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app|
        caret_on app, "A paragraph"
        app.copy_as_markdown
        clip.text.should eq "A paragraph with *emphasis* here."
        # The fence that follows the item opens the code block, not the item.
        caret_on app, "second"
        app.copy_as_markdown
        clip.text.should eq "- second item"
        # A code block comes with its fences.
        caret_on app, "puts 1"
        app.copy_as_markdown
        clip.text.should eq "```crystal\nputs 1\nputs 2\n```"
        notice(app).should eq " Copied 4 lines"
        caret_on app, "Last words"
        app.copy_as_markdown
        clip.text.should eq "Last words."
        # A selection takes the source of every block it touches.
        block = caret_on app, "first"
        app.viewer.selection_anchor = block.position
        app.viewer.cursor_pos = app.viewer.document.plain_text.index!("puts 2") + 3
        app.copy_as_markdown
        clip.text.should eq "- first item\n- second item\n```crystal\nputs 1\nputs 2\n```"
      end
    end
  end

  it "says when there is nothing to copy" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), view: true do |app|
        clip.copy "before"
        app.viewer.focused?.should be_true
        app.copy
        notice(app).should eq " Nothing to copy"
        clip.text.should eq "before"
      end
    end
  end

  it "copies on Ctrl+C when the pane has no selection to copy itself" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app, window|
        caret_on app, "Last words"
        press(window, Tput::Key::CtrlC).accepted?.should be_true
        clip.text.should eq "Last words."
        notice(app).should eq " Copied 11 characters"
      end
    end
  end
end

describe "Md::App clipboard modes" do
  it "pipes the copy to the command in Command mode, and to nothing in Internal mode" do
    with_clipboard do |clip, recorder|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app, window|
        caret_on app, "Last words"
        app.clipboard_mode = Md::App::ClipboardMode::Command
        clip.mode.should eq Crysterm::Application::Clipboard::Mode::Command
        window.output.as(IO::Memory).clear
        app.copy
        recorder.calls.should eq [{["copy-cmd", "--in"], "Last words."}]
        sent(window).should_not contain Base64.strict_encode("Last words.")
        notice(app).should eq " Copied 11 characters"

        recorder.output = nil
        app.copy
        notice(app).should eq " Copied 11 characters within md only: copy-cmd failed"
        clip.text.should eq "Last words."

        app.clipboard_mode = Md::App::ClipboardMode::Internal
        recorder.calls.clear
        app.copy
        recorder.calls.should be_empty
        sent(window).should_not contain Base64.strict_encode("Last words.")
        notice(app).should eq " Copied 11 characters"
        clip.text.should eq "Last words."
      end
    end
  end

  it "offers the modes under Options → Clipboard, the current one checked" do
    with_clipboard do |clip|
      with_app do |app|
        modes = menu(app, 4).actions.find!(&.text.==("&Clipboard")).menu || [] of Crysterm::Action
        modes.map(&.text).should eq ["&Terminal (OSC 52)", "&Command (copy-cmd)", "&Internal (Within md)"]
        modes.map(&.checked?).should eq [true, false, false]
        modes.all?(&.enabled?).should be_true
        modes[1].trigger
        app.clipboard_mode.should eq Md::App::ClipboardMode::Command
        clip.mode.should eq Crysterm::Application::Clipboard::Mode::Command
        modes.map(&.checked?).should eq [false, true, false]
        app.clipboard_mode = Md::App::ClipboardMode::Internal
        modes.map(&.checked?).should eq [false, false, true]
        modes[2].trigger # re-picking the checked mode keeps it
        modes.map(&.checked?).should eq [false, false, true]
      end

      # Without a command on the PATH the entry says so and cannot be picked.
      clip.copy_command = nil
      with_app do |app|
        modes = menu(app, 4).actions.find!(&.text.==("&Clipboard")).menu || [] of Crysterm::Action
        modes[1].text.should eq "&Command (None Found)"
        modes[1].enabled?.should be_false
      end
    end
  end

  it "keeps the mode in the settings and restores it" do
    with_clipboard do |clip|
      settings = Md::Settings.new("unused.json")
      settings.clipboard_mode.should be_nil
      settings.clipboard_mode = Md::App::ClipboardMode::Internal
      settings.get("clipboard_mode", "").should eq "internal"
      with_app settings: settings do |app|
        app.clipboard_mode.should eq Md::App::ClipboardMode::Internal
        clip.mode.should eq Crysterm::Application::Clipboard::Mode::Internal
        app.clipboard_mode = Md::App::ClipboardMode::Terminal
        settings.clipboard_mode.should eq Md::App::ClipboardMode::Terminal
      end
      # A new app without a stored choice starts from the default, and
      # applies it to the shared clipboard.
      with_app do |app|
        app.clipboard_mode.should eq Md::App::ClipboardMode::Terminal
        clip.mode.should eq Crysterm::Application::Clipboard::Mode::Terminal
      end
    end
  end
end

# The Paste Special entries under Edit, by their text.
private def paste_special(app)
  menu(app, 1).actions.find!(&.text.==("Paste &Special")).menu || [] of Crysterm::Action
end

describe "Md::App pasting" do
  it "pastes the clipboard into the editor at the caret, replacing the selection, as one undo step" do
    with_clipboard do |clip|
      with_app Md::Source.new, text: CLIP_DOC, view: false do |app|
        clip.mode = Crysterm::Application::Clipboard::Mode::Internal
        clip.copy "pasted"
        app.show_pane Md::App::Pane::Viewer
        app.editor.focus
        app.editor.cursor_position = 0
        app.paste
        app.markdown.should start_with "pasted# Title"
        app.viewer.document.plain_text.should start_with "pasted# Title" # the viewer followed
        notice(app).should eq " Pasted 6 characters"
        app.editor.selection_anchor = 0
        app.editor.cursor_pos = 6
        clip.copy "two\nlines"
        app.paste
        app.markdown.should start_with "two\nlines# Title"
        notice(app).should eq " Pasted 2 lines"
        app.editor.document.undo # the deletion and the insertion together
        app.markdown.should start_with "pasted# Title"
      end
    end
  end

  it "says when there is nothing to paste, and why a command paste failed" do
    with_clipboard do |clip, recorder|
      with_app do |app|
        clip.mode = Crysterm::Application::Clipboard::Mode::Internal
        clip.copy ""
        app.paste
        notice(app).should eq " Nothing to paste"
        app.clipboard_mode = Md::App::ClipboardMode::Command
        recorder.output = nil
        app.paste
        notice(app).should eq " Cannot paste: paste-cmd failed"
        recorder.output = "from the command"
        app.paste
        recorder.calls.last.should eq({["paste-cmd", "--out"], ""})
        app.markdown.should eq "from the command"
      end
    end
  end

  it "pastes on Ctrl+V from the viewer, showing and focusing the editor at the source of the viewer's caret" do
    with_clipboard do |clip|
      with_app Md::Source.new(path: "doc.md"), text: CLIP_DOC, view: true do |app, window|
        clip.mode = Crysterm::Application::Clipboard::Mode::Internal
        clip.copy "NEW "
        caret_on app, "Last words"
        app.visible_panes.should eq [Md::App::Pane::Viewer]
        press(window, Tput::Key::CtrlV).accepted?.should be_true
        app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
        app.editor.focused?.should be_true
        app.markdown.should contain "NEW Last words."
        # From the table of contents too.
        caret_on app, "A paragraph"
        app.show_pane(Md::App::Pane::Toc).focus
        press(window, Tput::Key::CtrlV).accepted?.should be_true
        app.editor.focused?.should be_true
        app.markdown.should contain "NEW A paragraph"
      end
    end
  end

  it "offers the sources under Edit → Paste Special" do
    with_clipboard do |clip|
      with_app do |app|
        entries = paste_special(app)
        entries.map(&.text).should eq ["From &Terminal Clipboard", "From &Command (paste-cmd)", "From &Internal Buffer", "From &Kill Ring"]
        entries.map(&.enabled?).should eq [true, true, true, false]
        menu(app, 1).actions.find!(&.text.==("&Paste")).shortcut_text.should eq "Ctrl+V"
      end
      clip.paste_command = nil
      with_app do |app|
        entries = paste_special(app)
        entries[1].text.should eq "From &Command (none found)"
        entries[1].enabled?.should be_false
      end
    end
  end

  it "pastes the command's output and the internal buffer whatever the mode" do
    with_clipboard do |clip, recorder|
      with_app do |app|
        clip.mode = Crysterm::Application::Clipboard::Mode::Terminal
        clip.copy "internal"
        recorder.output = "from the command"
        app.paste_from_command
        app.markdown.should eq "from the command"
        app.editor.select_all
        app.paste_from_internal
        app.markdown.should eq "internal"
        recorder.output = nil
        app.paste_from_command
        notice(app).should eq " Cannot paste: paste-cmd failed"
        app.markdown.should eq "internal"
      end
    end
  end

  it "asks the terminal for its clipboard and pastes the answer, or gives up after the wait" do
    with_clipboard do |clip|
      with_app do |app, window|
        clip.mode = Crysterm::Application::Clipboard::Mode::Internal # the terminal is asked regardless
        window.output.as(IO::Memory).clear
        app.paste_from_terminal
        sent(window).should contain "\e]52;c;?" # the OSC 52 read
        notice(app).should contain "Asking the terminal"
        window.emit Crysterm::Event::ClipboardChanged, Crysterm::Event::ClipboardChanged.new("from the terminal")
        app.markdown.should eq "from the terminal"
        notice(app).should eq " Pasted 17 characters"
        # A late answer is not a second paste.
        window.emit Crysterm::Event::ClipboardChanged, Crysterm::Event::ClipboardChanged.new("again")
        app.markdown.should eq "from the terminal"

        app.terminal_paste_timeout = 30.milliseconds
        app.paste_from_terminal
        settle { notice(app).includes? "did not answer" }
        app.markdown.should eq "from the terminal"
        window.emit Crysterm::Event::ClipboardChanged, Crysterm::Event::ClipboardChanged.new("too late")
        app.markdown.should eq "from the terminal"
      end
    end
  end

  it "lists the kill ring most recent first as the Edit menu opens, and pastes the entry picked" do
    with_clipboard do |_|
      with_app do |app|
        ring = Crysterm::KillRing.new
        app.editor.kill_ring = ring
        app.paste_from_kill_ring
        notice(app).should eq " Nothing killed yet"
        ring.kill "first kill"
        ring.interrupt
        ring.kill "second\nkill & more"
        app.kill_ring_entries.should eq ["second\nkill & more", "first kill"]
        edit = menu(app, 1)
        edit.emit Crysterm::Event::AboutToShow
        ring_action = paste_special(app)[3]
        ring_action.enabled?.should be_true
        entries = ring_action.menu || [] of Crysterm::Action
        entries.map(&.text).should eq ["&1 second⏎kill && more", "&2 first kill"]
        entries[1].trigger
        app.markdown.should eq "first kill"
        app.paste_from_kill_ring 0
        app.markdown.should eq "first killsecond\nkill & more"
        app.paste_from_kill_ring 5
        notice(app).should eq " No kill ring entry 6"
      end
    end
  end
end
