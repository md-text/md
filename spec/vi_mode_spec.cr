require "./spec_helper"

# Edit → Vi Mode (Neovim): the editor edited by an embedded Neovim (`app_vi.cr`).

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
  menu(app, 1).actions.find!(&.text.==("V&i Mode (Neovim)"))
end

describe "Md::App Vi Mode" do
  it "is an Edit entry, disabled with a reason when nvim is missing" do
    with_app do |app|
      entry = vi_entry(app)
      entry.name.should eq "vi-mode"
      entry.checkable?.should be_true
      entry.enabled?.should eq Crysterm::Neovim.available?
      menu(app, 4).actions.find!(&.text.==("Vi Mode: Use &Neovim Config")).name.should eq "vi-config"
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
      # md's own keys still work: Alt-W is Format → Soft Wrap.
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
      File.read(path).should eq "# Title\nnew line\n"
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

  it "writes a copy on :w FILE, keeping the document's name, and saves as on :saveas FILE" do
    path = tempfile("# Title\n")
    copy = tempfile(nil)
    named = tempfile(nil)
    with_app Md::Source.new(path: path), text: File.read(path), view: false do |app, window|
      app.vi_mode = true
      vi_type window, "Gonew<Esc>:w #{copy}<CR>"
      settle { File.exists? copy }
      File.read(copy).should eq "# Title\nnew\n"
      File.read(path).should eq "# Title\n"
      app.source.path.should eq path
      app.editor.document.modified?.should be_true

      vi_type window, ":saveas #{named}<CR>"
      settle { File.exists? named }
      File.read(named).should eq "# Title\nnew\n"
      File.realpath(app.source.path.as(String)).should eq File.realpath(named)
      app.editor.document.modified?.should be_false
    end
  ensure
    [path, copy, named].each do |file|
      next unless file
      File.delete? file
      File.delete? "#{file}~"
    end
  end

  it "asks a new document's name on :wq and closes once it is saved there, staying when it is not" do
    path = tempfile(nil)
    with_app do |app, window|
      app.vi_mode = true
      vi_type window, "ihi<Esc>:wq<CR>"
      # The name is asked, and no unsaved-changes question takes its place.
      settle { question(app) == "Save as: " }
      app.main.status_bar.line_prompt.cancel
      sleep 50.milliseconds
      window.destroyed?.should be_false

      vi_type window, ":wq<CR>"
      settle { question(app) == "Save as: " }
      answer app, path
      settle { window.destroyed? }
      File.read(path).should contain "hi"
    end
  ensure
    if path
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "shows and focuses the editor when turned on from the menu, and says nothing of Neovim ending when turned off" do
    with_app text: "# A\n\ntext\n" do |app, window|
      app.viewer.focused?.should be_true
      vi_entry(app).trigger
      app.vi.attached?.should be_true
      app.editor.focused?.should be_true
      vi_type window, "ggAb<Esc>"
      app.markdown.should eq "# Ab\n\ntext\n"
      vi_entry(app).trigger
      app.vi_mode?.should be_false
      sleep 50.milliseconds
      notice(app).should_not contain "Neovim ended"
    end
  end

  it "turns off when the editor's buffer is closed in Neovim" do
    with_app text: "# A\n" do |app, window|
      app.vi_mode = true
      app.editor.focus
      vi_type window, ":bw!<CR>"
      settle { !app.vi_mode? }
      app.vi.attached?.should be_false
      notice(app).should contain "Vi Mode is off"
      vi_entry(app).checked?.should be_false
    end
  end

  it "keeps the editor's buffer in Neovim's window on :enew" do
    with_app text: "# A\n" do |app, window|
      app.vi_mode = true
      app.editor.focus
      vi_type window, ":enew<CR>"
      vi_type window, "ggAb<Esc>"
      app.markdown.should eq "# Ab\n"
      app.vi_mode?.should be_true
      settle { notice(app).includes? "own buffer" }
    end
  end

  it "starts Neovim's undo history afresh in a document opened" do
    path = tempfile("# B\n")
    with_app text: "# A\n" do |app, window|
      app.vi_mode = true
      app.editor.focus
      vi_type window, "ggAb<Esc>"
      app.markdown.should eq "# Ab\n"
      app.open_file(path).should be_true
      app.editor.focus
      app.vi.sync
      vi_type window, "u"
      app.markdown.should eq "# B\n"
      app.vi_mode?.should be_true
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

  it "keeps md's Ctrl-Q, Ctrl-S, Ctrl-N and Ctrl-W in Normal mode, and gives every Ctrl key to Neovim in Insert mode" do
    path = tempfile "one two\n"
    begin
      with_app Md::Source.new(path: path), text: "one two\n", view: false do |app, window|
        app.window_opener = ->(title : String) { headless_window.tap(&.title=(title)) }
        app.vi_mode = true
        app.editor.focused?.should be_true
        vi_type window, "A three<Esc>"
        app.markdown.should eq "one two three\n"
        # Normal mode: md's.
        press window, Tput::Key::CtrlS
        File.read(path).should eq "one two three\n"
        other = (press(window, Tput::Key::CtrlN); Md::App.instances.find { |a| !a.same?(app) }) || fail("no window was opened")
        begin
          vi_field(app).text.should eq "NORMAL"
          other.show_pane(Md::App::Pane::Editor).focus
          other.vi_mode = true                 # the config would have turned it on there too
          press other.window, Tput::Key::CtrlW # closes that window, not a word
          other.window.destroyed?.should be_true
        ensure
          other.window.destroy
        end
        vi_type window, "A four<Esc>"
        press window, Tput::Key::CtrlQ
        question(app).should start_with "Save changes to"
        answer app, 'c'
        vi_field(app).text.should eq "NORMAL" # not V-BLOCK
        # Insert mode: Neovim's (Ctrl-W deletes the word before the caret).
        vi_type window, "A"
        press window, Tput::Key::CtrlW
        vi_type window, "<Esc>"
        app.markdown.should eq "one two three \n"
        window.destroyed?.should be_false
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end
end
