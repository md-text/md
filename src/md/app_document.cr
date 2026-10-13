module Md
  class App
    # The window as a view on its `Document` (`document.cr`), the way a
    # `QPlainTextEdit` is a view on its `QTextDocument`: the editor edits
    # the document's text, the viewer and the table of contents are this
    # window's own, rendered from it, and so are the carets, the scroll, the
    # panes and the search.
    #
    # An edit in another window on the document reaches this one through
    # the document (`Event::DocumentEdited`): the editor shows it at once
    # (Crysterm patches every view of a text), and the rest — the viewer
    # re-rendered, the search highlights, the status — is posted to this
    # window's render fiber, once a frame however many edits came
    # (`#document_changed`). Crysterm's `TextChanged` comes only from the
    # view that edited; md does not rely on it for the other windows, so a
    # toolkit that sent it to every view, as Qt's does, would change
    # nothing here (the revision check makes the second notice a no-op).

    # Makes this window a view on its document (from `#initialize`, and
    # after a switch, `#switch_document`): attached and subscribed, its
    # Watch File entry tied to the document's, the viewer rendered from the
    # text, the measurements and the title fresh.
    private def enter_document : Nil
      doc = @document
      doc.attach self
      join_link if Documents.window_link.linked?
      subs = @document_subscriptions
      subs.on(doc, Md::Event::DocumentEdited) { schedule_catch_up }
      subs.on(doc, Md::Event::DocumentReset) { schedule_catch_up }
      subs.on(doc, Md::Event::DocumentRenamed) { @window.post { renamed } }
      subs.on(doc, Md::Event::DocumentNotice) { |e| @window.post { notice e.text } }
      subs.on(doc.text, Crysterm::Event::ModificationChanged) { @window.post { refresh_status } }
      # The stream's chunks: at once in the window whose render fiber took
      # them; posted to the others, in order (a window's queue is FIFO).
      subs.on(doc, Md::Event::StreamAppended) { |e| on_own_fiber { stream_appended e.chunk } }
      subs.on(doc, Md::Event::StreamEnded) { |e| on_own_fiber { stream_ended e.message } }
      # View → Watch File is the document's: the entry's property follows
      # the document's, both ways.
      @watch_link = Crysterm::Reactive.link(doc.watch_file, @watch_file)
      subs.add doc.watch_file.on_change { refresh_status }
      @seen_revision = doc.revision
      if doc.streaming?
        # Joining a stream: the viewer starts from what arrived so far and
        # takes the rest as it comes, following the tail.
        @viewer.set_markdown ""
        @viewer.append_markdown markdown
        @viewer.follow_tail = true
      else
        # A file holds still: the viewer follows no tail, whatever it did
        # on a stream it showed before.
        @viewer.set_markdown markdown
        @viewer.follow_tail = false
      end
      @viewer_stale = false
      text_changed
      @document.views.each &.retitle
    end

    # Takes this window off its document: the subscriptions dropped, the
    # document detached (the last view closing it; the recovery file going
    # only when this window was on screen, its session ending as the user
    # meant it to, or when *clean* says the guard settled its changes), and
    # the windows left on it renamed — their `:N` may go. From the window's
    # `Destroy`, and before a switch to another document.
    private def leave_document(clean : Bool = @started) : Nil
      leave_shared_vi
      link.try &.remove(self)
      @document_subscriptions.off
      @watch_link.try &.dispose
      @watch_link = nil
      doc = @document
      doc.detach self, clean: clean
      doc.views.each &.retitle
    end

    # Shows *doc* in this window instead of its document (File → Open, a
    # link, File → Close…): this window leaves its document — closing it
    # when no other window shows it — and becomes a view on *doc*, its
    # editor on *doc*'s text (Qt's `setDocument`, which puts the caret at
    # the start and tells Neovim, when Vi Mode is on, to follow). Linked
    # windows go together (`ViewLink#move`) — a window alone in its group
    # too, so the group's trail goes with it.
    protected def switch_document(doc : Document) : Nil
      return if doc.same?(@document)
      if link = self.link
        link.move doc, self
      else
        move_to doc
      end
    end

    # This window's part of a switch to *doc* (`#switch_document`). A
    # stream this window followed goes on for the other windows on it (the
    # last one leaving abandons it, `Document#detach`); a `--line` waiting
    # for one of its lines gives way to the new document's own position.
    protected def move_to(doc : Document) : Nil
      return if doc.same?(@document)
      @pending_line = nil
      leave_document clean: true
      @document = doc
      @editor.document = doc.text
      enter_document
      # A separate window's own Neovim follows the editor to the new text
      # (Crysterm's `DocumentChanged`); a linked one joins the document's.
      apply_vi_mode if vi_mode? && link
      apply_base_url
    end

    # Runs *job* now when the stream's chunk arrived on this window's render
    # fiber (`Document#receiver`), else posts it to this window's.
    private def on_own_fiber(&job : ->) : Nil
      if @document.receiver.same?(self)
        job.call
      else
        @window.post(&job)
      end
    end

    # Posts a catch-up with the document (`#document_changed`) to this
    # window's render fiber, unless one is posted already: a burst of edits
    # — a macro, a Replace All, Neovim's changes — costs one.
    private def schedule_catch_up : Nil
      return if @catch_up_posted
      @catch_up_posted = true
      @window.post do
        @catch_up_posted = false
        document_changed
      end
    end

    # Brings the window up to date with an edit or a reset made in another
    # window (in this one, `#edited` and the reset's caller did it at once
    # and nothing is left): the viewer re-rendered, keeping the reader's
    # place — now when it or the table of contents is shown, else when next
    # shown — the search highlights, the measurements and the status.
    protected def document_changed : Nil
      return if @seen_revision == @document.revision || @window.destroyed?
      @seen_revision = @document.revision
      text_changed
      highlight_matches Pane::Editor
      if @viewer.visible? || @toc.visible?
        render_viewer
      else
        @viewer_stale = true
      end
      refresh_status
    end

    # The document has another name (a Save As here or in another window):
    # the title, the links' base and the status follow.
    private def renamed : Nil
      retitle
      apply_base_url
      refresh_status
    end
  end
end
