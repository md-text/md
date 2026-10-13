require "./spec_helper"
require "file_utils"

describe "Md::App#save_as_prompt" do
  it "takes a leading ~ typed out in full for the home directory" do
    home = File.tempname("md-spec-home")
    Dir.mkdir_p home
    saved = ENV["HOME"]?
    ENV["HOME"] = home
    begin
      with_app Md::Source.new, text: "home notes\n" do |app|
        app.save_as_prompt
        answer app, "~/notes.md"
        app.source.path.should eq File.join(home, "notes.md")
        File.read(File.join(home, "notes.md")).should eq "home notes\n"
        Dir.exists?("~").should be_false
      end
    ensure
      saved ? (ENV["HOME"] = saved) : ENV.delete("HOME")
      FileUtils.rm_rf home
    end
  end
end
