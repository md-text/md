require "./spec_helper"

# View → Media Backend → None: Crysterm's `media.backend: none`, which draws
# no images and fetches none; a titled image shows its title where its
# picture would be.
describe "Md::App media backend None" do
  it "offers None after Auto, with a tooltip saying what it does, and draws no pictures under it" do
    text = "# Title\n\n![Peak](matterhorn.png \"The Matterhorn\")\n\nAfter\n"
    with_app Md::Source.new(path: "#{__DIR__}/../matterhorn.md"), text: text, view: true do |app, window|
      entries = menu(app, 3).actions.find!(&.text.==("Media &Backend")).menu.should_not(be_nil).reject(&.separator?)
      none = entries.find!(&.text.==("Non&e"))
      entries.index!(none).should eq entries.index!(&.text.starts_with?("&Auto")) + 1
      none.enabled?.should be_true
      none.tool_tip.should eq "Draw no images and fetch none: an image shows its title, if it has one, in the picture's place"
      none.trigger
      app.media_backend.should eq Crysterm::Widget::Media::Backend::None
      Crysterm::Config.media_backend.should eq Crysterm::Widget::Media::Backend::None
      Crysterm::Widget::Media.disabled?.should be_true
      window.repaint
      app.viewer.block_media.should be_empty
    end
  ensure
    Crysterm::Config.reset "media.backend"
  end

  it "keeps None with the settings and reads it back" do
    with_config %(media:\n  backend: none\n) do |path|
      with_app config: true do |app|
        app.media_backend.should eq Crysterm::Widget::Media::Backend::None
        app.media_backend = Crysterm::Widget::Media::Backend::Ansi
        app.media_backend = Crysterm::Widget::Media::Backend::None
        app.save_config
      end
      config_file(path)["media"]["backend"].as_s.should eq "None"
      with_app config: true do |app|
        app.media_backend.should eq Crysterm::Widget::Media::Backend::None
      end
    end
  ensure
    Crysterm::Config.reset "media.backend"
  end
end
