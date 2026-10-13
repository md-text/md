module Md
  class App
    # Windows: several md windows in one process, each a terminal window of
    # its own — the Window menu, after `QMdiArea`'s. Window → New (`Ctrl-N`)
    # asks Crysterm for another terminal window (`Crysterm::Window.open`: the
    # emulator md runs in is told to open one — kitty, Terminal.app, a tmux
    # window inside tmux…, `Crysterm::Terminal`) and builds a second `App`
    # on it, a second view on this window's document (`Document`), the way
    # Qt Creator, Kate and Emacs show one buffer in two windows: the text is
    # one, so an edit in either window is in both, one undo history takes
    # back the last edit whichever window made it, and the document is
    # modified, saved, watched and auto-saved for both at once. Each window
    # keeps its own caret, scroll, panes and search, unless windows are
    # linked (Window → Linking, `app_linking.cr`); the new one starts where
    # this one is. A document still streaming in streams into both,
    # and on after the window that started it closes.
    #
    # Windows on one document are named `README.md:1`, `README.md:2` in their
    # titles and in the Window menu (`#window_name`), plain `README.md` again
    # once one is left. Closing a window asks about unsaved changes only when
    # it is the last on its document; quitting asks once per document, in
    # the last window on it, as Qt's `QApplication::closeAllWindows` does.
    # The history and the settings are shared and written by whichever
    # window ends last (`#finish`).
    #
    # The new window joins the running application (`Application#show`), so
    # the loop runs until the last window is gone: Window → Close Current
    # (`Ctrl-W`) closes one window through its guard (`Window#try_close`),
    # and in the last window is Quit. File → Quit (`Ctrl-Q`, `q`) closes
    # every window, each through its own guard. The menu lists the open
    # windows by title, this one checked; picking another activates it, which
    # raises it when the two share a terminal (a tmux window does not, and a
    # notice says where it is). Where no window can be opened — no display
    # and no multiplexer, or no emulator Crysterm knows how to drive — New
    # Window is disabled and its key says why.

    # Every `App` alive in this process, in creation order: what the Window
    # menus list. An app leaves it when its window is destroyed.
    class_getter instances = [] of App

    # The Window menu and its two fixed entries (`#build_window_menu`); the
    # list after the separator is remade by `#refresh_window_menu`.
    @window_menu : Crysterm::Widget::Menu?
    @new_window_action : Crysterm::Action?
    @window_entries = [] of Crysterm::Action

    # How Window → New opens a terminal window, given the title and the
    # frame to put it at (nil: where the window manager puts it; Window →
    # Remember Positions, `window_places.cr`): Crysterm's `Window.open`,
    # which picks the emulator. Replaceable, so a spec can hand out headless
    # windows — and a replacement is taken to work wherever it runs, so the
    # entry is enabled (`#window_opener=`).
    @window_opener : Proc(String, WindowPlaces::Frame?, Crysterm::Window) = ->(title : String, frame : WindowPlaces::Frame?) { Crysterm::Window.open(title: title, frame: frame) }

    def window_opener : Proc(String, WindowPlaces::Frame?, Crysterm::Window)
      @window_opener
    end

    def window_opener=(opener : Proc(String, WindowPlaces::Frame?, Crysterm::Window)) : Proc(String, WindowPlaces::Frame?, Crysterm::Window)
      @window_opener = opener
      self.window_refusal = nil
      opener
    end

    # An opener given the title alone, which places nothing.
    def window_opener=(opener : Proc(String, Crysterm::Window)) : Proc(String, Crysterm::Window)
      self.window_opener = ->(title : String, _frame : WindowPlaces::Frame?) { opener.call(title) }
      opener
    end

    # Why no window can be opened here, in a sentence, or nil when one can:
    # Window → New's enabled state, and what its key says while disabled. Found
    # once per process (`.window_refusal`) — the session does not change —
    # and settable, so a spec can see the disabled entry anywhere.
    @window_refusal : String?

    def window_refusal : String?
      @window_refusal
    end

    def window_refusal=(reason : String?) : String?
      @window_refusal = reason
      refresh_window_menu
      reason
    end

    @@window_refusal : String?
    @@window_refusal_known = false

    # Crysterm's verdict on opening a window from this session, found the
    # first time it is asked for.
    def self.window_refusal : String?
      unless @@window_refusal_known
        @@window_refusal = Crysterm::Terminal.window_refusal
        @@window_refusal_known = true
      end
      @@window_refusal
    end

    # Takes this app out of the process when its window goes: out of the
    # list, its end saved (`#finish`), its document left, every window's
    # list remade. Subscribed in `#initialize` before the window becomes a
    # view on its document, so a constructor that fails after that, its
    # window destroyed by the caller (Window → New), leaves no view behind.
    private def watch_destroy : Nil
      @window.on(Crysterm::Event::Destroy) do
        App.instances.delete self
        forget_active
        finish
        leave_document
        App.refresh_window_menus
      end
    end

    # Puts this app in the process's list and remakes every window's list
    # (from `#initialize`, once the menus exist); `#watch_destroy` takes it
    # out again.
    private def register_window : Nil
      @window_refusal = App.window_refusal
      App.instances << self
      # A close (`Window#close`: Close Current, Quit, the terminal window shut)
      # tells before the teardown, while the panes still have their sizes.
      @window.on(Crysterm::Event::WindowClosed) { finish }
      App.refresh_window_menus
    end

    # Saves what a window's end saves (`#finish`) when *application* is
    # about to quit — Crysterm's own quit key, an error ending the loop —
    # before it tears the windows down (from `#run` and `#join`, where the
    # application is known); the subscription ends with the window.
    private def watch_quit(application : Crysterm::Application) : Nil
      subscription = application.on(Crysterm::Event::AboutToQuit) { finish }
      @window.on(Crysterm::Event::Destroy) { subscription.off }
    end

    # What the end of a window saves, once: the auto-save stopped and its
    # recovery file dropped once every window on the document has ended
    # (the others still show it until then; at a quit, which may exit
    # without tearing the windows down, each ends in turn and the last
    # one drops it), the history with the position, the config file when
    # anything changed. From the window's close or the application's quit,
    # before the teardown; from the window's `Destroy` as the last
    # resort (a direct destroy, as a spec's), when the pane sizes are gone
    # with the panes and are left as they were (`#record_pane_sizes`); and
    # from `#run` after the loop ended. Whichever comes first — and only for
    # a window that was put on screen (`#run`, `#join`): an app built and
    # dropped without running, as a spec's, has nothing to save.
    private def finish : Nil
      return if @finished || !@started
      @finished = true
      record_window_place
      @document.finish_autosave if @document.views.all?(&.finished?)
      save_history
      save_config
    end

    @finished = false

    # Whether the window's end was saved (`#finish`).
    def finished? : Bool
      @finished
    end

    # Set once the window is on screen (`#run`, `#join`).
    @started = false

    # Window → New (`Ctrl-N`): opens a terminal window and an `App` on it,
    # a view on this window's document (see above), joined to the running
    # application. Returns the new app, or nil with a notice saying why
    # there is none: the session cannot open windows, or the emulator would
    # not (the window did not start in time, say).
    #
    # The new window shows the panes this one shows, its caret, selection
    # and scroll where this window's are, and the focus in the same pane;
    # from then on it moves on its own, unless windows are linked.
    def new_window : App?
      if reason = @window_refusal
        notice "Cannot open a window: #{reason}"
        return
      end
      number, frame = next_window_place
      window = @window_opener.call(title, frame)
      begin
        app = App.new(@document, view: @viewer.visible?, window: window, history: @history, config: @config)
        app.window_number = number
      rescue ex
        # The terminal window is open already; an App that failed to build
        # must not leave it behind, empty.
        window.destroy
        raise ex
      end
      app.window_opener = @window_opener
      app.join exec_application
      app.take_view_of self
      app
    rescue ex
      notice "Cannot open a window: #{ex.message}"
      nil
    end

    # Starts this window where *other*, on the same document, is: the same
    # panes shown and focused, the editor's caret, selection and scroll, the
    # viewer's caret and scroll, and Sync Cursor (Window → New).
    protected def take_view_of(other : App) : Nil
      Pane.each do |pane|
        if other.widget(pane).visible?
          show_pane pane
        else
          hide_pane pane
        end
      end
      @sync_cursor.value = other.sync_cursor?
      @editor.text_cursor = other.editor.text_cursor
      @editor.scroll_cursor_to_row other.editor.cursor_viewport_row
      @viewer.text_cursor = other.viewer.text_cursor
      @viewer.scroll_cursor_to_row other.viewer.cursor_viewport_row
      focused = Pane.values.find { |pane| other.widget(pane).focused? }
      widget(focused).focus if focused
      refresh_status
    end

    # Puts this app's window on screen in *application*, running or not
    # (`Application#show`): rendered, reading input, and reporting md's
    # handler errors in its own status bar as the first window does
    # (`#run`).
    def join(application : Crysterm::Application) : Nil
      @started = true
      application.show @window
      @main.report_handler_errors(NOTICE_TIMEOUT) { |error| error_notice error }
      watch_quit application
    end

    # The application this app's window runs under (`Window#exec_application`:
    # its own once added, else the global one).
    def exec_application : Crysterm::Application
      @window.exec_application
    end

    # Window → Close Current (`Ctrl-W`): closes this window alone, after the
    # unsaved-changes guard (`Window#try_close` asks through the close
    # request, whose handler asks the user and closes on their answer). The
    # other windows stay; with none, the loop ends and `#run` returns.
    def close_window : Nil
      @window.try_close
    end

    # Makes *app*'s window the active one (Window menu). On a shared
    # terminal (tmux windows are not shared; stacked windows on one terminal
    # are) that raises it; otherwise it is in its own terminal window, which
    # a notice says. The window picked is the one used last, and leads its
    # group while windows are linked (Window → Linking), as input in it
    # would make it. The checks go back to each window's own entry.
    private def activate_window(app : App) : Nil
      unless app.same? self
        app.became_active
        app.window.activate
        notice "#{app.window_name} is in another terminal window" unless app.window.screen.same? @window.screen
      end
      App.refresh_window_menus
    end

    # The Window menu: the two commands, then the open windows
    # (`#refresh_window_menu`), remade as windows come and go and when the
    # menu opens, since a title changes with the file.
    private def build_window_menu(bar : Crysterm::Widget::MenuBar) : Nil
      menu = bar.add_menu "Wi&ndow"
      @new_window_action = named "new-window", tip menu.add_action("&New", shortcut: "Ctrl+N") { new_window },
        "Open this document in another md window, in a new terminal window: the same text, edited in either"
      # The editor's `Ctrl-W` kills a word, so the key works outside it.
      named "close-window", tip menu.add_action("&Close Current", shortcut: "Ctrl+W") { close_window },
        "Close this window, asking about unsaved changes when no other window shows the document; the last window closing quits md"
      add_linking_menu menu
      add_remember_positions menu
      menu.add_separator
      menu.on(Crysterm::Event::AboutToShow) { refresh_window_menu }
      @window_menu = menu
    end

    # Remakes the list of windows in this window's menu — one check entry
    # per open window, named as its title names it (`#window_name`, the
    # title without its ` • MD`), this one checked — and
    # enables New as the session allows.
    def refresh_window_menu : Nil
      return unless menu = @window_menu
      @new_window_action.try &.enabled = @window_refusal.nil?
      @window_entries.each { |entry| menu.remove_action entry }
      group = Crysterm::ActionGroup.new
      @window_entries = App.instances.map do |app|
        entry = Crysterm::Action.new literal_label(app.window_name), checkable: true
        tip entry, (app.same?(self) ? "This window" : "Bring the window showing #{app.window_name} to the front, where the terminal allows")
        entry.checked = app.same? self
        group.add_action entry
        entry.on(Crysterm::Event::Triggered) { activate_window app }
        menu.add_action entry
      end
    end

    # Remakes every window's list: a window opened or closed.
    def self.refresh_window_menus : Nil
      @@instances.each &.refresh_window_menu
    end

    # `Ctrl-N` while Window → New is disabled: a disabled entry's shortcut does
    # not fire, so the key says why here; enabled, the entry takes the key
    # itself and this is not reached. Returns whether it answered.
    private def refuse_new_window : Bool
      return false unless reason = @window_refusal
      notice "Cannot open a window: #{reason}"
      true
    end
  end
end
