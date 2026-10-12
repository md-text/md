module Md
  class App
    # The choices kept across runs: the View and Options settings, which are
    # options in Crysterm's registry (`Md::Config`, `config.cr`), and the
    # pane sizes. When the app keeps the configuration (`config: true`; the
    # CLI does, specs do not, so a spec's picks stay its own), each choice's
    # reactive property is linked to its option both ways
    # (`Reactive.link_config`): the property starts as the option was
    # configured — the file, a variable, a flag — and a change from either
    # side reaches the other, so a pick in a menu is recorded in the option
    # at once, and a config file loaded while md runs (Options → Load
    # Config…) moves the menu entries and takes effect through the
    # properties' change handlers. Without the link, a property is still
    # given its option's value at start, so `--md-text-width 80` is honored
    # either way. The file is written at exit (`#save_config`,
    # from `#run`) when anything changed, and on request (Options → Save
    # Config and Save Config As…, `#save_config_prompt`).
    #
    # Watch File is not among them: it is per run, as `--watch` is;
    # overwrite mode is the editor's state, not a choice. The pane sizes
    # (`#pane_sizes`) are recorded at exit, when the write is due anyway: a
    # drag changes them many times a second.
    getter? config : Bool

    # Puts the options' values into the properties — a value that differs
    # from a property's default reaches the panes through its change handler,
    # so this runs once the bar and the panes exist — and, when the app keeps
    # the configuration, links each property to its option (see above).
    private def apply_config : Nil
      link @resizable_panes, "md.resizable_panes"
      link @bars, "md.bars"
      link @sync_cursor, "md.sync_cursor"
      link @highlight_line, "md.highlight_line"
      link @line_numbers, "md.line_numbers"
      link @viewer_line_numbers, "md.viewer_line_numbers"
      link @soft_wrap, "md.soft_wrap"
      link @hard_wrap, "md.hard_wrap"
      link @text_width, "md.text_width"
      link @center_text, "md.center_text"
      link @horizontal_ruler, "md.horizontal_ruler"
      link @vertical_ruler, "md.vertical_ruler"
      link @guides, "md.guides"
      link @dialog_style, "md.dialog_style"
      link @confirm_discard, "md.confirm_discard"
      link @autosave, "md.autosave"
      link @backup_file, "md.backup_file"
      link @mouse_mode, "md.mouse_mode"
      link @clipboard_mode, "md.clipboard_mode"
      link @tooltips, "md.tooltips"
      link @theme, "colors.theme"
      link @images, "md.images"
      link @media_backend, "media.backend"
      link @color_depth, "colors.depth"
      link @hyperlinks, "render.hyperlinks"
      link @reduced_motion, "render.reduced_motion"
      link @tear_off_menus, "menu.tear_off"
      link @link_double_click, "md.link_double_click"
      link @vi_config, "md.vi_config"
      link @vi_mode, "md.vi_mode"
      # The pane sizes are not a property: applied from the option now and,
      # with the configuration kept, whenever it changes (a file loaded);
      # recorded at exit. The window's end unhooks the listener, as it does
      # the links'.
      apply_pane_sizes
      return unless @config
      handle = Crysterm::Config.on_change("md.pane_sizes") { apply_pane_sizes }
      @window.on(Crysterm::Event::Destroy) { Crysterm::Config.off_change "md.pane_sizes", handle }
    end

    # Puts option *key*'s value into *property*, and links the two when the
    # configuration is kept (`Reactive.link_config`, ended with the window).
    private def link(property : Crysterm::Reactive::Property(T), key : String) forall T
      if @config
        Crysterm::Reactive.link_config property, key, @window
      else
        property.value = Crysterm::Config.get(key, T)
      end
    end

    # Gives the panes the widths `md.pane_sizes` holds, when it holds one
    # per pane: `"40,60,20"` (`#pane_sizes=` ignores anything else).
    private def apply_pane_sizes : Nil
      sizes = Crysterm::Config.md_pane_sizes.split(',').map(&.strip.to_i?)
      self.pane_sizes = sizes.compact if sizes.size == Pane.values.size && sizes.none?(Nil)
    end

    # Records the pane sizes and writes the config file when anything
    # changed (at exit, from `#run`). A write that fails is let go: at exit
    # there is no one left to tell, and the choices are not worth an error.
    def save_config : Nil
      return unless @config
      record_pane_sizes
      Config.save if Config.dirty?
    end

    # Options → Save Config: writes the config file now, with a notice
    # saying so, or that it could not be written.
    def save_config_now : Nil
      write_config Config.path
    end

    # Options → Save Config As…: asks for a file name (`#ask_text`), the
    # config file's filled in, and writes the settings there; a cancelled or
    # empty answer writes nothing.
    def save_config_prompt : Nil
      ask_text("Save config as: ", Config.path) do |answer|
        path = answer.try &.strip
        write_config path if path && !path.empty?
      end
    end

    # Puts the pane sizes, as they are now, into their option, for a write —
    # when the panes still have them: after a teardown the splitter has
    # none, and the option keeps what it had.
    private def record_pane_sizes : Nil
      sizes = pane_sizes
      Crysterm::Config.md_pane_sizes = sizes.join(',') if sizes.size == Pane.values.size
    end

    # Writes the settings to *path*, with a notice saying so, or that it
    # could not be written.
    private def write_config(path : String) : Nil
      record_pane_sizes
      notice(Config.save(path) ? "Saved #{path}" : "Cannot write #{path}")
    end

    # Options → Load Config…: asks for a file name, the config file's filled
    # in, and applies the file now (`Config.load_file`): its values take
    # effect through the linked properties, and are recorded as picks, so
    # the config file gets them at exit. A file that cannot be read, or a
    # value that does not fit, is a notice.
    def load_config_prompt : Nil
      ask_text("Load config: ", Config.path) do |answer|
        path = answer.try &.strip
        next if path.nil? || path.empty?
        begin
          Config.load_file path
          notice "Loaded #{path}"
        rescue ex : Error
          notice "Cannot load #{path}: #{ex.message}"
        end
      end
    end
  end
end
