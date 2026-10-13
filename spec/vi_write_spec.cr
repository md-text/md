require "./spec_helper"

# Vi Mode's `:w FILE` naming the document's own file (`App#vi_write`).

private def vi_keys(window, keys : String)
  keys.scan(/<[^>]+>|./m) do |match|
    case match[0]
    when "<Esc>" then press window, Tput::Key::Escape
    when "<CR>"  then press window, Tput::Key::Enter
    else              press window, match[0][0]
    end
  end
end

describe "Md::App Vi Mode :w FILE" do
  unless Crysterm::Neovim.available?
    pending "needs nvim in PATH"
    next
  end

  it "saves on :w! naming the document's own file, as Vim does, rather than writing a copy over it" do
    path = tempfile("# Title\n")
    with_app Md::Source.new(path: path), text: File.read(path), view: false do |app, window|
      app.vi_mode = true
      vi_keys window, "Gonew<Esc>:w! #{path}<CR>"
      settle { File.read(path) == "# Title\nnew\n" }
      File.read(path).should eq "# Title\nnew\n"
      settle { !app.editor.document.modified? }
      app.editor.document.modified?.should be_false
      app.source.path.should eq path
    end
  ensure
    if path
      File.delete? path
      File.delete? "#{path}~"
    end
  end
end
