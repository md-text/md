require "./spec_helper"
require "file_utils"

# File → Export as HTML… and Export as Text…: the document rendered to a
# file, as `md --export` prints it.

EXPORT_DOC = "# Title\n\nSome *text*.\n\n- one\n- two\n"

private def export_entry(app, text)
  menu(app, 0).actions.find!(&.text.==(text))
end

private def with_export_dir(&)
  dir = File.tempname("md-spec-export")
  Dir.mkdir_p dir
  yield dir
ensure
  FileUtils.rm_rf dir if dir
end

describe "Md::App export" do
  it "exports the current text as HTML, suggesting the document's name with .html" do
    with_export_dir do |dir|
      doc = File.join(dir, "notes.md")
      File.write doc, "old\n"
      with_app Md::Source.new(path: doc), text: EXPORT_DOC, view: true do |app|
        entry = export_entry(app, "&Export as HTML…")
        entry.name.should eq "export-html"
        entry.trigger
        question(app).should contain "Export as HTML to:"
        app.main.status_bar.line_prompt.field.value.should eq File.join(dir, "notes.html")
        answer app, File.join(dir, "notes.html")
        File.read(File.join(dir, "notes.html")).should eq Md::Export.render(EXPORT_DOC, "html")
        notice(app).should eq " Exported #{File.join(dir, "notes.html")}"
        # A copy: the document keeps its file, its text unsaved as it was.
        app.source.path.should eq doc
        File.read(doc).should eq "old\n"
      end
    end
  end

  it "exports as text, a typed ~/ being the home directory" do
    with_export_dir do |home|
      saved = ENV["HOME"]?
      ENV["HOME"] = home
      begin
        with_app Md::Source.new, text: EXPORT_DOC do |app|
          export_entry(app, "Export as &Text…").name.should eq "export-text"
          app.export_prompt "text"
          app.main.status_bar.line_prompt.field.value.should eq "" # no file, no name
          answer app, "~/out.txt"
          File.read(File.join(home, "out.txt")).should eq Md::Export.render(EXPORT_DOC, "text")
          Dir.exists?("~").should be_false
        end
      ensure
        saved ? (ENV["HOME"] = saved) : ENV.delete("HOME")
      end
    end
  end

  it "suggests an added extension when the name has the format's already" do
    with_app Md::Source.new(path: "/tmp/plain.txt"), text: "x\n" do |app|
      app.export_prompt "text"
      app.main.status_bar.line_prompt.field.value.should eq "/tmp/plain.txt.txt"
    end
  end

  it "does not write over a file open in md, and says why a write failed" do
    with_export_dir do |dir|
      doc = File.join(dir, "notes.md")
      File.write doc, "source\n"
      with_app Md::Source.new(path: doc), text: "source\n", view: true do |app|
        app.export(doc, "html").should be_false
        notice(app).should eq " Not exporting to #{doc}: it is open in md"
        File.read(doc).should eq "source\n"
        missing = File.join(dir, "no", "such", "out.html")
        app.export(missing, "html").should be_false
        notice(app).should start_with " Cannot export #{missing}: "
      end
    end
  end
end
