**Build status**: [![CI](https://github.com/md-text/md/actions/workflows/ci.yml/badge.svg)](https://github.com/md-text/md/actions/workflows/ci.yml)
[![Version](https://img.shields.io/github/tag/md-text/md.svg?maxAge=360)](https://github.com/md-text/md/releases/latest)
[![License](https://img.shields.io/github/license/md-text/md.svg)](https://github.com/md-text/md/blob/main/LICENSE)

# md

**Markdown editor and viewer for the terminal.**

Includes simultaneous editing and viewing, dynamic/real-time updates,
graphics display, multiple terminal windows, Vi keys (integration with
Neovim), rulers and guides, TUI themes, everything configurable, etc.

```sh
md README.md                 # read/view a document
md                           # edit document (editor opens by default)
some-command | md            # watch output render as it arrives
md --export html notes.md    # or use it as a filter
```

## Installation

Download an archive for your platform from the
[releases page](https://github.com/md-text/md/releases):

| Archive                          | Platform                                   |
| -------------------------------- | ------------------------------------------ |
| `md-vX.Y.Z-linux-x86_64.tar.gz`  | Linux, 64-bit Intel/AMD (any distribution) |
| `md-vX.Y.Z-linux-aarch64.tar.gz` | Linux, 64-bit ARM (any distribution)       |
| `md-vX.Y.Z-macos-aarch64.tar.gz` | macOS, Apple Silicon                       |
| `md-vX.Y.Z-macos-x86_64.tar.gz`  | macOS, Intel                               |

The Linux binaries are fully static, and the macOS ones use only system
libraries. For example, on Linux x86_64:

```sh
VERSION=vX.Y.Z   # the latest release
curl -LO https://github.com/md-text/md/releases/download/$VERSION/md-$VERSION-linux-x86_64.tar.gz
curl -LO https://github.com/md-text/md/releases/download/$VERSION/md-$VERSION-linux-x86_64.tar.gz.sha256
shasum -a 256 -c md-$VERSION-linux-x86_64.tar.gz.sha256
tar xzf md-$VERSION-linux-x86_64.tar.gz
sudo install -m 0755 md-$VERSION-linux-x86_64/md /usr/local/bin/md
sudo cp -r md-$VERSION-linux-x86_64/share /usr/local/   # man page and shell completions
```

On macOS, a binary downloaded with a web browser is quarantined by
Gatekeeper. Download it with `curl` as above, or run
`xattr -d com.apple.quarantine md`.
To build md yourself, see [CONTRIBUTING.md](CONTRIBUTING.md#building-from-source).

## Getting started

(All options also exist in the TUI menus.)

```sh
md                          # an empty editor
md +120 notes.md            # open on line 120
md --watch notes.md         # reload whenever the file changes on disk
md --edit README.md         # start in the editor instead of the viewer
md --export text doc.md     # render as plain text to standard output
md --help --verbose         # every option and setting
```

A few keys to get you going (subject to change later. Mouse is also supported):

| Key                   | Action                                          |
| --------------------- | ----------------------------------------------- |
| `F1`, `F2`, `F3`, `F4`      | Toggle the editor, viewer, ToC, menu       |
| `F10` or `Alt`+letter | Activate menu                                  |
| `Ctrl-O`, `Ctrl-S`    | Open, save                                      |
| `/`, `n`, `N`         | Search (`Ctrl-F`, `Ctrl-G` in the editor)       |
| `]`, `[`              | Next and previous heading                       |
| `:` or `Alt-K`        | Run any command by name, or go to a line        |
| `F6`                  | Cycle themes                                    |
| `Ctrl-Q`              | Quit                                            |

Every menu entry shows its shortcut and a one-line description.

## License

Copyright (C) 2026 Davor Ocelic

md is free software: you can redistribute it and/or modify it under the
terms of the GNU Affero General Public License, version 3, as published by
the Free Software Foundation.

md is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the [LICENSE](LICENSE) for details.
