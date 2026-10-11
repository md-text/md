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
    # Back and Forward (Edit → Back and Forward, `Alt-Left` and `Alt-Right`;
    # `Backspace` too in the viewer and the table of contents; Qt's
    # `QTextBrowser::backward`/`forward`) retrace the places left. A step is a
    # link followed — to another file, or to a heading in this one, as in Qt,
    # where an anchor jump is a history step, so a table of contents jump can
    # be undone too — or a file opened over this one (File → Open, Open
    # Recent). A place is the file and the caret's source position, put back
    # through `#go_to_line`; going back to another file passes the guard like
    # any open. The stack is md's, not the viewer's: the editor is the source
    # of truth, and the viewer's own history would only swap the viewer's
    # document, so the viewer's link following is turned off
    # (`open_links = false`) and it is left with the event.

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

    @back = [] of Place
    @forward = [] of Place
    @back_action : Crysterm::Action?
    @forward_action : Crysterm::Action?
    # Set while Back or Forward reopens a file, so the open is not recorded
    # as a step of its own.
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

    def back_available? : Bool
      !@back.empty?
    end

    def forward_available? : Bool
      !@forward.empty?
    end

    # Follows *url*, a link activated in the viewer — or chosen in the table
    # of contents (`#jump_to`): see the class comment for where each kind of
    # link goes.
    def follow_link(url : String) : Nil
      path, fragment = Crysterm::Widget::TextBrowser.sanitize_location url
      if path.empty?
        jump_to_anchor fragment
      elsif target = local_target(path)
        follow_file target, fragment
      else
        open_url url
      end
    end

    # Goes back to the place left last (Edit → Back), through the guard when
    # it is in another file. Returns whether there was one.
    def go_back : Bool
      travel(@back, @forward) || begin
        notice "Nothing to go back to"
        false
      end
    end

    # Undoes the last Back (Edit → Forward). Returns whether there was one.
    def go_forward : Bool
      travel(@forward, @back) || begin
        notice "Nothing to go forward to"
        false
      end
    end

    # The links' part of the viewer's wiring (from `#wire_panes`): the follow
    # is ours, and `Backspace` (`Ctrl-H` on terminals that send it so) goes
    # back through our stack. The viewer binds the key to its own history,
    # which stays empty with `open_links` off; our handler, subscribed here,
    # runs before the reading listener the viewer subscribes when focused, so
    # the key is ours first and a no-op for the viewer after.
    private def wire_links : Nil
      @viewer.open_links = false
      @viewer.on(Crysterm::Event::AnchorClick) { |e| follow_link e.url }
      @viewer.on(Crysterm::Event::KeyPress) do |e|
        next if e.accepted?
        next unless e.key.in?(Tput::Key::Backspace, Tput::Key::CtrlH)
        e.accept
        go_back
      end
    end

    # `Backspace` outside the editor goes back (the table of contents; the
    # viewer handles its own); returns whether *key* was it. In the editor
    # the key deletes, and an unconsumed one (at the start of the text) is
    # left alone.
    private def navigation_key(key : Tput::Key) : Bool
      return false if !key.backspace? || @editor.focused?
      go_back
      true
    end

    # Edit → Back and Forward, after *menu*'s last entry, with Qt's shortcuts
    # for them (`Alt-Left`/`Alt-Right`, which the menu names); disabled while
    # there is nothing to go to.
    private def add_navigation_actions(menu : Crysterm::Widget::Menu) : Nil
      menu.add_separator
      back = Crysterm::Action.new "&Back"
      back.shortcut = "Alt+Left"
      back.on(Crysterm::Event::Triggered) { go_back }
      menu.add_action back
      @back_action = back
      forward = Crysterm::Action.new "For&ward"
      forward.shortcut = "Alt+Right"
      forward.on(Crysterm::Event::Triggered) { go_forward }
      menu.add_action forward
      @forward_action = forward
      refresh_navigation
    end

    # Records the place left when a file is opened over the document
    # (`#open_file`): a Back step, unless Back or Forward is doing the
    # opening. A document without a file is gone for good once another is
    # opened over it, and so are the places in it.
    private def leave_document : Nil
      return if @retracing
      if @source.path
        push place
      else
        @back.clear
        @forward.clear
        refresh_navigation
      end
    end

    # Jumps to the heading *name* (a fragment without its `#`) in the
    # document shown, the place left recorded. Returns whether there is one.
    private def jump_to_anchor(name : String) : Bool
      here = place
      return false unless go_to_anchor name
      push here
      true
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
      confirm_discard do
        open_file target
        go_to_anchor fragment unless fragment.empty?
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
      (path = @source.path) ? File.dirname(path) : Dir.current
    end

    private def markdown_file?(path : String) : Bool
      MARKDOWN_EXTENSIONS.includes? File.extname(path).downcase
    end

    # Where the reader is (`#source_position`, as the history records it).
    # Nil while the editor has yet to receive a streamed document, which has
    # no source positions to speak of.
    private def place : Place?
      return if @editor_stale
      line, column = source_position
      Place.new @source.path, line, column
    end

    # Puts *here* on the Back stack — once, when it is already on top — and
    # forgets the Forward stack: a new step leaves the undone ones behind, as
    # in any browser.
    private def push(here : Place?) : Nil
      return unless here
      @back << here unless @back.last? == here
      @forward.clear
      refresh_navigation
    end

    # Moves to the last place on *from*, the place left going onto *onto*.
    # A place in another file is opened through the guard, so the move may
    # be refused (Cancel); the stacks change only once it happened. Returns
    # whether there was a place to go to.
    private def travel(from : Array(Place), onto : Array(Place)) : Bool
      target = from.last? || return false
      here = place
      arrive(target) do
        from.pop
        onto << here if here
        refresh_navigation
      end
      true
    end

    # Puts the panes at *target*, then runs *arrived*: at once in the same
    # document — which a place without a file is always in, since a document
    # without a file is only ever left for good — after opening the file
    # otherwise.
    private def arrive(target : Place, &arrived : ->) : Nil
      path = target.path
      if path.nil? || path == @source.path
        go_to_line target.line, target.column
        arrived.call
        return
      end
      confirm_discard do
        @retracing = true
        begin
          open_file path
        ensure
          @retracing = false
        end
        go_to_line target.line, target.column
        arrived.call
      end
    end

    # Keeps the Back and Forward entries enabled only while they lead
    # somewhere (which also stands their shortcuts down).
    private def refresh_navigation : Nil
      @back_action.try &.enabled = back_available?
      @forward_action.try &.enabled = forward_available?
    end
  end
end
