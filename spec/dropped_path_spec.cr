require "./spec_helper"
require "file_utils"

describe "Md::App#open_dropped" do
  it "opens a file with a quote in its name dropped on a VTE terminal, which single-quotes it" do
    dir = File.tempname("md-spec-drop")
    Dir.mkdir_p dir
    path = File.join(dir, "it's here.md")
    File.write path, "# Quoted\n"
    begin
      with_app do |app|
        app.open_dropped("'#{path.gsub("'", "'\\''")}' ").should be_true
        app.source.path.should eq path
      end
    ensure
      FileUtils.rm_rf dir
    end
  end
end
