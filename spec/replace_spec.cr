require "./spec_helper"

# A key typed into the prompt, as the replace question is answered.
private def key(app, char : Char)
  answer app, char
end

REPLACE_DOC = <<-MD
  # Alpha

  The needle is here, and a Needle there.

  ## Beta

  No match in this paragraph.

  ## Gamma

  A last needle.
  MD

describe "Md::App replace" do
  it "asks at each match, and y replaces, n skips and q stops" do
    with_app Md::Source.new(path: "doc.md"), text: REPLACE_DOC, view: false do |app, _|
      app.editor.focus
      app.replace "needle", "pin"
      app.main.status_bar.prompting?.should be_true
      question(app).should start_with "Replace? (y)es (n)o (a)ll (q)uit"
      app.editor.selected_text.should eq "needle"
      app.editor.extra_selections.size.should eq 3 # the search's underlines
      key app, 'y'
      app.markdown.should contain "The pin is here, and a Needle there."
      app.editor.selected_text.should eq "Needle" # smartcase: a lowercase pattern ignores case
      app.replace_count.should eq 1
      key app, 'n'
      app.editor.selected_text.should eq "needle"
      app.editor.text_cursor.block_number.should eq 10
      key app, 'q'
      app.main.status_bar.prompting?.should be_false
      app.editor.focused?.should be_true
      notice(app).should contain "1 replacement"
      app.markdown.should contain "A last needle."
      app.search_pattern.should eq "needle" # `n` picks the search up
      app.editor.document.undo
      app.markdown.should eq REPLACE_DOC
    end
  end

  it "replaces every match on a, in one undo step, wrapping around to where it started" do
    with_app Md::Source.new(path: "doc.md"), text: REPLACE_DOC, view: false do |app, _|
      app.editor.focus
      app.go_to_line 11 # the Gamma paragraph
      app.replace "needle", "pin"
      app.editor.selected_text.should eq "needle"
      app.editor.text_cursor.block_number.should eq 10
      key app, 'y'
      notice(app).should contain "Search hit BOTTOM, continuing at TOP"
      app.editor.text_cursor.block_number.should eq 2
      key app, 'a'
      app.main.status_bar.prompting?.should be_false
      notice(app).should contain "3 replacements"
      app.markdown.should eq REPLACE_DOC.gsub(/needle/i, "pin")
      app.markdown.should_not contain "pinpin"
      # The caret is left after the last replacement, the Needle of line 3.
      app.editor.selection?.should be_false
      app.editor.cursor_position.should eq app.markdown.index!("pin there") + 3
      app.editor.document.undo # the `a` as a whole
      app.markdown.should eq REPLACE_DOC.sub("last needle", "last pin")
      app.editor.document.undo # the `y`
      app.markdown.should eq REPLACE_DOC

      app.replace "needle", "pin", all: true
      app.main.status_bar.prompting?.should be_false
      notice(app).should contain "3 replacements"
      app.editor.document.undo
      app.markdown.should eq REPLACE_DOC
    end
  end

  it "takes a regular expression, with group references in the replacement" do
    with_app Md::Source.new, text: "one two\n", view: false do |app, _|
      app.editor.focus
      app.replace "(\\w+) (\\w+)", "\\2 \\1 [\\0] \\\\ \\x \\3"
      key app, 'y'
      app.markdown.should eq "two one [one two] \\ \\x \n"
      notice(app).should contain "1 replacement"
      app.replace "z*", "y" # an empty match is no match
      app.main.status_bar.prompting?.should be_false
      notice(app).should contain "Pattern not found: z*"
      app.markdown.should eq "two one [one two] \\ \\x \n"
    end
  end

  it "ignores case unless the pattern has an uppercase letter" do
    with_app Md::Source.new(path: "doc.md"), text: REPLACE_DOC, view: false do |app, _|
      app.editor.focus
      app.replace "Needle", "pin", all: true
      notice(app).should contain "1 replacement"
      app.markdown.should eq REPLACE_DOC.sub("Needle", "pin")
      app.replace "NEEDLE", "pin", all: true
      notice(app).should contain "Pattern not found: NEEDLE"
      app.replace "needle", "pin", all: true
      notice(app).should contain "2 replacements"
      app.markdown.should eq REPLACE_DOC.gsub(/needle/i, "pin")
    end
  end

  it "shows and focuses the editor when started from the viewer, with the prompts chained on Alt-H" do
    with_app Md::Source.new(path: "doc.md"), text: REPLACE_DOC, view: true do |app, window|
      app.visible_panes.should eq [Md::App::Pane::Viewer]
      app.search "gamma" # the default pattern
      press window, Tput::Key::AltH
      question(app).should eq "Replace: "
      app.main.status_bar.line_prompt.field.value.should eq "gamma"
      answer app, "needle"
      question(app).should eq "With: "
      answer app, "pin"
      app.editor.visible?.should be_true
      app.editor.selected_text.should eq "needle"
      key app, 'y'
      key app, 'q'
      app.editor.focused?.should be_true
      app.markdown.should contain "The pin is here"
      app.viewer.document.plain_text.should contain "The pin is here" # re-rendered
    end
  end

  it "cancels at any prompt, leaving the text alone" do
    with_app Md::Source.new(path: "doc.md"), text: REPLACE_DOC, view: false do |app, window|
      app.editor.focus
      press window, Tput::Key::AltH
      app.main.status_bar.line_prompt.cancel
      app.main.status_bar.prompting?.should be_false
      press window, Tput::Key::AltH
      answer app, "needle"
      app.main.status_bar.line_prompt.cancel
      app.main.status_bar.prompting?.should be_false
      app.replace "needle", "pin"
      key app, 'y'
      app.main.status_bar.line_prompt.cancel # Escape at the question
      app.main.status_bar.prompting?.should be_false
      notice(app).should contain "1 replacement"
      app.replace "needle", "pin"
      app.main.status_bar.line_prompt.cancel
      notice(app).should contain "0 replacements"
      app.markdown.should eq REPLACE_DOC.sub("needle", "pin")
    end
  end
end
