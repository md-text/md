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

  it "keeps lines queued in a host that opens another file for the window left" do
    path = tempfile "# File\n"
    application = Crysterm::Application.new
    begin
      with_app Md::Source.new(stdin: true), view: true do |a, first_window|
        application.add first_window
        a.window_opener = recording_opener
        b = a.new_window || fail("no window was opened")
        begin
          a.stream IO::Memory.new("# One\n\n# Two\n\n")
          Fiber.yield # the lines wait in the host's queue
          a.open_file(path).should be_true
          b.document.host.should be b
          settle { !b.streaming? }
          b.markdown.should eq "# One\n\n# Two\n\n"
          settle { b.viewer.document.outline.size == 2 }
          a.viewer.follow_tail?.should be_false
          a.markdown.should eq "# File\n"
        ensure
          b.window.destroy
        end
      end
    ensure
      File.delete? path
    end
    Md::Documents.all.should be_empty
  end

  it "stops following the stream in every window of a linked group that opens a file" do
    path = tempfile "# File\n"
    reader, writer = IO.pipe
    application = Crysterm::Application.new
    begin
      with_app Md::Source.new(stdin: true), view: true do |a, first_window|
        application.add first_window
        a.window_opener = recording_opener
        a.window_link = Md::App::WindowLink::Linked
        a.stream reader
        b = a.new_window || fail("no window was opened")
        begin
          writer << "# One\n\n"
          writer.flush
          settle { b.viewer.document.outline.size == 1 }
          streamed = a.document
          b.viewer.follow_tail?.should be_true
          a.open_file(path).should be_true
          b.source.path.should eq path
          b.viewer.follow_tail?.should be_false
          a.viewer.follow_tail?.should be_false
          Md::Documents.all.should_not contain streamed # the last window left it
        ensure
          b.window.destroy
          Md::Documents.link_windows Md::App::WindowLink::Separate
        end
      end
    ensure
      writer.close
      File.delete? path
    end
    Md::Documents.all.should be_empty
  end
  it "takes nothing of the stream into a window that opened another file meanwhile" do
    path = tempfile "# File\n"
    application = Crysterm::Application.new
    begin
      with_app Md::Source.new(stdin: true), view: true do |a, first_window|
        application.add first_window
        a.window_opener = recording_opener
        b = a.new_window || fail("no window was opened")
        begin
          a.document.start_stream IO::Memory.new # streaming; its end comes later
          # Taken in on a's fiber: b gets the chunk and the end by post…
          a.receive "# Late\n\n"
          a.finish_stream
          # …and opens a file before its render fiber took them.
          b.open_file(path).should be_true
          settle { a.viewer.document.outline.size == 1 && !a.streaming? }
          sleep 50.milliseconds
          b.viewer.document.outline.map(&.text).should eq ["File"]
          b.viewer.follow_tail?.should be_false
        ensure
          b.window.destroy
        end
      end
    ensure
      File.delete? path
    end
    Md::Documents.all.should be_empty
  end

  it "posts another window one job for any number of chunks, so taking them in never waits on its queue" do
    reader, writer = IO.pipe
    application = Crysterm::Application.new
    with_app Md::Source.new(stdin: true), view: true do |a, first_window|
      application.add first_window
      a.window_opener = recording_opener
      b = a.new_window || fail("no window was opened")
      begin
        a.document.start_stream reader
        waited = false
        spawn { waited = true }
        # More chunks than a window's queue holds, taken in on a's fiber.
        2000.times { |i| a.receive "line #{i}\n" }
        waited.should be_false # nothing blocked on b's queue
        writer.close
        settle { !b.streaming? }
        settle { b.viewer.document.to_plain_text.includes?("line 1999") }
        b.markdown.should eq (0...2000).join { |i| "line #{i}\n" }
      ensure
        b.window.destroy
      end
    end
    Md::Documents.all.should be_empty
  ensure
    reader.try &.close
  end
end
