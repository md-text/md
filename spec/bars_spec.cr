require "./spec_helper"

# `F4` and View → Menu and Status Bars: the two bars hidden and shown
# together, the panes taking the whole terminal meanwhile; a prompt shows
# the status bar for as long as it is open; kept across runs.

describe "Md::App menu and status bars" do
  it "hides both bars on F4 and the View entry, and shows them again" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.bars?.should be_true
      entry = menu(app, 3).actions.find!(&.text.==("Menu and Status &Bars"))
      entry.checked?.should be_true
      window.repaint
      app.main.menu_bar.visible?.should be_true
      app.main.status_bar.visible?.should be_true
      top = app.viewer.atop

      press(window, Tput::Key::F4).accepted?.should be_true
      app.bars?.should be_false
      entry.checked?.should be_false
      app.main.menu_bar.visible?.should be_false
      app.main.status_bar.visible?.should be_false
      window.repaint
      app.viewer.atop.should be < top # the pane moved up into the bar's row
      app.viewer.aheight.should eq window.aheight

      entry.trigger
      app.bars?.should be_true
      window.repaint
      app.main.menu_bar.visible?.should be_true
      app.viewer.atop.should eq top
    end
  end

  it "keeps the entries' keys live while the bars are hidden, but not the bar's own" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.bars = false
      window.repaint
      press(window, Tput::Key::AltO).accepted?.should be_false # the viewer takes Alt-F itself
      app.main.menu_bar.menus.any?(&.visible?).should be_false
      press(window, Tput::Key::F10).accepted?.should be_false
      press(window, Tput::Key::CtrlO).accepted?.should be_true # File → Open…'s key
      app.main.status_bar.prompting?.should be_true
      app.main.status_bar.line_prompt.cancel
    end
  end

  it "shows the status bar for a prompt and hides it again after the answer" do
    with_app Md::Source.new(path: "doc.md"), text: "# T\n\ntext\n", view: true do |app, window|
      app.bars = false
      window.repaint
      app.main.status_bar.visible?.should be_false
      app.go_to_line_prompt
      app.main.status_bar.visible?.should be_true
      window.repaint
      question(app).should eq ":"
      answer app, "2"
      app.main.status_bar.visible?.should be_false
      app.editor.text_cursor.block_number.should eq 1

      app.go_to_line_prompt
      app.main.status_bar.visible?.should be_true
      app.open_prompt # a question over a question: the bar stays
      app.main.status_bar.visible?.should be_true
      question(app).should eq "Open: "
      app.main.status_bar.line_prompt.cancel
      app.main.status_bar.visible?.should be_false

      app.bars = true
      app.main.status_bar.visible?.should be_true
    end
  end

  it "keeps the choice across runs" do
    with_config "md:\n  bars: false\n" do |path|
      with_app Md::Source.new(path: "doc.md"), text: "# T\n", view: true, config: true do |app|
        app.bars?.should be_false
        app.main.menu_bar.visible?.should be_false
        Md::Config.dirty?.should be_false
        app.bars = true
        Md::Config.dirty?.should be_true
        app.save_config
      end
      config_file(path)["md"]["bars"].as_bool.should be_true
    end
  end
end
