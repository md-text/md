require "./spec_helper"

describe Md::Manual do
  it "keeps every text line of the man page within 80 bytes, as mandoc's lint asks" do
    Md::Manual.man.each_line do |line|
      # A request, or a tagged paragraph's tag (a flag and its names), which
      # cannot break.
      next if line.starts_with?('.') || line.starts_with?("\\fB")
      line.bytesize.should be <= 80
    end
  end
end
