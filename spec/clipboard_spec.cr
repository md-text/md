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
