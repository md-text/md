# Contributing

Thank you for considering a contribution. Bug reports, feature requests and
pull requests are all welcome.

## Reporting a problem

Open an issue describing what you did, what you expected and what happened
instead. Please include the output of `md --version`, your operating system,
and the terminal emulator you use (and its `TERM` value), since terminal
behavior differs between emulators.

## Making changes

1. Fork the repository and create a branch for your change.
2. Set up a development environment as described in
   [Building from source](#building-from-source) below.
3. Make your change. Add or adjust specs under `spec/` for behavior that can
   be tested without a terminal.
4. Run `make check`. It runs the specs, the [Ameba](https://github.com/crystal-ameba/ameba)
   linter and the Crystal formatter check; all three also run in CI on every
   pull request, on Linux and macOS.
5. Add an entry to the *Unreleased* section of [CHANGELOG.md](CHANGELOG.md).
6. Open a pull request. Keep it focused on one change; describe the motivation,
   not only the mechanics.

Code is formatted with `crystal tool format` (`make format`). Comments explain
*why* something is done; the code itself shows *what*.

## Building from source

md is written in [Crystal](https://crystal-lang.org). To build it you need
Crystal 1.21 or newer, the [unibilium](https://github.com/neovim/unibilium)
library and `make`:

```sh
# Debian/Ubuntu
curl -fsSL https://crystal-lang.org/install.sh | sudo bash
sudo apt-get install -y libunibilium-dev make
# macOS
brew install crystal unibilium make

make release && sudo make install   # PREFIX=/usr/local by default
```

> To build against local checkouts of Crysterm, Tput or the other
> dependencies, list them in a `shard.override.yml` of your own; git ignores
> it. `shard.lock` is not tracked: a build takes the newest release each
> dependency's constraint in `shard.yml` allows.

## Development

```sh
make                  # build bin/md
make test             # run the specs
make lint             # run ameba (static analysis, formatting included)
make format           # reformat the sources
make check            # test + lint, the same as CI
```

Layout:

```
src/bin/md.cr         executable entry point
src/md.cr             library root
src/md/cli.cr         the command line: the option table, parsing, launching
src/md/source.cr      where the document comes from (file, stdin, nothing)
src/md/export.cr      --export: the document rendered to standard output
src/md/manual.cr      --generate: the man page and the shell completions
src/md/app.cr         the Crysterm application: window, panes, keys, streaming
src/md/app_panes.cr   the panes' splitter: resizing, the sizes kept
src/md/app_status.cr  the status bar fields, the mouse modes
src/md/app_menu.cr    the menu bar
src/md/app_search.cr  search, go to line, heading jumps
src/md/app_file.cr    open, reload, watch; the unsaved-changes guard; recent files
src/md/app_links.cr   following links; Previous File and Next File
src/md/app_theme.cr   the theme: Crysterm's built-in themes, switched at runtime
src/md/app_media.cr   View → Images and Media Backend, with its Change for 5s trial
src/md/app_toolkit.cr Crysterm's own options in the menus: color depth, terminal links, no animations, detachable menus
src/md/app_autosave.cr auto-save to a recovery file; the backup file
src/md/app_view.cr    soft wrap, hard wrap, text width and centering, rulers and guides
src/md/app_clipboard.cr copying and pasting; the clipboard modes
src/md/app_edit.cr    Markdown-aware editing: lists continued and indented, the Format menu
src/md/app_dialogs.cr the questions md asks, at the prompt or in a dialog (View → Dialog Style)
src/md/app_caches.cr  Options → Clear Caches…
src/md/app_config.cr  the menus' choices linked to their options, the config file written
src/md/app_tips.cr    the menu entries' descriptions; where they show (View → Tooltips)
src/md/app_windows.cr the Window menu: more windows on the document, in new terminal windows
src/md/config.cr      the choices as Crysterm (Superconf) options; the config file (~/.config/md/config.yml)
src/md/history.cr     the recent files and positions (~/.local/state/md/history.json)
src/md/version.cr     Md::VERSION, read from shard.yml at compile time
spec/                 specs (crystal spec)
```

The man page and the completions are not kept in the repository: the
binary is their source (`md --generate`), the release workflow runs it, and
a spec checks that every option is in each of them.

CI runs the specs and lints every push and pull request on Linux (x86_64,
aarch64) and macOS (Intel, Apple Silicon), with the latest Crystal release
and, on one platform, Crystal nightly.

### Releasing

1. Set the new version in `shard.yml` and move the *Unreleased* entries in
   `CHANGELOG.md` under a heading for it.
2. Commit, then tag and push:

   ```sh
   git tag -a vX.Y.Z -m "md vX.Y.Z"
   git push origin main vX.Y.Z
   ```

3. Once the *Release* workflow has passed on the tag, publish the release:

   ```sh
   gh release create vX.Y.Z --verify-tag --title vX.Y.Z --generate-notes
   ```

Pushing the tag creates no release: the *Release* workflow only builds an
archive per supported platform, with a SHA-256 checksum, holding the binary
and the man page and completions it generated, and keeps them as workflow
artifacts. Publishing the release runs the workflow again for its tag, and
that run attaches the archives to it. The workflow can also be run by hand
from the *Actions* tab against a tag whose release exists, or without a tag
to produce the archives as workflow artifacts only.

## License

By contributing you agree that your contributions are licensed under the
[GNU Affero General Public License v3.0 only](LICENSE), the same license
that covers the project.
