require "./spec_helper"
require "file_utils"

# Options → Links → Open Local Programs: a link to a program on this
# computer is refused unless it is on, where any other file goes to the
# platform's opener.

# A directory holding a document and the files its links name; yields the
# directory and the document's path.
private def with_program_docs(&)
  dir = File.tempname("md-spec-programs")
  Dir.mkdir_p dir
  doc = File.join(dir, "doc.md")
  File.write doc, "# Doc\n"
  File.write File.join(dir, "tool.sh"), "#!/bin/sh\necho hi\n"
  File.chmod File.join(dir, "tool.sh"), 0o755
  File.write File.join(dir, "run.command"), "echo hi\n" # no x bit: macOS's Terminal runs it anyway
  File.write File.join(dir, "start.desktop"), "[Desktop Entry]\nExec=true\n"
  Dir.mkdir_p File.join(dir, "Thing.app", "Contents")
  Dir.mkdir_p File.join(dir, "folder")
  File.write File.join(dir, "notes.txt"), "text\n"
  File.write File.join(dir, "readme.md"), "# Readme\n"
  File.chmod File.join(dir, "readme.md"), 0o755 # Markdown, executable or not, is read
  File.symlink File.join(dir, "tool.sh"), File.join(dir, "alias.pdf")
  yield dir, doc
ensure
  FileUtils.rm_rf dir if dir
end

describe "Md::App local programs" do
  it "tells programs from the other files" do
    with_program_docs do |dir, _doc|
      {"tool.sh", "run.command", "start.desktop", "Thing.app", "Thing.app/", "alias.pdf"}.each do |name|
        {name, Md::App.program?(File.join(dir, name))}.should eq({name, true})
      end
      {"notes.txt", "folder", "doc.md", "missing.exe"}.each do |name|
        {name, Md::App.program?(File.join(dir, name))}.should eq({name, false})
      end
    end
  end

  it "refuses a link to a program by default, and opens it with Open Local Programs on" do
    with_program_docs do |dir, doc|
      with_app Md::Source.new(path: doc), text: "# Doc\n", view: true do |app|
        opened = [] of String
        app.url_opener = ->(url : String) { opened << url; nil }
        app.open_local_programs?.should be_false
        {"tool.sh", "run.command", "start.desktop", "Thing.app", "alias.pdf", "file://#{dir}/tool.sh"}.each do |link|
          app.follow_link link
          target = link.starts_with?("file:") ? File.join(dir, "tool.sh") : File.join(dir, link)
          notice(app).should eq " Not running #{target}: a program (Options → Links → Open Local Programs)"
        end
        opened.should be_empty

        # Remote URLs and plain files are unaffected.
        app.follow_link "https://example.com/setup.exe"
        app.follow_link "notes.txt"
        opened.should eq ["https://example.com/setup.exe", File.join(dir, "notes.txt")]
        app.follow_link "folder"
        notice(app).should eq " Not a file: #{File.join(dir, "folder")}"
        # An executable Markdown file is read, not run.
        app.follow_link "readme.md"
        app.source.path.should eq File.join(dir, "readme.md")
        app.follow_link "doc.md"

        entry = menu(app, 4).actions.find!(&.text.==("Lin&ks")).menu.try(&.find(&.text.==("Open Local &Programs"))) || fail("no Open Local Programs entry")
        entry.name.should eq "open-local-programs"
        entry.checked?.should be_false
        entry.trigger
        app.open_local_programs?.should be_true
        app.follow_link "tool.sh"
        app.follow_link "Thing.app"
        opened[-2..].should eq [File.join(dir, "tool.sh"), File.join(dir, "Thing.app")]
      end
    end
  end

  it "keeps Open Local Programs with the settings" do
    with_config %(md:\n  open_local_programs: true\n) do |path|
      with_app config: true do |app|
        app.open_local_programs?.should be_true
        app.open_local_programs = false
        app.save_config
      end
      config_file(path)["md"]["open_local_programs"].as_bool.should be_false
    end
  end
end
