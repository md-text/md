module Md
  class App
    # The document's file, beyond saving: opening another (File → Open…,
    # `Ctrl-O`, asked for like Save As, `app_dialogs.cr`), closing it for
    # the next on the trail or a blank one (File → Close, `app_links.cr`),
    # re-reading it from disk (File → Reload, `Ctrl-R`) and following it as
    # other programs rewrite it (Options → Watch File, `--watch`), the guard
    # that asks before unsaved changes are lost, and the history of recent
    # files and positions (`History`, File → Open Recent).
    #
    # The guard (`#confirm_discard`) sits in front of quitting, opening,
    # closing and reloading: with changes unsaved it asks — Save, Don't save
    # or Cancel — and the action goes ahead only on an answer that settles
    # the changes. Quitting asks through Crysterm's close request
    # (`Event::CloseRequest`, which the default `q`/`Ctrl-Q` keys honor), so
    # File → Quit and the keys take the same path. Options → Ask Before
    # Discarding Changes turns the guard off for those who save by habit.
    #
    # Watching polls the file (`Crysterm::FileWatcher`) and reloads it when
    # its contents changed on disk — unless the document holds unsaved
    # changes, in which case a notice says the file changed and the changes
    # are kept. A reload is an edit of what differs on disk, one undo step
    # (`Document#reload`), and the viewer keeps its place through it, so
    # `md --watch notes.md` beside an editor shows each save where the
    # reader was. Watching is the document's (`Document#watch_file`): every
    # window on it shows the same check, and one watcher serves them all.
    #
    # A document shown in several windows is lost only with the last of
    # them: opening another file in one window, closing it, asks nothing
    # while another window shows the document — unless the windows are
    # linked (Window → Linking), when the whole group leaves it and the
    # question is asked. Reloading drops the edits for every window, so it
    # asks whenever there are some.

    # The polling interval of the watcher this window starts for its
    # document, as its host (specs shorten it).
    property watch_interval : Time::Span = Document::WATCH_INTERVAL

    # Options → Ask Before Discarding Changes. A reactive property, so the
    # menu entry binds to it.
    @confirm_discard : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    # Options → Watch File. Likewise; `#watch_file=` is its plain face. Kept
    # equal to the document's (`#enter_document`).
    @watch_file : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @watch_link : Crysterm::Reactive::PropertyLink?
    # The recent files and positions, when the app keeps them (the CLI does;
    # specs pass none).
    getter history : History?
    # The File → Open Recent submenu, remade from the history as it changes.
    @recent_action : Crysterm::Action?

    def confirm_discard? : Bool
      @confirm_discard.value
    end

    # Turns the unsaved-changes guard on or off (Options → Ask Before
    # Discarding Changes).
    def confirm_discard=(value : Bool) : Bool
      @confirm_discard.value = value
    end

    def watch_file? : Bool
      @watch_file.value
    end

    # Starts or stops following the document's file (Options → Watch File), in
    # every window on it (`Document#setup_watcher`).
    def watch_file=(value : Bool) : Bool
      @watch_file.value = value
    end

    # Quits: settles every document with unsaved changes first — one
    # question per document, this window's own first, each in a window
    # showing it (`#settle_documents`) —
    # and closes every window (`app_windows.cr`) only once all are saved or
    # given up, as Kate and Qt Creator ask before they close anything. A
    # Cancel at any question closes nothing: every window stays as it was,
    # with nothing to undo. With one window, the one question.
    def quit : Nil
      settle_documents(([@document] + App.instances.map(&.document)).uniq) do
        App.instances.dup.each &.window.close
      end
    end

    # Asks about the first of *docs* with unsaved changes (`#confirm_discard`,
    # which honors Options → Ask Before Discarding Changes), in this window
    # when it shows the document, else in the first window that does, which
    # is brought forward; then about the next, and so on; *done* runs once
    # none is left. A Cancel, or a save that did not happen, ends the chain:
    # *done* never runs.
    protected def settle_documents(docs : Array(Document), &done : ->) : Nil
      unless doc = docs.find { |candidate| candidate.text.modified? && !candidate.views.empty? }
        done.call
        return
      end
      rest = docs.reject(&.same?(doc))
      view = doc.views.includes?(self) ? self : doc.views.first
      view.window.activate unless view.same?(self)
      view.confirm_discard(last_view_only: false) { settle_documents(rest, &done) }
    end

    # Asks for a file to open (`#ask_text`; a line prompt completes the
    # name) and opens the answer; unsaved changes are settled first.
    def open_prompt : Nil
      confirm_discard do
        ask_text("Open: ", "") do |answer|
          path = answer.try &.strip
          open_file App.typed_path(path) if path && !path.empty?
        end
      end
    end

    # Whether *path* is a place md can go back to: a file on disk, or one a
    # window still has open (its text in memory). A file deleted since it
    # was left is not — reopening it would make a new, empty document under
    # its name — and is said so ("No such file"), as Qt Creator does for a
    # recent file that is gone. For Previous File, Next File, File → Close's
    # next place and File → Open Recent, asked before their unsaved-changes
    # question, which would be for nothing.
    private def reopenable?(path : String) : Bool
      return true if File.exists?(path) || Documents.find(path)
      notice "No such file: #{path}"
      false
    end

    # The file a name typed at a prompt stands for: a leading `~` or `~/`
    # is the home directory, as in the shell, Qt's file dialogs and the
    # prompt's own completion (which expands it only on `Tab`), so
    # `~/notes.md` typed out in full is not `./~/notes.md`; any other name
    # is as typed, a relative one counting from the working directory.
    def self.typed_path(text : String) : String
      text == "~" || text.starts_with?("~/") ? Path[text].expand(home: true).to_s : text
    end

    # Makes *path* the document: an existing file is read and shown in the
    # viewer (shown and focused if it was hidden), a file that does not exist
    # yet is a new, empty document in the editor (shown and focused). The
    # document left — a stream being followed too — goes on in the other
    # windows showing it, if any. The position remembered for the file, if
    # any, is restored. Watch File carries over to the file opened.
    # A file another window has open — through whatever path, symlink or
    # hard link (`Documents.find`) — is not read again: this window joins
    # that window's document, unsaved edits and all (`#join_document`).
    # Returns whether the file could be opened.
    def open_file(path : String) : Bool
      path = File.expand_path path
      if open = Documents.find(path)
        return join_document(path, open)
      end
      raw = File.read(path) if File.exists?(path)
      text = raw.try { |read| Source.decode read }
      remember_position
      push_leaving_place
      doc = Document.new Source.new(path: path), text || ""
      doc.watch_file.value = watch_file?
      # The caret starts at the top, as Qt's `setPlainText` and
      # `setDocument` put it (`#switch_document`), unless the history
      # remembers a place (`#restore_position`).
      switch_document doc
      if text
        show_pane(Pane::Viewer).focus unless @viewer.visible?
      else
        show_pane(Pane::Editor).focus
      end
      restore_position
      remember_position # the file just opened leads the recent list
      refresh_status
      notice(text ? "Opened #{path}#{" (invalid UTF-8 replaced by �)" unless text.same?(raw)}" : "New file #{path}")
      doc.check_recovery.try { |found| notice found }
      true
    rescue ex : IO::Error
      notice "Cannot open #{path}: #{Md.error_text(ex)}"
      false
    end

    # Opens *path* by showing *doc*, the document another window (or this
    # one) has it open as: no read from disk and no recovery check, the
    # text as it is in memory, with a notice saying when it has unsaved
    # changes. The caret goes to the position the history remembers, or the
    # top. The document this window already shows stays as it is — opening
    # it again goes nowhere (File → Reload reads it again) — but a link to
    # it still leaves a place on the trail.
    private def join_document(path : String, doc : Document) : Bool
      remember_position
      push_leaving_place
      return true if doc.same?(@document)
      switch_document doc
      if File.exists?(path)
        show_pane(Pane::Viewer).focus unless @viewer.visible?
      else
        show_pane(Pane::Editor).focus
      end
      restore_position
      remember_position
      refresh_status
      notice(doc.text.modified? ? "#{doc.name}: unsaved changes from another window" : "Opened #{path} (also in another window)")
      true
    end

    # Runs *action*, an opening of *path*, through the guard
    # (`#confirm_discard`) — unless *path* is the document this window
    # shows, which the opening does not leave.
    private def confirm_open(path : String, &action : ->) : Nil
      if Documents.find(path).same?(@document)
        action.call
      else
        confirm_discard(&action)
      end
    end

    # Makes a blank new document, as `md` started with no file has (File →
    # Close with nothing ahead on the trail, `app_links.cr`): no name — Save
    # asks for one, the title and the status bar show none — nothing to
    # watch, no recovery file yet (the one of the document left goes,
    # unless another window still shows it), and a stream being followed is
    # left to the other windows on it, if any. The editor is shown and
    # focused to take the text; the other panes stay as they were.
    private def blank_document : Nil
      switch_document Document.new
      show_pane(Pane::Editor).focus
      refresh_status
    end

    # Opens a file dropped on the window. A terminal has no drop of its
    # own: dropping a file pastes its path, as the shell would want it —
    # with spaces backslash-escaped (Terminal.app, iTerm2, kitty), quoted
    # (VTE terminals), or as a `file:` URL (some others) — so a paste that
    # names one existing file, outside the editor (which pastes into its
    # text), opens it, through the unsaved-changes guard. Anything else is
    # not a drop and is let be. Returns whether a file was opened.
    def open_dropped(pasted : String) : Bool
      return false unless path = dropped_path(pasted)
      confirm_open(path) { open_file path }
      true
    end

    # The one file path *pasted* spells, or nil when it does not. A bare
    # path comes shell-escaped — a backslash before each space, quote,
    # parenthesis or other character the shell would read — and the
    # backslashes come off. A single-quoted one (VTE's) spells a quote in
    # the name as `'\''`, closing the quotes around an escaped one.
    private def dropped_path(pasted : String) : String?
      text = pasted.strip
      return if text.empty? || text.includes?('\n')
      if text.starts_with?("file://")
        text = URI.decode(URI.parse(text).path)
      elsif text.size > 1 && text.starts_with?('\'') && text.ends_with?('\'')
        text = text[1...-1].gsub("'\\''", "'")
      elsif text.size > 1 && text.starts_with?('"') && text.ends_with?('"')
        text = text[1...-1]
      else
        text = text.gsub(/\\(.)/) { $1 }
      end
      text if File.file?(text)
    end

    # Re-reads the document's file from disk, keeping the reader's place;
    # unsaved changes are settled first (File → Reload, `Ctrl-R`) — whatever
    # other windows show the document, since the reload drops the changes in
    # all of them. That an undo takes the reload back, changes and all, does
    # not spare the question, as it does not in Qt Creator: an undo is not
    # where a reader looks for changes a reload dropped. A document without
    # a file (new, or streamed) has nothing to reload.
    def reload : Nil
      unless path = source.path
        notice "No file to reload"
        return
      end
      confirm_discard(last_view_only: false) { notice "Reloaded #{path}" if reload_document }
    end

    # Runs *action*, once unsaved changes are out of the way: at once when
    # there are none (or the guard is off), otherwise after the user chose
    # to save them or to drop them — a saved document is one the action can
    # replace. Cancel, or a save that did not happen, leaves everything as it
    # was. With *last_view_only*, an action that only takes this window off
    # the document (an open, a close) asks only when no other window shows
    # it: the changes are not lost while one does.
    def confirm_discard(last_view_only : Bool = true, &action : ->) : Nil
      # Linked windows leave the document together: no window is left on it.
      at_stake = @confirm_discard.value && @document.text.modified? && (!last_view_only || last_view? || link)
      unless at_stake
        action.call
        return
      end
      ask_discard do |answer|
        case answer
        in .save?    then save_then { action.call }
        in .discard? then action.call
        in .cancel?  then nil
        end
      end
    end

    # The answers to the unsaved-changes question.
    enum DiscardAnswer
      Save
      Discard
      Cancel
    end

    # The unsaved-changes question (`#ask_choice`): three buttons in a
    # dialog, or `(y)es, (n)o, (c)ancel` at the prompt; a dismissal is a
    # Cancel. The answer goes to *block*. The question says how many windows
    # show the document when it is more than this one.
    private def ask_discard(&block : DiscardAnswer ->) : Nil
      windows = @document.views.size
      question = "Save changes to #{source.name || "the new document"}#{" (open in #{windows} windows)" if windows > 1}?"
      ask_choice(question, [{"Save", "(y)es"}, {"Don't save", "(n)o"}, {"Cancel", "(c)ancel"}]) do |index|
        block.call(case index
        when 0 then DiscardAnswer::Save
        when 1 then DiscardAnswer::Discard
        else        DiscardAnswer::Cancel
        end)
      end
    end

    # Saves, asking for a name when the document has none, and runs *block*
    # once the document is saved; a save that did not happen (the prompt
    # cancelled, a write error) runs nothing.
    private def save_then(&block : ->) : Nil
      if source.path
        block.call if save
      else
        save_as_prompt { |saved| block.call if saved }
      end
    end

    # Reads the document's file again (`Document#reload`), as an edit of
    # what differs — one undo step, which `Ctrl-Z` takes back — the viewer
    # keeping its place and every window's caret moving with the change as
    # with any edit. The document is then the file's, unmodified, as after a
    # save, so the recovery file of the edits given up goes too
    # (`app_autosave.cr`): left behind, it would announce them as lost at
    # the next open. The other windows on the document catch up on their
    # own render fibers. Returns whether the file could be read; when not,
    # its notice says so and the document stays as it was.
    private def reload_document : Bool
      @document.reload
      @seen_revision = @document.revision
      @viewer.set_markdown markdown, keep_view: true
      @viewer_stale = false
      text_changed
      highlight_matches_everywhere
      refresh_status
      true
    rescue ex : IO::Error
      notice "Cannot reload #{source.path}: #{Md.error_text(ex)}"
      false
    end

    # Records the document's file and the caret's place in the history, if
    # there is a file and a history: the editor's caret while editing, the
    # source of the viewer's while reading.
    def remember_position : Nil
      return unless (history = @history) && (path = source.path)
      line, column = source_position
      history.touch path, line, column, !@editor.focused?
      refresh_recent_menus
    end

    # Where the reader is, as a 1-based source line and column: the editor's
    # caret while editing, the source of the viewer's while reading — what
    # the history and the Previous File stack (`app_links.cr`) record, and
    # `#go_to_line` takes back.
    protected def source_position : {Int32, Int32}
      pos = @editor.focused? ? @editor.cursor_position : editor_position(@viewer.cursor_position)
      cursor = Crysterm::TextCursor.new(@document.text, pos)
      {cursor.block_number + 1, cursor.column_number + 1}
    end

    # Puts the panes where the history remembers the document's file, when
    # it does.
    private def restore_position : Nil
      return unless (history = @history) && (path = source.path)
      return unless entry = history.entry(path)
      go_to_line entry.line, entry.column if entry.line > 1 || entry.column > 1
    end

    # Writes the history, with the current position in it.
    def save_history : Nil
      return unless history = @history
      remember_position
      history.save if history.dirty?
    end

    # File → Open Recent's entry for *path*: opened through the guard, or,
    # when the file is gone from disk, taken off the list with a notice
    # (`#reopenable?`).
    private def open_recent(path : String) : Nil
      if reopenable?(path)
        confirm_open(path) { open_file path }
      elsif (history = @history) && history.forget(path)
        history.save
        refresh_recent_menus
      end
    end

    # Rebuilds File → Open Recent in every window keeping this window's
    # history (`#refresh_recent_menu`): the windows share it, so a file
    # opened, or the list cleared, in one shows in the others' menus too.
    private def refresh_recent_menus : Nil
      refresh_recent_menu
      return unless history = @history
      App.instances.each { |app| app.refresh_recent_menu if !app.same?(self) && app.history.same?(history) }
    end

    # Rebuilds File → Open Recent from the history: the files most recently
    # used first, the current one included, each opening on activation.
    protected def refresh_recent_menu : Nil
      return unless (history = @history) && (action = @recent_action)
      entries = history.recent
      actions = entries.map do |entry|
        a = Crysterm::Action.new literal_label(entry.path)
        a.on(Crysterm::Event::Triggered) { open_recent entry.path }
        tip a, "Open this file again, at the place left in it"
      end
      action.menu = actions
      action.enabled = !actions.empty?
    end
  end
end
