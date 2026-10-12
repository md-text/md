require "./spec_helper"
require "file_utils"

describe "Md::App open" do
  it "opens a file into the viewer, and a new name into the editor" do
    path = tempfile "# Opened\n\nBody.\n"
    fresh = File.tempname("md-spec-new", ".md")
    begin
      with_app do |app, window|
        app.visible_panes.should eq [Md::App::Pane::Editor]
        app.open_file(path).should be_true
        app.source.path.should eq path
        app.title.should eq "#{File.basename path} • MD"
        window.title.should eq app.title
        app.markdown.should eq "# Opened\n\nBody.\n"
        app.viewer.document.plain_text.should contain "Body."
        app.visible_panes.should eq [Md::App::Pane::Editor, Md::App::Pane::Viewer]
        app.viewer.focused?.should be_true
        app.editor.document.modified?.should be_false
        notice(app).should contain "Opened #{path}"

        app.open_file(fresh).should be_true
        app.markdown.should eq ""
        app.editor.focused?.should be_true
        notice(app).should contain "New file #{fresh}"
        File.exists?(fresh).should be_false
      end
    ensure
      File.delete? path
    end
  end

  it "asks for the file in place of the status bar and makes the path absolute" do
    path = tempfile "text\n"
    begin
      with_app do |app, window|
        app.open_prompt
        app.main.status_bar.prompting?.should be_true
        window.repaint
        window.dump.to_s.lines[31][1..-2].should start_with "Open: "
        Dir.cd(File.dirname(path)) { answer app, File.basename(path) }
        File.realpath(app.source.path || "").should eq File.realpath(path)
        app.markdown.should eq "text\n"
      end
    ensure
      File.delete? path
    end
  end

  it "abandons a stream being followed" do
    path = tempfile "file\n"
    begin
      with_app Md::Source.new(stdin: true), view: true do |app|
        app.stream IO::Memory.new("")
        app.receive "streamed\n"
        app.open_file path
        app.streaming?.should be_false
        app.receive "late\n" # the reader fiber may still deliver
        app.markdown.should eq "file\n"
        app.viewer.follow_tail?.should be_false
      end
    ensure
      File.delete? path
    end
  end
end

describe "Md::App reload" do
  it "re-reads the file, keeping the viewer's place and the editor's caret" do
    long = (1..60).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"
    path = tempfile long
    begin
      with_app Md::Source.new(path: path), text: long, view: true do |app, window|
        app.show_pane Md::App::Pane::Editor
        app.viewer.focus
        window.repaint
        app.go_to_line 40
        window.repaint
        scroll = app.viewer.scroll_position
        scroll.should be > 0
        caret = app.editor.cursor_position
        File.write path, long.sub("Paragraph 1\n", "Paragraph one\n")
        app.reload
        app.markdown.should contain "Paragraph one"
        app.viewer.document.plain_text.should contain "Paragraph one"
        app.viewer.scroll_position.should eq scroll
        app.editor.cursor_position.should eq caret # the same offset, not the same text
        app.editor.document.modified?.should be_false
        notice(app).should contain "Reloaded #{path}"
      end
    ensure
      File.delete? path
    end
  end

  it "has nothing to reload without a file" do
    with_app do |app|
      app.reload
      notice(app).should contain "No file to reload"
    end
  end
end

describe "Md::App watch" do
  it "reloads the file as it changes on disk, unless the editor holds changes" do
    path = tempfile "first\n"
    begin
      with_app Md::Source.new(path: path), text: "first\n", view: true do |app|
        app.watch_interval = 20.milliseconds
        app.watch_file?.should be_false
        app.watch_file = true
        app.main.status_bar.normal_widgets[0].as(Crysterm::Widget::Label).text.should contain "(watching)"
        File.write path, "second\n"
        settle { app.markdown == "second\n" }
        notice(app).should contain "changed on disk"

        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.cursor_position = 0
        app.editor.insert_text "edited "
        File.write path, "third\n"
        settle { notice(app).includes? "unsaved changes kept" }
        app.markdown.should eq "edited second\n"

        app.watch_file = false
        app.main.status_bar.normal_widgets[0].as(Crysterm::Widget::Label).text.should_not contain "(watching)"
      end
    ensure
      File.delete? path
    end
  end

  it "starts watching from the command line's flag and follows the file opened next" do
    path = tempfile "a\n"
    other = tempfile "b\n"
    begin
      with_app Md::Source.new(path: path), text: "a\n", view: true, watch: true do |app|
        app.watch_file?.should be_true
        app.watch_interval = 20.milliseconds
        app.open_file other
        File.write other, "b2\n"
        settle { app.markdown == "b2\n" }
        File.write path, "a2\n" # the old file is no longer watched
        sleep 100.milliseconds
        app.markdown.should eq "b2\n"
      end
    ensure
      File.delete? path
      File.delete? other
    end
  end

  it "follows the file saved under another name" do
    path = tempfile "a\n"
    other = tempfile nil
    begin
      with_app Md::Source.new(path: path), text: "a\n", view: true, watch: true do |app|
        app.watch_interval = 20.milliseconds
        app.save_as(other).should be_true
        File.write other, "b2\n"
        settle { app.markdown == "b2\n" }
        File.write path, "a2\n" # the old file is no longer watched
        sleep 100.milliseconds
        app.markdown.should eq "b2\n"
      end
    ensure
      File.delete? path
      File.delete? other
      File.delete? "#{other}~"
    end
  end
end

