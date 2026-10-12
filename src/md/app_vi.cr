module Md
  class App
    # Edit → Vi Mode (`#vi_mode?`): the editor is edited as in Neovim, by an
    # embedded `nvim` (Crysterm's `Neovim::Handler`, Qt Creator's FakeVim
    # done with the real engine). The editor keeps its document, so the
    # viewer, the status bar, Format, Find and the rest work on it as
    # before; the keys go to Neovim, except the function keys and the `Alt`
    # combinations, which stay md's menus and shortcuts. `u` and `Ctrl-R`
    # are Neovim's undo and redo (`Ctrl-Z`, the editor's undo otherwise, is
    # Neovim's key too); an edit md makes — Format, Replace, a paste —
    # reaches Neovim as an outside edit, and `u` undoes it as well.
    #
    # The status bar shows Neovim's mode beside the position (`NORMAL`,
    # `INSERT`, `VISUAL`, …), and the command line in place of the
    # document's name while one is typed; Neovim's messages come as notices.
    # `:w` saves (File → Save), `:w FILE` saves as FILE (File → Save As),
    # `:q` closes the window as Window → Close Current does, asking about
    # unsaved changes, `:q!` closes it without asking, `:qa` quits as
    # File → Quit does (`:qa!` without asking), and `:wq`, `:x` and `ZZ`
    # save, then close.
    #
    # Neovim starts with `--clean` — none of the user's config — unless
    # Options → Vi Mode Uses Your Neovim Config is on (`md.vi_config`); a
    # change to it restarts Neovim when Vi Mode is on. Without `nvim` the
    # entry is disabled and says why; a Neovim that ends turns Vi Mode off.
    #
    # The viewer's `:` stays md's command line, the viewer being no text
    # input. The line prompts keep plain editing: a question is answered in
    # a few keys, where starting in Normal mode would only be in the way.
    @vi_mode : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @vi_config : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    # The handler driving the editor while Vi Mode is on.
    getter vi : Crysterm::Neovim::Handler = Crysterm::Neovim::Handler.new

    # The status bar's mode field, shown while Vi Mode is on.
    @vi_field : Crysterm::Widget::Label = Crysterm::Widget::Label.new(text: "", width: 9)

    def vi_mode? : Bool
      @vi_mode.value
    end

    # Turns Vi Mode on or off (Edit → Vi Mode).
    def vi_mode=(value : Bool) : Bool
      @vi_mode.value = value
    end

    def vi_config? : Bool
      @vi_config.value
    end

    # Whether Neovim reads the user's config (Options → Vi Mode Uses Your
    # Neovim Config).
    def vi_config=(value : Bool) : Bool
      @vi_config.value = value
    end

    # Hooks the handler's events to md and the properties to the handler;
    # the status bar's field goes in by `#build_status`.
    private def wire_vi : Nil
      @vi_mode.on_change { apply_vi_mode }
      @vi_config.on_change { apply_vi_mode if vi_mode? }
      @vi.on(Crysterm::Event::ViModeChanged) { refresh_status }
      @vi.on(Crysterm::Event::ViCommandLineChanged) { refresh_status }
      @vi.on(Crysterm::Event::ViMessageChanged) { |e| e.text.try { |text| notice text } }
      @vi.on(Crysterm::Event::ViWriteRequested) { |e| vi_write e.path }
      @vi.on(Crysterm::Event::ViQuitRequested) { |e| vi_quit e.bang, e.all }
      # Neovim ended under the editor: the editor is its own again.
      @vi.on(Crysterm::Event::ProcessExited) do
        @vi_mode.value = false
        notice "Neovim ended; Vi Mode is off"
      end
    end

    # Attaches the handler to the editor, or detaches it, as the property
    # says; a Neovim that cannot start turns the property back off.
    private def apply_vi_mode : Nil
      @vi.detach
      if vi_mode?
        @vi.args = vi_args
        unless @vi.attach(@editor)
          notice "Cannot start Neovim (#{Crysterm::Neovim.executable}); Vi Mode is off"
          @vi_mode.value = false
        end
      end
      refresh_status
    end

    # Neovim's arguments: `--clean` unless the user's config is wanted.
    private def vi_args : Array(String)
      vi_config? ? ["--headless", "-n"] : Crysterm::Neovim::Handler.default_args.dup
    end

    # `:w`: saves, or saves as *path* (`:w FILE`).
    private def vi_write(path : String?) : Nil
      if path
        save_as path
      else
        save
      end
    end

    # `:q`: closes this window, or every window with *all* (`:qa`), asking
    # about unsaved changes unless *bang* (`:q!`).
    private def vi_quit(bang : Bool, all : Bool) : Nil
      apps = all ? App.instances.dup : [self]
      apps.each do |app|
        if bang
          app.window.close
        else
          app.close_window
        end
      end
    end

    # The mode field's text: Neovim's mode while Vi Mode is on.
    private def vi_mode_text : String
      @vi.attached? ? @vi.mode.label : ""
    end

    # The Edit and Options entries (`#build_menus`).
    private def add_vi_actions(edit : Crysterm::Widget::Menu, options : Crysterm::Widget::Menu) : Nil
      available = Crysterm::Neovim.available?
      missing = " (needs nvim, which was not found)"
      edit.add_separator
      entry = add_toggle edit, "V&i Mode", "vi-mode", @vi_mode, option_tip("md.vi_mode") + (available ? "" : missing)
      entry.enabled = available
      config = add_toggle options, "Vi Mode Uses Your &Neovim Config", "vi-config", @vi_config, option_tip("md.vi_config") + (available ? "" : missing)
      config.enabled = available
    end
  end
end
