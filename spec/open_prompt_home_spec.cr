require "./spec_helper"
require "file_utils"

describe "Md::App#open_prompt" do
  it "takes a leading ~ typed out in full for the home directory" do
    home = File.tempname("md-spec-home")
    Dir.mkdir_p home
    File.write File.join(home, "notes.md"), "home notes\n"
    saved = ENV["HOME"]?
    ENV["HOME"] = home
    begin
      with_app do |app|
        app.open_prompt
        answer app, "~/notes.md"
        app.source.path.should eq File.join(home, "notes.md")
        app.markdown.should eq "home notes\n"
      end
      Md::App.typed_path("~").should eq home
      Md::App.typed_path("~user/x.md").should eq "~user/x.md"
      Md::App.typed_path("a/~/b.md").should eq "a/~/b.md"
    ensure
      saved ? (ENV["HOME"] = saved) : ENV.delete("HOME")
      FileUtils.rm_rf home
    end
  end
end
