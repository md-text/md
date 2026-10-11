# md: a Markdown viewer and editor for the terminal, built on Crysterm.
#
# This file is the library root. The executable's entry point is
# `src/bin/md.cr`, which simply calls `Md::CLI.run`.
require "./md/version"
require "./md/source"
require "./md/history"
require "./md/settings"
require "./md/export"
require "./md/manual"
require "./md/cli"
require "./md/app"
require "./md/app_panes"
require "./md/app_status"
require "./md/app_menu"
require "./md/app_search"
require "./md/app_file"
require "./md/app_settings"
require "./md/app_links"
require "./md/app_theme"
require "./md/app_autosave"
require "./md/app_view"
require "./md/app_clipboard"

module Md
end
