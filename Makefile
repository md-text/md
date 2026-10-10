# Build, test and install md.
#
#   make            build a development binary in bin/md
#   make release    build an optimized binary in bin/md
#   make test       run the specs
#   make lint       run ameba and check the formatting
#   make check      test + lint
#   make install    install bin/md into $(PREFIX)/bin  (default /usr/local)
#
# Requires Crystal >= 1.21 and the unibilium library; see README.md.

PREFIX   ?= /usr/local
DESTDIR  ?=
BINDIR    = $(DESTDIR)$(PREFIX)/bin

NAME      = md
SOURCES   = $(shell find src -type f -name '*.cr') shard.yml
PROGRAM   = bin/$(NAME)

# Extra flags for `crystal build`, e.g. `make release CRFLAGS=-Dwithout_readline`.
CRFLAGS  ?=

.PHONY: all build release test lint format check install uninstall clean distclean

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

install: release
	install -d $(BINDIR)
	install -m 0755 $(PROGRAM) $(BINDIR)/$(NAME)

uninstall:
	rm -f $(BINDIR)/$(NAME)

clean:
	rm -rf bin

distclean: clean
	rm -rf lib .shards
