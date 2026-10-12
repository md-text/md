module Md
  class App
    # The document's file, beyond saving: opening another (File → Open…,
    # `Ctrl-O`, asked for like Save As, `app_dialogs.cr`), re-reading it
    # from disk (File → Reload,
    # `Ctrl-R`) and following it as other programs rewrite it (View → Watch
    # File, `--watch`), the guard that asks before unsaved changes are lost,
    # and the history of recent files and positions (`History`, File → Open
    # Recent).
    #
    # The guard (`#confirm_discard`) sits in front of quitting, opening and
    # reloading: with changes unsaved it asks — Save, Don't save or Cancel —
    # and the action goes ahead only on an answer that settles the changes.
    # Quitting asks through Crysterm's close request (`Event::CloseRequest`,
    # which the default `q`/`Ctrl-Q` keys honor), so File → Quit and the
    # keys take the same path. Options → Ask Before Discarding Changes turns
    # the guard off for those who save by habit.
    #
    # Watching polls the file (`Crysterm::FileWatcher`) and reloads it when
    # its contents changed on disk — unless the editor holds unsaved changes,
    # in which case a notice says the file changed and the changes are kept.
    # The viewer keeps its place through a reload, so `md --watch notes.md`
    # beside an editor shows each save where the reader was.

    # How often a watched file is polled, unless `#watch_interval` says.
    WATCH_INTERVAL = 1.second

    # The polling interval of the watcher started next (specs shorten it).
    property watch_interval : Time::Span = WATCH_INTERVAL

    # Options → Ask Before Discarding Changes. A reactive property, so the
    # menu entry binds to it.
    @confirm_discard : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)
    # View → Watch File. Likewise; `#watch_file=` is its plain face.
    @watch_file : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @watcher : Crysterm::FileWatcher?
    # Set once a stream is abandoned for a file opened over it, so chunks
    # still arriving from standard input no longer land in the document.
    @stream_abandoned = false
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

    # Starts or stops following the document's file (View → Watch File). It
    # takes effect through the property's change handler (`#setup_file`).
    def watch_file=(value : Bool) : Bool
      @watch_file.value = value
    end

    # Quits: closes every window (`app_windows.cr`), each through its own
    # guard — the window asks its handlers (`Window#try_close`) and ours
    # asks the user when changes are unsaved, closing after their answer, so
    # a window with changes stays until its question is answered. The last
    # window's close ends the loop. With one window, the one question.
    def quit : Nil
      App.instances.dup.each &.close_window
    end

    # Asks for a file to open (`#ask_text`; a line prompt completes the
    # name) and opens the answer; unsaved changes are settled first.
    def open_prompt : Nil
      confirm_discard do
        ask_text("Open: ", "") do |answer|
          path = answer.try &.strip
          open_file path if path && !path.empty?
        end
      end
    end

    # Makes *path* the document: an existing file is read and shown in the
    # viewer (shown and focused if it was hidden), a file that does not exist
    # yet is a new, empty document in the editor (shown and focused). A
    # stream being followed is abandoned. The position remembered for the
    # file, if any, is restored. Returns whether the file could be opened.
    def open_file(path : String) : Bool
      path = File.expand_path path
      text = File.exists?(path) ? File.read(path) : nil
      remember_position
      leave_document
      abandon_stream
      drop_recovery
      @source = Source.new path: path
      @window.title = title
      apply_base_url
      load text || ""
      @editor.document.modified = false
      text_changed
      if text
        show_pane(Pane::Viewer).focus unless @viewer.visible?
      else
        show_pane(Pane::Editor).focus
      end
      restore_position
      remember_position # the file just opened leads the recent list
      setup_file
      refresh_status
      notice(text ? "Opened #{path}" : "New file #{path}")
      check_recovery
      true
    rescue ex : IO::Error
      notice "Cannot open #{path}: #{ex.message}"
      false
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
      confirm_discard { open_file path }
      true
    end

    # The one file path *pasted* spells, or nil when it does not.
    private def dropped_path(pasted : String) : String?
      text = pasted.strip
      return if text.empty? || text.includes?('\n')
      if text.starts_with?("file://")
        text = URI.decode(URI.parse(text).path)
      elsif (text.starts_with?('\'') && text.ends_with?('\'')) || (text.starts_with?('"') && text.ends_with?('"'))
        text = text[1...-1]
      else
        text = text.gsub("\\ ", " ")
      end
      text if File.file?(text)
    end

    # Re-reads the document's file from disk, keeping the reader's place;
    # unsaved changes are settled first (File → Reload, `Ctrl-R`). A document
    # without a file (new, or streamed) has nothing to reload.
    def reload : Nil
      unless path = @source.path
        notice "No file to reload"
        return
      end
      confirm_discard do
        reload_from path
        notice "Reloaded #{path}"
      end
    end

    # Runs *action*, once unsaved changes are out of the way: at once when
    # there are none (or the guard is off), otherwise after the user chose
    # to save them or to drop them — a saved document is one the action can
    # replace. Cancel, or a save that did not happen, leaves everything as it
    # was.
    def confirm_discard(&action : ->) : Nil
      unless @confirm_discard.value && @editor.document.modified?
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
    # Cancel. The answer goes to *block*.
    private def ask_discard(&block : DiscardAnswer ->) : Nil
      question = "Save changes to #{@source.name || "the new document"}?"
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
      if @source.path
        block.call if save
      else
        save_as_prompt { |saved| block.call if saved }
      end
    end

    # Reads *path* into the document as a reset — no undo entry, the viewer
    # keeping its place, the editor's caret where it was (clamped).
    private def reload_from(path : String) : Nil
      text = File.read path
      caret = @editor.cursor_position
      @loading = true
      @editor.plain_text = text
      @loading = false
      @editor.cursor_position = caret.clamp(0, @editor.document.size)
      @viewer.set_markdown text, keep_view: true
      @viewer_stale = false
      @editor_stale = false
      @editor.document.modified = false
      text_changed
      highlight_matches_everywhere
      refresh_status
    rescue ex : IO::Error
      notice "Cannot reload #{path}: #{ex.message}"
    end

    # Points the watcher at the document's file, or takes it down: run when
    # the file or the setting changes.
    private def setup_file : Nil
      @watcher.try &.stop
      @watcher = nil
      path = @source.path
      return unless @watch_file.value && path
      watcher = Crysterm::FileWatcher.new @watch_interval, window: @window
      watcher.on(Crysterm::Event::FileChanged) { |e| file_changed e.path }
      watcher.add_path path
      @watcher = watcher
    end

    # The watched file changed on disk: reload it, unless the text on disk
    # is what the editor already holds (our own save) or the editor holds
    # unsaved changes, which are kept with a notice.
    private def file_changed(path : String) : Nil
      return unless path == @source.path
      if @editor.document.modified?
        notice "#{path} changed on disk; unsaved changes kept"
        return
      end
      return if File.exists?(path) && File.read(path) == markdown
      reload_from path
      notice "Reloaded #{path} (changed on disk)"
    rescue IO::Error
      # A file mid-rewrite; the next change is polled.
    end

    # Stops taking the stream's chunks into the document, once a file was
    # opened over it (the reader fiber cannot be stopped; its chunks are
    # dropped).
    private def abandon_stream : Nil
      return unless @streaming
      @stream_abandoned = true
      @streaming = false
      @viewer.follow_tail = false
    end

    # Records the document's file and the caret's place in the history, if
    # there is a file and a history: the editor's caret while editing, the
    # source of the viewer's while reading.
    def remember_position : Nil
      return unless (history = @history) && (path = @source.path)
      line, column = source_position
      history.touch path, line, column, !@editor.focused?
      refresh_recent_menu
    end

    # Where the reader is, as a 1-based source line and column: the editor's
    # caret while editing, the source of the viewer's while reading — what
    # the history and the Previous File stack (`app_links.cr`) record, and
    # `#go_to_line` takes back.
    private def source_position : {Int32, Int32}
      pos = @editor.focused? ? @editor.cursor_position : editor_position(@viewer.cursor_position)
      cursor = Crysterm::TextCursor.new(@editor.document, pos)
      {cursor.block_number + 1, cursor.column_number + 1}
    end

    # Puts the panes where the history remembers the document's file, when
    # it does.
    private def restore_position : Nil
      return unless (history = @history) && (path = @source.path)
      return unless entry = history.entry(path)
      go_to_line entry.line, entry.column if entry.line > 1 || entry.column > 1
    end

    # Writes the history, with the current position in it.
    def save_history : Nil
      return unless history = @history
      remember_position
      history.save if history.dirty?
    end

    # Rebuilds File → Open Recent from the history: the files most recently
    # used first, the current one included, each opening on activation.
    private def refresh_recent_menu : Nil
      return unless (history = @history) && (action = @recent_action)
      entries = history.recent
      actions = entries.map do |entry|
        a = Crysterm::Action.new entry.path
        a.on(Crysterm::Event::Triggered) { confirm_discard { open_file entry.path } }
        tip a, "Open this file again, at the place left in it"
      end
      action.menu = actions
      action.enabled = !actions.empty?
    end
  end
end
