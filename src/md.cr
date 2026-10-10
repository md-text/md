# md: a Markdown viewer and editor for the terminal, built on Crysterm.
#
# This file is the library root. The executable's entry point is
# `src/bin/md.cr`, which simply calls `Md::CLI.run`.
require "./md/version"
require "./md/source"
require "./md/cli"
require "./md/app"
require "./md/app_status"
require "./md/app_menu"

module Md
end
