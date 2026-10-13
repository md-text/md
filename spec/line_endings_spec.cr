require "./spec_helper"

# A file with CRLF line endings: the text holds `'\n'` line breaks only
# (Crysterm's `TextDocument` takes `"\r\n"` as one, as Qt does), so every
# line-anchored pattern works on it — a closing fence, Rewrap, Enter on an
# empty item — and a save writes the file's own line endings back
# (`Md::Document::LineTerminator`, Qt Creator's `TextFileFormat`): opening
# and saving a file does not change its line endings.

private def place(app, line, column)
  doc = app.editor.document
  app.editor.text_cursor = Crysterm::TextCursor.new(doc, doc.block_position(line) + column)
end

private def encoding(app) : String
  app.main.status_bar.permanent_widgets[3].as(Crysterm::Widget::Label).text
end

describe "Md::App line endings" do
  it "saves a CRLF file CRLF throughout, its unchanged lines as they were" do
    original = "# Title\r\n\r\n```\r\ncode\r\n```\r\n\r\nsome text\r\n"
    path = tempfile original
    begin
      with_app do |app|
        app.open_file(path).should be_true
        app.markdown.should eq original.gsub("\r\n", "\n")
        app.document.line_terminator.crlf?.should be_true
        encoding(app).should eq "UTF-8 CRLF"
        place app, 6, 9
        app.editor.insert_text "\nmore"
        app.save.should be_true
        File.read(path).should eq original.sub("some text\r\n", "some text\r\nmore\r\n")
        File.read(path).lines(chomp: false)[0...7].should eq original.lines(chomp: false)
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "closes a fence, rewraps and ends a list on a CRLF file" do
    path = tempfile "```\r\ncode\r\n```\r\n\r\naa\r\nbb\r\n\r\n- item\r\n- \r\n"
    begin
      with_app do |app, window|
        app.open_file(path).should be_true
        app.text_width = 20
        app.show_pane(Md::App::Pane::Editor).focus
        place app, 4, 0
        app.rewrap_paragraph.should be_true
        app.markdown.should eq "```\ncode\n```\n\naa bb\n\n- item\n- \n"
        # Enter on the empty item ends the list rather than continuing it.
        place app, 7, 2
        press(window, Tput::Key::Enter)
        app.markdown.should eq "```\ncode\n```\n\naa bb\n\n- item\n\n"
        # The viewer has the paragraph after the fence as a paragraph.
        app.viewer.document.blocks.map(&.text).should contain "aa bb"
      end
    ensure
      File.delete? path
    end
  end

  it "keeps an LF file LF, and a new document is LF" do
    path = tempfile "one\ntwo\n"
    begin
      with_app do |app|
        encoding(app).should eq "UTF-8 LF"
        app.open_file(path).should be_true
        encoding(app).should eq "UTF-8 LF"
        app.editor.insert_text "zero "
        app.save.should be_true
        File.read(path).should eq "zero one\ntwo\n"
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "saves a mixed file with its first line's ending throughout" do
    crlf_first = tempfile "a\r\nb\nc\r\n"
    lf_first = tempfile "a\nb\r\nc\n"
    begin
      with_app do |app|
        app.open_file(crlf_first).should be_true
        app.markdown.should eq "a\nb\nc\n"
        app.save.should be_true
        File.read(crlf_first).should eq "a\r\nb\r\nc\r\n"
        app.open_file(lf_first).should be_true
        app.save.should be_true
        File.read(lf_first).should eq "a\nb\nc\n"
      end
    ensure
      {crlf_first, lf_first}.each { |file| File.delete? file; File.delete? "#{file}~" }
    end
  end

  it "writes a copy with the file's line endings and detects them again on a reload" do
    path = tempfile "a\r\nb\r\n"
    copy = File.tempname("md-spec-copy", ".md")
    begin
      with_app do |app|
        app.open_file(path).should be_true
        app.document.write_copy copy
        File.read(copy).should eq "a\r\nb\r\n"
        File.write path, "a\nb\nc\n"
        app.reload
        app.markdown.should eq "a\nb\nc\n"
        encoding(app).should eq "UTF-8 LF"
      end
    ensure
      File.delete? path
      File.delete? copy
    end
  end

  it "takes a stream's line endings from its first line" do
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream IO::Memory.new("")
      app.receive "# One\r\n\r\ntwo\n"
      app.document.line_terminator.crlf?.should be_true
      app.markdown.should eq "# One\n\ntwo\n"
      app.finish_stream
      encoding(app).should eq "UTF-8 CRLF"
    end
  end
end
