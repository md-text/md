require "./spec_helper"

# The terminal's title: the document's file name, without its directory,
# followed by ` • MD`, or
# `[No Name] • MD`, sent to the terminal at start and whenever the document
# changes (File → Open, Save As, Close), the terminal's own title saved
# first and put back when md lets the terminal go.

# The titles sent to the terminal so far, in order.
private def sent_titles(window) : Array(String)
  window.tput.flush
  window.output.as(IO::Memory).to_s.scan(/\e\]0;([^\a]*)\a/).map(&.[1])
end

describe "Md::App terminal title" do
  it "is [No Name] • MD for a document without a name, and follows the file" do
    path = tempfile "# T\n"
    saved = File.tempname("md-spec-title", ".md")
    begin
      with_app do |app, window|
        app.title.should eq "[No Name] • MD"
        app.document_name.should eq "[No Name]"
        sent_titles(window).last.should eq "[No Name] • MD"

        app.open_file(path).should be_true
        sent_titles(window).last.should eq "#{File.basename path} • MD"

        app.save_as(saved).should be_true
        sent_titles(window).last.should eq "#{File.basename saved} • MD"
      end
    ensure
      File.delete? path
      File.delete? saved
    end
  end

  it "names the file without its directory, the status bar keeping the path" do
    with_app Md::Source.new(path: "docs/guide.md"), text: "# G\n" do |app, window|
      app.title.should eq "guide.md • MD"
      sent_titles(window).last.should eq "guide.md • MD"
      app.main.status_bar.normal_widgets.first.as(Crysterm::Widget::Label).text.should contain "docs/guide.md"
    end
  end

  it "names a stream stdin" do
    with_app Md::Source.new(stdin: true) do |app, window|
      app.title.should eq "stdin • MD"
      sent_titles(window).last.should eq "stdin • MD"
    end
  end

  it "saves the terminal's title before the first and puts it back at the end" do
    window = headless_window
    Md::App.new(Md::Source.new(path: "doc.md"), text: "# T\n", window: window)
    window.tput.flush
    out = window.output.as(IO::Memory).to_s
    out.index!("\e[22;0t").should be < out.index!("\e]0;doc.md • MD\a")
    window.output.as(IO::Memory).clear
    window.destroy
    window.output.as(IO::Memory).to_s.should contain "\e[23;0t"
  end
end
