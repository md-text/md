require "crysterm"

module Md
  # `--export`: the document rendered to standard output, no terminal
  # involved — md as a filter. The Markdown goes through the same import the
  # viewer renders with (`TextDocument#set_markdown`), so the output is what
  # the viewer shows: Crysterm's HTML export (`TextDocument#to_html`, a body
  # fragment, as pandoc without `--standalone` prints) or the plain text
  # (`TextDocument#to_plain_text`) laid out as the viewer lays it out — the
  # blank rows of the block margins between paragraphs, list items with
  # their markers, quotes and nested items indented — with no markup in it.
  module Export
    # The formats, as `--export` names them.
    FORMATS = {"html", "text"}

    # Cells per level of list nesting and quoting, as the viewer indents them.
    INDENT = "  "

    # *format* checked against `FORMATS`: a usage error otherwise.
    def self.format(value : String) : String
      return value if FORMATS.includes?(value)
      raise ArgumentError.new("unknown export format: #{value} (#{FORMATS.join(", ")})")
    end

    # *markdown* rendered as *format* (`.format` checked), ending with a
    # newline.
    def self.render(markdown : String, format : String) : String
      doc = Crysterm::TextDocument.from_markdown(markdown)
      out = format == "html" ? doc.to_html : text(doc)
      out.ends_with?('\n') ? out : "#{out}\n"
    end

    # The document's blocks as the viewer paints them, less the styling.
    private def self.text(doc : Crysterm::TextDocument) : String
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
            io << lf.marker(n, checked: bf.checked?)
          end
          io << block.text << '\n'
          bf.bottom_margin.times { io << '\n' }
        end
      end
    end
  end
end
