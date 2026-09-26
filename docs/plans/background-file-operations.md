# Background file operations

Long-running file operations keep the panels usable. A ring in the trailing edge of the window title bar draws their combined progress as an arc. Clicking it opens a list of what is running, what is waiting, what finished, and what failed. A running row can be cancelled. A waiting row can be cancelled too, and then it never starts.

The ring matches the reference image: a dim circular track, hollow in the middle, with a bright arc along that track.

## Summary

Copy, move (including pack and unpack), Move to Trash, permanent delete, and delete-from-archive always run as **background tasks**. The blocking progress overlay goes away. The user can keep browsing, and can start another long operation while earlier ones are still going.

Each window runs at most `operations.max-active` tasks at once. The default is 3, and the value is configurable. A task confirmed past that limit is **Waiting**: it has a row, it has not touched the filesystem, and Cancel removes it so it never runs. When a running task finishes, fails, or is cancelled, the oldest waiting task starts.

Each window shows a **task indicator** in the title bar when that window has work to report. The arc is the combined progress of that window's running tasks. Waiting tasks do not move the arc. Clicking the ring opens the **task list**: every running task, every waiting task, then the most recent finished, failed, and cancelled ones, capped at `max(10, running + waiting)`. Cancel on a running task abandons the rest of that task. It does not resume, and it does not undo items already copied, moved, or removed.

Rename and New Folder stay as they are: a short dialog, then a single quick change.

## Goals

- The panels, keyboard, and command bar stay usable during copy, move, unpack, pack, and folder removal.
- Up to `operations.max-active` of those operations run at the same time in one window. The rest wait.
- Progress is visible without covering the file lists.
- Finished and failed work stays visible long enough to read, without an unbounded log.
- Cancel on a running task means "do not process the remaining items." Already-finished items stay as they are.
- Cancel on a waiting task means the task is never executed.

## Non-goals

- Resume, retry, or undo of a cancelled or failed task.
- A byte-level progress report inside one `FileManager` copy or remove. Progress stays per top-level item, which is what the services report today.
- A global queue shared by every window. Each window keeps its own tasks, matching `FileOperationViewModel` living on that window's `AppState`. The limit is applied per window.
- A lock that stops two running tasks from touching the same files. Tasks that are both running may overlap; a conflict or a failure is reported on the task that hit it.
- Persisting the task list across relaunch. Quit and relaunch start from an empty list.
- Changing confirmation copy, conflict choices (overwrite / skip / rename / apply to all), or the command set. Unpack is still Copy. There is no Extract command.

## Product principles

1. Long work never takes the window away from the user.
2. The indicator is quiet when nothing is running and impossible to miss while something is.
3. Every running task and every waiting task is always listed. History fills whatever room is left.
4. Cancel is per task and final.
5. A failure is a row in the list, not a modal alert that interrupts browsing.

---

## What becomes a background task

| User action | Today | This plan |
|---|---|---|
| Copy (`F5`), including copy out of an archive (unpack) and copy into an archive (pack) | Confirmation, then a blocking progress overlay | Confirmation, then a background task |
| Move (`F6`), including move in or out of an archive | Same overlay | Background task |
| Move to Trash (`F8`) | Confirmation, then the UI waits with no progress | Background task |
| Delete permanently (`⌘⌫`) | Confirmation, then the UI waits | Background task |
| Delete inside an archive | Confirmation, then the UI waits | Background task |
| Drop files onto a panel | Runs untracked, no progress | Background task, no extra confirmation |
| New Folder (`F7`), Rename (`Return` / `F2`) | Dialog, then one quick change | Unchanged. Not background tasks |

Confirmation dialogs stay. DESIGN requires destructive operations to ask first, and copy/move already ask. The dialog is only the decision to enqueue. Once the user confirms, the task is either running or waiting, and the panels are free.

---

## User experience

### Task indicator

A 16 pt ring, vertically centered in the window's title bar, inset a few points from the trailing edge. It is a button. The center is empty — the title bar shows through. This is the reference image: a circular stroke, not a filled pie.

Two strokes, both about 2.5 pt, with round line caps:

