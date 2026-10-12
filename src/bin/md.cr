# Crysterm reads its config file, the CRYSTERM_* variables and ARGV as it
# loads — before md's options exist, and before `CLI.run` could report a
# value that does not fit (`--colors-theme=bogus` ended in a backtrace). md
# reads all of it itself, in `Config.configure`, where an error is a message
# and an exit status. The variable has to be set before Crysterm is required:
# a required file's top-level code runs at the point of the require. It is
# put back afterwards, so a program md starts (the clipboard command, a shell)
# does not inherit it.
no_auto_configure = ENV["CRYSTERM_NO_AUTO_CONFIGURE"]?
ENV["CRYSTERM_NO_AUTO_CONFIGURE"] = "1"
require "../md"
if no_auto_configure
  ENV["CRYSTERM_NO_AUTO_CONFIGURE"] = no_auto_configure
else
  ENV.delete "CRYSTERM_NO_AUTO_CONFIGURE"
end

exit Md::CLI.run(ARGV)
