require "./spec_helper"

# Where an interactive Replace started — where its wrap-around stops — moves
# with the text, edits made in another window on the document included.

ORIGIN_DOC = "foo 1\nfoo 2\nfoo 3\n"

describe "Md::App replace origin" do
  it "stops where it began after the other window inserts text before it" do
    with_two_windows(text: ORIGIN_DOC, view: false) do |a, b|
      a.editor.focus
      a.editor.cursor_position = 6 # the start of "foo 2"
      a.replace "foo", "bar"
      a.editor.selected_text.should eq "foo"
      a.editor.text_cursor.selection_start.should eq 6
      # The other window puts a line at the top while the question is up:
      # the first "foo" is now past where the replace began, as it was.
      b.editor.cursor_position = 0
      b.editor.insert_text "inserted\n"
      a.markdown.should eq "inserted\n" + ORIGIN_DOC
      answer a, 'a'
      a.main.status_bar.prompting?.should be_false
      notice(a).should contain "3 replacements"
      a.markdown.should eq "inserted\nbar 1\nbar 2\nbar 3\n"
    end
  end

  it "stops right after replacing the match it began at" do
    with_two_windows(text: ORIGIN_DOC, view: false) do |a, _|
      a.editor.focus
      a.editor.cursor_position = 6 # the start of "foo 2"
      a.replace "foo", "xfoo"
      a.editor.text_cursor.selection_start.should eq 6
      answer a, 'y' # "foo 2", where it began: the new text is past the start
      answer a, 'y' # "foo 3"
      notice(a).should contain "Search hit BOTTOM, continuing at TOP"
      answer a, 'y' # "foo 1"; the next one is "xfoo 2", where it began
      a.main.status_bar.prompting?.should be_false
      notice(a).should contain "3 replacements"
      a.markdown.should eq "xfoo 1\nxfoo 2\nxfoo 3\n"
    end
  end
end
