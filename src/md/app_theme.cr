module Md
  class App
    # View → Theme: which of Crysterm's built-in color themes the window is
    # drawn in — the choices `--colors-theme` takes, `none` aside, as
    # `QStyleFactory::keys` lists the styles `QApplication::setStyle` can
    # switch to at runtime. Three are generated in code (`CSS::Theme`): the
    # terminal's own colors, dark and light. Five are Qt themes — Breeze and
    # QDarkStyle, dark and light each, and qtmodern's dark — embedded in
    # Crysterm as Qt stylesheets (`CSS::Theme::BUILTIN_STYLESHEETS`) and laid
    # over its generated rules in a palette drawn from the sheet's own window
    # colors, so the whole window takes the Qt theme's look. All ship inside
    # the binary with nothing to read from disk; a swap installs the picked
    # theme's stylesheet as the default sheet, and Crysterm restyles and
    # repaints the whole window on the next frame. An author stylesheet
    # (`--colors-stylesheet`) layers over the theme and stays over whichever
    # one is picked.
    #
    # The choice is Crysterm's `colors.theme` option itself: the property is
    # linked to it (`app_config.cr`), so a pick from the menu is recorded
    # there and kept in the config file, and `--colors-theme` (or
    # `CRYSTERM_COLORS_THEME`, or Crysterm's own config file) is what the
    # property starts from. The option's precedence does the rest:
    # `--colors-theme` wins for the run it is given and is not recorded,
    # while the stored choice stays stored, so the next plain run is back to
    # it; a pick from the menu is recorded as usual.
    alias Theme = Crysterm::CSS::Theme::Choice

    # The themes offered, in menu order: the terminal's own colors first, as
    # it is Crysterm's default, then the generated palettes, then the Qt
    # themes. `none` is not offered: it is no look of its own.
    THEMES = Theme.values - [Theme::None]

    # A reactive property, so the View → Theme entries bind to it
    # (`#build_menus`); `#theme` and `#theme=` are its plain face. Starts
    # as the theme Crysterm installed when the window was created, which is
    # its `colors.theme` option's.
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
    # (`CSS.resolve_theme`): the terminal one is derived from this window's
    # probe of the terminal, a Qt theme from its embedded sheet.
    private def crysterm_theme(choice : Theme) : Crysterm::CSS::Theme?
      Crysterm::CSS.resolve_theme choice, @window
    end

    private def theme_tip(theme : Theme) : String
      case theme
      in .terminal?         then "Draw the window in the terminal's own colors"
      in .dark?             then "Draw the window in Crysterm's dark theme"
      in .light?            then "Draw the window in Crysterm's light theme"
      in .none?             then "Draw the window unstyled"
      in .breeze_dark?      then "Draw the window in KDE's Breeze Dark"
      in .breeze_light?     then "Draw the window in KDE's Breeze Light"
      in .qdarkstyle_dark?  then "Draw the window in the QDarkStyle dark stylesheet"
      in .qdarkstyle_light? then "Draw the window in the QDarkStyle light stylesheet"
      in .qtmodern_dark?    then "Draw the window in the Qt Modern dark stylesheet"
      end
    end

    private def theme_label(theme : Theme) : String
      case theme
      in .terminal?         then "&Terminal Default"
      in .dark?             then "&Dark"
      in .light?            then "&Light"
      in .none?             then "&None"
      in .breeze_dark?      then "&Breeze Dark"
      in .breeze_light?     then "Breeze L&ight"
      in .qdarkstyle_dark?  then "&QDarkStyle Dark"
      in .qdarkstyle_light? then "QDarkStyle Li&ght"
      in .qtmodern_dark?    then "Qt &Modern Dark"
      end
    end
  end
end
