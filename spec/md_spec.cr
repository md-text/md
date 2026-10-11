require "./spec_helper"

describe Md do
  it "has a semantic version taken from shard.yml" do
    Md::VERSION.should match(/\A\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?\z/)
    shard_version = File.read_lines(File.join(__DIR__, "..", "shard.yml"))
      .find!(&.starts_with?("version:"))["version:".size..].strip
    Md::VERSION.should eq shard_version
  end
end

describe Md::CLI do
  it "prints the version" do
    output = IO::Memory.new
    Md::CLI.run(["--version"], stdout: output).should eq 0
    output.to_s.should eq "md #{Md::VERSION}\n"
  end

  it "prints help" do
    output = IO::Memory.new
    Md::CLI.run(["--help"], stdout: output).should eq 0
    output.to_s.should contain "Usage: md"
    output.to_s.should contain "--version"
  end

  it "keeps the Crysterm toolkit options out of plain help" do
    output = IO::Memory.new
    Md::CLI.run(["--help"], stdout: output).should eq 0
    output.to_s.should_not contain "--colors-theme"
  end

  it "lists the Crysterm toolkit options with --help --verbose, in either order" do
    ["--help", "--verbose"].each_permutation do |flags|
      output = IO::Memory.new
      Md::CLI.run(flags, stdout: output).should eq 0
      output.to_s.should contain "Usage: md"
      output.to_s.should contain "--colors-theme=VALUE"
      output.to_s.should contain "--crysterm-dump-config"
      output.to_s.index!("Usage: md").should be < output.to_s.index!("--colors-theme")
    end
  end

  it "passes Crysterm toolkit options through" do
    output = IO::Memory.new
    Md::CLI.run(["--colors-theme", "dark", "--colors-stylesheet=/dev/null", "--version"], stdout: output).should eq 0
    output.to_s.should eq "md #{Md::VERSION}\n"
  end

  it "rejects unknown options" do
    error = IO::Memory.new
    Md::CLI.run(["--bogus"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "unknown option: --bogus"
  end

  it "rejects a second file argument" do
    error = IO::Memory.new
    Md::CLI.run(["a.md", "b.md"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "unexpected argument: b.md"
  end

  it "takes a line from +N or --line, apart from the file" do
    options = Md::CLI.parse(["+12", "notes.md"])
    options.line.should eq 12
    options.positional.should eq ["notes.md"]
    Md::CLI.parse(["notes.md", "--line", "7"]).line.should eq 7
    Md::CLI.parse(["-l7"]).line.should eq 7
    Md::CLI.parse(["--line=7"]).line.should eq 7
    Md::CLI.parse(["+"]).line.should eq 0 # the end, as in vim
    Md::CLI.parse(["notes.md"]).line.should be_nil
    # Beyond `--`, `+N` is a file name.
    Md::CLI.parse(["--", "+1"]).positional.should eq ["+1"]
  end

  it "rejects a line that is not a number, and a --line without one" do
    error = IO::Memory.new
    Md::CLI.run(["--line", "ten"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "not a line number: ten"
    error = IO::Memory.new
    Md::CLI.run(["+abc"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "not a line number: +abc"
    error = IO::Memory.new
    Md::CLI.run(["--line"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "Missing option: --line"
    error.to_s.should contain "Usage: md"
  end

  it "takes --view and --edit, but not both" do
    Md::CLI.parse(["--view", "new.md"]).view.should be_true
    Md::CLI.parse(["--edit", "README.md"]).view.should be_false
    Md::CLI.parse(["README.md"]).view.should be_nil
    Md::CLI.parse(["--view", "--view"]).view.should be_true
    error = IO::Memory.new
    Md::CLI.run(["--view", "--edit"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "--view and --edit cannot be combined"
  end

  it "lists the new options in help" do
    output = IO::Memory.new
    Md::CLI.run(["--help"], stdout: output).should eq 0
    help = output.to_s
    help.should contain "[+N]"
    {"-l N, --line N", "--view", "--edit"}.each { |flag| help.should contain flag }
  end
end
