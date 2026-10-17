require "./spec_helper"
require "file_utils"

# View → Images: the viewer draws a block image as a picture through
# Crysterm's `TextEdit#images_enabled`, its relative source resolved against
# the document's directory (the viewer document's `base_url`).

private PICTURE = "#{__DIR__}/../lib/crysterm/data/image/matterhorn.png" # 240 × 84 pixels

private IMAGE_DOC = "# Pictures\n\n![Matterhorn](matterhorn.png)\n\nAfter the picture.\n"

# A directory holding the document beside its picture, and a second document
# in a subdirectory; yields the directory and the two documents' paths.
private def with_picture_docs(&)
  dir = File.tempname("md-spec-images")
  Dir.mkdir_p File.join(dir, "docs")
  doc = File.join(dir, "doc.md")
  other = File.join(dir, "docs", "other.md")
  File.write doc, IMAGE_DOC
  File.write other, "# Other\n\nNo picture here.\n"
  FileUtils.cp PICTURE, File.join(dir, "matterhorn.png")
  yield dir, doc, other
ensure
  FileUtils.rm_rf dir if dir
end

# The View menu's Images entry.
private def images_entry(app) : Crysterm::Action
  menu(app, 4).actions.find!(&.text.==("&Images"))
end

describe "Md::App images" do
  it "draws a block image in the viewer, its source counted from the document's directory" do
    with_picture_docs do |dir, doc, _other|
      with_app Md::Source.new(path: doc), text: IMAGE_DOC, view: true do |app, window|
        app.images?.should be_true
        app.viewer.images_enabled?.should be_true
        app.viewer.document.base_url.should eq dir
        window.repaint
        media = app.viewer.block_media
        media.size.should eq 1
        media[0].file.should eq File.join(dir, "matterhorn.png")
        media[0].aheight.should be > 0
        media[0].aheight.should be <= 14 # at most half of the pane's rows
      end
    end
  end

  it "offers View → Images right before Media Backend, checked, and the entry turns the pictures off and on" do
    with_picture_docs do |_dir, doc, _other|
      with_app Md::Source.new(path: doc), text: IMAGE_DOC, view: true do |app, window|
        texts = menu(app, 4).actions.map(&.text)
        texts.index!("&Images").should eq texts.index!("Media &Backend") - 1
        entry = images_entry(app)
        entry.checkable?.should be_true
        entry.checked?.should be_true
        window.repaint
        app.viewer.block_media.size.should eq 1

        entry.trigger
        app.images?.should be_false
        app.viewer.images_enabled?.should be_false
        window.repaint
        app.viewer.block_media.should be_empty

        app.images = true
        entry.checked?.should be_true
        app.viewer.images_enabled?.should be_true
        window.repaint
        app.viewer.block_media.size.should eq 1
      end
    end
  end

  it "starts with the pictures off under a configured md.images: false" do
    with_config "md:\n  images: false\n" do
      with_picture_docs do |_dir, doc, _other|
        with_app Md::Source.new(path: doc), text: IMAGE_DOC, view: true, config: true do |app, window|
          app.images?.should be_false
          images_entry(app).checked?.should be_false
          app.viewer.images_enabled?.should be_false
          window.repaint
          app.viewer.block_media.should be_empty
        end
      end
    end
  end

  it "moves the base URL with the document's file: opened, saved as, or without one" do
    with_picture_docs do |dir, doc, other|
      with_app Md::Source.new(path: doc), text: IMAGE_DOC, view: true do |app|
        app.viewer.document.base_url.should eq dir
        app.open_file other
        app.viewer.document.base_url.should eq File.join(dir, "docs")
        app.previous_file
        app.viewer.document.base_url.should eq dir
        app.save_as File.join(dir, "docs", "copy.md")
        app.viewer.document.base_url.should eq File.join(dir, "docs")
      end
    end
    with_app do |app|
      app.viewer.document.base_url.should eq Dir.current # a new document: the working directory
    end
  end
end
