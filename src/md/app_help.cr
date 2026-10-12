module Md
  class App
    # The Help menu, last on the bar as Qt applications put it: Manual opens
    # md's manual as a document, About names md, its version, its author and
    # its website in the status bar. Its mnemonic is `p` (`Alt+P`), since
    # `Alt+H` is Replace.
    private def build_help_menu(bar : Crysterm::Widget::MenuBar) : Nil
      help = bar.add_menu "Hel&p"
      tip help.add_action("&Manual") { show_manual }, "Open md's manual, the README's chapters on using md, as a document"
      tip help.add_action("&About md") { about }, "Show md's version, author and website in the status bar"
    end

    # Where Help → Manual writes the manual to open it: md's cache directory
    # (`App.cache_dir`), rewritten from the binary each time, so it is always
    # this version's.
    def self.manual_path : String
      Path[cache_dir].join("manual.md").to_s
    end

    # Help → Manual: the manual (`Manual.markdown`) opened as the document,
    # after unsaved changes are settled, as File → Open opens a file — on the
    # trail, so File → Previous File goes back to what was open before.
    # Returns nothing; a manual that cannot be written says so in a notice.
    def show_manual : Nil
      confirm_discard do
        path = App.manual_path
        begin
          Dir.mkdir_p File.dirname(path)
          File.write path, Manual.markdown
        rescue ex : IO::Error | File::Error
          notice "Cannot write the manual to #{path}: #{ex.message}"
          next
        end
        open_file path
      end
    end

    # Help → About: md's name, version, author and website, in the status bar
    # as a notice, as Qt's About box would name them.
    def about : Nil
      notice "md #{VERSION} by #{AUTHOR} — #{WEBSITE}"
    end
  end
end
