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
    # A rescan of the text from its start per match (`Regex#match` from a
    # character index, `MatchData#begin`) costs nothing in ASCII text, where
    # the character and byte positions are the same, and many times the
    # whole replace once a character is non-ASCII: so the replace over the
    # accented lines is held to the time of the one over plain lines rather
    # than to a time of its own, which a slow runner would miss either way.
    plain = replace_all_time "Line %d - unicode text with a needle in it."
    accented = replace_all_time "Line %d — ünïcödé text with a needle in it."
    accented.should be < plain * 5
  end
end

# How long Replace's `a` takes over 4000 lines of *line* (its `%d` the line's
# number), the matches checked as replaced.
private def replace_all_time(line : String) : Time::Span
  text = String.build { |io| 4000.times { |i| io << (line % i) << '\n' } }
  with_app Md::Source.new, text: text, view: false do |app, _|
    app.editor.focus
    app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, 0)
    started = Time.instant
    app.replace "needle", "pin", all: true
    elapsed = Time.instant - started
    app.markdown.scan("pin").size.should eq 4000
    app.markdown.includes?("needle").should be_false
    elapsed
  end
end
