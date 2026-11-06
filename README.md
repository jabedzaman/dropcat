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

Versioning is automatic via [release-please](https://github.com/googleapis/release-please).
Commit messages must follow [Conventional Commits](https://www.conventionalcommits.org):

| Prefix | Effect |
| --- | --- |
| `fix:` | patch bump |
| `feat:` | minor bump |
| `feat!:` / `BREAKING CHANGE:` | major bump |
| `chore:`, `docs:`, `ci:`, `test:` | no release |

While in beta, versions look like `0.1.0-beta`, `0.1.0-beta.1`, … Merging the release PR that
release-please opens tags the release and a macOS build is attached to it.
Release builds are unsigned: on first launch, right-click → Open.
