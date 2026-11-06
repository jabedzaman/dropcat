# DropCat

A Finder-style macOS app for browsing remote machines over SSH and moving files with `scp`.

- Machines sidebar with status dots, favorites and per-machine state
- Finder-like list and icon views, tree expansion, inline rename, new folder, delete
- Drag files in from Finder to upload; Quick Look (Space) previews remote files
- Reuses your system `ssh`, keys and agent. `~/.ssh/config` is only used to pre-fill or import hosts

## Install

Download the latest `.dmg` from the [Releases page](https://github.com/jabedzaman/dropcat/releases/latest) and drag **DropCat** into **Applications**.

DropCat isn't notarized yet, so macOS blocks the first launch with *"Apple could not verify “DropCat” is free of malware"*. Clear the quarantine flag once and it opens normally:

```sh
xattr -cr /Applications/DropCat.app
```

Or: System Settings → Privacy & Security → scroll down → **Open Anyway**.
