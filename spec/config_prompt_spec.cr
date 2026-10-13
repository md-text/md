require "./spec_helper"

describe "Options → Save Config As… and Load Config…" do
  it "take a leading ~ as the home directory" do
    home = File.tempname("md-spec-home")
    Dir.mkdir_p home
    previous = ENV["HOME"]?
    ENV["HOME"] = home
    begin
      with_config do
        with_app config: true do |app|
          app.save_config_prompt
          answer app, "~/saved.yml"
          saved = File.join(home, "saved.yml")
          notice(app).should eq " Saved #{saved}"
          File.exists?(saved).should be_true
          Dir.exists?("~").should be_false

          app.load_config_prompt
          answer app, "~/saved.yml"
          notice(app).should eq " Loaded #{saved}"
        end
      end
    ensure
      previous ? (ENV["HOME"] = previous) : ENV.delete("HOME")
      FileUtils.rm_rf home
    end
  end
end
