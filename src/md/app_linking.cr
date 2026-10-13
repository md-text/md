module Md
  class App
    # Window → Linking (`md.window_link`): how windows on one document
    # behave towards each other. The text, its undo history and its modified
    # state are one either way (`Document`); the choice is about the rest.
    #
    # Separate Views, the default, is what a second window on a buffer is in
    # Vim, Emacs, Kate or Qt Creator: each window keeps its own caret,
    # scroll, panes, search and trail of files, and opening another file in
    # it takes it alone there. Linked (Mirrored) makes the windows on a
    # document act as the panes of one window (`ViewLink`): the carets and
    # selections, the scroll (the same first line, whatever each window's
    # height), the viewer's place, the table of contents' entry, the search
    # and Sync Cursor follow the window used last, and opening a file,
    # following a link, Previous File and File → Close move every window of
    # the group. With Sync Cursor on, a move in one window's editor moves
    # another window's viewer even when that window shows no editor, as it
    # would move the viewer beside the editor in one window. Each window
    # keeps its own panes, focus, sizes and wrapping.
    #
    # The choice is one for the process (`Documents.link_windows`): picked
    # in any window, it applies to every window at once — linking each
    # document's windows to the one used most recently, or letting each go
    # on alone from where it is, with a copy of the trail — and every Window
    # menu shows it.
    enum WindowLink
      Separate
      Linked
    end

    # Window → Linking. A reactive property, so the menu entries bind to it
    # and the config keeps it; `#window_link` and `#window_link=` are its
    # plain face.
    @window_link : Crysterm::Reactive::Property(WindowLink) = Crysterm::Reactive::Property.new(WindowLink::Separate)

    # The window that took input last, of all md's windows: the leader of
    # its group when linking starts, and after its group's leader leaves.
    class_property last_active : App?

    # Something the link mirrors moved here since the last publish
    # (`#publish_view`).
    @view_moved = false
    # Set while this window applies a mirror, which it then does not
    # publish.
    @mirroring = false
    @mirror_posted = false

    def window_link : WindowLink
      @window_link.value
    end

    # Picks how the windows on a document behave (Window → Linking), for
    # every window.
    def window_link=(mode : WindowLink) : WindowLink
      @window_link.value = mode
    end

    # The group this window mirrors with, while windows are linked.
    def link : ViewLink?
      @document.link
    end

    # The trail of this window's own, apart from any link's.
    protected def own_trail : Trail
      @trail
    end

    # Wires linking (from `#initialize`): the setting applied for every
    # window, input making the window the leader, the moves the link
    # mirrors noted, and a frame painted with something moved published.
    private def wire_linking : Nil
      # A window opened while windows are linked shows it from the start;
      # the config, when linked to it, agrees (`app_config.cr`).
      @window_link.value = Documents.window_link
      @window_link.on_change { Documents.link_windows @window_link.value, self }
      # At the beginning, ahead of whatever the input does: the leader is
      # the window the input is for, before the caret it moves reports.
      first = ::EventHandler.at_beginning
      @window.on(Crysterm::Event::KeyPress, at: first) { became_active }
      @window.on(Crysterm::Event::Paste, at: first) { became_active }
      @window.on(Crysterm::Event::Mouse, at: first) do |e|
        became_active if e.mouse.action.in?(Tput::Mouse::Action::Down, Tput::Mouse::Action::WheelUp,
                           Tput::Mouse::Action::WheelDown, Tput::Mouse::Action::Focus)
      end
      @editor.on(Crysterm::Event::CursorPositionChanged) { mark_view_moved }
      @editor.on(Crysterm::Event::SelectionChanged) { mark_view_moved }
      @editor.on(Crysterm::Event::Scroll) { mark_view_moved }
      @viewer.on(Crysterm::Event::CursorPositionChanged) { mark_view_moved }
      @viewer.on(Crysterm::Event::Scroll) { mark_view_moved }
      @window.on(Crysterm::Event::Rendered) { publish_view }
    end

    # This window took input, or was picked in the Window menu: it is the
    # last active, and its group's leader.
    protected def became_active : Nil
      App.last_active = self
      link.try &.leader = self
    end

    # Notes a move the link mirrors — unless it is a mirror being applied —
    # and asks for a frame, after which it is published.
    protected def mark_view_moved : Nil
      return if @mirroring
      @view_moved = true
      @window.update
    end

    # After a frame: the leader of a group publishes what moved, measured
    # on the layout just painted (the first line shown is known only then).
    private def publish_view : Nil
      return unless @view_moved
      @view_moved = false
      return unless (link = self.link) && link.leader.same?(self)
      link.publish self
    end

    # Asks this window to mirror its leader on its own render fiber, once
    # however many publishes come before it runs.
    protected def schedule_mirror : Nil
      return if @mirror_posted
      @mirror_posted = true
      @window.post do
        @mirror_posted = false
        if (link = self.link) && !link.leader.same?(self)
          mirror link.leader
        end
      end
    end

    # Puts this window where *leader* is: Sync Cursor and the search as the
    # leader has them, the editor's caret and selection exactly (the text is
    # the same), its first line the leader's, the viewer's place (`#mirror_viewer`),
    # and the table of contents on the heading the carets are under.
    protected def mirror(leader : App) : Nil
      return if @window.destroyed? || leader.window.destroyed?
      @mirroring = true
      begin
        @sync_cursor.value = leader.sync_cursor?
        adopt_search leader
        @editor.text_cursor = leader.editor.text_cursor
        @editor.scroll_position_to_row leader.editor.top_position
        mirror_viewer leader
        track_toc
        refresh_navigation
      ensure
        @mirroring = false
      end
      refresh_status
    end

    # The viewer's part of a mirror. With Sync Cursor on and the leader in
    # its editor, the viewer follows this window's own editor, as the pane
    # beside the editor would — so a window showing only the viewer follows
    # another's editor. Otherwise it takes the leader's viewer place: the
    # same position when the two render the same text, else the position
    # mapped through the source (`#editor_position`, `#viewer_position`),
    # and the same first line likewise; with Sync Cursor on, an editor the
    # leader could not move (it was hidden there) follows this viewer.
    private def mirror_viewer(leader : App) : Nil
      if @sync_cursor.value && leader.editor.focused?
        @viewer.text_cursor = Crysterm::TextCursor.new(@viewer.document, viewer_position(@editor.cursor_position))
        @viewer.scroll_cursor_to_row leader.editor.cursor_viewport_row
        return
      end
      same = leader.viewer.document.size == @viewer.document.size && leader.viewer.width == @viewer.width
      map = ->(pos : Int32) { same ? pos : viewer_position(leader.editor_position(pos)) }
      @viewer.text_cursor = Crysterm::TextCursor.new(@viewer.document, map.call(leader.viewer.cursor_position))
      @viewer.scroll_position_to_row map.call(leader.viewer.top_position)
      return if !@sync_cursor.value || leader.editor.visible?
      @editor.text_cursor = Crysterm::TextCursor.new(@document.text, editor_position(@viewer.cursor_position))
      align_rows @viewer, @editor
    end

    # Takes *leader*'s search — the pattern, its direction and whether its
    # matches are underlined — re-highlighting when it changed.
    private def adopt_search(leader : App) : Nil
      regex = leader.@search_regex
      return if leader.search_pattern == @search_pattern && regex == @search_regex &&
                leader.search_backward? == @search_backward && leader.@highlighting == @highlighting
      @search_pattern = leader.search_pattern
      @search_regex = regex
      @search_backward = leader.search_backward?
      @highlighting = leader.@highlighting
      if @highlighting
        highlight_matches_everywhere
      else
        Pane.each { |pane| set_match_selections pane, [] of Crysterm::Widget::TextEdit::ExtraSelection }
      end
    end

    # This window joins its document's group (`#enter_document`, while
    # linked): the group there takes it in, or it starts one, leading it
    # with its own trail.
    private def join_link : Nil
      if link = @document.link
        link.add self
        link.leader.mark_view_moved
      else
        @document.link = ViewLink.new(@document, self, @trail)
      end
    end

    # Linking ended (`ViewLink#dissolve`): the window goes on alone, from
    # where it is, retracing *trail*, its copy of the group's.
    protected def unlink(trail : Trail) : Nil
      @trail = trail
      refresh_navigation
    end

    # The Window → Linking submenu (`#build_window_menu`).
    private def add_linking_menu(menu : Crysterm::Widget::Menu) : Nil
      add_choices(menu, "&Linking", "window-link", WindowLink.values, @window_link,
        option_tip("md.window_link"), ->window_link_tip(WindowLink)) { |mode| window_link_label mode }
    end

    private def window_link_label(mode : WindowLink) : String
      case mode
      in .separate? then "&Separate Views"
      in .linked?   then "&Linked (Mirrored)"
      end
    end

    private def window_link_tip(mode : WindowLink) : String
      case mode
      in .separate? then "Each window on a document keeps its own caret, scroll, search and trail"
      in .linked?   then "The windows on a document mirror each other, as the panes of one window, and move to another file together"
      end
    end
  end
end
