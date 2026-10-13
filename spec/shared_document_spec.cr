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
      window_menu(b).actions[5..].map(&.text).should eq ["doc.md:1", "doc.md:2"]
      a.window.close
      b.window.title.should eq "doc.md • MD"
      window_menu(b).actions[5..].map(&.text).should eq ["doc.md"]
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

# Two windows with documents of their own (two `with_app`s under one
# application), the second opening files the first has open.
private def with_side_by_side(path : String, &)
  application = Crysterm::Application.new
  with_app Md::Source.new(path: path), text: File.read(path), view: true do |a, first_window|
    application.add first_window
    with_app do |b, second_window|
      application.add second_window
      yield a, b
    end
  end
  Md::Documents.all.should be_empty
end

describe "Md::App opening a file another window has open" do
  it "joins it, unsaved edits and all, with a notice, and reads nothing from disk" do
    path = tempfile "# Doc\n"
    begin
      with_side_by_side(path) do |a, b|
        a.editor.cursor_position = 0
        a.editor.insert_text "edited "
        File.write path, "changed on disk\n"
        b.open_file(path).should be_true
        b.document.should be a.document
        b.markdown.should eq "edited # Doc\n"
        notice(b).should contain "unsaved changes from another window"
        b.editor.insert_text "x"
        a.markdown.should contain "x"
      end
    ensure
      File.delete? path
    end
  end

  it "joins through a symlink and a hard link" do
    dir = File.tempname("md-spec-links")
    Dir.mkdir dir
    path = File.join(dir, "a.md")
    File.write path, "# A\n"
    File.symlink path, File.join(dir, "soft.md")
    File.link path, File.join(dir, "hard.md")
    begin
      with_side_by_side(path) do |a, b|
        b.open_file(File.join(dir, "soft.md")).should be_true
        b.document.should be a.document
        notice(b).should contain "also in another window"
        b.open_file(File.join(dir, "hard.md")).should be_true # the same document: nowhere to go
        b.document.should be a.document
      end
      with_side_by_side(File.join(dir, "hard.md")) do |a, b|
        b.open_file(path).should be_true
        b.document.should be a.document
      end
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "asks nothing when leaving a document another window shows" do
    path = tempfile "# Doc\n"
    other = tempfile "# Other\n"
    begin
      with_side_by_side(path) do |a, b|
        b.open_file(path)
        a.editor.insert_text "x"
        b.open_dropped(other).should be_true
        question(b).should eq ""
        b.source.path.should eq other
        a.document.views.should eq [a]
      end
    ensure
      File.delete? path
      File.delete? other
    end
  end

  it "leaves the other window on the document when File → Close closes it in one" do
    path = tempfile "# Doc\n"
    begin
      with_side_by_side(path) do |a, b|
        b.open_file(path)
        a.editor.insert_text "x"
        b.close_document
        question(b).should eq ""
        b.source.path.should be_nil
        a.document.views.should eq [a]
        a.markdown.should contain "x"
      end
    ensure
      File.delete? path
    end
  end

  it "goes to its place without re-reading when re-opening the window's own file" do
    path = tempfile "# Doc\n"
    begin
      with_side_by_side(path) do |a, _|
        a.editor.cursor_position = 0
        a.editor.insert_text "edited "
        File.write path, "on disk\n"
        a.open_file(path).should be_true
        question(a).should eq ""
        a.markdown.should eq "edited # Doc\n"
      end
    ensure
      File.delete? path
    end
  end

  it "merges on Save As onto a file open and unmodified elsewhere" do
    path = tempfile "one\ntwo\nthree\n"
    begin
      with_side_by_side(path) do |a, b|
        a.show_pane(Md::App::Pane::Editor).focus
        a.go_to_line 2
        b.editor.insert_text "new text\n"
        b.save_as(path).should be_true
        File.read(path).should eq "new text\n"
        a.document.should be b.document
        a.markdown.should eq "new text\n"
        a.editor.text_cursor.block_number.should eq 1 # line 2 kept, clamped
        Md::Documents.find(path).should be b.document
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "refuses Save As onto a file modified elsewhere and writes nothing" do
    path = tempfile "one\n"
    begin
      with_side_by_side(path) do |a, b|
        a.editor.insert_text "x"
        b.editor.insert_text "mine"
        b.save_as(path).should be_false
        notice(b).should contain "has unsaved changes in another window"
        File.read(path).should eq "one\n"
        b.source.path.should be_nil
      end
    ensure
      File.delete? path
    end
  end
end

describe "Md::App linked windows switching documents" do
  it "keeps the group's trail when a window left alone in its group opens a file" do
    first = tempfile "# First\n"
    second = tempfile "# Second\n"
    begin
      with_two_windows(Md::Source.new(path: first), "# First\n", linked: true) do |a, b|
        a.window.close
        b.open_file(second).should be_true
        b.previous_file_available?.should be_true
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  it "keeps the saving window's trail when Save As takes another linked group in" do
    path = tempfile "# Other\n"
    left = tempfile "# Left\n"
    fresh = File.tempname("md-spec", ".md")
    begin
      with_side_by_side(path) do |a, b|
        a.window_link = Md::App::WindowLink::Linked
        b.open_file(left).should be_true
        b.open_file(fresh).should be_true
        b.previous_file_available?.should be_true
        a.previous_file_available?.should be_false
        b.editor.insert_text "mine\n"
        b.save_as(path).should be_true
        a.document.should be b.document
        b.link.should be a.link
        b.previous_file_available?.should be_true
        a.previous_file_available?.should be_true
      ensure
        Md::Documents.link_windows Md::App::WindowLink::Separate
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
      File.delete? left
      File.delete? fresh
    end
  end

  it "joins a group a linked group arrives at, its leader staying the leader and the arriving trail kept" do
    path = tempfile "# Doc\n"
    left = tempfile "# Left\n"
    begin
      with_side_by_side(path) do |a, b|
        a.window_link = Md::App::WindowLink::Linked
        b.window_opener = recording_opener
        b.open_file(left).should be_true
        c = b.new_window || fail("no window was opened")
        begin
          c.link.should be b.link
          a.link.try(&.leader).should be a
          b.open_file(path).should be_true
          b.document.should be a.document
          c.document.should be a.document
          b.link.should be a.link
          c.link.should be a.link
          a.link.try(&.leader).should be a
          a.previous_file_available?.should be_true # the arrivals' trail
          a.trail.back.last.path.should eq left
        ensure
          c.window.destroy
        end
      ensure
        Md::Documents.link_windows Md::App::WindowLink::Separate
      end
    ensure
      File.delete? path
      File.delete? left
    end
  end
