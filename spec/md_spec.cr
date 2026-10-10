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
end
