require "./spec_helper"
require "file_utils"

# The File menu's Previous File and Next File entries.
private def navigation(app)
  actions = app.main.menu_bar.menus[0].actions
  {actions.find! { |a| a.text == "&Previous File" }, actions.find! { |a| a.text == "&Next File" }}
end

# A directory with two linked documents; yields their paths.
private def with_docs(&)
  dir = File.tempname("md-spec-links")
  Dir.mkdir_p dir
  source = File.join(dir, "source.md")
  target = File.join(dir, "docs", "target.md")
  Dir.mkdir_p File.dirname(target)
  File.write source, SOURCE_DOC
  File.write target, TARGET_DOC
  File.write File.join(dir, "picture.png"), "not really a picture"
  yield dir, source, target
ensure
  FileUtils.rm_rf dir if dir
end

SOURCE_DOC = <<-MD
  # Source

  See [the target](docs/target.md), [its section](docs/target.md#deep),
  [the site](https://example.com/page), [a picture](picture.png),
  [a missing one](nowhere.md) and [the end](#the-end).

  Padding.

  ## The end

  Done.

  MD

TARGET_DOC = <<-MD
  # Target

  Intro.

  ## Deep

  Down here.

  MD

describe "Md::App links" do
  it "opens a relative Markdown link in the same window, and Backspace returns to the place left" do
    with_docs do |_dir, source, target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app, window|
        app.show_pane Md::App::Pane::Editor
        app.viewer.focus
        window.repaint
        back, forward = navigation(app)
        back.enabled?.should be_false
        app.go_to_line 7
        app.viewer.activate_link "docs/target.md" # Enter on the link, with the viewer's event
        app.source.path.should eq target
        app.markdown.should eq TARGET_DOC
        app.title.should eq "md - #{target}"
        app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
        back.enabled?.should be_true
        forward.enabled?.should be_false
        app.previous_file_available?.should be_true

        press window, Tput::Key::Backspace
        app.source.path.should eq source
        app.editor.text_cursor.block_number.should eq 6
        app.viewer.document.plain_text[app.viewer.cursor_position, 7].should eq "Padding"
        back.enabled?.should be_false
        forward.enabled?.should be_true

        app.next_file.should be_true
        app.source.path.should eq target
        forward.enabled?.should be_false
        back.enabled?.should be_true
        app.next_file.should be_false
        notice(app).should contain "No next file"
      end
    end
  end

  it "lands on the heading a relative link's fragment names" do
    with_docs do |_dir, source, target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app|
        app.show_pane Md::App::Pane::Editor
        app.viewer.focus
        app.follow_link "docs/target.md#deep"
        app.source.path.should eq target
        app.viewer.document.plain_text[app.viewer.cursor_position, 4].should eq "Deep"
        app.editor.text_cursor.block_number.should eq 4
        app.previous_file.should be_true
        app.source.path.should eq source
      end
    end
  end

  it "hands an external link to the opener and keeps the document" do
    with_docs do |_dir, source, _target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app|
        opened = [] of String
        app.url_opener = ->(url : String) { opened << url; nil }
        app.viewer.activate_link "https://example.com/page"
        opened.should eq ["https://example.com/page"]
        app.source.path.should eq source
        app.markdown.should eq SOURCE_DOC
        notice(app).should contain "Opening https://example.com/page"
        app.previous_file_available?.should be_false

        app.follow_link "mailto:someone@example.com"
        opened.last.should eq "mailto:someone@example.com"

        # An existing file that is not Markdown goes the same way, by path.
        app.follow_link "picture.png"
        opened.last.should eq File.join(File.dirname(source), "picture.png")

        app.url_opener = ->(url : String) { raise File::NotFoundError.new("no opener", file: url) }
        app.follow_link "https://example.com/other"
        notice(app).should contain "Cannot open URL: no opener"
      end
    end
  end

  it "notices a link to a file that does not exist" do
    with_docs do |_dir, source, _target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app|
        app.follow_link "nowhere.md"
        notice(app).should contain "No such file: #{File.join(File.dirname(source), "nowhere.md")}"
        app.source.path.should eq source
        app.previous_file_available?.should be_false
      end
    end
  end

  it "does not count a heading jump as a step, and Backspace in the table of contents goes to the previous file" do
    with_docs do |_dir, source, target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app, window|
        app.show_pane(Md::App::Pane::Toc).focus
        app.jump_to "#the-end"
        app.viewer.document.plain_text[app.viewer.cursor_position, 7].should eq "The end"
        app.previous_file_available?.should be_false
        press window, Tput::Key::Backspace
        notice(app).should contain "No previous file"
        app.viewer.document.plain_text[app.viewer.cursor_position, 7].should eq "The end"

        app.follow_link "docs/target.md"
        app.source.path.should eq target
        press window, Tput::Key::Backspace
        app.source.path.should eq source
        app.viewer.document.plain_text[app.viewer.cursor_position, 7].should eq "The end" # where it was left
        # The menu entries' shortcuts, live wherever the focused pane leaves the keys alone.
        press window, Tput::Key::AltRight
        app.source.path.should eq target
        press window, Tput::Key::AltLeft
        app.source.path.should eq source
      end
    end
  end

  it "asks about unsaved changes before leaving for a linked file, and records opens" do
    with_docs do |_dir, source, target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app, _|
        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.cursor_position = 0
        app.editor.insert_text "typed "
        app.follow_link "docs/target.md"
        answer app, 'c'
        app.source.path.should eq source
        app.follow_link "docs/target.md"
        answer app, 'n'
        app.source.path.should eq target

        # File → Open over a file is a step as well.
        app.open_file source
        app.previous_file_available?.should be_true
        app.previous_file
        app.source.path.should eq target
      end
    end
  end
end

describe "Md::App drop" do
  it "opens a file whose path is pasted outside the editor, however the terminal spells it" do
    with_docs do |dir, source, target|
      with_app Md::Source.new(path: source), text: SOURCE_DOC, view: true do |app, window|
        app.viewer.focus
        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new("#{target} \n")
        app.source.path.should eq target
        spaced = File.join(dir, "with space.md")
        File.write spaced, "# Spaced\n"
        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new(spaced.gsub(" ", "\\ "))
        app.source.path.should eq spaced
        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new("'#{source}'")
        app.source.path.should eq source
        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new("file://#{URI.encode_path(spaced)}")
        app.source.path.should eq spaced

        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new("just some words")
        app.source.path.should eq spaced
        window.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new(File.join(dir, "missing.md"))
        app.source.path.should eq spaced

        # A paste the editor takes is text, not a drop.
        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.emit Crysterm::Event::Paste, Crysterm::Event::Paste.new(source)
        app.source.path.should eq spaced
        app.markdown.should contain source
      end
    end
  end
end