end

describe "Md::App windows on one document reaching it again" do
  it "joins the other window's document on Previous File and on a followed link" do
    path = tempfile "# Doc\n"
    other = tempfile "# Other\n"
    begin
      with_side_by_side(path) do |a, b|
        b.open_file(path).should be_true
        b.open_file(other).should be_true
        a.editor.cursor_position = 0
        a.editor.insert_text "edited "
        File.write path, "changed on disk\n"
        b.previous_file.should be_true
        question(b).should eq "" # b's own document was unmodified
        b.document.should be a.document
        b.markdown.should eq "edited # Doc\n"
        notice(b).should contain "unsaved changes from another window"
        b.open_file(other).should be_true
        b.follow_link path
        b.document.should be a.document
      end
    ensure
      File.delete? path
      File.delete? other
    end
  end

  it "saves a new file that has become another window's file since as a Save As onto it" do
    dir = File.tempname("md-spec-collide")
    Dir.mkdir dir
    real = File.join(dir, "real.md")
    File.write real, "# Real\n"
    late = File.join(dir, "late.md")
    begin
      with_side_by_side(real) do |a, b|
        b.open_file(late).should be_true # a new file
        b.editor.insert_text "mine\n"
        File.symlink real, late # made a link to a's file since
        a.editor.insert_text "x"
        b.save.should be_false
        notice(b).should contain "has unsaved changes in another window"
        File.read(real).should eq "# Real\n"
        a.save.should be_true
        b.save.should be_true
        File.read(real).should eq "mine\n"
        a.document.should be b.document
        Md::Documents.find(real).should be b.document
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end

describe "Md::App watching a file shown in two windows" do
  it "tells every window when the file changes, changes under unsaved edits, or goes" do
    path = tempfile "first\n"
    begin
      with_two_windows(Md::Source.new(path: path), "first\n") do |a, b|
        a.watch_interval = 20.milliseconds
        b.watch_interval = 20.milliseconds
        a.watch_file = true
        File.write path, "second\n"
        settle { a.markdown == "second\n" }
        settle { notice(a).includes?("Reloaded") && notice(b).includes?("Reloaded") }
        b.editor.insert_text "x"
        File.write path, "third, longer\n"
        settle { notice(a).includes?("unsaved changes kept") && notice(b).includes?("unsaved changes kept") }
        a.markdown.should eq "xsecond\n" # the edit kept, not the file
        File.delete path
        settle { notice(a).includes?("removed from disk") && notice(b).includes?("removed from disk") }
      end
    ensure
      File.delete? path
    end
  end
end

# What a window leaves behind on the document it showed and in the process:
# nothing, however many windows came and went.
private def footprint(doc : Md::Document)
  {
    doc.views.size,
    doc.text.handlers(Crysterm::Event::ContentsChanged).size,
    doc.text.handlers(Crysterm::Event::ModificationChanged).size,
    doc.handlers(Md::Event::DocumentEdited).size,
    doc.handlers(Md::Event::DocumentNotice).size,
    doc.handlers(Md::Event::StreamAppended).size,
    doc.watch_file.handlers(Crysterm::Event::ReactiveChanged).size,
    Md::App.instances.size,
    Md::Documents.all.size,
  }
end

describe "Md::App windows coming and going" do
  {false, true}.each do |linked|
    it "leaves no view, handler, window or document behind#{linked ? " (linked)" : ""}" do
      path = tempfile "# Doc\n"
      other = tempfile "# Other\n"
      begin
        with_two_windows(Md::Source.new(path: path), "# Doc\n", linked: linked) do |a, b|
          doc = a.document
          b.window.destroy
          before = footprint(doc)
          quits = a.exec_application.handlers(Crysterm::Event::AboutToQuit).size
          6.times do
            c = a.new_window || fail("no window was opened")
            c.editor.insert_text "x"
            c.open_file(other).should be_true unless linked
            c.previous_file.should be_true unless linked
            c.window.destroy
          end
          a.document.should be doc
          footprint(doc).should eq before
          a.exec_application.handlers(Crysterm::Event::AboutToQuit).size.should eq quits
          doc.views.should eq [a]
          doc.link.try(&.views).try(&.should eq [a])
        end
      ensure
        File.delete? path
        File.delete? other
      end
    end
  end

  it "leaves no stream handlers behind on a stream's document" do
    reader, writer = IO.pipe
    begin
      with_two_windows(Md::Source.new(stdin: true), "") do |a, b|
        a.stream reader
        b.window.destroy
        doc = a.document
        before = footprint(doc)
        4.times do
          c = a.new_window || fail("no window was opened")
          writer.puts "line"
          c.window.destroy
        end
        footprint(doc).should eq before
        writer.close
        settle { !doc.streaming? }
        a.markdown.should eq "line\n" * 4
      end
    ensure
      reader.close
      writer.close
    end
  end
end
