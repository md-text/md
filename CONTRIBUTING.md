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
2. Set up a development environment as described in the
   [README](README.md#building-from-source).
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

## License

By contributing you agree that your contributions are licensed under the
[GNU Affero General Public License v3.0 or later](LICENSE), the same license
that covers the project.
