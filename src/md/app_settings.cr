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
    # choice.
    getter settings : Settings?

    # Puts the stored choices into the properties — a choice never made reads
    # nil and leaves the default — and has every change go back into the
    # store. Runs once the bar and the panes exist, so the properties' change
    # handlers can apply the choices to them. A theme named by Crysterm's
    # config (`--colors-theme`) keeps the stored one out for this run
    # (`app_theme.cr`).
    private def apply_settings : Nil
      return unless settings = @settings
      settings.follow_cursor?.try { |value| @follow_cursor.value = value }
      settings.highlight_line?.try { |value| @highlight_line.value = value }
      settings.confirm_discard?.try { |value| @confirm_discard.value = value }
      settings.mouse_mode.try { |mode| @mouse_mode.value = mode }
      settings.line_numbers?.try { |value| @editor.line_numbers = value }
      settings.theme.try { |theme| @theme.value = theme } unless theme_configured?
      settings.autosave?.try { |value| @autosave.value = value }
      settings.backup_file?.try { |value| @backup_file.value = value }
      settings.soft_wrap?.try { |value| @soft_wrap.value = value }
      settings.text_width.try { |value| @text_width.value = value }
      settings.center_text?.try { |value| @center_text.value = value }
      settings.clipboard_mode.try { |mode| @clipboard_mode.value = mode }
      @follow_cursor.on_change { settings.follow_cursor = @follow_cursor.value }
      @highlight_line.on_change { settings.highlight_line = @highlight_line.value }
      @confirm_discard.on_change { settings.confirm_discard = @confirm_discard.value }
      @mouse_mode.on_change { settings.mouse_mode = @mouse_mode.value }
      @editor.on(Crysterm::Event::LineNumbersChanged) { |e| settings.line_numbers = e.visible }
      @theme.on_change { settings.theme = @theme.value }
      @autosave.on_change { settings.autosave = @autosave.value }
      @backup_file.on_change { settings.backup_file = @backup_file.value }
      @soft_wrap.on_change { settings.soft_wrap = @soft_wrap.value }
      @text_width.on_change { settings.text_width = @text_width.value }
      @center_text.on_change { settings.center_text = @center_text.value }
      @clipboard_mode.on_change { settings.clipboard_mode = @clipboard_mode.value }
    end

    # Writes the settings, when any changed. A write that fails is let go:
    # at exit there is no one left to tell, and the choices are not worth
    # an error.
    def save_settings : Nil
      return unless settings = @settings
      settings.save if settings.dirty?
    end
  end
end
