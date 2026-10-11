module Md
  class App
    # Three of Crysterm's own options in the menus, beside the theme and the
    # media backend: the ones a reader may want to change while md runs,
    # and would otherwise set on the command line (`--colors-depth`,
    # `--render-hyperlinks`, `--render-reduced-motion`) or in a config file.
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
    # terminal over the detection; or never, for a terminal that shows the
    # escape sequence instead.
    #
    # Options → Reduced Motion (`#reduced_motion?`, `render.reduced_motion`):
    # Crysterm's animations — a button's press, a fade — are skipped and
    # their end state shown at once, as a desktop's reduced-motion setting
    # asks.
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

    # Skips Crysterm's animations, or lets them run (Options → Reduced
    # Motion).
    def reduced_motion=(value : Bool) : Bool
      @reduced_motion.value = value
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
        # The window took the option as its own policy when it was created;
        # it is told too.
        @window.hyperlinks = @hyperlinks.value
        @window.update
      end
      @reduced_motion.on_change { Crysterm::Config.render_reduced_motion = @reduced_motion.value }
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

    private def hyperlinks_label(policy : Hyperlinks) : String
      case policy
      in .auto? then "&When the Terminal Supports Them"
      in .on?   then "&Always"
      in .off?  then "&Never"
      end
    end
  end
end
