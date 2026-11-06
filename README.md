# SSHDrop

A Finder-style macOS app for browsing remote machines over SSH and moving files with `scp`.

- Machines sidebar with status dots, favorites and per-machine state
- Finder-like list and icon views, tree expansion, inline rename, new folder, delete
- Drag files in from Finder to upload; Quick Look (Space) previews remote files
- Reuses your system `ssh`, keys and agent. `~/.ssh/config` is only used to pre-fill or import hosts

## Build

```sh
brew install xcodegen
xcodegen generate
open SSHDrop.xcodeproj
```

Core logic lives in the `SSHDropCore` Swift package: `swift test`.

## Releases

Releases are cut locally with one script, no CI needed:

```sh
scripts/release.sh --dry-run     # show the next version + notes, change nothing
scripts/release.sh               # test, build, dmg, tag, publish to GitHub (asks first)
scripts/release.sh --no-publish  # test + build + dmg into dist/ only
```

Needs `git`, `swift`/Xcode, `xcodegen` and `gh` (logged in). Run it from a clean, pushed `main`.

The version comes from [Conventional Commits](https://www.conventionalcommits.org) since the last `v*` tag:

| Situation | Next version |
| --- | --- |
| First release | `0.1.0-beta` |
| Last tag is a beta | `0.1.0-beta.1`, `0.1.0-beta.2`, … (`--stable` graduates to `0.1.0`) |
| Last tag is stable | `feat:` minor, `fix:` patch, `feat!:` / `BREAKING CHANGE:` major |
| Only `chore:` `docs:` `ci:` `test:` | nothing to release |

Use `--version X.Y.Z` to override. Builds are unsigned (ad-hoc): on first launch, right-click → Open.
