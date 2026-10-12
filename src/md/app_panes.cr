module Md
  class App
    # The central area: a horizontal `Splitter` (Qt's `QSplitter`) holding
    # the editor, the viewer and the table of contents in `Pane` order, a
    # one-cell divider between neighbours. The editor and the viewer stretch
    # (`set_stretch_factor`): they share the width equally until a divider is
    # moved, and keep that proportion after, through terminal resizes; the
    # table of contents is a fixed column of `TOC_WIDTH` cells. A hidden pane
    # takes no width and shows no divider, and shown again it gets back the
    # width it had.
    #
    # A divider moves with the mouse, and from the keyboard through `Alt+R`
    # (`#resize_panes`, an application key): it focuses the divider at the
    # focused pane's right — its left for the last pane — so the arrow keys
    # move it a column at a time, and `Enter` or `Escape` (`#leave_divider`)
    # returns to the pane. The dividers are off the Tab chain, so `Tab` keeps
    # cycling the panes, and leaves a divider too. Qt has no keyboard for its
    # handles; a focused divider is the smallest addition that makes the
    # mouse optional, as it is everywhere else in md.
    #
    # Options → Resizable Panes (`#resizable_panes?`, a setting) is whether the
    # dividers move at all: unchecked, the panes stay locked as they are —
    # the splitter's `resizable` (Qt disables the handles) refuses the mouse
    # and the keys, and `Alt+R` says so — until it is checked again.
    #
    # The sizes are kept across runs as the splitter's state (`#pane_sizes`,
    # Qt's `saveState`): the width each pane wants, in cells — `[editor,
    # viewer, toc]`, 0 for a pane never sized — restored and recorded with
    # the other settings (`app_config.cr`). Cells rather than proportions:
    # the table of contents is a column that should not scale with the
    # terminal, and the splitter fits the two stretching panes to the width
    # at hand in proportion anyway, so a wider or narrower terminal next time
    # keeps the split the user set.
    getter splitter : Crysterm::Widget::Splitter

    # Options → Resizable Panes; see the class comment. A reactive property, so
    # the menu entry binds to it (`#build_menus`) and the config keeps it
    # (`app_config.cr`); `#resizable_panes?` and `#resizable_panes=` are
    # its plain face.
    @resizable_panes : Crysterm::Reactive::Property(Bool) = Crysterm::Reactive::Property.new(true)

    def resizable_panes? : Bool
      @resizable_panes.value
    end

    # Lets the dividers move, or locks the panes as they are (View →
    # Resizable Panes), through the property's change handler
    # (`#wire_resizable`).
    def resizable_panes=(value : Bool) : Bool
      @resizable_panes.value = value
    end

    # Fills the central splitter with the panes (from `#initialize`).
    private def build_central : Nil
      @main.central_widget = @splitter
      Pane.each { |pane| @splitter.add_widget widget(pane) }
      @splitter.set_stretch_factor Pane::Editor.value, 1
      @splitter.set_stretch_factor Pane::Viewer.value, 1
      @splitter.sizes = [0, 0, TOC_WIDTH]
    end

    # The widths the panes want, in cells, hidden panes included.
    def pane_sizes : Array(Int32)
      @splitter.save_state
    end

    # Gives the panes widths `#pane_sizes` returned; anything else (another
    # number of entries) is ignored.
    def pane_sizes=(sizes : Array(Int32)) : Nil
      @splitter.restore_state sizes
    end

    # The choice takes effect when it changes, whoever changed it (the menu
    # entry, the setter, the settings restored at start); locking while a
    # divider has the keys sends them back to the pane (from `#initialize`).
    private def wire_resizable : Nil
      @resizable_panes.on_change do
        @splitter.resizable = @resizable_panes.value
        leave_divider unless @resizable_panes.value
        refresh_status
      end
    end

    # `Alt+R`: focuses the divider beside the focused pane, for the arrow
    # keys to move. Nothing to resize with one pane shown, and a notice
    # instead while the panes are locked.
    def resize_panes : Nil
      unless @resizable_panes.value
        notice "Panes are locked (Options → Resizable Panes)"
        return
      end
      shown = visible_panes
      return if shown.size < 2
      current = shown.find { |pane| widget(pane).focused? } || shown.first
      index = shown.index!(current)
      index -= 1 if index == shown.size - 1
      @splitter.dividers[shown[index].value].focus
    end

    # `Enter` or `Escape` on a focused divider: back to the pane at its left.
    # Returns whether a divider had the focus.
    private def leave_divider : Bool
      return false unless divider = @splitter.dividers.find(&.focused?)
      widget(Pane.from_value(divider.index)).focus
      true
    end
  end
end
