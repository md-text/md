require "./spec_helper"

# Windows on one document (`Md::Document`, `app_document.cr`): Window → New
# shows the same text, edited in either window, with one undo history, one
# modified flag and one unsaved-changes question.

private def window_menu(app)
  menu(app, 5)
end

describe "Md::App windows on one document" do
  it "shows an edit made in one window in the other's editor, viewer and table of contents" do
    with_two_windows do |a, b|
      a.show_pane(Md::App::Pane::Editor).focus
      a.editor.cursor_position = a.editor.document.size
      a.editor.insert_text "\n## Two\n"
      b.editor.value.should contain "## Two" # the editor shares the text at once
      settle { b.viewer.document.outline.size == 2 }
      b.toc.document.should be b.viewer.document
      b.markdown.should eq a.markdown
    end
  end

  it "shares one undo: Ctrl-Z in B undoes A's edit and puts B's caret on it" do
    with_two_windows(text: (1..20).map { |number| "line #{number}" }.join('\n') + "\n") do |a, b|
      {a, b}.each(&.show_pane(Md::App::Pane::Editor).focus)
      b.editor.cursor_position = 0
      b.editor.insert_text "B"
      line16 = a.editor.document.block_position(15)
      a.editor.cursor_position = line16
      a.editor.insert_text "A"
      b.editor.undo.should be_true
      b.markdown.should_not contain "line A16"
      b.markdown.should contain "line 16"
      a.markdown.should eq b.markdown
      b.editor.cursor_position.should eq line16
      b.editor.undo.should be_true
      a.markdown.should start_with "line 1\n"
    end
  end

  it "shares the modified flag; the status of both says modified" do
    with_two_windows do |a, b|
      a.editor.insert_text "x"
      b.editor.document.modified?.should be_true
      settle { b.main.status_bar.permanent_widgets[4].as(Crysterm::Widget::Label).text == "✎ modified" }
      a.document.text.modified = false
      settle { b.main.status_bar.permanent_widgets[4].as(Crysterm::Widget::Label).text == "" }
    end
  end

  it "saves once, for both windows" do
    path = tempfile "# Doc\n"
    begin
      with_two_windows(Md::Source.new(path: path), "# Doc\n") do |a, b|
        b.editor.insert_text "x"
        a.save.should be_true
        File.read(path).should eq b.markdown
        b.editor.document.modified?.should be_false
        notice(a).should contain "Saved"
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "closes a window without asking while another shows the document; the last asks" do
    with_two_windows do |a, b|
      a.editor.insert_text "unsaved"
      b.close_window
      b.window.destroyed?.should be_true
      a.document.views.should eq [a]
      a.close_window
      question(a).should start_with "Save changes to"
      answer a, 'c'
      a.window.destroyed?.should be_false
    end
  end

  it "quits asking only in the last window on each modified document" do
    other = tempfile "# Other\n"
    begin
      with_two_windows do |one, two|
        two.open_file(other).should be_true
        three = one.new_window || fail("no window was opened")
        begin
          three.document.should be one.document
          one.editor.insert_text "a"
          two.editor.insert_text "b"
          one.quit
          one.window.destroyed?.should be_true # not the last on its document
          question(two).should start_with "Save changes to #{other}"
          question(three).should start_with "Save changes to doc.md"
          answer two, 'n'
          answer three, 'n'
          two.window.destroyed?.should be_true
          three.window.destroyed?.should be_true
        ensure
          three.window.destroy
        end
      end
    ensure
      File.delete? other
    end
  end

  it "asks before a reload whatever other windows show the document, saying how many" do
    path = tempfile "# Doc\n"
    begin
      with_two_windows(Md::Source.new(path: path), "# Doc\n") do |a, b|
        a.editor.insert_text "x"
        b.reload
        question(b).should start_with "Save changes to #{path} (open in 2 windows)?"
        answer b, 'n'
        a.markdown.should eq "# Doc\n"
        a.editor.document.modified?.should be_false
      end
    ensure
      File.delete? path
    end
  end

  it "names the windows doc.md:1 and doc.md:2 in titles and the Window menu, and back to doc.md when one closes" do
    with_two_windows do |a, b|
      a.window.title.should eq "doc.md:1 • MD"
      b.window.title.should eq "doc.md:2 • MD"
      window_menu(b).actions[3..].map(&.text).should eq ["doc.md:1", "doc.md:2"]
      a.window.close
      b.window.title.should eq "doc.md • MD"
      window_menu(b).actions[3..].map(&.text).should eq ["doc.md"]
    end
  end

  it "keeps each window's caret its own" do
    with_two_windows(text: "one\ntwo\nthree\n", view: false) do |a, b|
      a.editor.cursor_position = 0
      b.editor.cursor_position = 8
      a.editor.insert_text "zero\n"
      a.editor.cursor_position.should eq 5
      b.editor.cursor_position.should eq 13 # moved with the text, not with A's caret
    end
  end

  it "starts the new window where this one is" do
    with_app Md::Source.new(path: "doc.md"), text: "one\ntwo\nthree\n" do |a, _|
      a.window_opener = recording_opener
      a.show_pane(Md::App::Pane::Editor).focus
      a.editor.cursor_position = 4
      a.sync_cursor = true
      b = a.new_window || fail("no window was opened")
      begin
        b.visible_panes.should eq a.visible_panes
        b.editor.cursor_position.should eq 4
        b.editor.focused?.should be_true
        b.sync_cursor?.should be_true
      ensure
        b.window.destroy
      end
    end
  end

  it "makes Watch File the document's: toggled in one window, checked in both" do
    path = tempfile "# Doc\n"
    begin
      with_two_windows(Md::Source.new(path: path), "# Doc\n") do |a, b|
        a.watch_file = true
        b.watch_file?.should be_true
        a.document.watching?.should be_true
        b.watch_file = false
        a.watch_file?.should be_false
        a.document.watching?.should be_false
      end
    ensure
      File.delete? path
    end
  end

  it "renames every window on Save As in one" do
    saved = File.tempname("md-spec-shared", ".md")
    begin
      with_two_windows do |a, b|
        b.save_as(saved).should be_true
        a.source.path.should eq saved
        settle { a.window.title == "#{File.basename(saved)}:1 • MD" }
      end
    ensure
      File.delete? saved
    end
  end

  it "moves the watcher to the other window when the host's window closes" do
    path = tempfile "first\n"
    begin
      with_two_windows(Md::Source.new(path: path), "first\n") do |a, b|
        a.watch_interval = 20.milliseconds
        b.watch_interval = 20.milliseconds
        a.watch_file = true
        a.window.close
        b.document.host.should be b
        b.document.watching?.should be_true
        File.write path, "second\n"
        settle { b.markdown == "second\n" }
        settle { notice(b).includes? "changed on disk" }
      end
    ensure
      File.delete? path
    end
  end

  it "leaves no Document behind" do
    with_app Md::Source.new(path: "doc.md"), text: "A\n" do |app|
      Md::Documents.all.should eq [app.document]
    end
    Md::Documents.all.should be_empty
  end
end
