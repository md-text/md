module Md
  class App
    # The menu bar: File (save, quit), View (which panes are shown, whether
    # the editor's and the viewer's carets follow each other, and whether
    # the caret's line is highlighted) and
    # Options (the two modes the status bar toggles — overwrite mode and the
    # mouse mode — so every setting is reachable from the keyboard through
    # the menus as well, `Alt-F`/`Alt-V`/`Alt-O` opening them). The checked
    # states mirror the application's and are re-synced by `#refresh_menus`
    # whenever the status bar refreshes.
    @view_actions = {} of Pane => Crysterm::Action
    @follow_action : Crysterm::Action?
    @highlight_action : Crysterm::Action?
    @mouse_actions = {} of MouseMode => Crysterm::Action
    @overwrite_action : Crysterm::Action?

    private def build_menus : Nil
      bar = @main.menu_bar

      file = bar.add_menu "&File"
      file.add_action("&Save") { save }
      file.add_action("Save &As…") { save_as_prompt }
      file.add_separator
      file.add_action("&Quit") { @window.quit }

      view = bar.add_menu "&View"
      Pane.each do |pane|
        # Crysterm's toggle action shows and hides the pane and keeps its
        # check on the pane's visibility; showing from the menu also focuses
        # the pane. The last shown pane's entry is disabled rather than
        # refused (`#refresh_menus`), where `#hide_pane` refuses the keys.
        action = widget(pane).toggle_view_action pane_label(pane)
        action.on(Crysterm::Event::Triggered) { |e| widget(pane).focus if e.checked }
        view.add_action action
        @view_actions[pane] = action
      end
      view.add_separator
      follow = Crysterm::Action.new "&Follow cursor", checkable: true, checked: @follow_cursor
      follow.on(Crysterm::Event::Triggered) { |e| self.follow_cursor = e.checked }
      view.add_action follow
      @follow_action = follow
      highlight = Crysterm::Action.new "&Highlight line", checkable: true, checked: @highlight_line
      highlight.on(Crysterm::Event::Triggered) { |e| self.highlight_line = e.checked }
      view.add_action highlight
      @highlight_action = highlight

      options = bar.add_menu "&Options"
      overwrite = Crysterm::Action.new "&Overwrite mode", checkable: true, checked: @editor.overwrite_mode?
      overwrite.on(Crysterm::Event::Triggered) { |e| @editor.overwrite_mode = e.checked }
      options.add_action overwrite
      @overwrite_action = overwrite

      # A radio group: exactly one mode is checked, and re-picking the checked
      # one keeps it.
      group = Crysterm::ActionGroup.new
      MouseMode.each do |mode|
        action = Crysterm::Action.new mouse_label(mode), checkable: true, checked: mode == @mouse_mode
        group.add_action action
        action.on(Crysterm::Event::Triggered) { self.mouse_mode = mode }
        @mouse_actions[mode] = action
      end
      options.add_submenu "&Mouse", MouseMode.values.map { |mode| @mouse_actions[mode] }
    end

    # Brings the checkable menu entries in line with the panes and modes.
    def refresh_menus : Nil
      last = visible_panes.size == 1
      @view_actions.each { |pane, action| action.enabled = !(last && widget(pane).visible?) }
      @follow_action.try &.checked = @follow_cursor
      @highlight_action.try &.checked = @highlight_line
      @overwrite_action.try &.checked = @editor.overwrite_mode?
      @mouse_actions.each { |mode, action| action.checked = mode == @mouse_mode }
    end

    private def pane_label(pane : Pane) : String
      case pane
      in .editor? then "&Editor"
      in .viewer? then "&Viewer"
      in .toc?    then "&Table of contents"
      end
    end

    private def mouse_label(mode : MouseMode) : String
      icon = mouse_icon
      case mode
      in .all?    then "#{icon}=&a (always)"
      in .normal? then "#{icon}=&n (while reading)"
      in .insert? then "#{icon}=&i (while editing)"
      in .off?    then "#{icon}= (&never)"
      end
    end
  end
end
