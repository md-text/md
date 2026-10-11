require "spec"
require "../src/md"
require "file_utils"

# The helpers every App spec shares: a headless window (an in-memory
# terminal of 100 by 30 cells), an App on it, the keys pressed the way the
# terminal delivers them, the status bar's prompt answered and read, the
# unsaved-changes dialog chosen from, and a scratch file.

def headless_window
  Crysterm::Window.new input: IO::Memory.new, output: IO::Memory.new, width: 100, height: 30
end

# An App on a headless window, destroyed after the block, with the
# constructor's own defaults: a new document in the editor unless *text* is
# given, which the viewer shows.
def with_app(source = Md::Source.new, text = "", view = !text.empty?, settings = nil, history = nil, watch = false, line = nil, &)
  window = headless_window
  begin
    yield Md::App.new(source, text: text, view: view, window: window, settings: settings, history: history, watch: watch, line: line), window
  ensure
    window.destroy
  end
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
def answer(app, text)
  field = app.main.status_bar.line_prompt.field
  field.value = text
  field.emit Crysterm::Event::KeyPress, Crysterm::Event::KeyPress.new('\0', Tput::Key::Enter)
end

# The status bar's notice.
def notice(app)
  app.main.status_bar.message
end

# The menu at *index* on the bar: File, Edit, Format, View, Options.
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

# The unsaved-changes dialog's button labelled *text*, if the dialog is up.
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
