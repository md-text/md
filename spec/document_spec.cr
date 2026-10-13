require "./spec_helper"

# `Md::Document`: the text and what belongs to it rather than to a window.

describe Md::Document do
  it "counts its views and is forgotten when the last leaves" do
    with_two_windows do |a, b|
      a.document.views.should eq [a, b]
      a.document.host.should be a
      Md::Documents.all.should eq [a.document]
      b.window.destroy
      a.document.views.should eq [a]
    end
    Md::Documents.all.should be_empty
  end

  it "bumps its revision on edits, not on loads" do
    doc = Md::Document.new Md::Source.new, "text"
    doc.revision.should eq 0
    Crysterm::TextCursor.new(doc.text, 0).insert_text "more "
    doc.revision.should eq 1
    doc.loading { Crysterm::TextCursor.new(doc.text, 0).insert_text "quiet " }
    doc.revision.should eq 1
    doc.text.modified?.should be_true
  end

  it "reloads as one undoable edit of what differs, each view's caret moving with it" do
    path = tempfile "one\ntwo\nthree\n"
    begin
      with_two_windows(Md::Source.new(path: path), "one\ntwo\nthree\n", view: false) do |a, b|
        a.editor.cursor_position = 4
        b.editor.cursor_position = 8
        a.editor.insert_text "x" # "one\nxtwo\nthree\n", a's caret at 5, b's at 9
        revision = a.document.revision
        File.write path, "one\nTWO\nthree\nfour\n"
        a.document.reload
        a.markdown.should eq "one\nTWO\nthree\nfour\n"
        a.document.revision.should be > revision # an edit, for the views to catch up
        # b's caret, away from the change, keeps its place (the start of
        # "three"); a's, inside the text replaced, goes to its start.
        b.editor.cursor_position.should eq 8
        a.editor.cursor_position.should eq 4
        a.document.text.modified?.should be_false
        # The history stays: an undo takes the reload back, the edit it
        # dropped included, and makes the document modified again.
        a.document.text.undo.should be_true
        a.markdown.should eq "one\nxtwo\nthree\n"
        a.document.text.modified?.should be_true
        a.document.text.undo.should be_true
        a.markdown.should eq "one\ntwo\nthree\n"
        a.document.text.redo
        a.document.text.redo
        a.document.text.modified?.should be_false
      end
    ensure
      File.delete? path
    end
  end

  it "gives each unnamed document its own recovery name" do
    one = Md::Document.new
    two = Md::Document.new
    path = one.recovery_path
    Md::Documents.add one
    begin
      two.recovery_path.should_not eq path
    ensure
      Md::Documents.forget one
    end
  end

  it "keys a file by its real path" do
    dir = File.tempname("md-spec-keys")
    Dir.mkdir dir
    begin
      File.write File.join(dir, "a.md"), "a"
      File.symlink File.join(dir, "a.md"), File.join(dir, "link.md")
      real = File.realpath(File.join(dir, "a.md"))
      Md::Documents.key_for(File.join(dir, "link.md")).should eq real
      Md::Documents.key_for(File.join(dir, "new.md")).should eq File.join(File.realpath(dir), "new.md")
    ensure
      FileUtils.rm_rf dir
    end
  end
end
