module Md
  class App
    # View → Media Backend: how Crysterm draws images — the choices its
    # `--media-backend` option takes, as `QImageIOHandler` plugins or a
    # `QMediaPlayer`'s backends are a list to pick from. Auto-detect (the
    # default) leaves it to Crysterm, which picks the best backend the
    # terminal drives: Kitty graphics on a Kitty, Sixel on an xterm, sub-cell
    # glyphs or plain cells anywhere else. A pick names one instead and holds
    # it, drivable here or not (the user asked; Crysterm says so where the
    # terminal cannot, rather than quietly downgrading), so the menu disables
    # the entries this terminal cannot drive — ReGIS and Tektronix always,
    # since nothing detects them, the overlays without their helper program —
    # and Auto-detect never. Setting the property sets Crysterm's
    # `media.backend` option, and Crysterm rebuilds the media it resolved
    # under the old setting: every widget's CSS `background-image` layer is
    # dropped and comes back for the new backend on the next frame, in every
    # window. md's viewer renders no inline images today (the Markdown
    # importer degrades them to a placeholder glyph), so in md the visible
    # effect is on background images set by a stylesheet
    # (`--colors-stylesheet`), and on whatever media Crysterm adds later.
    #
    # "Change for 5s", above Auto-detect, is a trial: while it is checked, a
    # pick switches for `#media_trial_span` and then goes back to the backend
    # in force before the trial, so a backend can be seen without being
    # kept — a notice says what is on and that it is for a while. Another
    # pick during the trial restarts the time and keeps the same backend to
    # return to; picking that one ends the trial, as it is where the trial
    # would return. Unchecking "Change for 5s" during a trial keeps the
    # backend on screen and cancels the return, the one way to keep a trial's
    # backend without picking it again. The check is not kept across runs,
    # like Overwrite Mode; the backend itself is kept with the other
    # settings, by the name `--media-backend` spells it.
    alias MediaBackend = Crysterm::Widget::Media::Backend

    # The backends offered, in menu order: Auto-detect, then grouped by how
    # the pixels reach the window (`Media::Family`) — the cell grid, the
    # ANSI variants before the glyph ones; the terminal's own graphics,
    # Tektronix among them as the terminal draws that too; the external
    # overlays. The menu puts a separator between the groups.
    MEDIA_BACKENDS = [
      MediaBackend::Auto,
      MediaBackend::Ansi, MediaBackend::AnsiTrueColor, MediaBackend::AnsiC256, MediaBackend::AnsiC16, MediaBackend::AnsiC8,
      MediaBackend::Glyph, MediaBackend::GlyphBlock, MediaBackend::GlyphHalf, MediaBackend::GlyphQuadrant,
      MediaBackend::GlyphSextant, MediaBackend::GlyphOctant, MediaBackend::GlyphBraille, MediaBackend::GlyphAscii,
      MediaBackend::Sixel, MediaBackend::Regis, MediaBackend::Kitty, MediaBackend::Iterm, MediaBackend::Tek,
      MediaBackend::Overlay, MediaBackend::Ueberzug,
    ]

    # A reactive property, so the View → Media Backend entries bind to it
    # (`#build_media_menu`); `#media_backend` and `#media_backend=` are its
    # plain face. Starts as Crysterm's config has it, which is what the
    # window was created under: `--media-backend` or the default, Auto.
    @media_backend : Crysterm::Reactive::Property(MediaBackend) = Crysterm::Reactive::Property.new(Crysterm::Config.media_backend)

    # "Change for 5s": whether a pick is a trial. Not kept across runs.
    @media_trial = Crysterm::Reactive::Property(Bool).new(false)

    # How long a trial lasts; the menu entry names the default. Settable for
    # specs.
    property media_trial_span : Time::Span = 5.seconds

    # The backend in force before the running trial, to return to, or `nil`
    # when none is running; and the timer that returns.
    @media_trial_origin : MediaBackend?
    @media_trial_timer : Crysterm::Timer?

    # Set while the trial's return assigns the property, so the change
    # handler does not take the return for another trial pick.
    @media_trial_returning = false

    def media_backend : MediaBackend
      @media_backend.value
    end

    # Switches the backend; it is applied when it changes (the property's
    # change handler, in `#wire_media`). While "Change for 5s" is checked,
    # this starts or restarts a trial.
    def media_backend=(backend : MediaBackend) : MediaBackend
      @media_backend.value = backend
    end

    def media_trial? : Bool
      @media_trial.value
    end

    def media_trial=(on : Bool) : Bool
      @media_trial.value = on
    end

    # Whether a trial is running, with a return pending.
    def media_trial_running? : Bool
      !@media_trial_origin.nil?
    end

    # Applies the backend on changes, through Crysterm's option, which has
    # Crysterm rebuild the media resolved under the old one; the frame is
    # asked for here, as a change from a setter paints nothing on its own.
    # A pick under "Change for 5s" arms the return; the return itself, and a
    # pick of the backend the trial would return to, end the trial.
    private def wire_media : Nil
      previous = @media_backend.value
      @media_backend.on_change do
        backend = @media_backend.value
        Crysterm::Config.media_backend = backend
        @window.update
        if @media_trial_returning
          notice "Media backend: back to #{backend.label}"
        elsif @media_trial.value && backend != @media_trial_origin
          origin = (@media_trial_origin ||= previous)
          arm_media_trial
          notice "Media backend: #{backend.label} for #{media_trial_text}, then back to #{origin.label}"
        else
          cancel_media_trial
          notice "Media backend: #{backend.label}"
        end
        previous = backend
      end
      # Unchecking during a trial keeps what is on screen; the return is off.
      @media_trial.on_change { cancel_media_trial unless @media_trial.value }
    end

    # Starts, or restarts, the trial's clock; at its end the backend in
    # force before the trial is put back.
    private def arm_media_trial : Nil
      @media_trial_timer.try &.stop
      @media_trial_timer = @window.after(@media_trial_span) { end_media_trial }
    end

    # The trial's end: the backend before it comes back, unless the trial
    # was cancelled meanwhile.
    private def end_media_trial : Nil
      @media_trial_timer = nil
      return unless origin = @media_trial_origin
      @media_trial_origin = nil
      @media_trial_returning = true
      begin
        self.media_backend = origin
      ensure
        @media_trial_returning = false
      end
    end

    # Forgets the pending return, keeping the backend on screen.
    private def cancel_media_trial : Nil
      @media_trial_timer.try &.stop
      @media_trial_timer = nil
      @media_trial_origin = nil
    end

    # The trial's length as the entry and the notice say it: `5s`.
    private def media_trial_text : String
      span = @media_trial_span
      span < 1.second ? "#{span.total_milliseconds.to_i}ms" : "#{span.total_seconds.to_i}s"
    end

    # The View → Media Backend submenu: the trial check entry, a separator,
    # then the radio entries (`#add_choices`' manner: exactly the current
    # backend is checked, picking one sets the property) in `MEDIA_BACKENDS`'
    # order, a separator where the family changes, the entries this terminal
    # cannot drive disabled. Returns the backend entries in that order.
    private def build_media_menu(menu : Crysterm::Widget::Menu) : Array(Crysterm::Action)
      actions = [] of Crysterm::Action
      trial = Crysterm::Action.new "Change for &#{media_trial_text}", checkable: true
      trial.bind_checked @media_trial
      tip trial, "Try the next backend picked for #{media_trial_text}, then go back to the one before"
      actions << trial << Crysterm::Action.separator
      group = Crysterm::ActionGroup.new
      entries = [] of Crysterm::Action
      family = nil
      MEDIA_BACKENDS.each_with_index do |backend, index|
        actions << Crysterm::Action.separator if index > 0 && media_group(backend) != family
        family = media_group(backend)
        action = Crysterm::Action.new media_backend_label(backend), checkable: true
        action.bind_checked(@media_backend) { @media_backend.value == backend }
        tip action, media_backend_tip(backend)
        action.enabled = backend.available?(@window.tput)
        group.add_action action
        action.on(Crysterm::Event::Triggered) { @media_backend.value = backend }
        actions << action
        entries << action
      end
      tip menu.add_submenu("Media &Backend", actions), "How images are drawn: the best way this terminal has, or one named here"
      entries
    end

    # The menu's groups: Auto-detect alone, the cell grid, what the terminal
    # itself draws (in-band graphics and the Tektronix window), the external
    # overlays.
    private def media_group(backend : MediaBackend) : Int32
      case backend.family
      in Nil                                                                                then 0
      in Crysterm::Widget::Media::Family::Cells                                             then 1
      in Crysterm::Widget::Media::Family::Graphics, Crysterm::Widget::Media::Family::Window then 2
      in Crysterm::Widget::Media::Family::External                                          then 3
      end
    end

    # Crysterm's name for the backend, with a mnemonic; each letter once in
    # the submenu, `5` being Change for 5s'.
    private def media_backend_tip(backend : MediaBackend) : String
      case backend
      in .auto?            then "Let Crysterm pick the best way this terminal draws images"
      in .ansi?            then "Draw images as colored cells, one per pixel, at the terminal's color depth"
      in .ansi_true_color? then "Draw images as colored cells in true color"
      in .ansi_c256?       then "Draw images as colored cells from the 256-color palette"
      in .ansi_c16?        then "Draw images as colored cells from the 16 ANSI colors"
      in .ansi_c8?         then "Draw images as colored cells from the 8 ANSI colors"
      in .glyph?           then "Draw images with the finest sub-cell glyphs this terminal renders"
      in .glyph_block?     then "Draw images with solid blocks, one pixel per cell"
      in .glyph_half?      then "Draw images with half blocks, two pixels per cell"
      in .glyph_quadrant?  then "Draw images with quadrant blocks, four pixels per cell"
      in .glyph_sextant?   then "Draw images with sextant blocks, six pixels per cell"
      in .glyph_octant?    then "Draw images with octant blocks, eight pixels per cell"
      in .glyph_braille?   then "Draw images with Braille dots, eight per cell"
      in .glyph_ascii?     then "Draw images with ASCII characters alone"
      in .sixel?           then "Draw images with Sixel graphics, as xterm and VTE terminals do"
      in .regis?           then "Draw images with ReGIS vector graphics, on a DEC-compatible terminal"
      in .kitty?           then "Draw images with the Kitty graphics protocol"
      in .iterm?           then "Draw images with iTerm2's inline images protocol"
      in .tek?             then "Draw images in a Tektronix 4014 window, as xterm emulates one"
      in .overlay?         then "Draw images in a window a helper program lays over the terminal"
      in .ueberzug?        then "Draw images with the ueberzug helper, laid over the terminal"
      end
    end

    private def media_backend_label(backend : MediaBackend) : String
      case backend
      in .auto?            then "&Auto-detect"
      in .ansi?            then "A&NSI, One Cell per Pixel"
      in .ansi_true_color? then "ANSI, &True Color"
      in .ansi_c256?       then "ANSI, 25&6 Colors"
      in .ansi_c16?        then "ANSI, &16 Colors"
      in .ansi_c8?         then "ANSI, &8 Colors"
      in .glyph?           then "Sub-Cell &Glyphs"
      in .glyph_block?     then "Solid &Blocks"
      in .glyph_half?      then "Unicode &Half Blocks"
      in .glyph_quadrant?  then "Unicode &Quadrants"
      in .glyph_sextant?   then "Unicode Se&xtants"
      in .glyph_octant?    then "Unicode &Octants"
      in .glyph_braille?   then "Braille &Dots"
      in .glyph_ascii?     then "ASCII &Contours"
      in .sixel?           then "&Sixel"
      in .regis?           then "&ReGIS"
      in .kitty?           then "&Kitty Graphics"
      in .iterm?           then "&iTerm2 Inline Images"
      in .tek?             then "Tektronix 401&4"
      in .overlay?         then "&w3mimgdisplay Overlay"
      in .ueberzug?        then "Überzug Overla&y"
      end
    end
  end
end
