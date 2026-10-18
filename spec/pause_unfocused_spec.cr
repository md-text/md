require "./spec_helper"

# View → Pause When Unfocused: Crysterm's `render.pause_when_unfocused`,
# with Crysterm's default, on; the window's animations hold while its
# terminal window is unfocused, and everything else paints as it comes.

private def entry(app)
  menu(app, 4).actions.find!(&.text.==("&Pause When Unfocused"))
end

describe "Md::App View → Pause When Unfocused" do
  it "is on by default, as in Crysterm, and puts a change on the window" do
    with_config do
      with_app config: true do |app, window|
        app.pause_when_unfocused?.should be_true
        window.pause_when_unfocused?.should be_true
        entry(app).name.should eq "pause-when-unfocused"
        entry(app).checked?.should be_true
        entry(app).trigger
        app.pause_when_unfocused?.should be_false
        window.pause_when_unfocused?.should be_false
        Crysterm::Config.render_pause_when_unfocused.should be_false
        app.pause_when_unfocused = true
        window.pause_when_unfocused?.should be_true
      end
    end
  end

  it "takes the config file's choice" do
    with_config("render:\n  pause_when_unfocused: false\n") do
      with_app config: true do |app, window|
        app.pause_when_unfocused?.should be_false
        window.pause_when_unfocused?.should be_false
        entry(app).checked?.should be_false
      end
    end
  end

  it "holds no edit from another window while unfocused" do
    with_two_windows do |a, b|
      b.window.pause_when_unfocused?.should be_true
      b.window.dispatch_mouse Tput::Mouse::Event.blur
      b.window.animations_paused?.should be_true
      a.editor.text_cursor.insert_text "typed "
      settle { b.editor.to_plain_text.starts_with? "typed " }
      b.window.dispatch_mouse Tput::Mouse::Event.focus
      b.window.animations_paused?.should be_false
    end
  end
end
