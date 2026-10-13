require "./spec_helper"

# A notice up in the status bar ends when the bar is put to another use — a
# question asked in its place, Vi Mode's command line — as a Qt application
# clears a status message for it; the notice neither hides the use nor comes
# back after it.

private def name_field(app)
  app.main.status_bar.normal_widgets.first.as(Crysterm::Widget::Label)
end

describe "Md::App status notices" do
  it "ends a notice when a question takes the bar" do
    with_app Md::Source.new(path: "doc.md"), text: "# Doc\n", view: true do |app|
      app.find_next # a notice: no previous search
      notice(app).should_not eq ""
      app.search_prompt
      notice(app).should eq ""
      app.main.status_bar.line_prompt.cancel
      notice(app).should eq "" # not back after the question
      name_field(app).visible?.should be_true
    end
  end

  unless Crysterm::Neovim.available?
    pending "needs nvim in PATH"
    next
  end

  it "ends a notice when Vi Mode's command line opens, showing the command line" do
    path = tempfile "# Title\n"
    begin
      with_app Md::Source.new(path: path), text: "# Title\n", view: false do |app, window|
        app.vi_mode = true
        press window, 'x'
        press window, ':'
        press window, 'w'
        press window, Tput::Key::Enter
        settle { notice(app).includes? "Saved" }
        press window, ':'
        settle { name_field(app).visible? && name_field(app).text == " :" }
        notice(app).should eq ""
        press window, Tput::Key::Escape
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end
end
