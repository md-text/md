require "./spec_helper"

# CommonMark's HTML blocks (§4.6) to Format → Rewrap, Format → Hard Wrap
# and `Enter`: raw HTML, its lines left as they are, a paragraph ending
# where one of kinds 1–6 starts (`App.code_lines`).

# Puts the editor's caret at *column* of *line*, both 0-based.
# *text* after Format → Rewrap → Document to *width* columns.
private def rewrapped(text, width = 20)
  result = ""
  with_app text: text, view: false do |app|
    app.text_width = width
    app.rewrap_document
    result = app.markdown
  end
  result
end

# One HTML block of each kind, each after a paragraph's line it must not
# join (kind 7 after a blank line, since it cannot interrupt one), with a
# line inside that a refill would change.
HTML_BLOCKS = {
  "<pre>"         => "aaaa\n<pre>\n  x    y   z    w    v    u\n\nlong line of words here\n</pre>\n",
  "<script>"      => "aaaa\n<SCRIPT type=\"x\">\nvar a = 1;   var b = 2; var c = 3;\n\n- x\n</script> tail\n",
  "<style>"       => "aaaa\n<style>\np { color: red }   q { color: blue }\n</style>\n",
  "<textarea>"    => "aaaa\n<textarea>\n\n  aaaa bbbb cccc dddd eeee\n</textarea>\n",
  "comment"       => "aaaa\n<!-- aaaa bbbb cccc dddd eeee\n\nffff gggg hhhh iiii jjjj -->\n",
  "instruction"   => "aaaa\n<?php echo 1; echo 2; echo 3; echo 4;\n\n?>\n",
  "declaration"   => "aaaa\n<!DOCTYPE html aaaa bbbb cccc dddd eeee\n\nffff gggg hhhh iiii >\n",
  "CDATA"         => "aaaa\n<![CDATA[ aaaa bbbb cccc dddd eeee\n\nffff gggg hhhh ]]>\n",
  "block tag"     => "aaaa\n<div class=\"x\">\naaaa bbbb cccc dddd eeee ffff\n</div>\n",
  "closing block" => "aaaa\n</details>\naaaa bbbb cccc dddd eeee ffff\n",
  "complete tag"  => "aaaa\n\n<my-tag a=\"1\">\naaaa bbbb cccc dddd eeee ffff\n</my-tag>\n",
}

describe "Md::App editing, HTML blocks" do
  HTML_BLOCKS.each do |kind, text|
    it "leaves an HTML block (#{kind}) byte for byte as it is, the paragraph above it apart" do
      rewrapped(text).should eq text
      rewrapped(text, 80).should eq text
    end
  end

  it "ends a paragraph where an HTML block of kinds 1 to 6 starts, not where a complete tag (kind 7) is" do
    rewrapped("aaaa\n<div>\nbbbb\n").should eq "aaaa\n<div>\nbbbb\n"
    rewrapped("aaaa\n<span>\nbbbb\n").should eq "aaaa <span> bbbb\n"
    # A block of kinds 1 to 5 ends on the line its end condition is met.
    rewrapped("<!-- x -->\naaaa\nbbbb\n").should eq "<!-- x -->\naaaa bbbb\n"
    rewrapped("<?>\naaaa\nbbbb\n").should eq "<?>\naaaa bbbb\n"
    # A block of kinds 6 and 7 at a blank line.
    rewrapped("<div>\naaaa\n\nbbbb\ncccc\n").should eq "<div>\naaaa\n\nbbbb cccc\n"
    # A lowercase `<!doctype>` is text to cmark-gfm and markd (CommonMark
    # 0.29); four columns in, a tag is an indented code block's.
    rewrapped("aaaa\n<!doctype html>\n").should eq "aaaa <!doctype html>\n"
    rewrapped("aaaa\n\n    <div>  x\n").should eq "aaaa\n\n    <div>  x\n"
  end

  it "ends an HTML block in a quote or a list item with the quote or the item" do
    rewrapped("> <div>\naaaa\nbbbb\n").should eq "> <div>\naaaa bbbb\n"
    rewrapped("- aaaa\n\n  <div>\n  x  y\ncccc\ndddd\n").should eq "- aaaa\n\n  <div>\n  x  y\ncccc dddd\n"
    rewrapped("> <pre>\n> x  y\n>\n> z  w\n> </pre>\n> aaaa\n> bbbb\n").should eq "> <pre>\n> x  y\n>\n> z  w\n> </pre>\n> aaaa bbbb\n"
  end

  it "does not break a line typed in a <pre> block" do
    with_app text: "<pre>\naaaa bbbb cccc ddd\n</pre>\n", view: false do |app, window|
      app.hard_wrap = true
      app.text_width = 20
      place app, 1, 18
      " eeee ffff".each_char { |char| press window, char }
      app.markdown.should eq "<pre>\naaaa bbbb cccc ddd eeee ffff\n</pre>\n"
    end
  end

  it "does not continue a list on Enter in an HTML block" do
    with_app text: "<pre>\n- foo\n</pre>\n<div>\n1. bar\n", view: false do |app, window|
      place app, 1, 5
      press(window, Tput::Key::Enter)
      app.markdown.should eq "<pre>\n- foo\n\n</pre>\n<div>\n1. bar\n"
      place app, 5, 6
      press(window, Tput::Key::Enter)
      app.markdown.should eq "<pre>\n- foo\n\n</pre>\n<div>\n1. bar\n\n"
    end
  end
end
