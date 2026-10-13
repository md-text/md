module Md
  class App
    # Edit → Vi Mode (Neovim) (`#vi_mode?`): the editor is edited as in Neovim, by an
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
    # Options → Vi Mode: Use Neovim Config is on (`md.vi_config`); a
    # change to it restarts Neovim when Vi Mode is on. Without `nvim` the
    # entry is disabled and says why; a Neovim that ends, or the editor's
    # buffer closed in Neovim (`:bw`), turns Vi Mode off.
    #
    # Turned on from the menu or by name, Vi Mode shows and focuses the
    # editor. The viewer's `:` stays md's command line, the viewer being no
    # text input. The line prompts keep plain editing: a question is answered in
    # a few keys, where starting in Normal mode would only be in the way.
    @vi_mode : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @vi_config : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    # The handler driving the editor while Vi Mode is on.
    getter vi : Crysterm::Neovim::Handler = Crysterm::Neovim::Handler.new

    # The status bar's mode field, shown while Vi Mode is on; made in
    # `#initialize` with the other fields, once the window exists.
    @vi_field : Crysterm::Widget::Label

    def vi_mode? : Bool
      @vi_mode.value
    end

    # Turns Vi Mode on or off (Edit → Vi Mode (Neovim)).
    def vi_mode=(value : Bool) : Bool
      @vi_mode.value = value
    end

    def vi_config? : Bool
      @vi_config.value
    end

    # Whether Neovim reads the user's config (Options → Vi Mode: Use
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
      # The editor's buffer closed in Neovim (`:bw`), or Neovim failing a
      # call: the handler has let go of the editor.
      @vi.on(Crysterm::Event::ViDetached) do |e|
        @vi_mode.value = false
        notice "#{e.reason}; Vi Mode is off"
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
      args = Crysterm::Neovim::Handler.default_args.dup
      args.delete "--clean" if vi_config?
      args
    end

    # While `:w` asks for the name of a document that has none, the quit of
    # a `:wq` (`:x`, `ZZ`) that came with it, `{bang, all}`: it waits for the
    # answer, and is dropped when nothing was saved, as Neovim's `:wq` stays
    # when its write fails.
    @vi_naming = false
    @vi_quit_after_naming : {Bool, Bool}? = nil

    # `:w`: saves, or saves as *path* (`:w FILE`); a document without a
    # file asks for a name (File → Save As).
    private def vi_write(path : String?) : Nil
      if path
        save_as path
      elsif @source.path
        save
      else
        @vi_naming = true
        save_as_prompt do |saved|
          @vi_naming = false
          quit = @vi_quit_after_naming
          @vi_quit_after_naming = nil
          vi_quit *quit if quit && saved
        end
      end
    end

    # `:q`: closes this window, or every window with *all* (`:qa`), asking
    # about unsaved changes unless *bang* (`:q!`); after the save of a `:wq`
    # still asking for a name, once it is answered.
    private def vi_quit(bang : Bool, all : Bool) : Nil
      if @vi_naming
        @vi_quit_after_naming = {bang, all}
        return
      end
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
      entry = add_toggle edit, "V&i Mode (Neovim)", "vi-mode", @vi_mode, option_tip("md.vi_mode") + (available ? "" : missing)
      entry.enabled = available
      # Turned on from the menu or by name, Vi Mode takes the keys of the
      # editor, which it shows and focuses: with the viewer focused (where
      # a file opens), the keys typed next went to the viewer, which has no
      # Insert mode, while the status bar already said NORMAL. The setting
      # loaded at start leaves the focus where the document opens.
      entry.on(Crysterm::Event::Triggered) { |e| show_pane(Pane::Editor).focus if e.checked && vi_mode? }
      config = add_toggle options, "Vi Mode: Use &Neovim Config", "vi-config", @vi_config, option_tip("md.vi_config") + (available ? "" : missing)
      config.enabled = available
    end
  end
end
