module Md
  # Linked windows (Window → Linking → Linked, `md.window_link`): the
  # windows on one document acting as if they were panes of one window. The
  # link is the group — every window showing its document — and holds what
  # the group shares beyond the text: which window leads, and the trail of
  # files left (`Trail`). The rest of the mirrored state (the carets and
  # selections, the scroll, the viewer's place, the search, Sync Cursor) is
  # read from the leader as it is (`App#mirror`).
  #
  # The leader is the window that took the group's latest input — a key, a
  # click or the wheel, a paste, the terminal window coming to the front
  # (`App#became_active`). Only the leader publishes: after each frame it
  # painted with something moved (`App#publish_view`), every other window
  # is asked to mirror it, on its own render fiber, once a frame however
  # much moved. A window applying a mirror publishes nothing, so nothing
  # bounces back.
  #
  # The group moves together: opening another file in one window, following
  # a link, Previous File and File → Close take every window of the group
  # to the new document (`#move`), as they would take the panes of one
  # window; a document that has a group of its own already takes the
  # arrivals in, and they adopt its place, its leader staying the leader.
  class ViewLink
    # The document the group shows.
    property document : Document
    # The windows of the group, the first linked first.
    getter views = [] of App
    # The window whose state the others mirror.
    getter leader : App
    # The files the group left, which Previous File retraces in any of its
    # windows.
    property trail : Trail

    # A group of *leader*, on *document*, retracing *trail*.
    def initialize(@document : Document, @leader : App, @trail : Trail)
      @views << @leader
    end

    # Makes *app*, a window of the group, the leader: what it moves from
    # now on is what the others mirror (`#publish`). A window outside the
    # group is ignored.
    def leader=(app : App) : App
      return app if app.same?(@leader) || !@views.includes?(app)
      @leader = app
    end

    # Adds *app* to the group (a window opened on the document, or arriving
    # with a group move).
    def add(app : App) : Nil
      @views << app unless @views.includes?(app)
    end

    # Takes *app* out of the group (its window closed, or it shows another
    # document now). A leader leaving hands over to the window used most
    # recently, else the first; the last leaving ends the link.
    def remove(app : App) : Nil
      return unless @views.delete(app)
      if @views.empty?
        @document.link = nil if @document.link.same?(self)
      elsif @leader.same?(app)
        @leader = App.last_active.try { |last| last if @views.includes?(last) } || @views.first
        @leader.mark_view_moved
      end
    end

    # Has every window but *leader* mirror it (`App#schedule_mirror`).
    def publish(leader : App) : Nil
      @views.each { |view| view.schedule_mirror unless view.same?(leader) }
    end

    # Takes the whole group to *doc*, as *by* (which acted) asked: each
    # window leaves the document for *doc*, the arriving trail going with
    # them. A group already on *doc* takes them in and keeps its leader;
    # otherwise *by* leads the new group.
    def move(doc : Document, by : App) : Nil
      arriving = [by] + (@views - [by])
      trail = @trail
      existing = doc.link
      arriving.each &.move_to(doc)
      return unless target = doc.link
      target.trail = trail
      target.leader = by unless existing
      target.leader.mark_view_moved
    end

    # Ends the link (Window → Linking → Separate Views): each window goes on
    # alone from where it is, with its own copy of the trail.
    def dissolve : Nil
      @views.each &.unlink(@trail.dup)
      @views.clear
      @document.link = nil if @document.link.same?(self)
    end
  end
end
