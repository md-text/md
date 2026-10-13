require "./spec_helper"

# The replace question's `l` (last), as Vim's `:s///c` has it: replace this
# match, then stop.
describe "Md::App replace, l" do
  it "replaces the match asked about and stops" do
    with_app Md::Source.new(path: "doc.md"), text: "one needle, two needle, three needle", view: false do |app, _|
      app.editor.focus
      app.replace "needle", "pin"
      question(app).should eq "Replace? (y)es (n)o (a)ll (q)uit (l)ast "
      answer app, 'n'
      answer app, 'l'
      app.main.status_bar.prompting?.should be_false
      app.markdown.should eq "one needle, two pin, three needle"
      notice(app).should contain "1 replacement"
      app.replace_count.should eq 0 # the session is over
      app.editor.selection?.should be_false
      app.editor.cursor_position.should eq "one needle, two pin".size
      app.editor.document.undo
      app.markdown.should eq "one needle, two needle, three needle"
    end
  end
end