describe "Md::App unsaved-changes guard" do
  it "lets the window close when nothing is modified or the guard is off" do
    with_app do |app, window|
      window.request_close.should be_true
      app.editor.insert_text "x"
      window.request_close.should be_false
      answer app, 'c'
      app.confirm_discard = false
      window.request_close.should be_true
    end
  end

  it "asks, and runs the action on Don't save, or after a save on Save, not on Cancel" do
    path = File.tempname("md-spec", ".md")
    begin
      with_app Md::Source.new(path: path) do |app, window|
        app.editor.insert_text "unsaved"
        ran = 0
        app.confirm_discard { ran += 1 }
        ran.should eq 0
        window.repaint
        window.dump.to_s.should contain "Save changes to /"
        question(app).should end_with "? (y)es, (n)o, (c)ancel: "
        answer app, 'c'
        ran.should eq 0
        app.editor.document.modified?.should be_true
        app.confirm_discard { ran += 1 }
        answer app, "" # an empty Enter is no answer: a Cancel
        ran.should eq 0

        app.confirm_discard { ran += 1 }
        answer app, 'n'
        ran.should eq 1
        app.editor.document.modified?.should be_true # dropped only by what follows

        app.confirm_discard { ran += 1 }
        answer app, "yes" # typed out, the first letter counts
        ran.should eq 2
        File.read(path).should eq "unsaved"
        app.editor.document.modified?.should be_false
        app.main.status_bar.prompting?.should be_false

        app.confirm_discard { ran += 1 } # nothing to ask about now
        ran.should eq 3
      end
    ensure
      File.delete? path
    end
  end

  it "asks for a name first when a new document is saved from the question" do
    path = File.tempname("md-spec", ".md")
    begin
      with_app do |app, _|
        app.editor.insert_text "new text"
        ran = false
        app.confirm_discard { ran = true }
        answer app, 'y'
        question(app).should eq "Save as: "
        answer app, path
        settle { ran }
        File.read(path).should eq "new text"
        app.source.path.should eq path
      end
    ensure
      File.delete? path
    end
  end

  it "guards opening and reloading too" do
    path = tempfile "on disk\n"
    begin
      with_app Md::Source.new(path: path), text: "on disk\n", view: true do |app, _|
        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.cursor_position = 0
        app.editor.insert_text "typed "
        app.reload
        answer app, 'c'
        app.markdown.should eq "typed on disk\n"
        app.reload
        answer app, 'n'
        app.markdown.should eq "on disk\n"
        app.editor.cursor_position = 0
        app.editor.insert_text "again "
        app.open_prompt
        question(app).should start_with "Save changes to" # the question comes first
        answer app, 'n'
        question(app).should eq "Open: "
        app.main.status_bar.line_prompt.cancel
      end
    ensure
      File.delete? path
    end
  end
end

describe "Md::App history" do
  it "restores the remembered position, keeps the recent files, and offers them in the File menu" do
    dir = File.tempname("md-spec-history")
    Dir.mkdir_p dir
    doc = File.join(dir, "doc.md")
    other = File.join(dir, "other.md")
    text = (1..20).map { |i| "Line #{i}" }.join("\n\n") + "\n"
    File.write doc, text
    File.write other, "# Other\n"
    history_path = File.join(dir, "history.json")
    begin
      history = Md::History.new(history_path)
      history.touch other, 1, 1, true
      history.touch doc, 11, 3, true
      with_app Md::Source.new(path: doc), text: text, view: true, history: history do |app, window|
        window.repaint
        app.editor.text_cursor.block_number.should eq 10
        app.editor.text_cursor.column_number.should eq 2
        # The 11th source line is the 6th paragraph; the column carries over.
        app.viewer.document.plain_text[app.viewer.cursor_position - 2, 6].should eq "Line 6"
        recent = app.main.menu_bar.menus[0].actions[1]
        recent.text.should eq "Open &Recent"
        recent.enabled?.should be_true
        (recent.menu || [] of Crysterm::Action).map(&.text).should eq [doc, other]

        app.go_to_line 15
        app.save_history
        reloaded = Md::History.load(history_path)
        entry = reloaded.entry(doc) || fail("doc.md was not remembered")
        entry.line.should eq 15
        entry.viewing.should be_true

        # Opening from the menu records the file left, and lists the new one first.
        (recent.menu || [] of Crysterm::Action)[1].trigger
        app.source.path.should eq other
        (recent.menu || [] of Crysterm::Action).map(&.text).should eq [other, doc]
      end
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "opens on the line asked for, over the remembered position" do
    text = (1..20).map { |i| "Line #{i}" }.join("\n\n") + "\n"
    history = Md::History.new("unused.json")
    history.touch "doc.md", 11, 3, true
    with_app Md::Source.new(path: "doc.md"), text: text, view: true, history: history, line: 5 do |app|
      app.editor.text_cursor.block_number.should eq 4
      app.editor.text_cursor.column_number.should eq 0
      app.viewer.document.plain_text[app.viewer.cursor_position, 6].should eq "Line 3"
    end
    # Past the end: the last line. In the editor as well as in the viewer.
    with_app Md::Source.new(path: "doc.md"), text: text, view: false, line: 500 do |app|
      app.visible_panes.should eq [Md::App::Pane::Editor]
      app.editor.text_cursor.block_number.should eq 39
    end
  end

  it "runs without a history" do
    with_app Md::Source.new(path: "doc.md"), text: "x\n", view: true do |app|
      app.history.should be_nil
      app.remember_position
      app.save_history
      app.main.menu_bar.menus[0].actions[1].enabled?.should be_false
    end
  end
end
