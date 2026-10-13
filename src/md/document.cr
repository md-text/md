module Md
  # md's own events, emitted by a `Document` to the windows showing it.
  module Event
    include ::EventHandler

    # The text was edited (by a key, an undo, Format, Replace, Neovim…) in
    # any window: *revision* is the document's after the edit. Not emitted
    # for a programmatic replace (`DocumentReset`).
    event DocumentEdited, revision : Int64

    # The text was replaced as a whole — a reload from disk — at *revision*;
    # the carets were kept, clamped.
    event DocumentReset, revision : Int64

    # The document has another name: a Save As, or an unnamed document saved
    # for the first time.
    event DocumentRenamed

    # A notice about the document rather than about an action a window took
    # — the file changed or removed on disk, an auto-save that failed — for
    # every window showing it.
    event DocumentNotice, text : String

    # A *chunk* of a document streaming in on standard input arrived; each
    # window appends it to its viewer.
    event StreamAppended, chunk : String

    # The stream ended, cut short by an error with *message*, or at its end
    # when nil.
    event StreamEnded, message : String?
  end

  # One open text and everything that belongs to the text rather than to a
  # window (Qt Creator's `Core::IDocument`, Kate's `KTextEditor::Document`):
  # the Markdown source — a `Crysterm::TextDocument`, with its undo history
  # and its modified flag — the file it is read from and saved to, the
  # watcher that follows the file (View → Watch File), and the auto-save
  # and recovery file that guard its unsaved edits (`app_autosave.cr`).
  #
  # Each md window (`App`) is a view on one document: its editor edits the
  # document's text, and its viewer and table of contents are rendered from
  # it. Window → New shows the same document in another window, and so does
  # opening a file another window has open (`Documents`), so an edit made
  # in one window is in every window on the document, one undo takes back
  # the last edit whichever window made it, and the document is modified,
  # saved or reloaded for all of them at once.
  #
  # The views are the reference count: a document lives while a window
  # shows it, and the last one leaving closes it — the watcher and the timer
  # stop, a recovery file goes when the session ended the way the user meant
  # it to, and the registry forgets it. What runs on a window's render fiber
  # (the watcher's events, the auto-save ticks) runs on the first view's,
  # the host's, and moves on when the host leaves.
  #
  # A document read from standard input streams in (`#start_stream`): a
  # reader fiber takes the lines as they come and hands them to the host's
  # render fiber, or to the next window's when the host's is gone, so the
  # stream outlives the window that started it; every window on the
  # document appends the chunk to its own viewer (`Event::StreamAppended`).
  # The text is filled from what arrived only when a window first shows its
  # editor (`#fill`), so a long stream into hidden editors costs nothing per
  # chunk. The last window leaving abandons the stream.
  #
  # Edits reach the views through the text's `ContentsChanged`, the one
  # signal every edit sends, whichever view made it: the document counts
  # them (`#revision`) and tells the views (`Event::DocumentEdited`), each of
  # which brings its viewer, search highlights and status up to date on its
  # own render fiber, at most once a frame (`App#document_changed`).
  class Document
    include ::EventHandler

    # How often a watched file is polled, unless the host's
    # `App#watch_interval` says otherwise (specs shorten it).
    WATCH_INTERVAL = 1.second

    # The Markdown source: its text, undo history and modified flag.
    getter text : Crysterm::TextDocument

    # Where the document comes from: its file as given (typed, or expanded
    # by File → Open), standard input, or neither.
    getter source : Source

    # The canonical path the registry knows the document by
    # (`Documents.key_for`); nil for a document without a file.
    getter key : String?

    # The windows showing the document, the first being the host.
    getter views = [] of App

    # The group of linked windows on the document (Window → Linking →
    # Linked), nil while windows are separate.
    property link : ViewLink?

    # The Neovim the linked windows on the document share in Vi Mode, one
    # buffer for all of them (`#ensure_vi`); nil while none runs.
    getter vi : Crysterm::Neovim::Handler?

    # Set while the text is replaced programmatically (a load, a reload, a
    # stream filling it), so the resulting change is not taken for an edit.
    getter? loading = false

    # Counts the edits — and the resets — since the document was made: a
    # view that has caught up with revision N has nothing to do for it.
    getter revision : Int64 = 0_i64

    # View → Watch File, the document's (every window on it shows the same
    # check); `#setup_watcher` follows it.
    getter watch_file : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    # Each view's number while two or more windows show the document
    # (`README.md:1`, `README.md:2`): the lowest free one, kept while the view
    # stays.
    @numbers = {} of App => Int32

    @watcher : Crysterm::FileWatcher?
    @autosave_timer : Crysterm::Timer?
    # Set by every edit, cleared by every auto-save: the timer writes only
    # when there is something new to write.
    @autosave_dirty = false
    # The recovery file on disk, so a save, a reload or the end can remove
    # it; nil while there is none.
    @recovery_path : String?
    # Whether the last auto-save failed, so the notice is given once rather
    # than every interval.
    @autosave_failed = false

    # The text received from the stream, which the text is filled from when
    # an editor is first shown (`#fill`).
    @streamed = IO::Memory.new
    # Whether the text has yet to be filled from the stream.
    getter? editor_stale = false
    # Whether the document is streaming in.
    getter? streaming = false
    # Whether the document was read from a stream at all (`#start_stream`):
    # a chunk handed to any other document is not its to take.
    getter? from_stream = false
    # Set once the last window left a stream, so the lines the reader still
    # brings are dropped (the read itself cannot be stopped).
    @stream_abandoned = false
    # The lines the reader brought that no window has taken in yet, and the
    # end of the stream once read (with the error message that cut it short,
    # or nil): kept here, not in the job posted for them, so a job dropped
    # with a window destroyed before it ran loses nothing — the next job,
    # in whichever window, takes them (`#drain_stream`).
    @stream_pending = Deque(String).new
    @stream_end : Tuple(String?)? = nil
    # Whether the stream brought bytes that were not UTF-8 yet, so the
    # notice is given once, not for every line holding some.
    @stream_scrubbed = false

    # The window on whose render fiber the stream's chunk or end is being
    # taken in just now (`#receive`, `#finish_stream`): its handlers of
    # `Event::StreamAppended` and `Event::StreamEnded` run at once, the
    # other windows' are posted to their own fibers. Nil at other times.
    getter receiver : App?

    # A document of *source* holding *text*, unmodified, with no undo
    # history.
    def initialize(@source : Source = Source.new, text : String = "")
      @text = Crysterm::TextDocument.new text
      @key = @source.path.try { |path| Documents.key_for path }
      @text.on(Crysterm::Event::ContentsChanged) { |e| contents_changed e }
      @watch_file.on_change { setup_watcher }
    end

    # The document's Markdown source: what the stream brought while the text
    # has yet to be filled from it, the text otherwise.
    def markdown : String
      @editor_stale ? @streamed.to_s : @text.to_plain_text
    end

    # The document's name for windows and notices: the file's name without
    # its directory, `stdin` for a stream, or `[No Name]`.
    def name : String
      if path = @source.path
        File.basename path
      else
        @source.name || "[No Name]"
      end
    end

    # The window whose render fiber runs the document's watcher and
    # auto-save timer: the first view.
    def host : App?
      @views.first?
    end

    # *app*'s number among the views (`README.md:2`), or nil while it is the
    # only one.
    def number(app : App) : Int32?
      @numbers[app]? if @views.size > 1
    end

    # Adds *app* as a view (from its constructor, or a switch to this
    # document). The first view registers the document and hosts its watcher
    # and timer.
    def attach(app : App) : Nil
      return if @views.includes?(app)
      @views << app
      taken = @numbers.values
      @numbers[app] = (1..).find! { |number| !taken.includes?(number) }
      if @views.size == 1
        Documents.add self
        rehost
      end
    end

    # Takes *app* off the views (its window is gone, or shows another
    # document now). The last view leaving closes the document — dropping
    # the recovery file when *clean*, the session having ended the way the
    # user meant it to — and the host leaving hands the watcher and the timer
    # to the next view. What the stream brought and no window took in yet
    # — its job may have gone with the window — goes to the views left.
    def detach(app : App, clean : Bool = true) : Nil
      return unless index = @views.index(&.same?(app))
      @views.delete_at index
      @numbers.delete app
      if @views.empty?
        close clean
        return
      end
      rehost if index == 0
      deliver unless @stream_pending.empty? && @stream_end.nil?
    end

    # The end of the net, the session having ended the way the user meant
    # it to: the timer stops and the recovery file goes (from `App#finish`,
    # once every window on the document has ended, as a quit may exit
    # without the windows leaving it).
    def finish_autosave : Nil
      stop_autosave
      drop_recovery
    end

    # The end of the document: the shared Neovim ends, the stream is
    # abandoned, the watcher and the timer stop, the recovery file goes when
    # *clean*, and the registry forgets it.
    private def close(clean : Bool) : Nil
      @vi.try &.detach
      @vi = nil
      @stream_abandoned = true
      @streaming = false
      @stream_pending.clear
      @stream_end = nil
      stop_watcher
      stop_autosave
      drop_recovery if clean
      Documents.forget self
    end

    # Puts the watcher and the auto-save timer on the host's window.
    private def rehost : Nil
      setup_watcher
      setup_autosave
    end

    # Puts *editor* on the document's shared Neovim (Vi Mode in linked
    # windows): started with *args* and attached to *editor* when none runs,
    # else joined as another view of its buffer
    # (`Neovim::Handler#add_view`). Returns whether Neovim drives the
    # editor now.
    def ensure_vi(editor : Crysterm::Widget::PlainTextEdit, args : Array(String)) : Bool
      if (handler = @vi) && handler.attached?
        return handler.add_view(editor)
      end
      handler = Crysterm::Neovim::Handler.new
      handler.args = args
      return false unless handler.attach(editor)
      @vi = handler
      true
    end

    # Takes *editor* off the shared Neovim, if it is one of its views; the
    # last view leaving ends it.
    def release_vi(editor : Crysterm::Widget) : Nil
      return unless handler = @vi
      handler.remove_view editor if handler.views.includes?(editor)
      @vi = nil unless handler.attached?
    end

    # Replaces the text as a whole, programmatically (a reload): not an
    # edit (no undo entry, no `DocumentEdited`), the undo history cleared,
    # the document unmodified. Every view's caret stays where it was,
    # clamped to the new text, and the views are told
    # (`Event::DocumentReset`).
    def replace(text : String) : Nil
      carets = @views.map { |view| {view, view.editor.cursor_position} }
      @loading = true
      begin
        @text.set_plain_text text
      ensure
        @loading = false
      end
      carets.each { |view, caret| view.editor.cursor_position = caret.clamp(0, @text.size) }
      @revision += 1
      emit Md::Event::DocumentReset, @revision
    end

    # Runs the block as a programmatic change of the text (an append from a
    # stream): no `DocumentEdited`, no auto-save, and the modified flag kept
    # as it was.
    def loading(&) : Nil
      was_modified = @text.modified?
      @loading = true
      begin
        yield
      ensure
        @loading = false
        @text.modified = was_modified
      end
    end

    # Every change of the text: an edit (not a load) is counted, marks the
    # document for the next auto-save and goes to the views. A change of
    # formats only is no edit of the source.
    private def contents_changed(e : Crysterm::Event::ContentsChanged) : Nil
      return if @loading || e.kind.format?
      @editor_stale = false
      @revision += 1
      @autosave_dirty = true
      emit Md::Event::DocumentEdited, @revision
    end

    # Reads *io* on a fiber of its own, line by line, handing the lines to
    # `#receive` on a window's render fiber — the host's, or the next
    # window's when the host's is destroyed (`Window#post?`) — and ending
    # with `#finish_stream`. The lines wait in the document until a window
    # takes them (`#drain_stream`), so a window destroyed with them still
    # queued loses none, and a window busy while many came takes them in
    # one chunk. The read stops at the next line once no window is
    # left. The windows' viewers follow the tail (`App#stream`).
    def start_stream(io : IO) : Nil
      @from_stream = @streaming = @editor_stale = true
      spawn name: "md-stream" do
        message = nil
        begin
          io.each_line(chomp: false) do |line|
            break if @stream_abandoned
            @stream_pending << line
            break unless deliver
          end
        rescue ex : IO::Error
          message = ex.message
        end
        unless @stream_abandoned
          @stream_end = {message}
          deliver
        end
      end
    end

    # Posts `#drain_stream` to the render fiber of the first view whose
    # window takes it; false when none does (no view left, or the stream
    # abandoned).
    private def deliver : Bool
      return false if @stream_abandoned
      @views.any? { |view| view.window.post? { drain_stream view } }
    end

    # Takes in, on *view*'s render fiber, what the stream brought that no
    # window took in yet: the lines, joined into one chunk (`#receive`) —
    # one append to each viewer and one status refresh for a backlog, not
    # one a line, which made a fast stream ten times slower — then the end,
    # once read (`#finish_stream`). A job finding nothing left — an earlier
    # one took it — does nothing.
    private def drain_stream(view : App) : Nil
      unless @stream_pending.empty?
        chunk = @stream_pending.size == 1 ? @stream_pending.first : @stream_pending.join
        @stream_pending.clear
        receive chunk, view
      end
      if ended = @stream_end
        @stream_end = nil
        finish_stream ended[0], view
      end
    end

    # Takes a streamed *chunk* of Markdown into the document — into the text
    # too when it was filled — and hands it to every window
    # (`Event::StreamAppended`), at once in *by*, on whose render fiber it
    # arrived (`#receiver`). Bytes that are not UTF-8 are replaced, with a
    # notice the first time. A chunk after the stream was abandoned is
    # dropped.
    def receive(chunk : String, by : App? = nil) : Nil
      return if @stream_abandoned
      unless (decoded = Source.decode chunk).same?(chunk)
        notify "Invalid UTF-8 in #{name} replaced by �" unless @stream_scrubbed
        @stream_scrubbed = true
        chunk = decoded
      end
      @streamed << chunk
      loading { Crysterm::TextCursor.new(@text, @text.size).insert_text chunk } unless @editor_stale
      received_by(by) { emit Md::Event::StreamAppended, chunk }
    end

    # The end of the stream, with the error *message* that cut it short:
    # every window is told (`Event::StreamEnded`), at once in *by*, on whose
    # render fiber it arrived.
    def finish_stream(message : String? = nil, by : App? = nil) : Nil
      return if @stream_abandoned
      @streaming = false
      received_by(by) { emit Md::Event::StreamEnded, message }
    end

    # Runs the block with *by* as the `#receiver`.
    private def received_by(by : App?, &) : Nil
      @receiver = by
      begin
        yield
      ensure
        @receiver = nil
      end
    end

    # Fills the text from the stream, for *by*'s editor, now shown (a
    # programmatic replace, no edit; *by*'s caret at the end, as a load
    # leaves it). The other windows' editors show it too; their viewers
    # already do.
    def fill(by : App) : Nil
      return unless @editor_stale
      @loading = true
      begin
        by.editor.plain_text = @streamed.to_s
      ensure
        @loading = false
      end
      @editor_stale = false
    end

    # Saves to *path* (`#save`) and makes it the document's file: its key
    # taken up in the registry, the watcher moved to the new file, the
    # recovery file of the old name gone and every view told
    # (`Event::DocumentRenamed`). A save that fails (a directory that is not
    # there, no permission) raises `IO::Error` and leaves the document its
    # old name, as Qt's editors set the current file only once written.
    def save_as(path : String, backup : Bool) : String?
      previous, old = @source, @key
      @source = Source.new path: path
      @key = Documents.key_for path
      begin
        failure = save(backup)
      rescue ex
        @source, @key = previous, old
        raise ex
      end
      Documents.rekey self, old
      setup_watcher
      emit Md::Event::DocumentRenamed
      failure
    end

    # Writes the text to the document's file, the file's previous contents
    # kept as `FILE~` the first time in the session when *backup*. The
    # document is then unmodified for every view, its recovery file gone,
    # and its key the file's real path (a new file has one now). Returns
    # what went wrong with the backup, for the save's notice, or nil; raises
    # `IO::Error` when the file cannot be written, the document left as it
    # was.
    def save(backup : Bool) : String?
      path = @source.path || raise ArgumentError.new("the document has no file")
      failure = Documents.backup(path) if backup
      SaveFile.write path, markdown
      @text.modified = false
      autosave_settled
      unless (key = Documents.key_for(path)) == @key
        old, @key = @key, key
        Documents.rekey self, old
      end
      failure
    end

    # Writes the text to *path*, a copy (`:w FILE`): the document keeps its
    # name, its file and its unsaved state. Raises `IO::Error` when the copy
    # cannot be written.
    def write_copy(path : String) : Nil
      SaveFile.write path, markdown
    end

    # Reads the document's file again, as a reset (`#replace`): the edits
    # given up go, the undo history with them, every view keeping its place;
    # the recovery file of those edits goes too, as after a save. Raises
    # `IO::Error` when the file cannot be read, the document left as it was.
    def reload : Nil
      path = @source.path || raise ArgumentError.new("the document has no file")
      replace Source.decode(File.read(path))
      autosave_settled
    end

    # Tells every view *text* (`Event::DocumentNotice`).
    def notify(text : String) : Nil
      emit Md::Event::DocumentNotice, text
    end

    # Points the watcher at the document's file, on the host's window, or
    # takes it down: run when the file, the setting or the host changes.
    def setup_watcher : Nil
      stop_watcher
      path = @source.path
      return unless @watch_file.value && path && (host = self.host)
      watcher = Crysterm::FileWatcher.new host.watch_interval, window: host.window
      watcher.on(Crysterm::Event::FileChanged) { |e| file_changed e.path }
      watcher.add_path path
      @watcher = watcher
    end

    # Whether the file is being watched (the status bar says so).
    def watching? : Bool
      !@watcher.nil?
    end

    private def stop_watcher : Nil
      @watcher.try &.stop
      @watcher = nil
    end

    # The watched file changed on disk: reload it, unless the text on disk
    # is what the document already holds (our own save) or the document
    # holds unsaved changes, which are kept with a notice. A file removed is
    # said so, its text kept to be saved again; it is reloaded if it comes
    # back. A change the watcher posted before Watch File was turned off,
    # or before the document closed, is let be. On the host's render fiber;
    # every view hears of it.
    private def file_changed(path : String) : Nil
      return if @views.empty? || !@watch_file.value || path != @source.path
      unless File.exists?(path)
        notify "#{path} was removed from disk; the text is kept"
        return
      end
      if @text.modified?
        notify "#{path} changed on disk; unsaved changes kept"
        return
      end
      return if Source.decode(File.read(path)) == markdown
      reload
      notify "Reloaded #{path} (changed on disk)"
    rescue IO::Error
      # A file mid-rewrite; the next change is polled.
    end

    # Starts the auto-save timer on the host's settings, or takes it down:
    # run when a host's setting or interval changes and when the host does.
    # The tick is posted to the host's render fiber, where the text is read;
    # a tick still queued when its timer is stopped or replaced is dropped
    # there, so nothing is written after the document closed.
    def setup_autosave : Nil
      stop_autosave
      return unless (host = self.host) && host.autosave?
      timer = Crysterm::Timer.new host.autosave_interval, immediate: false
      timer.on_tick do
        self.host.try &.window.post { autosave_tick if @autosave_timer.same?(timer) }
      end
      @autosave_timer = timer.start
    end

    # Whether the auto-save timer runs.
    def autosaving? : Bool
      !@autosave_timer.nil?
    end

    private def stop_autosave : Nil
      @autosave_timer.try &.stop
      @autosave_timer = nil
    end

    # The timer's look at the text: unsaved edits since the last look are
    # written to the recovery file.
    private def autosave_tick : Nil
      return unless (host = self.host) && host.autosave? && @autosave_dirty && @text.modified?
      write_recovery
    end

    # Makes the next tick write the document, whose recovery file went
    # (Options → Clear Caches…).
    def mark_for_autosave : Nil
      @autosave_dirty = true
    end

    # The recovery file the document is (or would be) written to: the
    # escaped path of a named document, or a name of its own for one
    # without (`Documents.unnamed_recovery_name`).
    def recovery_path : String
      @recovery_path ||= File.join(App.autosave_dir, @source.path.try { |path| App.recovery_name path } || Documents.unnamed_recovery_name)
    end

    # Whether the document's recovery file is called *name* (so another
    # unnamed document takes another).
    def recovery_name_taken?(name : String) : Bool
      @recovery_path.try { |path| File.basename(path) == name } || false
    end

    # Writes the text to the recovery file whole (`SaveFile`), so a crash
    # mid-write leaves the previous copy intact. A failure is told to every
    # view, once until a write works again.
    private def write_recovery : Nil
      path = recovery_path
      Dir.mkdir_p File.dirname(path)
      SaveFile.write path, markdown
      @autosave_dirty = false
      @autosave_failed = false
    rescue ex : IO::Error
      notify "Cannot auto-save to #{path}: #{Md.error_text(ex)}" unless @autosave_failed
      @autosave_failed = true
    end

    # The document is on disk as the user wants it (a save, a reload): the
    # recovery file has nothing to add and goes.
    private def autosave_settled : Nil
      @autosave_dirty = false
      drop_recovery
    end

    # Removes the recovery file, if one was written: the document is saved,
    # reloaded, renamed or closed.
    def drop_recovery : Nil
      if path = @recovery_path
        @recovery_path = nil
        File.delete? path
      end
    rescue IO::Error
      # A recovery file that will not go is still only a copy.
    end

    # The notice for a recovery file newer than the document's file (or a
    # file that is not there): a session ended badly and the copy holds its
    # edits. For a new document without a name, the directory is looked at
    # for unnamed copies left behind. Nil when there is nothing to say. Run
    # when a document is first read from disk, never when a window joins it.
    def check_recovery : String?
      if path = @source.path
        copy = File.join(App.autosave_dir, App.recovery_name(path))
        return unless info = File.info?(copy)
        return if (file = File.info?(path)) && file.modification_time >= info.modification_time
        "Recovered copy from #{info.modification_time.to_local.to_s("%Y-%m-%d %H:%M")} exists: #{copy}"
      elsif !@source.stdin?
        copies = Dir.glob(File.join(App.autosave_dir, "unnamed-*.md"))
        return if copies.empty?
        "#{copies.size == 1 ? "Recovered copy exists" : "#{copies.size} recovered copies exist"} in #{App.autosave_dir}"
      end
    rescue IO::Error
      # A directory that cannot be read has no copies to offer.
    end
  end
end
