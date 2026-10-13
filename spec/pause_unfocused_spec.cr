require "./spec_helper"

# View → Pause When Unfocused: Crysterm's `render.pause_when_unfocused`,
# off by default in md (`Md::Config.apply_defaults`).

private def entry(app)
  menu(app, 3).actions.find!(&.text.==("&Pause When Unfocused"))
end

describe "Md::App View → Pause When Unfocused" do
  it "is off by default in md, and puts a change on the window" do
    with_config do
      with_app config: true do |app, window|
        app.pause_when_unfocused?.should be_false
        window.pause_when_unfocused?.should be_false
        entry(app).name.should eq "pause-when-unfocused"
        entry(app).checked?.should be_false
        entry(app).trigger
        app.pause_when_unfocused?.should be_true
        window.pause_when_unfocused?.should be_true
        Crysterm::Config.render_pause_when_unfocused.should be_true
        app.pause_when_unfocused = false
        window.pause_when_unfocused?.should be_false
      end
    end
  end

  it "takes the config file's choice" do
    with_config("render:\n  pause_when_unfocused: true\n") do
      with_app config: true do |app, window|
        app.pause_when_unfocused?.should be_true
        window.pause_when_unfocused?.should be_true
        entry(app).checked?.should be_true
      end
    end
  end
end
