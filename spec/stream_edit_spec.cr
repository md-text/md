require "./spec_helper"

# An edit made while the document is still streaming in: the viewer is
# re-rendered from the text as the stream so far, so the lines still to come
# continue it (`App#render_viewer`).

describe "Md::App edit on a streaming document" do
  it "renders the rest of the stream once, continuing the paragraph it was in" do
    reader, writer = IO.pipe
    with_app Md::Source.new(stdin: true), view: true do |app|
      app.stream reader
      writer << "# One\n\npara one\n"
      writer.flush
      settle { app.markdown.includes?("para one") }
      app.show_pane(Md::App::Pane::Editor).focus
      app.editor.cursor_position = 2
      app.editor.insert_text "X"
      writer << "para two\n\n# Three\n\n"
      writer.flush
      settle { app.viewer.document.outline.size == 2 }
      writer.close
      settle { !app.streaming? }
      app.markdown.should eq "# XOne\n\npara one\npara two\n\n# Three\n\n"
      app.viewer.document.blocks.map(&.text).should eq ["XOne", "para one para two", "Three"]
      # The source lines go on from the text, for Sync Cursor.
      app.viewer.document.blocks.map(&.source_line).should eq [1, 3, 6]
    end
  end
end
