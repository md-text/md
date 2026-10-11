module Md
  class App
    # The menu bar: File (open, the recent files, reload, save, quit), Edit
    # (find, repeat the find, go to a line), View (which panes are shown,
    # whether the editor's and the viewer's carets follow each other,
    # whether the caret's line is highlighted, and whether the file is
    # watched) and Options (the two modes the status bar toggles — overwrite
    # mode and the mouse mode — and the unsaved-changes guard, so every
    # setting is reachable from the keyboard through the menus as well,
    # `Alt-F`/`Alt-E`/`Alt-V`/`Alt-O` opening them). The checked states are
    # bound to what they stand for (`Action#bind_checked`): the View and
    # Options settings and the mouse mode are reactive properties, the pane
    # entries follow the panes, and the overwrite entry follows the editor.
    # Only the pane entries' enabled state is re-synced by `#refresh_menus`;
    # the recent files are remade by `#refresh_recent_menu`.
    @view_actions = {} of Pane => Crysterm::Action

    private def build_menus : Nil
      bar = @main.menu_bar

      file = bar.add_menu "&File"
      file.add_action("&Open…") { open_prompt }
      # Filled from the history (`#refresh_recent_menu`); without one, an
      # empty, disabled entry says the feature exists.
      recent = file.add_submenu "Open &Recent"
      recent.enabled = false
      @recent_action = recent
      file.add_action("&Reload") { reload }
      file.add_separator
      file.add_action("&Save") { save }
      file.add_action("Save &As…") { save_as_prompt }
      file.add_separator
      file.add_action("&Quit") { quit }

      edit = bar.add_menu "&Edit"
      edit.add_action("&Find…") { search_prompt }
      edit.add_action("Find &Next") { find_next }
      edit.add_action("Find &Previous") { find_next reverse: true }
      edit.add_action("Clear &Highlight") { clear_search_highlight }
      edit.add_separator
      edit.add_action("&Go to Line…") { go_to_line_prompt }

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
      follow = Crysterm::Action.new "&Follow cursor", checkable: true
      follow.bind_checked @follow_cursor
      view.add_action follow
      highlight = Crysterm::Action.new "&Highlight line", checkable: true
      highlight.bind_checked @highlight_line
      view.add_action highlight
      view.add_separator
      watch = Crysterm::Action.new "&Watch file", checkable: true
      watch.bind_checked @watch_file
      view.add_action watch

      options = bar.add_menu "&Options"
      overwrite = Crysterm::Action.new "&Overwrite mode", checkable: true
      overwrite.bind_checked(@editor, Crysterm::Event::OverwriteModeChanged) { @editor.overwrite_mode? }
      overwrite.on(Crysterm::Event::Triggered) { |e| @editor.overwrite_mode = e.checked }
      options.add_action overwrite
      confirm = Crysterm::Action.new "&Ask before discarding changes", checkable: true
      confirm.bind_checked @confirm_discard
      options.add_action confirm

      # A radio group: exactly one mode is checked, and re-picking the checked
      # one keeps it.
      group = Crysterm::ActionGroup.new
      modes = MouseMode.values.map do |mode|
        action = Crysterm::Action.new mouse_label(mode), checkable: true
        action.bind_checked(@mouse_mode) { @mouse_mode.value == mode }
        group.add_action action
        action.on(Crysterm::Event::Triggered) { self.mouse_mode = mode }
        action
      end
      options.add_submenu "&Mouse", modes

      # The bar's right end names the keys that reach it, since the bar is
      # off the Tab chain and nothing else on screen says so: `F10` (the
      # bar's `activation_key`) and the titles' `Alt-<letter>` mnemonics. A
      # plain label floating over the bar, outside its row of titles, in the
      # titles' style so it reads as part of the bar.
      hint = Crysterm::Widget::Label.new "#{menu_keys_text} ", top: 0, right: 0, height: 1
      hint.styles.normal = bar.style.item.dup
      bar.append hint
    end

    # What the menu bar's hint says: the activation key and the first
    # title's mnemonic, e.g. `Menu = F10 / Alt-F`.
    private def menu_keys_text : String
      bar = @main.menu_bar
      keys = [] of String
      bar.activation_key.try { |key| keys << key.to_s }
      bar.mnemonics.first?.try { |letter| keys << "Alt-#{letter.upcase}" }
      "Menu = #{keys.join(" / ")}"
    end

    # Keeps the last shown pane's View entry from hiding it; the other
    # entries follow their state through their bindings.
    def refresh_menus : Nil
      last = visible_panes.size == 1
      @view_actions.each { |pane, action| action.enabled = !(last && widget(pane).visible?) }
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
