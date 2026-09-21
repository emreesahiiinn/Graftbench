<div align="center">

# Graftbench

**A faster, sharper Git client for macOS.** — *Branch Further.*

A native SwiftUI Git client, built to be a more capable Fork/Tower — with the
premium features you actually use, and a UI that feels like it belongs on a Mac.

Created by **Emre Şahin**

</div>

---

## Features

**Workspace**
- Multiple repositories in **tabs**, plus a Home screen (open / clone / recents)
- **Auto-refresh** — the working copy, diffs and history update the moment files
  change on disk (FSEvents), no ⌘R needed
- **Undo** almost anything (commit, checkout, branch create/delete, cherry-pick,
  revert, reset, merge) from the toast — Tower-style
- **Quick Actions** command palette (⌘K)
- **Global search** across tracked files (`git grep`)

**History & diffs**
- Colored commit **graph** with lanes, refs, avatars
- **Syntax highlighting** + intra-line (word) diff
- **Unified / side-by-side** diff, **word wrap**, **show invisibles**,
  **ignore whitespace**, **tab width**, **hide hunk headers**, **whole-file** view
  — all persisted
- **Image diff** (before / after), **blame**, **file history**, **commit compare**

**Working copy**
- Stage / unstage / discard by file, **hunk**, or **individual lines**
- Commit (+ **Commit & Push**, amend with message prefill, GPG/SSH signing)
- ⭐️ **Pull a single file** from upstream (leave your other changes untouched)
- ⭐️ **Stop tracking / ignore local changes** (`rm --cached`, skip-worktree,
  assume-unchanged, add to .gitignore)

**Branching & remotes**
- Checkout, merge, **squash-merge**, **rebase onto**, rename (local & **on remote**),
  set upstream, push, delete (local & remote)
- **Interactive rebase** (drag to reorder · pick / reword / squash / fixup / drop)
- Cherry-pick · revert · reset (soft/mixed/hard) · **drag-and-drop** (drop a branch or
  commit onto the current branch to merge / cherry-pick)
- Fetch/pull/push with options (force-with-lease, push tags, prune, rebase)
- **Conflict resolver** (ours / theirs / take both), remotes manager
- **Tags**, **stashes** (with diff), **submodules**, **worktrees**, **reflog**, **bisect**

**Polish**
- Native light & dark themes, selectable **accent colors** (incl. Sea Green),
  optional **translucent** window
- HTTPS **credential** prompt → stored in the macOS Keychain and reused

## Install

**Homebrew**

```bash
brew tap emreesahiiinn/graftbench https://github.com/emreesahiiinn/Graftbench
brew install --cask graftbench
```

**Direct download** — grab the latest `Graftbench.dmg` from the
[Releases](https://github.com/emreesahiiinn/Graftbench/releases) page, open it and drag
Graftbench to Applications.

> The app is ad-hoc signed (not notarized). On first launch, right-click → **Open**, or run
> `xattr -dr com.apple.quarantine /Applications/Graftbench.app`.

## Requirements

- macOS 14+
- Xcode 26 / Swift 6 (to build)
- `git` (Apple’s or Homebrew)

## Build & run

```bash
swift build                 # compile
./Scripts/build_app.sh --run  # build Graftbench.app and launch it
./Scripts/build_app.sh --install   # copy to /Applications
./Scripts/package_dmg.sh    # build a .dmg
```

Or open `Package.swift` in Xcode and run.

Signing & notarization for distribution: see [Packaging/NOTARIZE.md](Packaging/NOTARIZE.md).

## License

**Graftbench is free for noncommercial use** under the
[PolyForm Noncommercial License 1.0.0](LICENSE). Commercial use requires a separate
license from the author. See [LICENSE](LICENSE) for details.

---

<div align="center">

Created with ❤️ by **Emre Şahin**

</div>
