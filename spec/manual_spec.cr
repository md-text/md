require "./spec_helper"

# Checks the script's syntax with *shell*, when it is installed here.
private def syntax_ok?(shell : String, script : String) : Bool
  return true unless Process.find_executable(shell)
  path = File.tempname("md-spec", ".#{shell}")
  File.write path, script
  begin
    Process.run(shell, ["-n", path]).success?
  ensure
    File.delete? path
  end
end

describe Md::Manual do
  it "generates a man page that lists every option and the files" do
    man = Md::Manual.man
    man.should start_with ".TH MD 1"
    {"NAME", "SYNOPSIS", "DESCRIPTION", "OPTIONS", "KEYS", "FILES", "SEE ALSO"}.each do |section|
      man.should contain ".SH #{section}\n"
    end
    Md::CLI::OPTIONS.each do |option|
      man.should contain "\\fB#{option.long.gsub('-', "\\-")}\\fR"
      if short = option.short
        man.should contain "\\fB#{short.gsub('-', "\\-")}\\fR"
      end
    end
    man.should contain "$XDG_STATE_HOME/md/history.json"
    man.should contain "$XDG_CACHE_HOME/md/md.log"
    man.should contain "View \\(-> Watch File"
    man.should contain ".SH SETTINGS\n"
    man.should contain "\\fB\\-\\-md\\-text\\-width\\fR \\fIVALUE\\fR (\\fBMD_TEXT_WIDTH\\fR, \\fImd.text_width\\fR)"
    man.should contain "$XDG_CONFIG_HOME/md/config.yml"
    man.should_not contain "→"
  end

  it "starts no text line with a dot or a quote, which roff would read as a request" do
    requests = /\A\.(TH|SH|TP|PP|br|B|BR|I)(\s|\z)/
    Md::Manual.man.each_line do |line|
      next unless line.starts_with?('.') || line.starts_with?('\'')
      line.should match(requests), line
    end
    # The wrap guards every line, not only the first: a word that opens with
    # a quote or a dot, pushed to the start of a continuation line (eight
    # words fill a 40-column line exactly, so the ninth opens the next).
    text = (["word"] * 8 + ["'set", "mouse='."] + ["word"] * 5 + [".B", "word"]).join(' ')
    Md::Manual.wrap(text, 40).lines.should eq [
      "word word word word word word word word",
      "\\&'set mouse='. word word word word word",
      "\\&.B word",
    ]
  end

  it "generates completions for bash, zsh and fish that mention every option" do
    bash = Md::Manual.bash
    zsh = Md::Manual.zsh
    fish = Md::Manual.fish
    Md::CLI::OPTIONS.each do |option|
      bash.should contain option.long
      zsh.should contain option.long
      fish.should contain "-l #{option.long[2..]}"
      if short = option.short
        fish.should contain "-s #{short[1..]}"
      end
    end
    bash.should contain "complete -o default -F _md md"
    bash.should contain "--export) COMPREPLY=($(compgen -W 'html text'"
    zsh.should start_with "#compdef md\n"
    zsh.should contain "'--generate[Print the man page or a shell completion script (man, bash, zsh, fish) and exit]:what:(man bash zsh fish)'"
    zsh.should contain "'1:file:_files'"
    fish.should contain "complete -c md -l export -x -a 'html text' -d 'Print FILE"
    fish.should contain "complete -c md -s l -l line -x -d"
    syntax_ok?("bash", bash).should be_true
    syntax_ok?("zsh", zsh).should be_true
  end

  it "is printed by --generate, which knows what it can generate" do
    Md::Manual::KINDS.each do |kind|
      output = IO::Memory.new
      Md::CLI.run(["--generate", kind], stdout: output).should eq 0
      output.to_s.should eq Md::Manual.generate(kind)
    end
    error = IO::Memory.new
    Md::CLI.run(["--generate", "tcsh"], stdout: IO::Memory.new, stderr: error).should eq 2
    error.to_s.should contain "cannot generate tcsh (man, bash, zsh, fish)"
  end
end
