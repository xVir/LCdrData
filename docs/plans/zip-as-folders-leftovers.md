# ZIP-as-folders leftovers

Items from [zip-as-folders.md](zip-as-folders.md) that shipped only in part, or not at all. The original slice is otherwise done: browse, pack/unpack, read-only guards, and session collapse all land. This file is the follow-up list, not a rewrite of those decisions.

Items in [zip-as-folders.md §9](zip-as-folders.md) stay out of scope: password prompt, tar / 7z / rar, nested zip-in-zip, extension-less sniffing, spanned zips, Cmd+L of `archive.zip/internal`.

---

## 1. Delete temp extracts when leaving an archive

**Source:** [zip-as-folders.md §4](zip-as-folders.md) — drag-out, Quick Look, and F4 extract a member to a per-window temp directory, then delete that tree when the panel leaves the archive and on terminate.

**Today:** [`PanelViewModel.preparedFileURL`](../../LCdrData/ViewModels/PanelViewModel.swift) creates `LCdrData-Preview-*` directories and appends them to `temporaryExtractionDirectories`. Nothing removes them on navigate-out, panel deinit, or app terminate.

**Work:** delete the recorded trees when `state.location` is no longer that archive, and again from `AppDelegate` termination. Keep extracts that a still-open Quick Look or drag session needs until those finish.

---

## 2. Copy-path uses the archive display path

**Source:** [zip-as-folders.md §3](zip-as-folders.md) — copy-path copies the display string (`/Users/…/photos.zip/vacation/file.txt`), not a filesystem URL.

**Today:** [`AppState.copySelectedPathsToPasteboard`](../../LCdrData/ViewModels/AppState.swift) maps `selectedNonParentURLs().map(\.path)`. Archive members currently carry a synthetic `url` that is not that display path.

**Work:** copy `BrowseLocation.displayPath` joined with the member name (or an equivalent `FileItem` display path) for archive rows; leave real `url.path` for directory rows.

---

## 3. Encrypted members fail copy-out with a clear error

**Source:** [zip-as-folders.md §5](zip-as-folders.md) and §8 — listing may work; extracting an encrypted member fails with a clear error. Tests should cover encrypted/unreadable zip.

**Today:** unreadable/corrupt zips are handled on enter. There is no encrypted-member path and no fixture test. `isWritable` is disk permissions only, so an encrypted archive is not treated as read-only unless the file itself is not writable.

**Work:** detect encrypted entries (ZIPFoundation exposes encryption on `Entry`), refuse extract/add of those rows with an `ArchiveServiceError` the overlay can show, and add an `ArchiveService` test with an encrypted fixture. A password prompt remains out of scope.

---

## 4. Abort extract if written bytes exceed the claimed size

**Source:** [zip-as-folders.md §4](zip-as-folders.md) — zip-bomb: refuse if claimed uncompressed size of the batch exceeds free space; abort if written bytes exceed the claim; 4 GB per-member hard cap.

**Today:** [`ArchiveService.extract`](../../LCdrData/Services/ArchiveService.swift) enforces the 4 GB cap and the free-space check against claimed `uncompressedSize`. After `archive.extract(entry, to:)`, it does not compare bytes actually written to the claim.

**Work:** after each member, measure the written file (or stream count) and throw if it exceeds the claim, leaving a partial extract cleaned up or at least not treated as success.

---

## 5. Reload every panel whose location is that archive

**Source:** [zip-as-folders.md §4](zip-as-folders.md) — serialize mutations per archive file so two rewrites cannot clobber each other; reload every panel whose location is that archive.

**Today:** mutations go through the `ArchiveService` actor (serialization per process). After copy/move/delete/mkdir/rename, [`MainWindowView`](../../LCdrData/Views/MainWindowView.swift) reloads the two panels in that window only. A second window sitting in the same zip is stale until its `DirectorySession` watcher fires — and a same-process rewrite may or may not.

**Work:** after a successful archive mutation, reload every live panel whose `watchURL` is that container, across windows. The watcher can stay as the fallback for external editors.

---

## 6. Missing unit tests

**Source:** [zip-as-folders.md §8](zip-as-folders.md).

| Gap | Where it should live |
| --- | --- |
| Drop onto an archive-backed panel packs (same path as copy-in) | `FileOperationViewModel` / `BrowseOperationService` — `performDrop` exists; no test drives it into a zip |
| Hidden-files filter inside a zip | `PanelViewModel` (and/or `ArchiveService.list` with `showHidden: false`) — listing already skips `.*` names, but no test asserts it |

---

## 7. Optional archive icon

**Source:** [zip-as-folders.md §7](zip-as-folders.md) — archive icon optional (`doc.zipper` vs `doc`).

**Today:** [`FileTableView.fileIcon`](../../LCdrData/Views/FileTableView.swift) uses `doc` for every non-directory file, including `.zip` rows.

**Work:** if we want the visual cue, branch `item.isArchive` to `doc.zipper`. Skip this if the SF Symbol looks worse at table-row size; it was optional on purpose.
