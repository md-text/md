require "crysterm"

module Md
  # `--export`: the document rendered to standard output, no terminal
  # involved — md as a filter. The Markdown goes through the same import the
  # viewer renders with (`TextDocument#set_markdown`), so the output is what
  # the viewer shows: Crysterm's HTML export (`TextDocument#to_html`, a body
  # fragment, as pandoc without `--standalone` prints) or the plain text
  # (`TextDocument#to_plain_text`) laid out as the viewer lays it out — the
  # blank rows of the block margins between paragraphs, list items with
  # their markers, GFM alerts with their title chips, quotes and nested
  # items indented — with no markup in it.
  module Export
    # The formats, as `--export` names them.
    FORMATS = {"html", "text"}

    # Cells per level of list nesting and quoting, as the viewer indents them.
    INDENT = "  "

    # How wide `text` draws a horizontal rule: the viewer draws one across
    # the pane, and a filter has no pane, so it takes the width pandoc's
    # plain-text writer gives its rules (`--columns`' default).
    RULE_WIDTH = 72

    # *format* checked against `FORMATS`: a usage error otherwise.
    def self.format(value : String) : String
      return value if FORMATS.includes?(value)
      raise ArgumentError.new("unknown export format: #{value} (#{FORMATS.join(", ")})")
    end

    # *markdown* rendered as *format* (`.format` checked), ending with a
    # newline — or nothing at all for an empty document, as `cat` and a
    # Markdown renderer give for an empty file.
    def self.render(markdown : String, format : String) : String
      doc = Crysterm::TextDocument.from_markdown(markdown)
      return "" if doc.empty? && doc.blocks[0].block_format == Crysterm::TextBlockFormat.default
      out = format == "html" ? doc.to_html : text(doc)
      out.ends_with?('\n') ? out : "#{out}\n"
    end

    # The document's blocks as the viewer paints them, less the styling. A
    # horizontal rule is a line of the viewer's rule glyph (`RULE_WIDTH`
    # wide), the separator the reader sees, where its empty text would be a
    # blank line that reads as one more paragraph gap. A GFM alert's block
    # starts with the alert's title chip (`ℹ NOTE `), where the viewer
    # paints it.
    private def self.text(doc : Crysterm::TextDocument) : String
      rule = Crysterm::Glyphs.str(Crysterm::Glyphs::Role::LineHorizontal, Crysterm::Glyphs::Tier::Unicode) * RULE_WIDTH
      # Items are numbered per list instance, in document order, as the
      # viewer numbers them.
      items = {} of UInt64 => Int32
      String.build do |io|
        doc.blocks.each_with_index do |block, i|
          bf = block.block_format
          bf.top_margin.times { io << '\n' } if i > 0
          io << INDENT * bf.quote_level
          if lf = bf.list_format
            n = items[lf.object_id]? || 0
            items[lf.object_id] = n + 1
            io << INDENT * (lf.indent - 1)
            io << lf.marker(n, checked: bf.checked?, task: bf.task?)
          elsif kind = bf.alert_kind
            io << kind.marker
          end
          io << (bf.horizontal_rule? ? rule : block.text) << '\n'
          bf.bottom_margin.times { io << '\n' }
        end
      end
    end
  end
end
