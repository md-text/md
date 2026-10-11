module Md
  class App
    # Options → Theme: which of Crysterm's built-in color themes the window
    # is drawn in — the choices `--colors-theme` takes, `none` aside, as
    # `QStyleFactory::keys` lists the styles `QApplication::setStyle` can
    # switch to at runtime. The themes are generated in code (`CSS::Theme`),
    # so they ship inside the binary with nothing to read from disk; a swap
    # installs the picked theme's stylesheet as the default sheet, and
    # Crysterm restyles and repaints the whole window on the next frame. An
    # author stylesheet (`--colors-stylesheet`) layers over the theme and
    # stays over whichever one is picked.
    #
    # The choice is kept in the settings. `--colors-theme` (or Crysterm's
    # config file or environment) wins for the run it is given — the stored
    # choice is not applied over it — and is not recorded, so the next plain
    # run is back to the stored choice; picking a theme from the menu records
    # it as usual.
    alias Theme = Crysterm::CSS::Theme::Choice

    # The themes offered, in menu order: the terminal's own colors first, as
    # it is Crysterm's default.
    THEMES = [Theme::Terminal, Theme::Dark, Theme::Light]

    # A reactive property, so the Options → Theme entries bind to it
    # (`#build_menus`); `#theme` and `#theme=` are its plain face. Starts
    # as the theme Crysterm installed when the window was created, which is
    # its config's.
    @theme : Crysterm::Reactive::Property(Theme) = Crysterm::Reactive::Property.new(Crysterm::Config.colors_theme)

    def theme : Theme
      @theme.value
    end

    # Switches the theme; it is applied to the window when it changes (the
    # property's change handler, in `#wire_theme`).
    def theme=(theme : Theme) : Theme
      @theme.value = theme
    end

    # Steps to the next offered theme (`F6`); from `none` to the first.
    def cycle_theme : Theme
      index = THEMES.index(@theme.value)
      self.theme = THEMES[index ? (index + 1) % THEMES.size : 0]
    end

    # Whether Crysterm's config names the theme for this run, in which case
    # the stored choice stands down (`#apply_settings`).
    def theme_configured? : Bool
      Superconf.configured? "colors.theme"
    end

    # Installs the chosen theme on changes. Crysterm notices the new default
    # sheet by itself on the next frame; the frame is asked for here, as a
    # change from a key or a setter paints nothing on its own.
    private def wire_theme : Nil
      @theme.on_change do
        Crysterm::CSS.theme = crysterm_theme(@theme.value)
        @window.update
      end
    end

    # The `CSS::Theme` *choice* stands for, as Crysterm resolves its config
    # (`CSS.resolve_config_theme`): the terminal one is derived from this
    # window's probe of the terminal.
    private def crysterm_theme(choice : Theme) : Crysterm::CSS::Theme?
      case choice
      in .terminal? then @window.terminal_theme
      in .dark?     then Crysterm::CSS::Theme.dark
      in .light?    then Crysterm::CSS::Theme.light
      in .none?     then nil
      end
    end

    private def theme_label(theme : Theme) : String
      case theme
      in .terminal? then "&Terminal (its own colors)"
      in .dark?     then "&Dark"
      in .light?    then "&Light"
      in .none?     then "&None"
      end
    end
  end
end
