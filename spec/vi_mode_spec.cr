require "./spec_helper"

# Edit → Vi Mode: the editor edited by an embedded Neovim (`app_vi.cr`).

# Types *keys* at the window, `<Esc>`, `<CR>`, `<F2>` and `<M-w>` naming those keys.
private def vi_type(window, keys : String)
  keys.scan(/<[^>]+>|./m) do |match|
    case match[0]
    when "<Esc>" then press window, Tput::Key::Escape
    when "<CR>"  then press window, Tput::Key::Enter
    when "<F2>"  then press window, Tput::Key::F2
    when "<M-w>" then press window, Tput::Key::AltW
    else              press window, match[0][0]
    end
  end
end

# The status bar's Vi Mode field.
private def vi_field(app)
  app.main.status_bar.permanent_widgets.first.as(Crysterm::Widget::Label)
end

private def name_field(app)
  app.main.status_bar.normal_widgets.first.as(Crysterm::Widget::Label)
end

private def vi_entry(app)
  menu(app, 1).actions.find!(&.text.==("V&i Mode"))
end

describe "Md::App Vi Mode" do
  it "is an Edit entry, disabled with a reason when nvim is missing" do
    with_app do |app|
      entry = vi_entry(app)
      entry.name.should eq "vi-mode"
      entry.checkable?.should be_true
      entry.enabled?.should eq Crysterm::Neovim.available?
      menu(app, 4).actions.find!(&.text.==("Vi Mode Uses Your &Neovim Config")).name.should eq "vi-config"
      app.vi_mode?.should be_false
      vi_field(app).visible?.should be_false
    end
  end

  unless Crysterm::Neovim.available?
    pending "needs nvim in PATH"
    next
  end

  it "edits the editor with Neovim's keys, shows the mode, and gives the keys back when turned off" do
    with_app do |app, window|
      app.editor.focused?.should be_true
      vi_entry(app).trigger
      app.vi_mode?.should be_true
      app.vi.attached?.should be_true
      vi_field(app).visible?.should be_true
      vi_field(app).text.should eq "NORMAL"
      vi_type window, "ihello world"
      vi_field(app).text.should eq "INSERT"
      vi_type window, "<Esc>"
      vi_field(app).text.should eq "NORMAL"
      app.markdown.should eq "hello world"
      vi_type window, "0dw"
      app.markdown.should eq "world"
      app.editor.document.modified?.should be_true
      vi_type window, "u"
      app.markdown.should eq "hello world"
      # md's own keys still work: Alt-W is View → Soft Wrap.
      wrap = app.soft_wrap?
      vi_type window, "<M-w>"
      app.soft_wrap?.should eq !wrap

      app.vi_mode = false
      app.vi.attached?.should be_false
      vi_field(app).visible?.should be_false
      vi_type window, "x"
      app.markdown.should contain "x"
    end
  end

  it "shows the command line in the status bar, saves on :w and closes on :q" do
    path = tempfile("# Title\n")
    with_app Md::Source.new(path: path), text: File.read(path), view: false do |app, window|
      app.vi_mode = true
      vi_type window, "Gonew line<Esc>"
      vi_type window, ":w"
      name_field(app).text.should eq " :w"
      vi_type window, "<CR>"
      settle { File.read(path).includes? "new line" }
      File.read(path).should eq "# Title\n\nnew line"
      app.editor.document.modified?.should be_false
      name_field(app).text.should_not contain ":w"

      vi_type window, "x:q<CR>"
      # Unsaved changes: the window asks first.
      settle { !question(app).empty? }
      answer app, 'c'
      window.destroyed?.should be_false
      vi_type window, ":q!<CR>"
      settle { window.destroyed? }
    end
  end

  it "keeps the viewer's : as md's command line" do
    with_app text: "# A\n\ntext\n" do |app, window|
      app.vi_mode = true
      app.viewer.focused?.should be_true
      press window, ':'
      question(app).should_not be_empty
      app.vi.attached?.should be_true
    end
  end
end
