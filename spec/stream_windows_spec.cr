require "./spec_helper"

# A document streaming in on standard input, shared live by every window on
# it (`Document#start_stream`).

# Writes *lines* into *writer* one by one, a little apart, then closes it.
private def feed(writer : IO, lines : Enumerable(String), pause = 5.milliseconds)
  spawn do
    lines.each do |line|
      writer << line
      writer.flush
      sleep pause
    end
    writer.close
  end
end

describe "Md::App windows on a stream" do
  it "gives a window opened on a streaming document the rest live" do
    reader, writer = IO.pipe
    application = Crysterm::Application.new
    with_app Md::Source.new(stdin: true), view: true do |a, first_window|
      application.add first_window
      a.window_opener = recording_opener
      a.stream reader
      writer << "# One\n\n"
      writer.flush
      settle { a.viewer.document.outline.size == 1 }
      b = a.new_window || fail("no window was opened")
      begin
        b.document.should be a.document
        b.streaming?.should be_true
        b.viewer.follow_tail?.should be_true
        settle { b.viewer.document.outline.size == 1 } # what arrived so far
        feed writer, ["# Two\n\n", "# Three\n\n"]
        settle { b.viewer.document.outline.size == 3 && a.viewer.document.outline.size == 3 }
        settle { !b.streaming? }
        b.markdown.should eq "# One\n\n# Two\n\n# Three\n\n"
      ensure
        b.window.destroy
      end
    end
    Md::Documents.all.should be_empty
  end

  it "goes on after the window that started it closes" do
    reader, writer = IO.pipe
    application = Crysterm::Application.new
    with_app Md::Source.new(stdin: true), view: true do |a, first_window|
      application.add first_window
      a.window_opener = recording_opener
      a.stream reader
      b = a.new_window || fail("no window was opened")
      begin
        a.window.close
        a.window.destroyed?.should be_true
        b.document.host.should be b
        feed writer, ["# One\n\n", "# Two\n\n"]
        settle { b.viewer.document.outline.size == 2 }
        settle { !b.streaming? } # the end reached the window left
      ensure
        b.window.destroy
      end
      Md::Documents.all.should be_empty
    end
  end

  it "loses no line still queued in the window that closes" do
    application = Crysterm::Application.new
    with_app Md::Source.new(stdin: true), view: true do |a, first_window|
      application.add first_window
      a.window_opener = recording_opener
      b = a.new_window || fail("no window was opened")
      begin
        a.stream IO::Memory.new("# One\n\n# Two\n\n# Three\n\n")
        # The reader posts every line and the end to the host's queue, and
        # the host goes before its render fiber took them.
        Fiber.yield
        a.window.destroy
        b.document.host.should be b
        settle { !b.streaming? }
        b.markdown.should eq "# One\n\n# Two\n\n# Three\n\n"
        settle { b.viewer.document.outline.size == 3 }
      ensure
        b.window.destroy
      end
      Md::Documents.all.should be_empty
    end
  end

  it "stops reading for a document no window shows any more" do
    reader, writer = IO.pipe
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream reader
      writer << "# One\n\n"
      writer.flush
      settle { app.viewer.document.outline.size == 1 }
      document = app.document
      app.close_document
      document.receive "late\n"
      document.markdown.should eq "# One\n\n"
    end
    writer.close
  end

  it "waits for --line in its own window only" do
    reader, writer = IO.pipe
    application = Crysterm::Application.new
    window = headless_window
    application.add window
    a = Md::App.new(Md::Source.new(stdin: true), stream: reader, view: true, window: window, line: 3)
    a.window_opener = recording_opener
    begin
      b = a.new_window || fail("no window was opened")
      begin
        feed writer, ["# One\n\n", "two\n\n", "# Three\n\n", "four\n\n"]
        settle { a.viewer.document.blocks.any? { |block| block.text == "Three" } && a.viewer.follow_tail? == false }
        a.editor.text_cursor.block_number.should eq 2
        settle { b.viewer.document.outline.size == 2 }
        b.viewer.follow_tail?.should be_true
      ensure
        b.window.destroy
      end
    ensure
      window.destroy
    end
  end
end
