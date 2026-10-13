require "./spec_helper"

# Crysterm's default quit keys (`q`, `Ctrl-Q`) quit every window when no one
# takes them, and md keeps `q` live past a grab for the viewer
# (`always_propagated_chars`): at a question md takes them itself, so a key
# meant for the question quits nothing over it (`App#key_pressed`).
describe "Md::App quit keys at a question" do
  it "takes q and Ctrl-Q while a modal dialog is up" do
    with_app Md::Source.new, text: "# Doc\n" do |app, window|
      app.dialog_style = Md::App::DialogStyle::Modal
      app.run_command "clear-caches"
      app.asking?.should be_true
      press(window, 'q').accepted?.should be_true
      press(window, Tput::Key::CtrlQ).accepted?.should be_true
      window.destroyed?.should be_false
      app.asking?.should be_true
    end
  end

  it "takes q while a question is up in place of the status bar" do
    with_app Md::Source.new, text: "# Doc\n" do |app, window|
      app.dialog_style = Md::App::DialogStyle::LinePrompt
      app.save_as_prompt
      app.asking?.should be_true
      press(window, 'q').accepted?.should be_true
      window.destroyed?.should be_false
    end
  end
end
