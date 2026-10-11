module Md
  class App
    # The settings kept across runs (`Settings`), when the app keeps them
    # (the CLI does; specs pass none, or one on a temporary file). The View
    # and Options choices that are reactive properties — Follow cursor,
    # Highlight line, Soft wrap, Text width, Center text, Ask before
    # discarding changes, Auto-save, Keep a backup file, the mouse and
    # clipboard modes, the theme — and the editor's line numbers are restored from the store on
    # construction and recorded in it as they change, whoever changes them
    # (a menu entry, a key, a setter), and the store is written at exit
    # (`#save_settings`, from `#run`). Watch file is not among them: it is
    # per run, as `--watch` is; overwrite mode is the editor's state, not a
    # choice. The pane sizes (`#pane_sizes`) are restored with them and
    # recorded at exit, when the write is due anyway: a drag changes them
    # many times a second.
    getter settings : Settings?

    # Puts the stored choices into the properties — a choice never made reads
    # nil and leaves the default — and has every change go back into the
    # store. Runs once the bar and the panes exist, so the properties' change
    # handlers can apply the choices to them. A theme named by Crysterm's
    # config (`--colors-theme`) keeps the stored one out for this run
    # (`app_theme.cr`).
    private def apply_settings : Nil
      return unless settings = @settings
      keep settings, @follow_cursor, "follow_cursor"
      keep settings, @highlight_line, "highlight_line"
      keep settings, @soft_wrap, "soft_wrap"
      keep settings, @text_width, "text_width"
      keep settings, @center_text, "center_text"
      keep settings, @confirm_discard, "confirm_discard"
      keep settings, @autosave, "autosave"
      keep settings, @backup_file, "backup_file"
      keep settings, @mouse_mode, "mouse_mode"
      keep settings, @clipboard_mode, "clipboard_mode"
      keep settings, @theme, "theme", apply: !theme_configured?
      # The editor's own state, not a property: applied and heard directly.
      settings.line_numbers?.try { |value| @editor.line_numbers = value }
      @editor.on(Crysterm::Event::LineNumbersChanged) { |e| settings.line_numbers = e.visible }
      settings.pane_sizes.try { |sizes| self.pane_sizes = sizes }
    end

    # Puts *settings*' value under *key* into *property* (when *apply*) and
    # records the property's every change under it: one line per choice.
    private def keep(settings : Settings, property : Crysterm::Reactive::Property(T), key : String, apply : Bool = true) forall T
      settings.get?(key, T).try { |value| property.value = value } if apply
      property.on_change { settings.set key, property.value }
    end

    # Writes the settings, when any changed — the pane sizes recorded first,
    # as they are now. A write that fails is let go: at exit there is no one
    # left to tell, and the choices are not worth an error.
    def save_settings : Nil
      return unless settings = @settings
      settings.pane_sizes = pane_sizes
      settings.save if settings.dirty?
    end
  end
end
