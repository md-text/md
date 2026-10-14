require "./spec_helper"

# `Md::SaveFile`: a file written whole through a temporary file, or in place
# where a rename would not keep the file what it was.
private def with_dir(&)
  dir = File.tempname("md-save-file")
  Dir.mkdir dir
  begin
    yield dir
  ensure
    File.chmod dir, 0o755 if Dir.exists?(dir)
    FileUtils.rm_rf dir
  end
end

describe Md::SaveFile do
  it "replaces the file through a temporary one, keeping its permissions, and creates a new one" do
    with_dir do |dir|
      path = File.join(dir, "a.md")
      File.write path, "old"
      File.chmod path, 0o640
      inode = File.info(path)
      Md::SaveFile.write path, "new"
      File.read(path).should eq "new"
      File.info(path).permissions.value.should eq 0o640
      File.info(path).same_file?(inode).should be_false # renamed over, not rewritten
      Dir.children(dir).should eq ["a.md"]

      fresh = File.join(dir, "b.md")
      Md::SaveFile.write fresh, "made"
      File.read(fresh).should eq "made"
      File.open(File.join(dir, "c.md"), "w") { } # what File.open makes of a new file
      File.info(fresh).permissions.should eq File.info(File.join(dir, "c.md")).permissions
      Dir.children(dir).sort.should eq ["a.md", "b.md", "c.md"] # the temporary file is gone
    end
  end

  it "writes a symbolic link's target, the link left a link" do
    with_dir do |dir|
      Dir.mkdir File.join(dir, "real")
      target = File.join(dir, "real", "a.md")
      File.write target, "old"
      link = File.join(dir, "link.md")
      File.symlink "real/a.md", link
      chain = File.join(dir, "chain.md")
      File.symlink link, chain
      Md::SaveFile.write chain, "new"
      File.symlink?(chain).should be_true
      File.symlink?(link).should be_true
      File.read(target).should eq "new"
      Md::SaveFile.target(chain).should eq target
    end
  end

  it "writes a hard-linked file in place, so every link sees the text" do
    with_dir do |dir|
      path = File.join(dir, "a.md")
      File.write path, "old"
      other = File.join(dir, "b.md")
      File.link path, other
      Md::SaveFile.write path, "new"
      File.read(other).should eq "new"
      File.info(path).same_file?(File.info(other)).should be_true
    end
  end

  it "writes in place in a directory it may not create files in, and refuses a read-only file" do
    with_dir do |dir|
      path = File.join(dir, "a.md")
      File.write path, "old"
      File.chmod dir, 0o555
      Md::SaveFile.write path, "new"
      File.read(path).should eq "new"
      File.chmod dir, 0o755

      File.chmod path, 0o444
      ex = expect_raises(File::AccessDeniedError) { Md::SaveFile.write path, "newer" }
      Md.error_text(ex).should eq "Permission denied"
      File.read(path).should eq "new"
    end
  end

  it "writes in place a name too long for the temporary file's, and a device with no disk to flush to" do
    with_dir do |dir|
      path = File.join(dir, "#{"a" * 250}.md")
      File.write path, "old"
      Md::SaveFile.write path, "new"
      File.read(path).should eq "new"
      Dir.children(dir).size.should eq 1
    end
    Md::SaveFile.write "/dev/null", "text"
  end

  it "leaves the file as it was when the text cannot be renamed over it" do
    with_dir do |dir|
      path = File.join(dir, "a.md")
      Dir.mkdir path # a regular file cannot replace a directory
      expect_raises(IO::Error) { Md::SaveFile.write path, "new" }
      Dir.exists?(path).should be_true
      Dir.children(dir).should eq ["a.md"]
    end
  end
end

describe "Md.error_text" do
  it "gives the OS's words alone for a file error, the message otherwise" do
    ex = expect_raises(File::NotFoundError) { File.read "/nonexistent-md-dir/x.md" }
    Md.error_text(ex).should eq "No such file or directory"
    Md.error_text(IO::Error.new("closed stream")).should eq "closed stream"
  end
end
