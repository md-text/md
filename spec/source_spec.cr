require "./spec_helper"

describe Md::Source do
  it "is an unnamed document with no argument and a terminal on stdin" do
    source = Md::Source.resolve([] of String, stdin_tty: true)
    source.path.should be_nil
    source.stdin?.should be_false
    source.name.should be_nil
  end

  it "reads stdin with no argument when stdin is not a terminal" do
    source = Md::Source.resolve([] of String, stdin_tty: false)
    source.stdin?.should be_true
    source.name.should eq "stdin"
  end

  it "reads stdin for `-` even when stdin is a terminal" do
    Md::Source.resolve(["-"], stdin_tty: true).stdin?.should be_true
  end

  it "names the file given" do
    source = Md::Source.resolve(["notes.md"], stdin_tty: false)
    source.path.should eq "notes.md"
    source.stdin?.should be_false
    source.name.should eq "notes.md"
  end

  it "rejects a second argument" do
    expect_raises(ArgumentError, "unexpected argument: b.md") do
      Md::Source.resolve(["a.md", "b.md"], stdin_tty: true)
    end
  end
end
