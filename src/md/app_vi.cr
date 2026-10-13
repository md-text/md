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
    # `:w` saves (File → Save), `:w FILE` writes a copy to FILE and keeps
    # the document's name, as Vim does (a document without a name takes
    # FILE as its own), `:saveas FILE` saves as FILE (File → Save As), `:q`
    # closes the window as Window → Close Current does, asking about
    # unsaved changes, `:q!` closes it without asking, `:qa` quits as
    # File → Quit does (`:qa!` without asking), and `:wq`, `:x` and `ZZ`
    # save, then close.
    #
    # Neovim starts with `--clean` — none of the user's config — unless
    # Options → Vi Mode: Use Neovim Config is on (`md.vi_config`); a
    # change to it restarts Neovim when Vi Mode is on. Without `nvim` the
    # entry is disabled and says why; a Neovim that ends or does not answer
    # (`Neovim::Handler#request_timeout`), or the editor's buffer closed in
    # Neovim (`:bw`), turns Vi Mode off.
    #
    # Windows on one document each run a Neovim of their own while they are
    # separate (Window → Linking), each taking the others' edits as outside
    # changes, so `u` in one undoes an edit made in another as well; marks,
    # registers and the jumplist are each window's. Linked windows share one
    # Neovim and one buffer for their document (`Document#vi`), as Vim's
    # windows on one buffer do: the keys of any of them go to it, and its
    # cursor to the window they came from, which the others mirror. `:w`
    # and `:q` act for the window whose keys typed them. Switching between
    # the two restarts Neovim, its own undo history with it (the document's
    # stays).
    #
    # Turned on from the menu or by name, Vi Mode shows and focuses the
    # editor. The viewer's `:` stays md's command line, the viewer being no
    # text input. The line prompts keep plain editing: a question is answered in
    # a few keys, where starting in Normal mode would only be in the way.
    @vi_mode : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)
    @vi_config : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    # The handler driving the editor while Vi Mode is on in a separate
    # window (`#vi` is the one in effect).
    @own_vi : Crysterm::Neovim::Handler = Crysterm::Neovim::Handler.new
    # The subscriptions to the handler in effect (`#follow_vi`).
    @vi_subscriptions = Crysterm::Subscriptions.new
    @followed_vi : Crysterm::Neovim::Handler?

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

    # The handler driving the editor while Vi Mode is on: the document's,
    # shared with the other windows on it, while linked; this window's own
    # otherwise — and while Vi Mode is off here, so a linked window not in
    # Vi Mode shows none of the shared Neovim's mode, command line or
    # messages, and is not turned off (with a notice) when it ends.
    def vi : Crysterm::Neovim::Handler
      (link && @document.vi if vi_mode?) || @own_vi
    end

    # Hooks the properties to the handler; the status bar's field goes in
    # by `#build_status`.
    private def wire_vi : Nil
      @vi_mode.on_change { apply_vi_mode }
      @vi_config.on_change { apply_vi_mode if vi_mode? }
      follow_vi
    end

    # Hooks the events of the handler in effect (`#vi`) to md, once per
    # handler: from `#wire_vi`, and whenever Vi Mode is applied, since
    # linking, a switch of document or another window's Neovim changes which
    # handler that is. The events of a shared handler come on the render
    # fiber of the window whose keys caused them, so this window's part is
    # posted to its own; a `:w` or `:q` is the active window's alone.
    private def follow_vi : Nil
      handler = vi
      return if handler.same?(@followed_vi)
      @vi_subscriptions.off
      @followed_vi = handler
      subs = @vi_subscriptions
      subs.on(handler, Crysterm::Event::ViModeChanged) { vi_post { refresh_status } }
      # A command line typed (`:`, `/`) is the name field's, which a notice
      # up in the bar covers: the notice ends there, as a Qt application
      # clears a status message when the bar is put to another use.
      subs.on(handler, Crysterm::Event::ViCommandLineChanged) do
        vi_post do
          @main.status_bar.clear_message if handler.command_line
          refresh_status
        end
      end
      subs.on(handler, Crysterm::Event::ViMessageChanged) { |e| e.text.try { |text| vi_post { notice text } } }
      subs.on(handler, Crysterm::Event::ViWriteRequested) { |e| vi_write e.path, e.rename if vi_active?(handler) }
      subs.on(handler, Crysterm::Event::ViQuitRequested) { |e| vi_quit e.bang, e.all if vi_active?(handler) }
      # Neovim ended under the editor: the editor is its own again.
      subs.on(handler, Crysterm::Event::ProcessExited) { vi_ended "Neovim ended" }
      # The editor's buffer closed in Neovim (`:bw`), or Neovim failing or
      # not answering a call: the handler has let go of the editor.
      subs.on(handler, Crysterm::Event::ViDetached) { |e| vi_ended e.reason }
    end

    # The handler let go of the editor, for *reason*: Vi Mode goes off, and
    # a notice says why (on this window's render fiber, `#vi_post`).
    private def vi_ended(reason : String) : Nil
      vi_post do
        @vi_mode.value = false
        notice "#{reason}; Vi Mode is off"
      end
    end

    # Runs *job* now for this window's own handler, else posts it to this
    # window's render fiber (a shared handler's event came from another's).
    private def vi_post(&job : ->) : Nil
      if @followed_vi.same?(@own_vi)
        job.call
      else
        @window.post(&job)
      end
    end

    # Whether this window's editor is the one *handler*'s keys came from
    # last (its only view, for a handler of one window).
    private def vi_active?(handler : Crysterm::Neovim::Handler) : Bool
      (handler.active_widget || handler.widget).same?(@editor)
    end

    # Attaches a handler to the editor, or lets go of it, as the property
    # says: this window's own while separate, the document's shared one
    # while linked (`Document#ensure_vi`), joined as one more view of the
    # buffer when another window started it. A Neovim that cannot start
    # turns the property back off.
    private def apply_vi_mode : Nil
      leave_shared_vi
      @own_vi.detach
      if vi_mode?
        started = if link
                    @document.ensure_vi(@editor, vi_args)
                  else
                    @own_vi.args = vi_args
                    @own_vi.attach(@editor)
                  end
        unless started
          notice "Cannot start Neovim (#{Crysterm::Neovim.executable}); Vi Mode is off"
          @vi_mode.value = false
        end
      end
      follow_vi
      refresh_status
    end

    # Vi Mode across a switch of Window → Linking: the Neovim in effect
    # changes (`Documents.link_windows`).
    protected def relink_vi : Nil
      if vi_mode?
        apply_vi_mode
      else
        follow_vi
      end
    end

    # Takes this window's editor off the document's shared handler, if it is
    # a view of it (Vi Mode turned off, the windows separated, another
    # document shown, the window destroyed); the last view's leaving ends
    # that Neovim. The subscriptions to it go too (`#follow_vi` makes them
    # again for the handler then in effect): the shared handler outlives a
    # window that leaves it, which it would otherwise keep, destroyed, and
    # keep telling.
    protected def leave_shared_vi : Nil
      unless @followed_vi.same?(@own_vi)
        @vi_subscriptions.off
        @followed_vi = nil
      end
      @document.release_vi @editor
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

    # `:w`: saves; with *path*, writes a copy there (`:w FILE`), or saves
    # as *path* when *rename* (`:saveas FILE`) or the document has no name
    # (Vim's 'cpoptions' `F`); a document without a name asks for one (File
    # → Save As). A *path* that is the document's own file — by whatever
    # name (`Documents.key_for`) — is a plain save, as Vim's `:w FILE` of
    # the file being edited is: Neovim knows the buffer by another name and
    # asks it as a copy (with `!`, the file existing), which would have
    # written the file and left the document unsaved, its file changed
    # under it.
    private def vi_write(path : String?, rename : Bool) : Nil
      path = nil if path && (own = source.path) && Documents.key_for(path) == Documents.key_for(own)
      if path && (rename || source.path.nil?)
        save_as path
      elsif path
        vi_write_copy path
      elsif source.path
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

    # `:w FILE` on a named document: the text goes to *path*, and the
    # document keeps its name, its file and its unsaved state.
    private def vi_write_copy(path : String) : Nil
      @document.write_copy path
      notice "Wrote a copy to #{path}"
    rescue ex : IO::Error
      notice "Cannot write #{path}: #{Md.error_text(ex)}"
    end

    # `:q`: closes this window, or every window with *all* (`:qa`, File →
    # Quit's way: every unsaved document asked about before anything closes),
    # asking about unsaved changes unless *bang* (`:q!`, `:qa!`); after the
    # save of a `:wq` still asking for a name, once it is answered.
    private def vi_quit(bang : Bool, all : Bool) : Nil
      if @vi_naming
        @vi_quit_after_naming = {bang, all}
        return
      end
      if !bang
        all ? quit : close_window
      elsif all
        App.instances.dup.each &.window.close
      else
        @window.close
      end
    end

    # The mode field's text: Neovim's mode while Vi Mode is on.
    private def vi_mode_text : String
      handler = vi
      handler.attached? ? handler.mode.label : ""
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
