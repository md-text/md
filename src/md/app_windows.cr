module Md
  class App
    # Windows: several md windows in one process, each a terminal window of
    # its own with its own document, editor and unsaved-changes guard — the
    # Window menu, after `QMdiArea`'s. Window → New Window (`Ctrl-N`) asks
    # Crysterm for another terminal window (`Crysterm::Window.open`: the
    # emulator md runs in is told to open one — kitty, Terminal.app, a tmux
    # window inside tmux…, `Crysterm::Terminal`) and builds a second `App`
    # on it, showing what this window shows now: the same file, the editor's
    # text as it stands, the viewer when the viewer is shown here. From then
    # on the two are independent: an edit in one is not in the other until
    # saved and reloaded (View → Watch File in the other does that), each
    # asks about its own unsaved changes, and the history and the settings
    # are shared and written by whichever window ends last (`#finish`).
    #
    # The new window joins the running application (`Application#show`), so
    # the loop runs until the last window is gone: Window → Close Window
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

    # How New Window opens a terminal window, given the title: Crysterm's
    # `Window.open`, which picks the emulator. Replaceable, so a spec can
    # hand out headless windows — and a replacement is taken to work
    # wherever it runs, so the entry is enabled (`#window_opener=`).
    @window_opener : Proc(String, Crysterm::Window) = ->(title : String) { Crysterm::Window.open(title: title) }

    def window_opener : Proc(String, Crysterm::Window)
      @window_opener
    end

    def window_opener=(opener : Proc(String, Crysterm::Window)) : Proc(String, Crysterm::Window)
      @window_opener = opener
      self.window_refusal = nil
      opener
    end

    # Why no window can be opened here, in a sentence, or nil when one can:
    # New Window's enabled state, and what its key says while disabled. Found
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

    # Puts this app in the process's list and takes it out when its window
    # goes, saving what a window's end saves (`#finish`) and remaking every
    # window's list (from `#initialize`, once the menus exist).
    private def register_window : Nil
      @window_refusal = App.window_refusal
      App.instances << self
      # A close (`Window#close`: Close Window, Quit, the terminal window shut)
      # tells before the teardown, while the panes still have their sizes.
      @window.on(Crysterm::Event::WindowClosed) { finish }
      @window.on(Crysterm::Event::Destroy) do
        App.instances.delete self
        finish
        App.refresh_window_menus
      end
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
    # recovery file dropped, the history with the position, the config file
    # when anything changed. From the window's close or the application's
    # quit, before the teardown; from the window's `Destroy` as the last
    # resort (a direct destroy, as a spec's), when the pane sizes are gone
    # with the panes and are left as they were (`#record_pane_sizes`); and
    # from `#run` after the loop ended. Whichever comes first — and only for
    # a window that was put on screen (`#run`, `#join`): an app built and
    # dropped without running, as a spec's, has nothing to save.
    private def finish : Nil
      return if @finished || !@started
      @finished = true
      finish_autosave
      save_history
      save_config
    end

    @finished = false
    # Set once the window is on screen (`#run`, `#join`).
    @started = false

    # Window → New Window (`Ctrl-N`): opens a terminal window and an `App`
    # on it showing this document as it stands (see above), joined to the
    # running application. Returns the new app, or nil with a notice saying
    # why there is none: the session cannot open windows, or the emulator
    # would not (the window did not start in time, say).
    def new_window : App?
      if reason = @window_refusal
        notice "Cannot open a window: #{reason}"
        return
      end
      window = @window_opener.call(title)
      app = App.new(@source, text: markdown, view: @viewer.visible?, window: window,
        history: @history, config: @config)
      app.window_opener = @window_opener
      app.join exec_application
      app
    rescue ex
      notice "Cannot open a window: #{ex.message}"
      nil
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

    # Window → Close Window (`Ctrl-W`): closes this window alone, after the
    # unsaved-changes guard (`Window#try_close` asks through the close
    # request, whose handler asks the user and closes on their answer). The
    # other windows stay; with none, the loop ends and `#run` returns.
    def close_window : Nil
      @window.try_close
    end

    # Makes *app*'s window the active one (Window menu). On a shared
    # terminal (tmux windows are not shared; stacked windows on one terminal
    # are) that raises it; otherwise it is in its own terminal window, which
    # a notice says. The checks go back to each window's own entry.
    private def activate_window(app : App) : Nil
      unless app.same? self
        app.window.activate
        notice "#{app.title} is in another terminal window" unless app.window.screen.same? @window.screen
      end
      App.refresh_window_menus
    end

    # The Window menu: the two commands, then the open windows
    # (`#refresh_window_menu`), remade as windows come and go and when the
    # menu opens, since a title changes with the file.
    private def build_window_menu(bar : Crysterm::Widget::MenuBar) : Nil
      menu = bar.add_menu "Wi&ndow"
      @new_window_action = tip menu.add_action("&New Window", shortcut: "Ctrl+N") { new_window },
        "Open this document in another md window, in a new terminal window"
      # The editor's `Ctrl-W` kills a word, so the key works outside it.
      tip menu.add_action("&Close Window", shortcut: "Ctrl+W") { close_window },
        "Close this window, asking about unsaved changes; the last window closing quits md"
      menu.add_separator
      menu.on(Crysterm::Event::AboutToShow) { refresh_window_menu }
      @window_menu = menu
    end

    # Remakes the list of windows in this window's menu — one check entry
    # per open window, titled as its window is, this one checked — and
    # enables New Window as the session allows.
    def refresh_window_menu : Nil
      return unless menu = @window_menu
      @new_window_action.try &.enabled = @window_refusal.nil?
      @window_entries.each { |entry| menu.remove_action entry }
      group = Crysterm::ActionGroup.new
      @window_entries = App.instances.map do |app|
        entry = Crysterm::Action.new app.title, checkable: true
        tip entry, (app.same?(self) ? "This window" : "Bring the window showing #{app.title} to the front, where the terminal allows")
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

    # `Ctrl-N` while New Window is disabled: a disabled entry's shortcut does
    # not fire, so the key says why here; enabled, the entry takes the key
    # itself and this is not reached. Returns whether it answered.
    private def refuse_new_window : Bool
      return false unless reason = @window_refusal
      notice "Cannot open a window: #{reason}"
      true
    end
  end
end
