require "./spec_helper"
require "file_utils"

# The status bar's name field.
private def name_field(app)
  app.main.status_bar.normal_widgets.first.as(Crysterm::Widget::Label)
end

# A directory with three documents of twenty paragraphs each; yields their
# paths.
private def with_three_docs(&)
  dir = File.tempname("md-spec-close")
  Dir.mkdir_p dir
  paths = {"a", "b", "c"}.map do |name|
    path = File.join(dir, "#{name}.md")
    File.write path, (1..20).map { |i| "#{name.upcase} #{i}" }.join("\n\n") + "\n"
    path
  end
  yield paths[0], paths[1], paths[2], dir
ensure
  FileUtils.rm_rf dir if dir
end

describe "Md::App#close_document" do
  it "opens the next document on the trail at its place, and leaves the closed one off the trail" do
    with_three_docs do |doc_a, doc_b, doc_c, dir|
      history = Md::History.new(File.join(dir, "history.json"))
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true, history: history do |app|
        app.open_file doc_b
        app.go_to_line 9
        app.open_file doc_c
        app.go_to_line 13
        app.previous_file.should be_true
        app.source.path.should eq doc_b
        app.go_to_line 5

        app.close_document
        app.source.path.should eq doc_c
        app.title.should eq "md - #{doc_c}"
        app.editor.text_cursor.block_number.should eq 12 # where c was left
        app.editor.document.modified?.should be_false
        (history.entry(doc_b) || fail("b.md was not remembered")).line.should eq 5
        app.next_file_available?.should be_false

        # Previous File passes b by: it leads to the file b was opened over.
        app.previous_file.should be_true
        app.source.path.should eq doc_a
        app.previous_file_available?.should be_false
        app.next_file.should be_true
        app.source.path.should eq doc_c
        app.next_file_available?.should be_false
      end
    end
  end

  it "skips a next file that can no longer be read" do
    with_three_docs do |doc_a, doc_b, doc_c|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true do |app|
        app.open_file doc_b
        app.open_file doc_c
        app.previous_file
        app.previous_file
        File.delete doc_b
        Dir.mkdir doc_b # there, but no file to read
        app.close_document
        app.source.path.should eq doc_c
        app.next_file_available?.should be_false
        app.previous_file_available?.should be_false
      end
    end
  end

  it "leaves a blank new document when nothing is ahead, from which Previous File still leads back" do
    with_three_docs do |doc_a, doc_b|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true, watch: true do |app, window|
        app.open_file doc_b
        name_field(app).text.should contain "(watching)"
        app.close_document
        app.source.path.should be_nil
        app.source.stdin?.should be_false
        app.title.should eq "md"
        window.title.should eq "md"
        app.markdown.should eq ""
        app.viewer.document.plain_text.strip.should eq ""
        app.editor.document.modified?.should be_false
        app.editor.focused?.should be_true
        name_field(app).text.should eq " [No Name]" # nothing to watch
        notice(app).should contain "Closed #{doc_b}"
        app.next_file_available?.should be_false
        app.previous_file_available?.should be_true

        app.save.should be_false # no name: Save asks for one
        question(app).should eq "Save as: "
        app.main.status_bar.line_prompt.cancel

        app.previous_file.should be_true
        app.source.path.should eq doc_a
        app.next_file_available?.should be_false # the blank document is left for good

        app.close_document # nothing behind counts: a blank document again
        app.source.path.should be_nil
        app.previous_file_available?.should be_false
      end
    end
  end

  it "takes every place in the closed file off the trail, never reopening it" do
    with_three_docs do |doc_a|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true do |app|
        app.go_to_line 3
        app.open_file doc_a # a link to the document itself, say
        app.go_to_line 7
        app.previous_file.should be_true # Next File now leads to a place in a.md
        app.next_file_available?.should be_true

        app.close_document
        app.source.path.should be_nil # not a again
        app.next_file_available?.should be_false
        app.previous_file_available?.should be_false
      end
    end
    with_three_docs do |doc_a, doc_b|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true do |app|
        app.open_file doc_b
        app.open_file doc_a
        app.previous_file.should be_true
        app.previous_file.should be_true # at a, with b and a ahead
        app.close_document
        app.source.path.should eq doc_b
        app.next_file_available?.should be_false # the place in a is gone too
      end
    end
  end

  it "keeps the trail when a file is opened over the blank document" do
    with_three_docs do |doc_a, doc_b, doc_c|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true do |app|
        app.open_file doc_b
        app.close_document
        app.open_file doc_c
        app.previous_file.should be_true
        app.source.path.should eq doc_a
      end
    end
  end

  it "asks about unsaved changes first, and Cancel keeps the document" do
    with_three_docs do |doc_a, doc_b|
      with_app Md::Source.new(path: doc_a), text: File.read(doc_a), view: true do |app|
        app.open_file doc_b
        app.show_pane(Md::App::Pane::Editor).focus
        app.editor.cursor_position = 0
        app.editor.insert_text "typed "
        app.close_document
        question(app).should start_with "Save changes to #{doc_b}?"
        answer app, 'c'
        app.source.path.should eq doc_b
        app.markdown.should start_with "typed B 1"
        app.editor.document.modified?.should be_true
        app.previous_file_available?.should be_true

        app.close_document
        answer app, 'n'
        app.source.path.should be_nil
        app.markdown.should eq ""
        app.editor.document.modified?.should be_false
        File.read(doc_b).should start_with "B 1"       # dropped, not saved
        app.main.status_bar.prompting?.should be_false # asked once
      end
    end
  end

  it "saves first on Save, and closes a new document's text once it is named" do
    with_three_docs do |_a, _b, _c, dir|
      saved = File.join(dir, "new.md")
      with_app do |app|
        app.editor.insert_text "new text"
        app.close_document
        question(app).should eq "Save changes to the new document? (y)es, (n)o, (c)ancel: "
        answer app, 'y'
        question(app).should eq "Save as: "
        answer app, saved
        settle { app.source.path.nil? }
        File.read(saved).should eq "new text"
        app.markdown.should eq ""
        notice(app).should contain "Closed #{saved}"
      end
    end
  end

  it "abandons a stream being read for the blank document" do
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream IO::Memory.new("")
      app.receive "# Streamed\n\ntext\n"
      name_field(app).text.should eq " stdin (streaming)"
      app.close_document
      app.streaming?.should be_false
      app.source.stdin?.should be_false
      app.source.name.should be_nil
      app.title.should eq "md"
      notice(app).should contain "Closed stdin"
      app.receive "late\n" # the reader fiber may still deliver
      app.finish_stream
      app.markdown.should eq ""
      app.viewer.document.plain_text.should_not contain "late"
      app.viewer.follow_tail?.should be_false
      name_field(app).text.should eq " [No Name]"
      app.editor.focused?.should be_true
    end
  end
end
