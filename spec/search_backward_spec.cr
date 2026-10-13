require "./spec_helper"

# A backward search (`?`, and `N` after `/`) takes the last match starting
# before the caret, as Vim's `?` and Qt's `FindBackward` do: a match the
# caret is inside is found from its start, and stepping back from a match
# selected by the search moves to the one before it each time.
describe "Md::App backward search" do
  it "finds the match the caret is inside, then steps back through adjacent matches and wraps" do
    with_app Md::Source.new, text: "foofoo x foo", view: false do |app, _window|
      app.editor.focus
      editor = app.editor
      editor.text_cursor = Crysterm::TextCursor.new(editor.document, 10) # inside the last "foo"
      app.search("foo", backward: true).should be_true
      {editor.text_cursor.selection_start, editor.text_cursor.selection_end}.should eq({9, 12})
      app.find_next.should be_true
      editor.text_cursor.selection_start.should eq 3
      app.find_next.should be_true
      editor.text_cursor.selection_start.should eq 0
      app.find_next.should be_true # wraps
      editor.text_cursor.selection_start.should eq 9
      notice(app).should contain "Search hit TOP"
      app.find_next(reverse: true).should be_true # forward, past the selection, over the wrap
      editor.text_cursor.selection_start.should eq 0
    end
  end

  it "goes to the match before when the caret is at a match's start" do
    with_app Md::Source.new, text: "foo foo", view: false do |app, _window|
      app.editor.focus
      app.editor.text_cursor = Crysterm::TextCursor.new(app.editor.document, 4)
      app.search("foo", backward: true).should be_true
      app.editor.text_cursor.selection_start.should eq 0
    end
  end
end
