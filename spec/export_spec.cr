require "./spec_helper"

# `md --export`'s rendering (`Md::Export.render`) of what the viewer draws
# but the document's text does not hold, and of an empty document.
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
end
