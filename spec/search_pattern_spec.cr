require "./spec_helper"

# The search pattern's rules (`App#compile_pattern`): line anchors and
# smartcase, as vi has them.

PATTERN_DOC = <<-MD
  # Alpha

  ## Beta

  Some text, and a word.
  MD

describe "Md::App search pattern" do
  it "anchors ^ and $ at every line, not only at the ends of the text" do
    with_app Md::Source.new, text: PATTERN_DOC, view: false do |app, _|
      app.editor.focus
      app.search("^## ").should be_true
      app.editor.selected_text.should eq "## "
      app.editor.text_cursor.block_number.should eq 2
      app.editor.extra_selections.size.should eq 1
      app.search("a$").should be_true
      app.editor.text_cursor.block_number.should eq 2 # "## Beta", after the caret
      app.editor.extra_selections.size.should eq 2    # and "# Alpha"
    end
  end
end
