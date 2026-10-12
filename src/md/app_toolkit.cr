module Md
  class App
    # Four of Crysterm's own options in the menus, beside the theme and the
    # media backend: the ones a reader may want to change while md runs,
    # and would otherwise set on the command line (`--colors-depth`,
    # `--render-hyperlinks`, `--render-reduced-motion`, `--menu-tear-off`) or
    # in a config file.
    # Each is a reactive property the menu entries bind to; a change sets
    # the option, which is where Crysterm reads it, and the property is
    # linked to the option with the other settings (`app_config.cr`), so a
    # pick is kept across runs by the option's own name.
    #
    # View → Color Depth (`#color_depth`, `colors.depth`): how many colors
    # the window is drawn with — auto-detected from the terminal, the
    # default, or forced to monochrome, 8, 16, 256 or true color — for a
    # terminal that reports fewer colors than it shows, or more, or to see
    # a theme as a plainer terminal would. Crysterm redraws the whole window
    # at the new depth on the next frame.
    #
    # View → Terminal Links (`#hyperlinks`, `render.hyperlinks`): whether
    # the links in the viewer are also the terminal's own hyperlinks (OSC 8),
    # clickable or hoverable where the terminal does that — on where the
    # terminal is known to support them, the default; always, trusting the
    # terminal over the detection; or never, which turns the viewer's links
    # off altogether: drawn as plain text, not followed by a click, `Enter`
    # or `Tab` (Crysterm's `TextEdit#links_enabled`, Qt's
    # `LinksAccessibleByMouse`/`ByKeyboard` flags), as a reader who wants no
    # links expects of Never. Below the policies, Double-click to Open
    # (`#link_double_click?`, `md.link_double_click`) makes a double click
    # follow a link where a single one does by default — the single- or
    # double-click choice desktops offer — through `TextBrowser#double_click_links`;
    # a single click then only places the caret, as on any text.
    #
    # Options → Reduced Motion (`#reduced_motion?`, `render.reduced_motion`):
    # Crysterm's animations — a button's press, a fade — are skipped and
    # their end state shown at once, as a desktop's reduced-motion setting
    # asks.
    #
    # Options → Detachable Menus (`#tear_off_menus?`, `menu.tear_off`): every
    # menu gets a grab strip (`⠿⠿⠿`) in the middle of its top border, after
    # GNOME 2's tear-off menus (Qt's `QMenu::tearOffEnabled`). Dragging the
    # strip — or clicking it — tears off a copy of the menu that stays on
    # screen where it is dropped, with the same entries kept in step with the
    # menu's own (Crysterm's torn-off menu shares the `Action`s), movable by
    # its strip and closed by the `✕` at its right end; the ordinary menus
    # are unchanged. A torn-off menu stays until closed, option or no option.
    alias ColorDepth = Crysterm::ColorDepth
    alias Hyperlinks = Crysterm::AutoToggle

    # The depths offered, in menu order: the terminal's own, then from the
    # fewest colors up.
    COLOR_DEPTHS = [ColorDepth::Auto, ColorDepth::None, ColorDepth::Basic, ColorDepth::Ansi, ColorDepth::Xterm256, ColorDepth::TrueColor]

    # Reactive properties, starting as Crysterm's options have it, which is
    # what the window was created under.
    @color_depth : Crysterm::Reactive::Property(ColorDepth) = Crysterm::Reactive::Property.new(Crysterm::Config.colors_depth)
    @hyperlinks : Crysterm::Reactive::Property(Hyperlinks) = Crysterm::Reactive::Property.new(Crysterm::Config.render_hyperlinks)
    @reduced_motion : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(Crysterm::Config.render_reduced_motion)
    @tear_off_menus : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(Crysterm::Config.menu_tear_off)
    @link_double_click : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(false)

    def color_depth : ColorDepth
      @color_depth.value
    end

    # Forces the output color depth, or lets Crysterm detect it (View →
    # Color Depth); applied when it changes (`#wire_toolkit`).
    def color_depth=(depth : ColorDepth) : ColorDepth
      @color_depth.value = depth
    end

    def hyperlinks : Hyperlinks
      @hyperlinks.value
    end

    # Sets the terminal hyperlink policy (View → Terminal Links).
    def hyperlinks=(policy : Hyperlinks) : Hyperlinks
      @hyperlinks.value = policy
    end

    def reduced_motion? : Bool
      @reduced_motion.value
    end

    def link_double_click? : Bool
      @link_double_click.value
    end

    # Makes a double click, or a single one, follow a link in the viewer
    # (View → Terminal Links → Double-click to Open).
    def link_double_click=(value : Bool) : Bool
      @link_double_click.value = value
    end

    # Skips Crysterm's animations, or lets them run (Options → Reduced
    # Motion).
    def reduced_motion=(value : Bool) : Bool
      @reduced_motion.value = value
    end

    def tear_off_menus? : Bool
      @tear_off_menus.value
    end

    # Gives the menus their tear-off strips, or takes them away (Options →
    # Detachable Menus); a menu already torn off stays until closed.
    def tear_off_menus=(value : Bool) : Bool
      @tear_off_menus.value = value
    end

    # Applies the choices on changes, through Crysterm's options, where
    # Crysterm reads them; the frame is asked for where one is needed, as a
    # change from a setter paints nothing on its own.
    private def wire_toolkit : Nil
      @color_depth.on_change do
        Crysterm::Config.colors_depth = @color_depth.value
        @window.update
      end
      @hyperlinks.on_change do
        Crysterm::Config.render_hyperlinks = @hyperlinks.value
        apply_hyperlinks
        @window.update
      end
      apply_hyperlinks
      @reduced_motion.on_change { Crysterm::Config.render_reduced_motion = @reduced_motion.value }
      # The menus read the option live, and Crysterm repaints the open ones.
      @tear_off_menus.on_change { Crysterm::Config.menu_tear_off = @tear_off_menus.value }
      @link_double_click.on_change { @viewer.double_click_links = @link_double_click.value }
    end

    # Puts the hyperlink policy on the window — which took the option as its
    # own when it was created, so it is told of a change — and, for Never,
    # takes the viewer's links away as well.
    private def apply_hyperlinks : Nil
      @window.hyperlinks = @hyperlinks.value
      @viewer.links_enabled = !@hyperlinks.value.off?
    end

    private def color_depth_label(depth : ColorDepth) : String
      case depth
      in .auto?       then "&Auto-detect"
      in .none?       then "&Monochrome"
      in .basic?      then "&8 Colors"
      in .ansi?       then "1&6 Colors"
      in .xterm256?   then "&256 Colors"
      in .true_color? then "&True Color"
      end
    end

    private def color_depth_tip(depth : ColorDepth) : String
      case depth
      in .auto?       then "Draw with as many colors as the terminal reports having"
      in .none?       then "Draw in monochrome: the terminal's two colors, and reverse video for the rest"
      in .basic?      then "Draw with the 8 ANSI colors"
      in .ansi?       then "Draw with the 16 ANSI colors"
      in .xterm256?   then "Draw with the 256-color palette"
      in .true_color? then "Draw with true color, 16 million colors"
      end
    end

    private def hyperlinks_tip(policy : Hyperlinks) : String
      case policy
      in .auto? then "Make the viewer's links hyperlinks where the terminal is known to support them"
      in .on?   then "Make the viewer's links hyperlinks whatever the terminal, trusting it over the detection"
      in .off?  then "Turn the viewer's links off altogether: plain text, followed by nothing"
      end
    end

    private def hyperlinks_label(policy : Hyperlinks) : String
      case policy
      in .auto? then "&When the Terminal Supports Them"
      in .on?   then "&Always"
      in .off?  then "&Never"
      end
    end
  end
end
