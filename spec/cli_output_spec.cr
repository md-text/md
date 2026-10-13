require "./spec_helper"

# Standard output piped into a reader that has gone (`md --help | head`, the
# head done): every write fails as the OS fails it, with `EPIPE`.
class ClosedPipe < IO
  def read(slice : Bytes) : NoReturn
    raise IO::Error.new("not readable")
  end

  def write(slice : Bytes) : NoReturn
    raise IO::Error.from_os_error("Error writing file", Errno::EPIPE)
  end
end

describe Md::CLI do
  it "ends quietly, as a filter killed by SIGPIPE, when the reader stops reading" do
    {["--help", "--verbose"], ["--version"], ["--generate", "man"], ["--export", "html", "-"]}.each do |args|
      error = IO::Memory.new
      Md::CLI.run(args, stdout: ClosedPipe.new, stderr: error, stdin: IO::Memory.new("# Doc\n")).should eq 141
      error.to_s.should be_empty
    end
  end
end

describe Md::Manual do
  it "keeps every text line of the man page within 80 bytes, as mandoc's lint asks" do
    Md::Manual.man.each_line do |line|
      # A request, or a tagged paragraph's tag (a flag and its names), which
      # cannot break.
      next if line.starts_with?('.') || line.starts_with?("\\fB")
      line.bytesize.should be <= 80
    end
  end
end
