require "./spec_helper"

# Vi Mode in windows on one document (`app_vi.cr`): one Neovim per window
# while separate, one buffer per document while linked.

private def vi_type(window, keys : String)
  keys.scan(/<[^>]+>|./m) do |match|
    case match[0]
    when "<Esc>" then press window, Tput::Key::Escape
    when "<CR>"  then press window, Tput::Key::Enter
    else              press window, match[0][0]
    end
  end
end

private def vi_field(app)
  app.main.status_bar.permanent_widgets.first.as(Crysterm::Widget::Label)
end

# Turns Vi Mode on in both windows, as the config does in the app.
private def vi_on(a, b)
  {a, b}.each do |app|
    app.show_pane(Md::App::Pane::Editor).focus
    app.vi_mode = true
  end
end

describe "Md::App Vi Mode in windows on one document" do
  unless Crysterm::Neovim.available?
    pending "needs nvim in PATH"
    next
  end

  it "shares one Neovim between linked windows: an insert typed in B is in the text and in A" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      a.vi.should be b.vi
      a.vi.views.should eq [a.editor, b.editor]
      vi_type b.window, "ggIhello <Esc>"
      a.markdown.should eq "hello one\n"
      settle { vi_field(a).text == "NORMAL" && vi_field(b).text == "NORMAL" }
    end
  end

  it "undoes in A what B typed, and repeats it in B" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      vi_type b.window, "ggIhello <Esc>"
      vi_type a.window, "u"
      a.markdown.should eq "one\n"
      vi_type b.window, "."
      b.markdown.should contain "hello"
    end
  end

  it "saves on :w in B, and closes B alone on :q, asking nothing while A shows the document" do
    path = tempfile "one\n"
    begin
      with_two_windows(Md::Source.new(path: path), "one\n", view: false, linked: true) do |a, b|
        vi_on a, b
        vi_type b.window, "ggIx<Esc>:w<CR>"
        File.read(path).should eq "xone\n"
        vi_type b.window, "ay<Esc>:q<CR>"
        b.window.destroyed?.should be_true
        a.window.destroyed?.should be_false
        a.vi.attached?.should be_true # A keeps the Neovim
        a.vi.views.should eq [a.editor]
        vi_type a.window, "ggIz<Esc>"
        a.markdown.should start_with "z"
      end
    ensure
      File.delete? path
      File.delete? "#{path}~"
    end
  end

  it "gives each window its own Neovim on separating, and one again on linking" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      shared = a.vi
      a.window_link = Md::App::WindowLink::Separate
      a.vi.should_not be b.vi
      a.vi.attached?.should be_true
      b.vi.attached?.should be_true
      shared.attached?.should be_false
      a.document.vi.should be_nil
      a.window_link = Md::App::WindowLink::Linked
      a.vi.should be b.vi
      a.vi.attached?.should be_true
    end
  end

  it "puts a window joining a linked group in Vi Mode on the group's Neovim" do
    first = tempfile "one\n"
    second = tempfile "two\n"
    begin
      with_two_windows(Md::Source.new(path: first), "one\n", view: false) do |a, b|
        c = a.new_window || fail("no window was opened")
        begin
          c.open_file(second).should be_true # separate: C alone goes
          Md::Documents.link_windows Md::App::WindowLink::Linked
          {a, b, c}.each do |app|
            app.show_pane(Md::App::Pane::Editor).focus
            app.vi_mode = true
          end
          own = c.vi
          own.should_not be a.vi
          c.open_file(first).should be_true # C joins A and B's group
          c.link.should be a.link
          c.vi.should be a.vi
          a.vi.views.should eq [a.editor, b.editor, c.editor]
          own.attached?.should be_false # the second document's Neovim ended with it
          vi_type b.window, "ggIb<Esc>"
          c.markdown.should eq "bone\n"
          # A window opened with Ctrl-N joins as well.
          d = a.new_window || fail("no window was opened")
          begin
            d.vi_mode = true
            d.vi.should be a.vi
            a.vi.views.size.should eq 4
          ensure
            d.window.destroy
          end
          a.vi.views.should eq [a.editor, b.editor, c.editor]
          # The group moving takes the Neovim along: one, on the new document.
          b.open_file(second).should be_true
          a.document.should be b.document
          c.document.should be b.document
          a.vi.should be b.vi
          a.vi.should be c.vi
          a.vi.attached?.should be_true
        ensure
          c.window.destroy
        end
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  # Crysterm's `TextEditing#swap_document` reports the caret it rewinds at
  # once (Qt's `setContent` emits `cursorPositionChanged`); were it left to
  # C's first key, the handler's caret push would land inside the `gg` it
  # splits.
  it "takes the first keys typed in a window that joined from another document" do
    first = tempfile "one\n"
    second = tempfile "two\n"
    begin
      with_two_windows(Md::Source.new(path: first), "one\n", view: false) do |a, b|
        c = a.new_window || fail("no window was opened")
        begin
          c.open_file(second).should be_true
          Md::Documents.link_windows Md::App::WindowLink::Linked
          {a, b, c}.each do |app|
            app.show_pane(Md::App::Pane::Editor).focus
            app.vi_mode = true
          end
          c.open_file(first).should be_true
          vi_type c.window, "ggIc<Esc>"
          b.markdown.should eq "cone\n"
        ensure
          c.window.destroy
        end
      end
    ensure
      File.delete? first
      File.delete? second
    end
  end

  it "quits every linked window on :qa, asking once about the modified document" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      vi_type b.window, "ggIx<Esc>:qa<CR>"
      settle { question(b).starts_with? "Save changes to" }
      a.window.destroyed?.should be_false # nothing closes before the answer
      b.window.destroyed?.should be_false
      answer b, 'n'
      settle { a.window.destroyed? && b.window.destroyed? }
    end
  end

  it "quits every linked window on :qa! without asking" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      vi_type a.window, "ggIx<Esc>:qa!<CR>"
      a.window.destroyed?.should be_true
      b.window.destroyed?.should be_true
    end
  end

  it "turns Vi Mode off in every linked window when Neovim ends, with a notice in each" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      pid = (a.vi.client || fail("no Neovim")).pid
      Process.signal Signal::KILL, pid # Neovim ends under the editors
      settle { !a.vi_mode? && !b.vi_mode? }
      settle { notice(a).includes?("Vi Mode is off") && notice(b).includes?("Vi Mode is off") }
      a.document.vi.should be_nil
    end
  end

  it "leaves no subscription of a closed window on the shared Neovim, however many come and go" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      vi_on a, b
      shared = a.vi
      listeners = shared.handlers(Crysterm::Event::ViModeChanged).size
      5.times do
        c = a.new_window || fail("no window was opened")
        c.show_pane(Md::App::Pane::Editor).focus
        c.vi_mode = true
        c.vi.should be shared
        c.window.destroy
      end
      a.vi.should be shared
      shared.views.should eq [a.editor, b.editor]
      shared.handlers(Crysterm::Event::ViModeChanged).size.should eq listeners
      shared.handlers(Crysterm::Event::ProcessExited).size.should eq listeners
      Md::App.instances.size.should eq 2
    end
  end

  it "shows nothing of the shared Neovim in a linked window not in Vi Mode, nor ends anything there" do
    with_two_windows(text: "one\n", view: false, linked: true) do |a, b|
      a.show_pane(Md::App::Pane::Editor).focus
      a.vi_mode = true
      b.vi.should_not be a.vi
      b.refresh_status
      vi_field(b).visible?.should be_false
      pid = (a.vi.client || fail("no Neovim")).pid
      Process.signal Signal::KILL, pid
      settle { !a.vi_mode? && notice(a).includes?("Vi Mode is off") }
      sleep 50.milliseconds
      notice(b).to_s.includes?("Vi Mode is off").should be_false
    end
  end

  it "runs a Neovim per separate window, each seeing the other's edits" do
    with_two_windows(text: "one\n", view: false) do |a, b|
      vi_on a, b
      a.vi.should_not be b.vi
      vi_type a.window, "ggIa<Esc>"
      b.markdown.should eq "aone\n"
      b.vi.sync
      vi_type b.window, "$ib<Esc>"
      a.markdown.should eq "aonbe\n"
      vi_type b.window, "u"
      a.markdown.should eq "aone\n"
    end
  end
end
