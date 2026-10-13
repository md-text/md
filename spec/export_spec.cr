require "./spec_helper"

# `md --export`'s rendering (`Md::Export.render`) of what the viewer draws
# but the document's text does not hold, of quotes and alerts, and of an
# empty document.
describe Md::Export do
  it "draws a horizontal rule in text as a line of the rule glyph" do
    rule = "─" * Md::Export::RULE_WIDTH
    Md::Export.render("above\n\n---\n\nbelow\n", "text").should eq "above\n\n#{rule}\n\nbelow\n"
  end

  it "renders an empty document as nothing" do
    {"html", "text"}.each do |format|
      Md::Export.render("", format).should eq ""
      Md::Export.render("\n\n", format).should eq ""
    end
  end

  it "keeps an empty heading" do
    Md::Export.render("#\n", "html").should eq "<h1></h1>\n"
  end

  it "starts a GFM alert's lines in text with the title chip the viewer paints" do
    note = Crysterm::TextBlockFormat::AlertKind::Note.marker
    Md::Export.render("> [!NOTE]\n> a\n>\n> b\n", "text").should eq "  #{note}a\n  #{note}\n  #{note}b\n"
  end

  it "writes a GFM alert in html as GitHub does" do
    Md::Export.render("> [!TIP]\n> a\n", "html").should eq \
      %(<div class="markdown-alert markdown-alert-tip"><p class="markdown-alert-title">Tip</p><p>a</p></div>\n)
  end

  it "writes two quotes a blank line apart in html as two blockquotes" do
    Md::Export.render("> a\n\n> b\n", "html").should eq "<blockquote><p>a</p></blockquote><blockquote>\n<p>b</p></blockquote>\n"
  end
end
