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
      subs = @document_subscriptions
      subs.on(doc, Md::Event::DocumentEdited) { schedule_catch_up }
      subs.on(doc, Md::Event::DocumentReset) { schedule_catch_up }
      subs.on(doc, Md::Event::DocumentRenamed) { @window.post { renamed } }
      subs.on(doc, Md::Event::DocumentNotice) { |e| @window.post { notice e.text } }
      subs.on(doc.text, Crysterm::Event::ModificationChanged) { @window.post { refresh_status } }
      # View → Watch File is the document's: the entry's property follows
      # the document's, both ways.
      @watch_link = Crysterm::Reactive.link(doc.watch_file, @watch_file)
      subs.add doc.watch_file.on_change { refresh_status }
      @seen_revision = doc.revision
      @editor_stale = false
      @viewer.set_markdown markdown
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
    # the start and tells Neovim, when Vi Mode is on, to follow).
    protected def switch_document(doc : Document) : Nil
      return if doc.same?(@document)
      leave_document clean: true
      @document = doc
      @editor.document = doc.text
      enter_document
      apply_base_url
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
      @editor_stale = false
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
