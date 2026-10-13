require "./spec_helper"

# The walk over a search's matches (`App#each_match`): by byte offset, the
# character positions counted on, so text with non-ASCII characters is
# walked in one pass rather than rescanned from its start at every match.

describe "Md::App match walk" do
  it "places the underlines and replacements right after wide and multi-byte characters" do
    text = "# Ŝearch\n\nÜber 😀 needle — 日本語 needle, ñ needle.\n"
    with_app Md::Source.new, text: text, view: false do |app, _|
      app.editor.focus
      app.search("needle").should be_true
      starts = app.editor.extra_selections.map(&.cursor.selection_start)
      starts.should eq [text.index!("needle"), text.index!("needle", 25), text.rindex!("needle")]
      app.editor.extra_selections.each(&.cursor.selected_text.should(eq "needle"))
      app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, 0)
      app.replace "(n)eedle", "\\1ail", all: true
      app.markdown.should eq "# Ŝearch\n\nÜber 😀 nail — 日本語 nail, ñ nail.\n"
      app.replace_count.should eq 0 # the replace is over
      notice(app).should contain "3 replacements"
    end
  end

  it "replaces thousands of matches in a long non-ASCII text without a rescan per match" do
    text = String.build { |io| 4000.times { |i| io << "Line #{i} — ünïcödé text with a needle in it.\n" } }
    with_app Md::Source.new, text: text, view: false do |app, _|
      app.editor.focus
      app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, 0)
      started = Time.instant
      app.replace "needle", "pin", all: true
      # A rescan of the text from its start per match (`Regex#match` from a
      # character index, `MatchData#begin`) takes many seconds here.
      (Time.instant - started).should be < 3.seconds
      app.markdown.scan("pin").size.should eq 4000
      app.markdown.includes?("needle").should be_false
    end
  end
end
