require "uri"

module Md
  class App
    # Links, and the way back from them.
    #
    # Following a link in the viewer (`Enter` on the focused link, a mouse
    # click; Crysterm's `AnchorClick`) is md's to handle, since the toolkit
    # has no resource system (`#follow_link`). A `#heading` fragment scrolls
    # to the heading in the document shown (the viewer's `goto_anchor`), the
    # editor on its source line, as a table of contents jump does. A relative
    # or `file:` link is resolved against the document's directory — the
    # working directory for a document without a file — and, when it names a
    # Markdown file (by extension, `MARKDOWN_EXTENSIONS`), opened in the same
    # window through `#open_file` and the unsaved-changes guard, landing on
    # the heading its fragment names. Any other link — `http:`, `mailto:`, an
    # existing file that is not Markdown (an image, a PDF, a page) — is handed
    # to the platform's opener, `open` on macOS and `xdg-open` elsewhere, as
    # `QDesktopServices::openUrl` does. A link to a file that does not exist
    # is a notice, not a new document.
    #
    # Previous File and Next File (File → Previous File, Next File, `Alt-Left`
    # and `Alt-Right`; `Backspace` too in the viewer and the table of
    # contents; Qt's `QTextBrowser::backward`/`forward`, for files) retrace
    # the files left. A step is a file opened over this one — a link
    # followed to another file, File → Open, Open Recent — and a place is
    # the file and the caret's source position in it, put back through
    # `#go_to_line`; going to another file passes the guard like any open. A
    # jump within the document (a `#heading` link, the table of contents) is
    # not a step: Previous File leads to a file, as its name says. The
    # stacks are the window's own, or its group's while windows are linked
    # (`#trail`). They are md's, not the viewer's: the document is the
    # source of truth, and the viewer's own history would only swap the
    # viewer's document, so the viewer's link following is turned off
    # (`open_links = false`) and it is left with the event.
    #
    # File → Close (`#close_document`) takes the document off the trail, as
    # closing a tab takes it out of a browser's tab strip: the document goes
    # through the guard, its place goes to the history as for any file left,
    # and the place Next File would lead to takes its place — the way
    # `QMdiArea::closeActiveSubWindow` activates the window after the one
    # closed. With nothing ahead, a blank new document is left, as `md`
    # starts with no file; Previous File still leads back from it.

    # A place the reader left: the document's file (`nil` for a new or
    # streamed document, which has nowhere to be reopened from) and the
    # caret's source line and column, 1-based.
    record Place, path : String?, line : Int32, column : Int32

    # The extensions a linked file is read as Markdown with; a file with any
    # other extension, or none, goes to the platform opener.
    MARKDOWN_EXTENSIONS = {".md", ".markdown", ".mdown", ".mkd", ".mkdn", ".mdwn"}

    # How an external URL is opened: the platform's opener unless a caller
    # supplies another (specs do, to see the URL without launching anything).
    property url_opener : Proc(String, Nil) = ->(url : String) { App.open_externally url }

    # The places left (`Trail`), the browser's back and forward stacks
    # `#travel` moves between: Previous File pops the one, Next File the
    # other. The window's own, unless it is linked (`#trail`).
    @trail = Trail.new
    @previous_action : Crysterm::Action?
    @next_action : Crysterm::Action?
    # Set while Previous File or Next File reopens a file, so the open is
    # not recorded as a step of its own.
    @retracing = false

    # Opens *url* with the platform's opener — `open` on macOS, `xdg-open`
    # elsewhere — detached, its output discarded (`QDesktopServices::openUrl`).
    # Raises `IO::Error` when the opener cannot be started.
    def self.open_externally(url : String) : Nil
      command = {{ flag?(:darwin) ? "open" : "xdg-open" }}
      process = File.open(File::NULL, "w") do |null|
        Process.new command, [url], input: Process::Redirect::Close, output: null, error: null
      end
      spawn(name: "md-opener") { process.wait }
    end

    # The trail this window retraces: its link's while linked (Window →
    # Linking), its own otherwise.
    def trail : Trail
      link.try(&.trail) || @trail
    end

    def previous_file_available? : Bool
      !trail.back.empty?
    end

    def next_file_available? : Bool
      !trail.forward.empty?
    end

    # Follows *url*, a link activated in the viewer — or chosen in the table
    # of contents (`#jump_to`): see the class comment for where each kind of
    # link goes.
    def follow_link(url : String) : Nil
      path, fragment = Crysterm::Widget::TextBrowser.sanitize_location url
      if path.empty?
        go_to_anchor fragment
      elsif target = local_target(path)
        follow_file target, fragment
      else
        open_url url
      end
    end

    # Goes back to the file left last, where it was left (File → Previous
    # File), through the guard. Returns whether there was one.
    def previous_file : Bool
      travel(trail.back, trail.forward) || begin
        notice "No previous file"
        false
      end
    end

    # Undoes the last Previous File (File → Next File). Returns whether
    # there was one.
    def next_file : Bool
      travel(trail.forward, trail.back) || begin
        notice "No next file"
        false
      end
    end

    # Closes the document (File → Close), through the guard, and takes it
    # off the trail: the place Next File leads to is opened in its stead —
    # where it was left, and a file that cannot be read any more is skipped
    # for the one after it, its notice saying so — or, with none ahead, a
    # blank new document (`#blank_document`), with a notice of the close (an
    # opened file has its own). The Previous File places stay, so Previous
    # File from the next document goes to the one the closed document was
    # opened over — all but those in the closed file, on either side: a
    # link to the document itself leaves one, which the close would
    # otherwise open again, or Next File later. The closed file's position
    # goes to the history, as when any file is left.
    def close_document : Nil
      confirm_discard do
        closed = source.name || "the new document"
        remember_position
        if @document.key
          trail.back.reject! { |place| here?(place) }
          trail.forward.reject! { |place| here?(place) }
        end
        while target = trail.forward.pop?
          next unless path = target.path
          @retracing = true # a close is no step: the closed place is not kept
          opened = begin
            open_file path
          ensure
            @retracing = false
          end
          if opened
            go_to_line target.line, target.column
            break
          end
        end
        unless opened
          blank_document
          notice "Closed #{closed}"
        end
        refresh_navigation
      end
    end

    # The links' part of the viewer's wiring (from `#wire_panes`): the follow
    # is ours, and `Backspace` (`Ctrl-H` on terminals that send it so) goes
    # to the previous file through our stack. The viewer binds the key to
    # its own history, which stays empty with `open_links` off; our handler,
    # subscribed here, runs before the reading listener the viewer
    # subscribes when focused, so the key is ours first and a no-op for the
    # viewer after.
    private def wire_links : Nil
      @viewer.open_links = false
      @viewer.on(Crysterm::Event::AnchorClick) { |e| follow_link e.url }
      @viewer.on(Crysterm::Event::KeyPress) do |e|
        next if e.accepted?
        next unless e.key.in?(Tput::Key::Backspace, Tput::Key::CtrlH)
        e.accept
        previous_file
      end
    end

    # `Backspace` outside the editor goes to the previous file (the table of
    # contents; the viewer handles its own); returns whether *key* was it.
    # In the editor the key deletes, and an unconsumed one (at the start of
    # the text) is left alone.
    private def navigation_key(key : Tput::Key) : Bool
      return false if !key.backspace? || @editor.focused?
      previous_file
      true
    end

    # File → Previous File and Next File, after *menu*'s last entry, with
    # Qt's shortcuts for a browser's back and forward (`Alt-Left`/`Alt-Right`,
    # which the menu names); disabled while there is no file to go to.
    private def add_navigation_actions(menu : Crysterm::Widget::Menu) : Nil
      previous = Crysterm::Action.new "&Previous File", name: "previous-file"
      previous.shortcut = "Alt+Left"
      previous.on(Crysterm::Event::Triggered) { previous_file }
      menu.add_action tip(previous, "Go back to the file this one was opened over, at the place left")
      @previous_action = previous
      following = Crysterm::Action.new "&Next File", name: "next-file" # `next` is a keyword
      following.shortcut = "Alt+Right"
      following.on(Crysterm::Event::Triggered) { next_file }
      menu.add_action tip(following, "Go forward again to the file Previous File came back from")
      @next_action = following
      refresh_navigation
    end

    # Records the place left when a file is opened over the document
    # (`#open_file`): a Previous File step, unless Previous File or Next
    # File is doing the opening. A document without a file is gone for good
    # once another is opened over it, so it leaves no place to come back to;
    # the trail behind it stays, as it does behind the blank document File →
    # Close leaves (`#close_document`).
    private def push_leaving_place : Nil
      return if @retracing
      push place if source.path
    end

    # Puts the viewer on heading *name* — on its top row, as a browser lands
    # a fragment — and the editor on the heading's source line, on the same
    # viewport row. Both panes move whether or not they follow each other: a
    # jump is an explicit move, not a caret drifting along. A hidden editor is
    # left alone, like a hidden pane when following. Returns whether there is
    # such a heading, with a notice when there is not.
    private def go_to_anchor(name : String) : Bool
      unless @viewer.goto_anchor name
        notice "No heading ##{name}"
        return false
      end
      if @editor.visible?
        pos = editor_position(@viewer.cursor_position)
        @editor.text_cursor = Crysterm::TextCursor.new(@editor.document, pos)
        align_rows @viewer, @editor if @viewer.visible?
      end
      true
    end

    # Opens the linked file *target* (absolute): a Markdown file in this
    # window, through the guard, landing on *fragment*'s heading when there
    # is one; another kind of file with the platform opener.
    private def follow_file(target : String, fragment : String) : Nil
      unless File.file? target
        notice "No such file: #{target}"
        return
      end
      unless markdown_file? target
        open_url target
        return
      end
      confirm_open(target) do
        # A file that could not be read (its notice says so) has no
        # headings to land on.
        go_to_anchor fragment if open_file(target) && !fragment.empty?
      end
    end

    # Hands *url* to `#url_opener`, with a notice either way.
    private def open_url(url : String) : Nil
      @url_opener.call url
      notice "Opening #{url}"
    rescue ex : IO::Error
      notice "Cannot open URL: #{ex.message}"
    end

    # The file a link's *path* names, absolute, or nil when the path is a URL
    # of another scheme. A relative path counts from the document's directory
    # (the working directory for a document without a file); a `file:` URL
    # and a percent-encoded name (`a%20b.md`) are taken apart first.
    private def local_target(path : String) : String?
      uri = URI.parse path
      scheme = uri.scheme.try &.downcase
      return unless scheme.nil? || scheme == "file"
      File.expand_path(URI.decode(scheme ? uri.path : path), link_base)
    rescue URI::Error
      File.expand_path(path, link_base)
    end

    # The directory relative links count from.
    private def link_base : String
      (path = source.path) ? File.dirname(path) : Dir.current
    end

    private def markdown_file?(path : String) : Bool
      MARKDOWN_EXTENSIONS.includes? File.extname(path).downcase
    end

    # Where the reader is (`#source_position`, as the history records it).
    # Nil while the editor has yet to receive a streamed document, which has
    # no source positions to speak of.
    private def place : Place?
      return if @document.editor_stale?
      line, column = source_position
      Place.new source.path, line, column
    end

    # Puts *here* on the Previous File stack — once, when it is already on
    # top — and forgets the Next File stack: a new step leaves the undone
    # ones behind, as in any browser.
    private def push(here : Place?) : Nil
      return unless here
      back = trail.back
      back << here unless back.last? == here
      trail.forward.clear
      refresh_navigation
    end

    # Moves to the last place on *from*, the place left going onto *onto* —
    # unless it is in a document without a file, which is left for good. A
    # place in another file is opened through the guard, so the move may be
    # refused (Cancel); the stacks change only once it happened. Returns
    # whether there was a place to go to.
    private def travel(from : Array(Place), onto : Array(Place)) : Bool
      target = from.last? || return false
      here = place
      arrive(target) do |moved|
        from.pop
        onto << here if here && here.path && moved
        refresh_navigation
      end
      true
    end

    # Puts the panes at *target*, then runs *arrived* with whether they got
    # there: at once in the same document — which a place without a file is
    # always in, since a document without a file is only ever left for good
    # and leaves no place on the stacks — after opening the file otherwise. A file unreadable since it was
    # left cannot be arrived at: its notice says so and the document stays
    # as it is; the place is still spent, so the next step leads somewhere.
    private def arrive(target : Place, &arrived : Bool ->) : Nil
      path = target.path
      if path.nil? || here?(target)
        go_to_line target.line, target.column
        arrived.call true
        return
      end
      confirm_discard do
        @retracing = true
        opened = begin
          open_file path
        ensure
          @retracing = false
        end
        go_to_line target.line, target.column if opened
        arrived.call opened
      end
    end

    # Whether *place* is in the document this window shows: its file is the
    # document's by canonical key (`Documents.key_for`), whatever path,
    # symlink or case it was left by.
    private def here?(place : Place) : Bool
      return false unless (path = place.path) && (key = @document.key)
      Documents.key_for(path) == key
    end

    # Keeps the Previous File and Next File entries enabled only while they
    # lead somewhere (which also stands their shortcuts down).
    private def refresh_navigation : Nil
      @previous_action.try &.enabled = previous_file_available?
      @next_action.try &.enabled = next_file_available?
    end
  end
end
