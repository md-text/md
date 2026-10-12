module Md
  class App
    # View → Tooltips: where a menu entry's description shows while the
    # entry is highlighted. Every entry has one sentence saying what it does
    # — an entry bound to a setting takes its option's description
    # (`#option_tip`), so the text is written once, in `config.cr`; a command
    # has its own, written beside the entry — set as the action's status tip
    # and its tooltip alike, as Qt's `QAction` carries a `statusTip` and a
    # `toolTip` (`#tip`). Crysterm then shows it the way the choice says:
    #
    # In Status Bar, the default: the sentence takes the status bar's
    # message field at once, the moment the entry is highlighted, and the
    # field comes back when the highlight leaves (Crysterm's `StatusTip`
    # event, Qt's `QStatusTipEvent`, which `QMainWindow` shows in its status
    # bar). As a Popup: after a moment (Crysterm's `tool_tip.delay`, 700 ms
    # like Qt's tooltip wake-up), a small popup beside the entry, inert and
    # gone as soon as the highlight moves on (Qt's `QMenu::toolTipsVisible`).
    # Never: neither. Whatever the choice, `F1` on a highlighted entry shows
    # its description in the popup, as Qt's `F1` in a menu opens the
    # entry's What's This.
    #
    # Applied to the main window (`status_tips`) and the bar's top-level
    # menus (`tool_tips_visible`), whose submenus — built fresh from their
    # entries' `menu` arrays on every open — inherit the setting; a menu
    # added later gets it by a call to `#apply_tooltips`. Kept across runs
    # with the other settings (`md.tooltips`, `app_config.cr`).
    enum Tooltips
      # In the status bar, at once.
      StatusBar
      # In a popup beside the entry, after a moment.
      Popup
      # Nowhere.
      Off
    end

    # A reactive property, so the View → Tooltips entries bind to it
    # (`#build_menus`); `#tooltips` and `#tooltips=` are its plain face.
    @tooltips : Crysterm::Reactive::Property(Tooltips) = Crysterm::Reactive::Property.new(Tooltips::StatusBar)

    def tooltips : Tooltips
      @tooltips.value
    end

    # Picks where the descriptions show (View → Tooltips); applied when
    # it changes (`#wire_tips`).
    def tooltips=(mode : Tooltips) : Tooltips
      @tooltips.value = mode
    end

    # Applies the choice now and on every change (from `#initialize`, once
    # the menus exist).
    private def wire_tips : Nil
      # A tip shows only while its entry is highlighted, so it may take the
      # whole bar when it needs it, covering the permanent fields for that
      # moment (Crysterm's `MainWindow#status_tips_full_width`).
      @main.status_tips_full_width = true
      @tooltips.on_change { apply_tooltips }
      apply_tooltips
    end

    # Puts the choice on the main window and on every menu of the bar — the
    # ones there are now, so a menu added later needs another call.
    private def apply_tooltips : Nil
      mode = @tooltips.value
      @main.status_tips = mode.status_bar?
      @main.menu_bar.menus.each &.tool_tips_visible = mode.popup?
    end

    # Gives *action* the description *text*, as its status tip — with the
    # leading space md's fields and notices share, so it lines up with them
    # in the bar — and as its tooltip and its What's This, the one text for
    # the three ways it is shown; returns the action.
    private def tip(action : Crysterm::Action, text : String) : Crysterm::Action
      action.status_tip = " #{text}"
      action.tool_tip = text
      action.whats_this = text
      action
    end

    # The description of the entry bound to the option *key*: the option's
    # description (`config.cr`) with its menu path stripped — `View → Sync
    # Cursor: keep the…` is `Keep the…` — so the two are one text.
    private def option_tip(key : String) : String
      text = Crysterm::Config[key].description.split(": ", 2).last
      text[0].upcase + text[1..]
    end

    private def tooltips_label(mode : Tooltips) : String
      case mode
      in .status_bar? then "In &Status Bar"
      in .popup?      then "As a &Popup"
      in .off?        then "&Never"
      end
    end

    private def tooltips_tip(mode : Tooltips) : String
      case mode
      in .status_bar? then "Show a highlighted entry's description in the status bar at once"
      in .popup?      then "Show a highlighted entry's description in a popup beside it after a moment"
      in .off?        then "Show no descriptions; F1 on a highlighted entry still shows it beside the entry"
      end
    end
  end
end
