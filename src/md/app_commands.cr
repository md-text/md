module Md
  class App
    # Commands: every action md has is named (`Action#name`, Qt's
    # `objectName`), and a command line runs it by that name, as vi's `:`
    # runs an ex command — `:save`, `:soft-wrap`, `:theme-breeze-dark`.
    # Names are kebab-case and fixed: a label may change, the name stays,
    # as Qt Creator's command ids and KDE's action names do. A menu entry's
    # name is given where the entry is built; a radio submenu's entries are
    # named after the submenu and the choice (`#add_choices`, `#command_slug`).
    # The keys no menu entry has — the pane keys, `F4`–`F6`, `Ctrl-Z`, `Alt-R`
    # — are named actions on the main window too (`#build_key_actions`),
    # their shortcuts fired by Crysterm on the same terms as the entries';
    # the pager's letters run named actions (`#pager_key`). Entries made on
    # the fly — the recent files, the windows, the kill ring — are not
    # commands.
    #
    # The command line is the viewer's `:` and Edit → Run Command… (`Alt-K`,
    # as Qt Creator's locator is `Ctrl-K`): a line number goes to the line, as
    # it did, anything else is a command name, `Tab` completing it
    # (`#command_prompt`). Crysterm finds the action by name among those the
    # window's widgets own (`#find_action`).

    # Names *action* and returns it: the entries are built in one expression.
    private def named(name : String, action : Crysterm::Action) : Crysterm::Action
      action.name = name
      action
    end

    # The part of a choice entry's name that names the choice: an enum member
    # in kebab-case (`BreezeDark` → `breeze-dark`), a number as written, with
    # `0` — no text width — as `off`.
    private def command_slug(choice : Enum) : String
      choice.to_s.underscore.tr("_", "-")
    end

    # :ditto:
    private def command_slug(choice : Int) : String
      choice.zero? ? "off" : choice.to_s
    end

    # The action named *name* in this window, or nil.
    def find_action(name : String) : Crysterm::Action?
      @window.find_action name
    end

    # Every command's name in this window, sorted.
    def command_names : Array(String)
      @window.find_actions.compact_map(&.name).uniq!.sort!
    end

    # Runs the command *name* (`Action#trigger`: a check entry flips, a
    # choice is picked), or says why not — no such command, or one that
    # cannot run now (a disabled entry, as its menu shows it). Returns
    # whether it ran.
    def run_command(name : String) : Bool
      unless action = find_action(name)
        notice "No such command: #{name}"
        return false
      end
      unless action.enabled?
        notice "Cannot run #{name} now"
        return false
      end
      action.trigger
      true
    end

    # The command line (`:`): a number goes to that line (`#go_to_line`), a
    # name runs that command (`#run_command`), `Tab` completing names. A line
    # prompt completes with the command names; a modal dialog has no
    # completion.
    def command_prompt : Nil
      ask_text(":", "", question: "Command or line:", completer: command_completer) do |answer|
        next unless answer
        text = answer.strip
        next if text.empty?
        if line = text.to_i?
          go_to_line line
        else
          run_command text
        end
      end
    end

    # Completes a command name from its start, the names in order.
    private def command_completer : Proc(String, Array(String))
      ->(text : String) { command_names.select(&.starts_with?(text.strip)) }
    end

    # The named actions behind the keys no menu entry has, on the main
    # window, so Crysterm fires them as it fires the entries' shortcuts —
    # after the focused pane had its turn, and not while a question is up —
    # and the command line finds them. The pane keys show and focus a pane,
    # or hide the focused one (`#toggle_pane`), a gesture of their own beside
    # View's show-and-hide entries.
    private def build_key_actions : Nil
      {
        {"toggle-editor", "Editor Pane", "F1", -> { toggle_pane Pane::Editor }, "Show and focus the editor, or hide it when it has the focus"},
        {"toggle-viewer", "Viewer Pane", "F2", -> { toggle_pane Pane::Viewer }, "Show and focus the viewer, or hide it when it has the focus"},
        {"toggle-toc", "Table of Contents Pane", "F3", -> { toggle_pane Pane::Toc }, "Show and focus the table of contents, or hide it when it has the focus"},
        {"toggle-bars", "Menu and Status Bars", "F4", -> { toggle_bars }, "Hide the menu and status bars, or show them again"},
        {"cycle-mouse-mode", "Next Mouse Mode", "F5", -> { cycle_mouse_mode; nil }, "Go on to the next mouse mode: a, n, i, off"},
        {"cycle-theme", "Next Theme", "F6", -> { cycle_theme; nil }, "Go on to the next theme"},
        {"suspend", "Suspend", "Ctrl+Z", -> { suspend }, "Stop md and go back to the shell, until fg"},
        {"resize-panes", "Resize Panes", "Alt+R", -> { resize_panes }, "Move a divider between the panes with the arrow keys"},
        {"find-backward", "Find Backward…", nil, -> { search_prompt backward: true }, "Search the document backward for a pattern"},
      }.each do |name, text, key, run, description|
        action = Crysterm::Action.new text, name: name
        action.shortcut = key if key
        action.on(Crysterm::Event::Triggered) { run.call }
        @main.add_action tip(action, description)
      end
    end
  end
end
