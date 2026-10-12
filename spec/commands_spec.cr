require "./spec_helper"

COMMANDS_DOC = <<-MD
  # Alpha

  First line.

  ## Beta

  Second line.
  MD

describe "Md::App commands" do
  it "names every command once, menu entries and keys alike" do
    with_app Md::Source.new(path: "doc.md"), text: COMMANDS_DOC, view: true do |app, _window|
      names = app.window.find_actions.compact_map(&.name)
      names.should eq names.uniq
      %w[open save save-as quit find find-backward find-next command go-to-line bold rewrap-paragraph
        editor viewer toc toggle-editor toggle-bars cycle-theme suspend resize-panes soft-wrap
        text-width-off text-width-80 mouse-all theme-breeze-dark new-window manual about].each do |name|
        app.command_names.should contain name
      end
    end
  end

  it "runs a command by name, or says why not" do
    with_app Md::Source.new(path: "doc.md"), text: COMMANDS_DOC, view: true do |app, _window|
      wrap = app.soft_wrap?
      app.run_command("soft-wrap").should be_true
      app.soft_wrap?.should eq !wrap
      app.run_command("theme-breeze-dark").should be_true
      app.theme.should eq Md::App::Theme::BreezeDark
      app.run_command("no-such").should be_false
      notice(app).should contain "No such command: no-such"
    end
  end

  it "takes a command or a line number at the viewer's :, completing names with Tab" do
    with_app Md::Source.new(path: "doc.md"), text: COMMANDS_DOC, view: true do |app, window|
      press window, ':'
      field = app.main.status_bar.line_prompt.field
      field.value = "soft-w"
      field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Tab)
      field.value.should eq "soft-wrap"
      wrap = app.soft_wrap?
      answer app, "soft-wrap"
      app.soft_wrap?.should eq !wrap
      press window, ':'
      answer app, "5"
      app.viewer.document.plain_text[app.viewer.cursor_position, 4].should eq "Beta"
    end
  end

  it "opens the command line from the editor with Alt-K" do
    with_app Md::Source.new(path: "doc.md"), text: COMMANDS_DOC, view: false do |app, window|
      app.editor.focus
      press window, Tput::Key::AltK
      question(app).should eq ":"
      answer app, "toggle-toc"
      app.visible_panes.should contain Md::App::Pane::Toc
    end
  end
end