- A track: the full ring, in a quaternary label color, low emphasis. On a light title bar it stays a neutral gray; it is not a hardcoded black.
- An arc: the system accent color (blue in the reference, the user's accent otherwise). It starts at 12 o'clock and grows clockwise. At 0 only the track shows. At 1 the arc closes the ring.

```swift
Circle().stroke(trackColor, lineWidth: 2.5)
Circle()
    .trim(from: 0, to: fraction)
    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
    .rotationEffect(.degrees(-90))
```

The fraction is the combined progress of every **running** task in this window. Waiting tasks are left out:

```
completed items across running tasks / total items across running tasks
```

A running task that has not reported progress yet counts as 0 completed. If the total is still 0, the fraction is 0 and the ring is track-only.

The control's accessibility label names the state: "Background tasks, 2 running, 1 waiting, 40 percent" while work is in progress, or "Background tasks, finished" / "Background tasks, 1 failed" when nothing is running but the list is still showing results.

There is no separate toolbar row. The window does not grow a toolbar to hold this control.

#### When it is visible

| Situation | Indicator |
|---|---|
| Nothing running, nothing waiting, and the list has nothing left to show | Hidden |
| One or more tasks running | Visible, accent arc growing |
| Only waiting tasks (should be brief; a free slot starts the oldest one) | Visible, track only |
| Nothing running or waiting, but finished / failed / cancelled rows are still unacknowledged | Visible, arc closed. If any of those rows failed, the ring uses the error color. Otherwise it uses a secondary color, so a settled ring does not look like work is still moving |

Opening the task list does not hide the indicator. Closing the list acknowledges every task that had already finished, failed, or been cancelled. If nothing is still running or waiting, the indicator hides and those rows leave the list. Running and waiting tasks stay, and so does the indicator.

If the user never opens the list, a settled ring remains, so a finished or failed task is not silent.

### Task list

Clicking the circle toggles a popover anchored to it, opening downward into the window. Clicking outside, or pressing Escape while the popover is key, closes it. Escape does not reach the panels while the popover is open. Closing it is what acknowledges settled rows (see above).

The popover is wide enough for one line of description, a status, and a Cancel button (about 320 pt). It does not cover both panels as a modal overlay.

#### How many rows

Let `running` be the tasks actually executing, `waiting` be the tasks not started because the window is at `operations.max-active`, and `settled` be finished, failed, and cancelled tasks, newest last.

```
cap     = max(10, running.count + waiting.count)
visible = all of running, then all of waiting, then the newest (cap - running.count - waiting.count) settled tasks
```

Examples, with `max-active` at 3:

- 0 running, 0 waiting, 15 settled → the 10 newest settled rows.
- 3 running, 2 waiting, 20 settled → 3 running + 2 waiting + the 5 newest settled.
- 3 running, 9 waiting, 5 settled → all 12 unfinished rows, and no settled rows. Unfinished work is never clipped to make room for history.

Order inside the popover, top to bottom: running tasks, oldest first; then waiting tasks, oldest first (the next one to start is at the top of that group); then settled tasks, newest first.

Storage can keep more settled tasks than the cap (a small buffer, 50 is enough). The cap is a display rule. Acknowledging on close drops the acknowledged rows from storage. It does not drop running or waiting rows.

#### A row

Every row shows:

- The operation description already on `FileOperation.displayDescription` ("Copying 4 items", "Moving 1 item", "Deleting 12 items", "Permanently deleting 3 items", and the same words for archive pack, unpack, and delete-from-archive — those are still Copy, Move, and Delete).
- One line of detail, truncated in the middle: the current item name while running, the destination path when there is one, and for a failure the error text. A waiting row has no current item.
- A status: Running, Waiting, Finished, Failed, Cancelled.

Running is `FileOperationStatus.inProgress`. Waiting is the existing `.pending` — queued, not started. Cancelled is `.cancelled`.

A running row shows its own progress ("3 of 12", or an indeterminate spinner until the first report) and a Cancel button. A waiting row shows no progress and a Cancel button. Settled rows have no Cancel button.

Cancel asks for no extra confirmation. It affects that task only.

A task that is already running and is paused on the conflict sheet stays **Running**. Its detail line says a name conflict needs a decision. That is not Waiting. Waiting means "not started, because the window is already at `max-active`."

### What the user can do while tasks run

- Browse either panel, switch panels, switch tabs, navigate, select, type-ahead, Quick Look, rename, and create folders.
- Start another copy, move, or delete. It is another row. If the window already has `max-active` tasks running, the new row is Waiting and does not start yet.
- Confirm or dismiss the *next* operation's confirmation dialog. That dialog is still modal to keyboard routing, exactly as today, because the operation has not been enqueued.
- Resolve a name conflict. The conflict sheet still appears, for one running task at a time. Other running tasks keep going. The conflict sheet gains a Cancel button that cancels that running task (same effect as Cancel on its row). Overwrite, skip, and rename are unchanged.
- If a second running task also needs a conflict decision, it stays Running and holds its slot. The sheet appears when the first decision returns. Its detail line says a decision is queued. It is not a Waiting row.

### What Cancel does

On a **running** task:

- The task stops before the next top-level item.
- Items already copied, moved, trashed, or deleted stay that way. Nothing is rolled back.
- The in-flight item is allowed to finish. `FileManager.copyItem`, `moveItem`, `trashItem`, and `removeItem` do not report progress or accept cancellation in the middle of one call. A single huge folder is one item, so Cancel on that task takes effect when that call returns, and the arc stays put until then.
- The row becomes Cancelled and counts as settled.
- The panels the task was acting on reload, the same as a finish, so partial results show up.
- The oldest waiting task starts if a slot is now free.

On a **waiting** task:

- The task is never executed. No file is copied, moved, or removed, and the panels do not reload for it.
- The row becomes Cancelled and counts as settled.
- Later waiting tasks keep their order. Nothing starts unless a running slot is free.

There is no Resume.

### Failures

A background task that fails marks its row Failed and keeps the error text on the row. It does not raise the window's error alert. The settled indicator uses the error color until the user opens and closes the list.

Rename and New Folder still use the error alert. They are not background tasks.

### Closing the window or quitting

Closing a window that has running or waiting tasks asks first: how many are running and how many are waiting, and that closing cancels them. Waiting tasks will not run. The default button is Cancel and Close; the other is Keep Open. The same question is asked on quit if any window still has running or waiting tasks.

A settled-only indicator does not block close. Those rows are discarded with the window.

---

## Behaviour that has to stay correct

### Which panels reload

Today `confirmOperation` reloads "the active panel" and "the inactive panel" when the task *ends*. Once the user can switch panels while a copy runs, that would refresh the wrong sides.

Capture the source panel and the destination panel at the moment of Confirm (or at the moment a drop starts). Reload those two when the task finishes, fails, or is cancelled — even if the user has since switched the active panel or navigated. A waiting task that is cancelled never reloads anything. Cursor intent:

- Copy: keep selection on both panels.
- Move and both kinds of delete: land on the neighbour of the removed items in the source panel; keep selection in the destination.

The confirmation handler's intent switch currently matches only the URL-based `.move` / `.delete` / `.permanentDelete` cases. The live operations are `.browseMove` and `.browseDelete`, so they already fall through to keep-selection. Fix that in the same change, using the items' URLs the cursor resolver already compares.

### How many tasks run

`operations.max-active` in KDL, parsed as `AppConfiguration.operationsMaxActive`. The key is already in `LCdrData/Resources/DefaultConfig.kdl` with value 3. Values below 1 are ignored, so the effective limit stays at least 1 and a task can always start.

The limit is per window. Two windows can each run 3 tasks. `AppState.applyEffectiveConfiguration()` pushes the current value into that window's `FileOperationViewModel` when settings are applied.

On confirm or drop:

- If `running.count < maxActive`, the task starts immediately (`.inProgress`) and its `Task` goes in the map.
- Otherwise the task is appended as `.pending` (Waiting). No `Task` is created. The filesystem is not touched.

When a running task leaves the running set (finished, failed, or cancelled), start the oldest waiting task if `running.count < maxActive`. Repeat until the slots are full or the waiting list is empty.

If the user raises `max-active` while tasks are waiting, start oldest-first until the new limit. If they lower it, do not cancel tasks that are already running. Just stop starting new ones until `running.count` is under the new limit.

Cancel on a waiting task sets `.cancelled`, drops it from the waiting list, and does not start a `Task`.

### One task handle is not enough

`FileOperationViewModel` stores a single `currentTask`. A second Confirm replaces it, so Cancel can only see the latest task. Replace that with a map from operation id to its `Task`, holding running tasks only. Waiting tasks are not in the map. Cancel on a running id cancels that task. Closing the window cancels every task still in the map and drops every waiting task without starting it.

`showProgressOverlay` and `FileOperationProgressView` go away. Keyboard routing stops treating "a progress overlay is up" as a reason to swallow keys. It still goes quiet for the confirmation dialog, the conflict sheet, rename, and new folder.

### Cancellation has to reach the loop

Copy and move already call `Task.checkCancellation()` between top-level items on the task that Confirm started, so Cancel works between items.

Trash and permanent delete wrap the whole loop in `Task.detached` and never check cancellation. A detached task does not see the parent task being cancelled. Move those loops onto the task the user cancelled (or forward cancellation into the detached task) and check between items. Report progress per item so the arc moves during a large trash or delete.

Archive delete walks entries in a loop with no cancellation check. Check between entries. Pack and unpack already report per item; they need the same between-item cancellation check if any branch of `BrowseOperationService` does not have one.

### Conflicts are per running task

The view model has one `conflictContinuation`. With several running tasks, a conflict belongs to the task that raised it. Keep a single sheet — one decision at a time — and hold the other running tasks that need a decision behind it. They stay `.inProgress` and keep their slots. Cancelling that running task resumes its continuation by throwing cancellation, and dismisses the sheet if that task is the one on screen.

This hold is not the Waiting list. Waiting tasks have not started and cannot raise a conflict.

`applyToAll` stays per task. One copy's "apply to all" must not answer another copy's conflicts.

### Drops

`performDrop` calls the browse copy service with an empty progress callback and never enters `activeOperations`. It becomes a normal background copy: a row, and either a running task or a waiting one under the same limit. A running drop reports progress, can be cancelled, and reloads the destination panel when it ends. A waiting drop does none of that until it starts.

### Same files, two tasks

No lock between tasks that are both running. If the user trashes a folder that another task is copying, that task fails and its row says why. The directory watcher still refreshes a panel that is showing the affected folder.

### Progress shape

`FileOperationProgress` stays item counts (`completedItems` / `totalItems` plus the current name). Do not add byte totals in this work. A one-folder copy is one item, so the arc stays empty until `copyItem` returns, then jumps to that item's share of the total.

### Several windows

The indicator and the list are per window. A copy started on the left window does not appear in the right window's title bar. The other window still sees the files change through its directory watcher.

The Settings window has no indicator.

---

## Vocabulary

Add these to [CONTEXT.md](../CONTEXT.md) when the feature lands. Use them in code and in the design doc.

### Background task

A copy, move, or delete tracked on the window's `FileOperationViewModel` while the panels stay usable. It is either **running** or **waiting**. Rename and New Folder are not background tasks.

_Avoid_: job; Extract (unpack is Copy).

### Waiting

A background task that has been confirmed and has not started, because the window already has `operations.max-active` running tasks. Cancel removes it and it never runs. The oldest waiting task starts when a running slot frees.

_Avoid_: using Waiting for a running task that is paused on a name-conflict sheet. That task is still running.

### Task indicator

The ring in the trailing title bar. Hidden when the window has nothing to report. Its arc is the combined item-progress of that window's running background tasks.

_Avoid_: pie; spinner (the arc length is the progress; the ring does not spin); toolbar button (it lives in the title bar).

### Task list

The popover opened from the task indicator. Every running background task, every waiting one, plus recent finished, failed, and cancelled ones, capped at `max(10, running + waiting)`.

_Avoid_: progress overlay (that is the view this replaces); notification center.

### Cancel

On a running background task: stop before the next top-level item. Partial results remain. On a waiting background task: do not start it. There is no resume.

_Avoid_: pause; continue; undo.

---

## Architecture

```
WindowRootView / MainWindowView
  └── WindowConfigurator
        └── NSTitlebarAccessoryViewController (.right)
              └── TaskIndicatorButton          SwiftUI ring, 16 pt
                    └── click → NSPopover
                          └── TaskListView     rows + Cancel

AppState (per window, unchanged owner)
  └── FileOperationViewModel
        ├── running: [FileOperation]          status inProgress
        ├── waiting: [FileOperation]          status pending, oldest first
        ├── settled: [FileOperation]          completed / failed / cancelled
        ├── tasks: [UUID: Task]               running ids only
        ├── maxActive: Int                    from operations.max-active, default 3
        ├── conflictQueue                     one sheet, one continuation per running task
        └── indicatorState                    hidden / running(fraction) / settled(hasFailure)

Models
  └── TaskListPolicy                          pure: visible rows + aggregate fraction

Services (unchanged routing)
  └── BrowseOperationService / FileOperationService / ArchiveService
        check cancellation between items; trash and delete report progress
```

`FileOperation`, `FileOperationStatus`, and `FileOperationProgress` stay. Waiting is `.pending`. Cancel writes `.cancelled`, and the row title is "Cancelled". No new operation kind. Archive pack and unpack stay `.copy` and `.move`.

### Title bar, not a toolbar

The window has no toolbar today. `WindowConfigurator` already reaches the `NSWindow` for `titlebarSeparatorStyle`. Extend that path:

- One `NSTitlebarAccessoryViewController` with `layoutAttribute = .right`, added once per window. `updateNSView` on the configurator must not add a second controller.
- Its view is an `NSHostingView` of the ring button.
- The popover is an AppKit `NSPopover` (transient) presented from that accessory view. A SwiftUI `.popover` attached inside a title-bar hosting view is the fallback only if the AppKit popover cannot anchor; prefer AppKit so the anchor stays on the ring when the window resizes.

Do not introduce `.toolbar` or a unified toolbar style for this. That would add a toolbar band under the title or change the chrome around the path bar.

The accessory is created with the window and kept up to date from `FileOperationViewModel` (the hosting view observes it). The view model does not import AppKit.

### Task list policy

A pure value type in `Models`, tested without a service or a window:

```swift
package struct TaskListPolicy: Sendable {
    package static let minimumSlots = 10
    package static let settledCapacity = 50

    package func visible(
        running: [FileOperation],
        waiting: [FileOperation],
        settledNewestLast: [FileOperation]
    ) -> [FileOperation]

    /// Nil when nothing is running. Waiting tasks are not included. Otherwise 0...1.
    package func aggregateFraction(running: [FileOperation]) -> Double?
}
```

`visible` implements the cap in the User experience section. `FileOperationViewModel` trims `settled` to `settledCapacity` on every insert, dropping the oldest.

### View model

`confirmOperation` and `performDrop` record a `FileOperation` and return immediately. If a running slot is free, they store its `Task` in the map. If not, they append `.pending` and store no task. The task body is the existing `executeBrowseTransfer` / `executeBrowseDelete` path with three changes:

- Do not set `showProgressOverlay`.
- On finish, fail, or cancel, move the operation from `running` to `settled` instead of deleting it, then start the oldest waiting task if a slot is free.
- Record which running task owns the in-flight conflict, so Cancel and the sheet's Cancel target that id.

`cancelCurrentOperation()` becomes `cancel(id: UUID)`. On a running id it cancels the task. On a waiting id it marks the row cancelled and does not start work. Remove the overlay flag once nothing reads it.

`maxActive` comes from `AppConfiguration.operationsMaxActive` (already parsed; default 3). `applyEffectiveConfiguration()` copies it onto the view model and then starts waiting tasks if the new limit has free slots.

Indicator state is computed:

- `running` non-empty → `.running(aggregateFraction)`. Waiting tasks do not change the fraction.
- `running` empty, `waiting` non-empty → `.running(0)` so the track shows and the button stays.
- both empty and `settled` non-empty → `.settled(hasFailure:)` where failure means any settled row is `.failed`.
- all three empty → `.hidden`.

Closing the popover calls `acknowledgeSettled()`, which drops settled rows. It does not touch `running` or `waiting`.

### Modules

| Piece | Module | Why |
|---|---|---|
| `TaskListPolicy` | `Models` | Leaf, no services, unit-tested beside `FileOperation` |
| `operations.max-active` | `Models` + `Services` | Already parsed into `AppConfiguration.operationsMaxActive` |
| Task map, waiting list, cancel, acknowledge, conflict queue | `ViewModels` (`FileOperationViewModel`) | Already the coordinator |
| Ring, list rows | `Views` | Presentation only |
| Title-bar controller and popover | `Views`, next to `WindowConfigurator` | AppKit stays out of the view model |
| Cancellation and progress in trash, delete, archive remove | `Services` | The loops live there |

No new Bazel target. `Views` still has no unit-test directory; the policy and the view model carry the tests. UI tests are out of this plan's routine check (run them only when explicitly asked).

---

## Documentation to update in the implementation

- [DESIGN.md](../DESIGN.md) — the `operations { max-active 3 }` block and a sentence for the key are already there. When the UI lands, replace "Long copies and moves show a progress overlay that can be cancelled part-way" with the ring, the list, Waiting, and Cancel. Mention that folder removal is included and that the panels stay usable.
- [CONTEXT.md](../CONTEXT.md) — the terms above, including Waiting.
- [CURRENT_ARCH.md](../CURRENT_ARCH.md) — the default KDL snippet already includes `operations.max-active`. When the UI lands, `FileOperationProgressView` is removed; describe the accessory and the view-model task map. Note that `FileOperationViewModel` is still per window.

---

## Implementation slices

Each slice is shippable on its own and keeps `bazel test //LCdrDataTests/...` green.

### 1. Policy and a multi-task view model

`operations.max-active` is already in the default KDL and on `AppConfiguration`. This slice consumes it.

Add `TaskListPolicy` and tests: cap math with waiting rows included, aggregate fraction that ignores waiting tasks, empty running.

Change `FileOperationViewModel` so each confirmed operation and each drop is its own row. The first `maxActive` run; the rest stay `.pending` with no task. `cancel(id:)` cancels one running task and leaves the others, or drops a waiting task without starting it. When a running task ends, the oldest waiting task starts. Settled rows accumulate and trim to 50. `applyEffectiveConfiguration()` copies `operationsMaxActive` onto the view model. Delete `showProgressOverlay` once the view no longer reads it — until slice 3, the window simply does not show the overlay (slice 1 can land behind a temporary "no overlay" if slice 3 follows immediately; do not leave the user with silent copies for long).

Tests in `FileOperationViewModelTests`: with `maxActive` 1, a second copy stays waiting and does not call the service; cancelling that waiting copy never calls the service; when the first finishes, the waiting one starts. With `maxActive` 3, three run and the fourth waits. A failure is a settled row and does not set `showErrorAlert`. Acknowledge clears settled and leaves running and waiting. A drop creates a row.

### 2. Services honour Cancel and report delete progress

Trash, permanent delete, and archive remove check cancellation between items and report `FileOperationProgress`. Copy, move, pack, and unpack already report progress; add a missing check if a branch has none.

Test with the existing fakes: a cancelled task does not process the item after the check; progress is published per item.

### 3. Title-bar indicator and task list

Add the accessory, the ring (track plus clockwise accent arc), and the popover. Wire Cancel on running and waiting rows, and the conflict sheet's Cancel. Remove `FileOperationProgressView`.

Keyboard routing no longer depends on the overlay. Confirmation, conflict, rename, and new-folder dialogs still suspend it.

Fix completion reload to capture the source and destination panels, and to use neighbour-landing for browse move and browse delete.

Window close and quit prompt when `running` or `waiting` is non-empty.

### 4. Docs

Update DESIGN, CONTEXT, and CURRENT_ARCH for the ring, the list, and Waiting, as listed above. The config key itself is already documented. Same change as slice 3, or the commit immediately after it. Do not describe the overlay as gone in slice 1 while it is still the real UI.

---

## Tests

Unit tests only, under Bazel:

- `LCdrDataTests/Core/Models` — `TaskListPolicy`, including waiting rows in the cap and excluded from the fraction.
- `LCdrDataTests/ViewModels` — the limit, cancel of a waiting task before it starts, promotion of the oldest waiting task, settled cap, acknowledge, drop, failure without an alert, conflict `applyToAll` isolated per running task.
- `LCdrDataTests/Services` — `operations.max-active` default 3, an override, and a value below 1 ignored (already added). Cancellation between items for trash, permanent delete, and archive remove; progress callbacks.

No new UI test in the routine run. When UI tests are explicitly requested, cover: the ring appears after a copy of several files, the list shows the row, Cancel leaves the already-copied files in place, a task past the limit shows Waiting and never runs if cancelled, and the panels still accept a click while a task is running.

---

## Decisions locked by this plan

These are the choices an implementation should follow. They are called out so they are not re-litigated mid-slice.

| Topic | Decision |
|---|---|
| How many run | `operations.max-active` per window, default 3. Already in `DefaultConfig.kdl`. Values below 1 are ignored. |
| Past the limit | Status Waiting (`.pending`). Not started. Cancel means it never runs. Oldest starts when a slot frees. |
| Lowering the limit | Running tasks keep going. No new task starts until under the new limit. |
| History cap | `max(10, running + waiting)` visible rows. Running and waiting rows are never omitted. |
| Settled rows | Finished, failed, and cancelled. All three share the history slots. |
| Indicator | A 16 pt ring. Dim track, accent arc clockwise from the top, hollow center. Matches the reference image. |
| Indicator after success | Stays, ring closed, secondary color, until the list is opened and closed. |
| Indicator after failure | Stays, ring closed, error color, until the same acknowledgement. No error alert. |
| Cancel on a running task | Between top-level items. No rollback, no resume. |
| One huge file or folder | One item. The arc does not move until that call returns. |
| Conflicts | Still a sheet, one at a time, on a running task. That task stays Running, not Waiting. |
| Scope | Per window. |
| Rename, New Folder | Not background tasks. |
