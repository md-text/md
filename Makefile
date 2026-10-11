# Build, test and install md.
#
#   make            build a development binary in bin/md
#   make release    build an optimized binary in bin/md
#   make test       run the specs
#   make lint       run ameba and check the formatting
#   make check      test + lint
#   make man        generate the man page, share/man/man1/md.1
#   make completions
#                   generate the bash, zsh and fish completions under share/
#   make install    install bin/md into $(PREFIX)/bin  (default /usr/local),
#                   the man page and the completions under $(PREFIX)/share
#
# Requires Crystal >= 1.21 and the unibilium library; see README.md.

PREFIX   ?= /usr/local
DESTDIR  ?=
ROOT      = $(DESTDIR)$(PREFIX)
BINDIR    = $(ROOT)/bin

NAME      = md
SOURCES   = $(shell find src -type f -name '*.cr') shard.yml
PROGRAM   = bin/$(NAME)

# The binary prints its own man page and completions (`md --generate`);
# they land under share/ in the layout they are installed in.
MAN       = share/man/man1/$(NAME).1
BASHCOMP  = share/bash-completion/completions/$(NAME)
ZSHCOMP   = share/zsh/site-functions/_$(NAME)
FISHCOMP  = share/fish/vendor_completions.d/$(NAME).fish

# Extra flags for `crystal build`, e.g. `make release CRFLAGS=-Dwithout_readline`.
CRFLAGS  ?=

.PHONY: all build release test lint format check man completions install uninstall clean distclean

all: build

build: $(PROGRAM)

$(PROGRAM): lib $(SOURCES)
	@mkdir -p bin
	crystal build $(CRFLAGS) -o $@ src/bin/$(NAME).cr

release: lib
	@mkdir -p bin
	crystal build --release --no-debug $(CRFLAGS) -o $(PROGRAM) src/bin/$(NAME).cr

# Dependencies. Development dependencies (ameba) are included; use
# `shards install --production` by hand for a dependencies-only install.
lib: shard.yml shard.lock
	shards install
	@touch lib

test: lib
	crystal spec

# Ameba ships no prebuilt binary; it is compiled from the development dependency.
bin/ameba: lib
	@mkdir -p bin
	crystal build -o $@ lib/ameba/bin/ameba.cr

lint: bin/ameba
	bin/ameba
	crystal tool format --check

format:
	crystal tool format

check: test lint

man: $(MAN)

completions: $(BASHCOMP) $(ZSHCOMP) $(FISHCOMP)

$(MAN): $(PROGRAM)
	@mkdir -p $(@D)
	$(PROGRAM) --generate man > $@

$(BASHCOMP): $(PROGRAM)
	@mkdir -p $(@D)
	$(PROGRAM) --generate bash > $@

$(ZSHCOMP): $(PROGRAM)
	@mkdir -p $(@D)
	$(PROGRAM) --generate zsh > $@

$(FISHCOMP): $(PROGRAM)
	@mkdir -p $(@D)
	$(PROGRAM) --generate fish > $@

install: release man completions
	install -d $(BINDIR) $(dir $(ROOT)/$(MAN) $(ROOT)/$(BASHCOMP) $(ROOT)/$(ZSHCOMP) $(ROOT)/$(FISHCOMP))
	install -m 0755 $(PROGRAM) $(BINDIR)/$(NAME)
	install -m 0644 $(MAN) $(ROOT)/$(MAN)
	install -m 0644 $(BASHCOMP) $(ROOT)/$(BASHCOMP)
	install -m 0644 $(ZSHCOMP) $(ROOT)/$(ZSHCOMP)
	install -m 0644 $(FISHCOMP) $(ROOT)/$(FISHCOMP)

uninstall:
	rm -f $(BINDIR)/$(NAME) $(ROOT)/$(MAN) $(ROOT)/$(BASHCOMP) $(ROOT)/$(ZSHCOMP) $(ROOT)/$(FISHCOMP)

clean:
	rm -rf bin share

distclean: clean
	rm -rf lib .shards
