# LiquidBar

A macOS menu bar replacement in Swift and SwiftUI. `Sources/LiquidBarCore` is the pure logic with tests, and `Sources/LiquidBar` is the app. [docs/details.md](docs/details.md) describes the behavior and the build, and [docs/configuration.md](docs/configuration.md) every config key.

## Build and test

- `make app` builds and signs `build/LiquidBar.app`. Never pass `SIGN=`: another signature loses the Accessibility grant.
- `swift test` runs the unit tests. CI runs them and a release build on every push and pull request.
- A change to what the user sees needs its docs updated in the same commit: `README.md`, `docs/configuration.md`, or `docs/details.md`.

## Commits

Commit subjects are the release notes. git-cliff (`cliff.toml`) builds `CHANGELOG.md` and each release's notes from them, so write the subject as one line a user can read.

- Use a conventional type: `feat: the bar's background has its own glass style`.
- `feat` goes under Added. `fix` and `perf` go under Fixed.
- `chore`, `docs`, `refactor`, `test`, `build`, `ci`, and `style` stay out of the notes. Use them for anything a user does not notice.
- Start the description in lower case and say what the app now does, in the present tense. Leave out the trailing period.
- A commit without a type, like a merged pull request's, goes under Added with its author credited.

## Releases

1. Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Support/Info.plist`, commit as `chore: v<version>`, and push `main`.
2. Run `make release` on the Mac that holds the Developer ID and the Sparkle key. It notarizes the app, pushes the signed tag, uploads the zip to a draft release, and starts the Release workflow.
3. The Release workflow writes the notes, publishes the release, and commits `CHANGELOG.md`, `appcast.xml`, and the Homebrew cask `Casks/liquid-bar.rb` to `main`. Run `git pull` afterwards.

Never edit `CHANGELOG.md` or `appcast.xml` by hand, nor the `version` and `sha256` lines of the cask. `CHANGELOG.md` follows Keep a Changelog, with a `## [version](release link) - date` heading for each version. A release's notes are that version's section without the heading.
