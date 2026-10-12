require "./spec_helper"

# The numeric keypad's Enter does what Return does, and its digits type:
# tput delivers an application-keypad key (`\eOM`, `\eOp`…) or kitty's
# `KP_*` code as the key it stands for (`Tput::KeyEvent#main_key`).

# Presses the keypad key whose application-keypad sequence ends in *final*,
# the way `Tput::Input#listen` delivers it.
private def press_keypad(window, final : Char) : Crysterm::Event::KeyPress
  ke = Tput::KeyEvent.from_ss3_keypad(final).not_nil!
  e = Crysterm::Event::KeyPress.new (ke.char || '\e'), ke.to_legacy_key, ['\e', 'O', final], ke
  window.emit Crysterm::Event::KeyPress, e
  e
end

describe "Md::App keypad" do
  it "Enter continues a list in the editor, as Return does, and the digits type" do
    with_app Md::Source.new, text: "- item", view: false do |app, window|
      app.editor.focus
      app.editor.cursor_position = "- item".size
      press_keypad(window, 'M').accepted?.should be_true
      press_keypad(window, 'u').accepted?.should be_true # 5
      app.editor.document.plain_text.should eq "- item\n- 5"
    end
  end

  it "Enter reads on in the viewer, as Return does" do
    long = (1..60).map { |i| "Paragraph #{i}" }.join("\n\n") + "\n"
    with_app Md::Source.new, text: long do |app, window|
      app.viewer.focus
      window.repaint
      press(window, Tput::Key::Enter)
      returned = {app.viewer.cursor_position, app.viewer.scroll_position}
      returned.should_not eq({0, 0})
      app.viewer.cursor_position = 0
      app.viewer.scroll_to 0
      window.repaint
      press_keypad(window, 'M').accepted?.should be_true
      {app.viewer.cursor_position, app.viewer.scroll_position}.should eq returned
    end
  end
end
