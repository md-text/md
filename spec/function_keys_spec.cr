require "./spec_helper"

# The pane keys and F4 from the bytes a terminal sends: SS3 (`\eOP`…, xterm
# and Terminal.app), rxvt's `\e[11~`…, and the kitty keyboard protocol's
# `\e[P`, `\e[Q`, `\e[13~`, `\e[S` (kitty, Ghostty, iTerm2, WezTerm), which
# Crysterm turns on where the terminal has it — under which F1, F2 and F4
# reached md as nothing and only F3 worked.

# Feeds *bytes* through tput's parser into the window, as the terminal's
# input would come.
private def type_bytes(window, bytes : String) : Nil
  tput = Tput.new input: IO::Memory.new(bytes), output: IO::Memory.new,
    screen_size: Tput::DEFAULT_SCREEN_SIZE, probe: false
  tput.listen { |e| window.handle_input e }
end

FUNCTION_KEY_ENCODINGS = {
  "SS3"   => {"\eOP", "\eOQ", "\eOR", "\eOS"},
  "rxvt"  => {"\e[11~", "\e[12~", "\e[13~", "\e[14~"},
  "kitty" => {"\e[P", "\e[Q", "\e[13~", "\e[S"},
}

describe "Md::App function keys from the terminal's bytes" do
  FUNCTION_KEY_ENCODINGS.each do |name, (f1, f2, f3, f4)|
    it "shows, focuses and hides the panes and the bars (#{name})" do
      with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
        window.repaint
        type_bytes window, f1
        app.editor.visible?.should be_true
        app.editor.focused?.should be_true
        type_bytes window, f1
        app.editor.visible?.should be_false

        type_bytes window, f3
        app.toc.visible?.should be_true
        app.toc.focused?.should be_true
        type_bytes window, f3
        app.toc.visible?.should be_false

        type_bytes window, f2
        app.viewer.focused?.should be_true

        app.bars?.should be_true
        type_bytes window, f4
        app.bars?.should be_false
        type_bytes window, f4
        app.bars?.should be_true
      end
    end
  end
end
