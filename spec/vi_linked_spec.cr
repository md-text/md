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
