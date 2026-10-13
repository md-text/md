require "spec"
require "../src/md"
require "file_utils"
require "yaml"

# The helpers every App spec shares: a headless window (an in-memory
# terminal of 100 by 30 cells), an App on it, the keys pressed the way the
# terminal delivers them, the status bar's prompt answered and read, the
# unsaved-changes dialog chosen from, and a scratch file.

# Every spec's state and cache — the history, the recovery files, the
# locks, the log, the manual's copy — go to scratch directories, never the
# user's; a spec needing its own points the variable elsewhere and back.
SPEC_XDG_HOME = File.tempname("md-spec-xdg")
ENV["XDG_STATE_HOME"] = File.join(SPEC_XDG_HOME, "state")
ENV["XDG_CACHE_HOME"] = File.join(SPEC_XDG_HOME, "cache")
at_exit { FileUtils.rm_rf SPEC_XDG_HOME }

def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

# An App on a headless window, destroyed after the block, with the
# constructor's own defaults: a new document in the editor unless *text* is
# given, which the viewer shows. The theme is one global for every window,
# so one the App switched to (View → Theme, a config file) is put back to
# the one the window found, for the specs after.
def with_app(source = Md::Source.new, text = "", view = !text.empty?, config = false, history = nil, watch = false, line = nil, &)
  window = headless_window
  theme = Crysterm::CSS.theme
  begin
    yield Md::App.new(source, text: text, view: view, window: window, config: config, history: history, watch: watch, line: line), window
  ensure
    window.destroy
    Crysterm::CSS.theme = theme unless Crysterm::CSS.theme == theme
  end
end

# A Window → New opener that hands out headless windows, recording them
# in *opened*.
def recording_opener(opened = [] of Crysterm::Window)
  ->(title : String) do
    window = headless_window
    window.title = title
    opened << window
    window
  end
end

# Two windows on one document, the way Window → New makes them: an App on
# *source* and *text* under one shared `Crysterm::Application`, and a second
# from its `#new_window`. Both are destroyed after the block, and then no
# document may be left in the registry.
#
# With *linked*, the windows are linked (Window → Linking → Linked) before
# the second opens, and separate again afterwards: the choice is one for
# the process.
def with_two_windows(source = Md::Source.new(path: "doc.md"), text = "# Doc\n\nText.\n", view = true, linked = false,
                     opener = recording_opener, &)
  application = Crysterm::Application.new
  with_app source, text: text, view: view do |a, window|
    application.add window
    a.window_link = Md::App::WindowLink::Linked if linked
    a.window_opener = opener
    b = a.new_window || fail("no window was opened")
    begin
      yield a, b
    ensure
      b.window.destroy
      Md::Documents.link_windows Md::App::WindowLink::Separate
    end
  end
  Md::Documents.all.should be_empty
end

# Runs the block with the configuration loaded as md loads it at start —
# from a config file holding *yaml* (none when nil) in a scratch
# `XDG_CONFIG_HOME`, so `Md::Config.path` is the scratch file, and from
# *argv* — and yields the file's path. The options are put back to their
# defaults afterwards: the registry is one for the whole spec run.
def with_config(yaml : String? = nil, argv = [] of String, &)
  dir = File.tempname("md-spec-config")
  previous = ENV["XDG_CONFIG_HOME"]?
  ENV["XDG_CONFIG_HOME"] = dir
  path = Md::Config.path
  begin
    Dir.mkdir_p File.dirname(path)
    File.write path, yaml if yaml
    Md::Config.configure file: path, argv: argv
    yield path
  ensure
    Md::Config.reset
    if previous
      ENV["XDG_CONFIG_HOME"] = previous
    else
      ENV.delete "XDG_CONFIG_HOME"
    end
    FileUtils.rm_rf dir
  end
end

# The parsed config file at *path*.
def config_file(path : String) : YAML::Any
  YAML.parse File.read(path)
end

# Presses a key the way the terminal delivers it, and returns the event so
# a spec can see who took it.
def press(window, key : Tput::Key) : Crysterm::Event::KeyPress
  e = Crysterm::Event::KeyPress.new('\0', key)
  window.emit Crysterm::Event::KeyPress, e
  e
end

def press(window, char : Char) : Crysterm::Event::KeyPress
  e = Crysterm::Event::KeyPress.new(char)
  window.emit Crysterm::Event::KeyPress, e
  e
end

# Answers the status bar's prompt with *text*.
def answer(app, text : String)
  field = app.main.status_bar.line_prompt.field
  field.value = text
  field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Enter)
end

# Answers a one-key question at the status bar's prompt — the
# unsaved-changes question's `y`/`n`/`c`, Replace's `y`/`n`/`a`/`q` — with
# *char*, typed into its field.
def answer(app, char : Char)
  app.main.status_bar.line_prompt.field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new(char)
end

# The prompt's label, while a question is up in place of the status bar.
def question(app)
  app.main.status_bar.line_prompt.label_box.content
end

# The modal input dialog that is up, if any (View → Dialog Style → Modal
# Dialogs).
def input_dialog(window)
  window.descendants.select(Crysterm::Widget::InputDialog).find(&.visible?)
end

# Answers that dialog with *text*: typed into its field and entered.
def answer_dialog(window, text : String)
  dialog = input_dialog(window) || fail("no input dialog is up")
  dialog.line_edit.value = text
  dialog.line_edit.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Enter)
end

# The status bar's notice.
def notice(app)
  app.main.status_bar.message
end

# The menu at *index* on the bar: File, Edit, Format, View, Options, Window,
# Help.
def menu(app, index)
  app.main.menu_bar.menus[index]
end

# Lets the window's render fiber run posted jobs until the condition holds.
def settle(timeout = 2.seconds, &)
  deadline = Time.instant + timeout
  until yield
    raise "the condition was not met within #{timeout}" if Time.instant > deadline
    sleep 10.milliseconds
  end
end

# The unsaved-changes dialog's button labelled *text*, if the dialog is up
# (View → Dialog Style → Modal Dialogs).
def choice(window, text)
  window.descendants.select(Crysterm::Widget::Button).find { |b| b.text == text && b.visible? }
end

# Clicks that button, which must be up.
def choose(window, text)
  (choice(window, text) || fail("no #{text} button is up")).click
end

# A scratch file with *content*, or the name of one not yet written.
def tempfile(content : String?) : String
  path = File.tempname("md-spec", ".md")
  File.write path, content if content
  path
end
