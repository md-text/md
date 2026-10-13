require "./spec_helper"

# `Md::Documents`: one document per file, found by its canonical key.

describe Md::Documents do
  it "keys a file by its realpath, through a symlink" do
    dir = File.tempname("md-spec-keys")
    Dir.mkdir dir
    begin
      File.write File.join(dir, "a.md"), "a"
      File.symlink File.join(dir, "a.md"), File.join(dir, "link.md")
      Md::Documents.key_for(File.join(dir, "link.md")).should eq File.realpath(File.join(dir, "a.md"))
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "keys a new file by its directory's realpath and its name" do
    dir = File.tempname("md-spec-keys")
    Dir.mkdir dir
    begin
      Md::Documents.key_for(File.join(dir, "new.md")).should eq File.join(File.realpath(dir), "new.md")
      Md::Documents.key_for("/no/such/dir/new.md").should eq "/no/such/dir/new.md"
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "finds a hard link to an open file as the same document" do
    dir = File.tempname("md-spec-keys")
    Dir.mkdir dir
    path = File.join(dir, "a.md")
    File.write path, "a"
    File.link path, File.join(dir, "b.md")
    begin
      with_app Md::Source.new(path: path), text: "a" do |app|
        Md::Documents.find(File.join(dir, "b.md")).should be app.document
      end
    ensure
      FileUtils.rm_rf dir
    end
  end

  it "finds a file by another case on a case-insensitive volume" do
    path = tempfile "a"
    begin
      upper = File.join(File.dirname(path), File.basename(path).upcase)
      pending! "case-sensitive volume" unless File.exists?(upper)
      with_app Md::Source.new(path: path), text: "a" do |app|
        Md::Documents.find(upper).should be app.document
      end
    ensure
      File.delete? path
    end
  end

  it "matches a file it cannot look at by key only, raising nothing" do
    dir = File.tempname("md-spec-keys")
    locked = File.join(dir, "locked")
    Dir.mkdir_p locked
    path = File.join(dir, "a.md")
    File.write path, "a"
    File.link path, File.join(dir, "b.md")
    File.chmod locked, 0o000
    begin
      with_app Md::Source.new(path: File.join(locked, "x.md")) do |hidden|
        with_app Md::Source.new(path: path), text: "a" do |app|
          Md::Documents.find(File.join(locked, "y.md")).should be_nil
          Md::Documents.find(path).should be app.document
          # The hard link is looked for past the document whose file
          # cannot be looked at.
          Md::Documents.find(File.join(dir, "b.md")).should be app.document
          Md::Documents.find(File.join(locked, "x.md")).should be hidden.document
        end
      end
    ensure
      File.chmod locked, 0o755
      FileUtils.rm_rf dir
    end
  end

  it "never matches unnamed or stdin documents by path" do
    with_app do |app|
      Md::Documents.all.should eq [app.document]
      Md::Documents.find(Dir.current).should be_nil
      Md::Documents.find("[No Name]").should be_nil
    end
  end

  it "re-keys on Save As and on the first save of a new file" do
    dir = File.tempname("md-spec-keys")
    Dir.mkdir dir
    begin
      with_app Md::Source.new(path: File.join(dir, "new.md")) do |app|
        Md::Documents.find(File.join(dir, "new.md")).should be app.document
        app.editor.insert_text "x"
        app.save.should be_true
        app.document.key.should eq File.realpath(File.join(dir, "new.md"))
        app.save_as(File.join(dir, "other.md")).should be_true
        Md::Documents.find(File.join(dir, "other.md")).should be app.document
        Md::Documents.find(File.join(dir, "new.md")).should be_nil
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end
