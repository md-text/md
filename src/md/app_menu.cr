module Md
  class App
    # The menu bar: File (open, the recent files, reload, the previous and
    # the next file, save, quit), Edit (copy, paste and paste from a named
    # source, find, repeat the find, replace, go to a line, jump between
    # headings), Format (the Markdown markup, `app_edit.cr`), View (which panes
    # are shown and whether they resize, whether the editor's and the viewer's
    # carets are kept in sync, whether the caret's line is highlighted,
    # whether the editor numbers its lines, the text's layout — soft wrap,
    # hard wrap, a text width and its centering, rulers and guides — the
    # theme the window is drawn in, how images are drawn (Media Backend, with
    # its Change for 5s trial, `app_media.cr`), how questions are asked
    # (Dialog Style, `app_dialogs.cr`) and whether the file is watched) and
    # Options (the two
    # modes the status bar toggles — overwrite mode and the mouse mode — the
    # unsaved-changes guard, auto-save and the backup file
    # (`app_autosave.cr`), the clipboard mode, the config file's entries
    # (`app_config.cr`) and Clear Caches…,
    # `app_caches.cr`), so every setting is reachable from the keyboard
    # through the menus as well, `Alt+F`/`Alt+E`/`Alt+M`/`Alt+V`/`Alt+O`
    # opening them (Format's letter is `m`, since Options has `o` and `Alt+R`
    # resizes the panes).
    #
    # The checked states are bound to what they stand for
    # (`Action#bind_checked`): a setting that is a reactive property gets a
    # check entry (`#add_toggle`) or, for a choice among several, a radio
    # submenu (`#add_choices`, Qt's exclusive `QActionGroup`: exactly one
    # entry is checked, and re-picking it keeps it); the pane entries follow
    # the panes, and the overwrite entry follows the
    # editor. Only the pane entries' enabled state is re-synced by
    # `#refresh_menus`; the recent files are remade by `#refresh_recent_menu`.
    #
    # An entry with a key carries it as its shortcut (`Action#shortcut`, in
    # Qt's spelling, `Ctrl+O`): the menu shows it in its right-hand column,
    # and Crysterm fires the entry on the key from anywhere in the window —
    # after the focused pane had its turn, so the editor keeps the keys it
    # uses, and not while a prompt is open. Of the View entries only Soft
    # Wrap (`Alt+W`, free in the editor, where `Alt+Z` is redo) has one: the
    # pane keys (`F1`–`F3`, `#app_key`) show and focus a pane or hide the
    # focused one, a different gesture from the entries' show-and-hide, so
    # they stay application keys, with `F4` (the bars, whose entry would
    # vanish with them), `F5`, `Alt+R` (which moves a divider,
    # where the Resizable Panes entry locks and unlocks them) and the pager
    # letters (`#pager_key`).
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
      # The files left, retraced (`app_links.cr`).
      add_navigation_actions file
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
      # `Ctrl+C` reaches the entry when the focused pane has no selection to
      # copy itself, `Ctrl+V` from a pane that does not paste
      # (`app_clipboard.cr`).
      edit.add_action("&Copy", shortcut: "Ctrl+C") { copy }
      edit.add_action("Copy as &Markdown") { copy_as_markdown }
      add_paste_actions edit
      edit.add_separator
      edit.add_action("&Find…", shortcut: "Ctrl+F") { search_prompt }
      edit.add_action("Find &Next", shortcut: "Ctrl+G") { find_next }
      edit.add_action("Find &Previous", shortcut: "Alt+G") { find_next reverse: true }
      edit.add_action("&Replace…", shortcut: "Alt+H") { replace_prompt }
      edit.add_action("Clear Search &Highlights") { clear_search_highlight }
      edit.add_separator
      edit.add_action("&Go to Line…", shortcut: "Ctrl+L") { go_to_line_prompt }
      edit.add_action("Nex&t Heading", shortcut: "Alt+Down") { jump_heading 1 }
      edit.add_action("Pre&vious Heading", shortcut: "Alt+Up") { jump_heading -1 }

      build_format_menu bar

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
      add_toggle view, "Resi&zable Panes", @resizable_panes
      # `F4` is the key, and the way back once the bars are gone.
      add_toggle view, "Menu and Status &Bars", @bars
      view.add_separator
      add_toggle view, "S&ync Cursor", @sync_cursor
      add_toggle view, "&Highlight Line", @highlight_line
      add_toggle view, "Line &Numbers", @line_numbers
      view.add_separator
      add_toggle(view, "&Soft Wrap", @soft_wrap).shortcut = "Alt+W"
      add_toggle view, "H&ard Wrap", @hard_wrap
      add_choices(view, "Te&xt Width", TEXT_WIDTHS, @text_width) { |width| text_width_label width }
      add_toggle view, "&Center Text", @center_text
      # `u` and `g`: Resizable Panes takes `z`, so `r` is free, but `u` stays.
      view.add_submenu "R&ulers", [toggle_action("&Horizontal", @horizontal_ruler), toggle_action("&Vertical", @vertical_ruler)]
      add_toggle view, "&Guides", @guides
      view.add_separator
      # The colors the window is drawn in, with the other appearance choices;
      # `F6` cycles them (`app_theme.cr`).
      add_choices(view, "The&me", THEMES, @theme) { |theme| theme_label theme }
      # How images are drawn, with the Change for 5s trial (`app_media.cr`).
      build_media_menu view
      # Two more of Crysterm's options (`app_toolkit.cr`); `L` and `K` are
      # free here.
      add_choices(view, "Co&lor Depth", COLOR_DEPTHS, @color_depth) { |depth| color_depth_label depth }
      add_choices(view, "Terminal Lin&ks", Hyperlinks.values, @hyperlinks) { |policy| hyperlinks_label policy }
      view.add_separator
      add_choices(view, "&Dialog Style", DialogStyle.values, @dialog_style) { |style| dialog_style_label style }
      add_toggle view, "&Watch File", @watch_file

      options = bar.add_menu "&Options"
      overwrite = Crysterm::Action.new "&Overwrite Mode", checkable: true
      overwrite.bind_checked(@editor, Crysterm::Event::OverwriteModeChanged) { @editor.overwrite_mode? }
      overwrite.on(Crysterm::Event::Triggered) { |e| @editor.overwrite_mode = e.checked }
      options.add_action overwrite
      add_toggle options, "&Ask Before Discarding Changes", @confirm_discard
      add_toggle options, "A&uto-Save", @autosave
      add_toggle options, "&Keep a Backup File", @backup_file
      add_choices(options, "&Mouse", MouseMode.values, @mouse_mode) { |mode| mouse_label mode }
      # The Command entry names the command found, and cannot be picked when
      # there is none.
      clipboard = add_choices(options, "&Clipboard", ClipboardMode.values, @clipboard_mode) { |mode| clipboard_label mode }
      clipboard[ClipboardMode::Command.value].enabled = !self.clipboard.copy_command.nil?
      # Crysterm's `render.reduced_motion` (`app_toolkit.cr`); `d` is free.
      add_toggle options, "Re&duced Motion", @reduced_motion
      options.add_separator
      # The config file (`app_config.cr`): applied from a file now, written
      # now, or written elsewhere; `L` and `S` are free here, `A` is Ask's.
      options.add_action("&Load Config…") { load_config_prompt }
      options.add_action("&Save Config") { save_config_now }
      options.add_action("Sa&ve Config As…") { save_config_prompt }
      options.add_separator
      # `C` is the clipboard's; the ellipsis says it asks first.
      options.add_action("Clea&r Caches…") { clear_caches_prompt }

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

    # A check entry for a setting that is a reactive property, its check
    # bound to the property and the property set by the entry.
    private def add_toggle(menu : Crysterm::Widget::Menu, text : String, property : Crysterm::Reactive::Property(Bool)) : Crysterm::Action
      menu.add_action toggle_action(text, property)
    end

    # A checkable entry bound to *property*, for a menu or a submenu.
    private def toggle_action(text : String, property : Crysterm::Reactive::Property(Bool)) : Crysterm::Action
      action = Crysterm::Action.new text, checkable: true
      action.bind_checked property
      action
    end

    # A radio submenu *title* for a setting that is a choice among
    # *choices*, each entry labelled by *label*: exactly the chosen one is
    # checked, and picking an entry sets the property. Returns the entries
    # in *choices*' order.
    private def add_choices(menu : Crysterm::Widget::Menu, title : String, choices : Enumerable(T), property : Crysterm::Reactive::Property(T), &label : T -> String) : Array(Crysterm::Action) forall T
      group = Crysterm::ActionGroup.new
      actions = choices.map do |choice|
        action = Crysterm::Action.new label.call(choice), checkable: true
        action.bind_checked(property) { property.value == choice }
        group.add_action action
        action.on(Crysterm::Event::Triggered) { property.value = choice }
        action
      end
      menu.add_submenu title, actions
      actions
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
      in .toc?    then "&Table of Contents"
      end
    end

    private def mouse_label(mode : MouseMode) : String
      icon = mouse_icon
      case mode
      in .all?    then "#{icon}=&a (Always)"
      in .normal? then "#{icon}=&n (While Reading)"
      in .insert? then "#{icon}=&i (While Editing)"
      in .off?    then "#{icon}= (&Never)"
      end
    end
  end
end
