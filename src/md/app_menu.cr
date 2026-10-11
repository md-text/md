module Md
  class App
    # The menu bar: File (open, the recent files, reload, save, quit), Edit
    # (find, repeat the find, go to a line, jump between headings), View
    # (which panes are shown, whether the editor's and the viewer's carets
    # follow each other, whether the caret's line is highlighted, whether
    # the editor numbers its lines, and whether the file is watched) and
    # Options (the two modes the status bar toggles — overwrite mode and the
    # mouse mode — the unsaved-changes guard, auto-save and the backup file
    # (`app_autosave.cr`) and the theme, so every setting is reachable from the keyboard through the menus as well,
    # `Alt+F`/`Alt+E`/`Alt+V`/`Alt+O` opening them). The checked states are
    # bound to what they stand for (`Action#bind_checked`): the View and
    # Options settings, the mouse mode and the theme are reactive
    # properties, the pane entries follow the panes, and the overwrite and
    # line-number entries follow the editor. Only the pane entries' enabled
    # state is re-synced by `#refresh_menus`; the recent files are remade by
    # `#refresh_recent_menu`.
    #
    # An entry with a key carries it as its shortcut (`Action#shortcut`, in
    # Qt's spelling, `Ctrl+O`): the menu shows it in its right-hand column,
    # and Crysterm fires the entry on the key from anywhere in the window —
    # after the focused pane had its turn, so the editor keeps the keys it
    # uses, and not while a prompt is open. The View entries have none: the
    # pane keys (`F2`–`F4`, `#app_key`) show and focus a pane or hide the
    # focused one, a different gesture from the entries' show-and-hide, so
    # they stay application keys, with `F5` and the pager letters
    # (`#pager_key`).
    @view_actions = {} of Pane => Crysterm::Action

    private def build_menus : Nil
      bar = @main.menu_bar

      file = bar.add_menu "&File"
      file.add_action("&Open…", shortcut: "Ctrl+O") { open_prompt }
      # Filled from the history (`#refresh_recent_menu`); without one, an
      # empty, disabled entry says the feature exists.
      recent = file.add_submenu "Open &Recent"
      recent.enabled = false
      @recent_action = recent
      file.add_action("&Reload", shortcut: "Ctrl+R") { reload }
      file.add_separator
      file.add_action("&Save", shortcut: "Ctrl+S") { save }
      file.add_action("Save &As…") { save_as_prompt }
      file.add_separator
      # The same key as Crysterm's default quit key: the entry's shortcut
      # consumes it, so the default stands down and the one path — the
      # window's close request, with the unsaved-changes guard on it — is
      # taken once.
      file.add_action("&Quit", shortcut: "Ctrl+Q") { quit }

      edit = bar.add_menu "&Edit"
      edit.add_action("&Find…", shortcut: "Ctrl+F") { search_prompt }
      edit.add_action("Find &Next", shortcut: "Ctrl+G") { find_next }
      edit.add_action("Find &Previous", shortcut: "Alt+G") { find_next reverse: true }
      edit.add_action("Clear &Highlight") { clear_search_highlight }
      edit.add_separator
      edit.add_action("&Go to Line…", shortcut: "Ctrl+L") { go_to_line_prompt }
      edit.add_action("Nex&t Heading", shortcut: "Alt+Down") { jump_heading 1 }
      edit.add_action("Pre&vious Heading", shortcut: "Alt+Up") { jump_heading -1 }
      add_navigation_actions edit

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
      # The editor's own state, like overwrite mode: the gutter is Crysterm's
      # (`PlainTextEdit#line_numbers`), the entry follows its event.
      numbers = Crysterm::Action.new "Line &numbers", checkable: true
      numbers.bind_checked(@editor, Crysterm::Event::LineNumbersChanged) { @editor.line_numbers? }
      numbers.on(Crysterm::Event::Triggered) { |e| @editor.line_numbers = e.checked }
      view.add_action numbers
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
      autosave = Crysterm::Action.new "A&uto-save", checkable: true
      autosave.bind_checked @autosave
      options.add_action autosave
      backup = Crysterm::Action.new "&Keep a backup file", checkable: true
      backup.bind_checked @backup_file
      options.add_action backup

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
      add_theme_menu options

      # The bar's right end names the keys that reach it, since the bar is
      # off the Tab chain and nothing else on screen says so: `F10` (the
      # bar's `activation_key`) and the titles' `Alt-<letter>` mnemonics. A
      # plain label floating over the bar, outside its row of titles; the
      # theme paints whatever sits on a bar in the bar's color, so it reads
      # as part of the bar like the titles do.
      hint = Crysterm::Widget::Label.new "#{menu_keys_text} ", top: 0, right: 0, height: 1
      bar.append hint
    end

    # What the menu bar's hint says: the activation key and the first
    # title's mnemonic, e.g. `Menu = F10 / Alt+F`, spelled as the menus
    # spell their shortcuts.
    private def menu_keys_text : String
      bar = @main.menu_bar
      keys = [] of String
      bar.activation_key.try { |key| keys << Crysterm::Action.key_stroke_text(key) }
      bar.mnemonics.first?.try { |letter| keys << "Alt+#{letter.upcase}" }
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
