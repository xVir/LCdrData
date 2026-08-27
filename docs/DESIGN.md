# LCdrData — Design Document

What LCdrData is meant to feel like to use. This document is the **product spec**: layout,
behaviour, keyboard model and configuration, described from the user's side.

> It deliberately contains no architecture or code. For how the app is actually built —
> modules, services, data flow — see **[CURRENT_ARCH.md](CURRENT_ARCH.md)**, which also
> records where the two currently disagree.

## Overview

LCdrData is a native macOS dual-panel file manager inspired by orthodox file managers
(Total Commander, ForkLift, Midnight Commander). The name "LCDR" stands for "Lieutenant
Commander" — a nod to the tradition of naming file managers after military and naval ranks
(Commander, Captain), and a reference to Lieutenant Commander Data from *Star Trek: The Next
Generation*.

It offers a keyboard-driven, power-user file management experience: two side-by-side
directory panels, a function-key command bar, and file operations that always run between
the two panels.

## Design principles

1. **Keyboard-first.** Every action is reachable from the keyboard; the mouse is optional.
2. **Native macOS.** It behaves like a Mac app — Quick Look, the Trash, Finder integration,
   the standard menu bar, and the system's own folder-access prompts.
3. **Responsive.** Large directories stay usable; nothing blocks the window.
4. **Focused.** A small, coherent core rather than a feature checklist.
5. **Transparent.** Operations show real progress, and failures say what went wrong.

## The window

Minimum 800 × 500 points; opens at 1100 × 700.

```
┌──────────────────────────────────────────────────────────┐
│  /Users/dan/Documents  │  /Users/dan/Downloads           │  Path bars
├────────────────────────┼─────────────────────────────────┤
│  ..                    │  ..                             │
│  > Projects/      4 KB │  archive.zip          12.3 MB   │
│  > Photos/       12 KB │  report.pdf            2.1 MB   │
│    notes.txt      1 KB │  > screenshots/         4 KB    │
│    readme.md      3 KB │    image.png          845 KB    │
│                        │                                 │
├────────────────────────┼─────────────────────────────────┤
│  3 items, 8 KB         │  4 items, 15.2 MB               │  Status bars
├────────────────────────┴─────────────────────────────────┤
│  [F3 View] [F5 Copy] [F6 Move] [F7 Mkdir] [F8 Delete]    │  Command bar
└──────────────────────────────────────────────────────────┘
```

**Multiple windows.** `⌘N` opens another window with its own pair of panels, starting from
the frontmost window's directories. Windows are independent, but granted folder access and
settings are shared across all of them. Closing the last window quits the app, and the next
launch restores where you left off.

## Panels

- Two side-by-side panels, each independently navigable, separated by a resizable splitter.
- Exactly one panel is **active** at a time, shown by a tinted border. `Tab` switches;
  clicking a panel activates it.
- Each panel has a path bar, a file table and a status bar showing item counts and the size
  of the selection.
- File operations always run **from the active panel to the other one**, which is what makes
  a two-panel layout worth having.

## The file table

- Columns: Name, Size, Date Modified, Kind. Click a header to sort; click again to reverse.
  Directories group before files.
- A `..` row sits at the top of every listing except the filesystem root.
- Click to select, `⌘`-click to add to the selection, `⇧`-click for a range.
- `Return` enters a directory or a `.zip`; on any other **file** it starts a rename, the way
  Finder does.
  `F2` renames whatever is focused, orthodox-style. Neither applies to `..`.
- Double-click or `⌘↓` opens a file and enters a directory.
- `Delete` and forward delete go to the **parent directory** — the same as activating `..` —
  when the list has keyboard focus and the path bar is not being edited. This is the orthodox
  convention, and it is why moving to the Trash is `F8` rather than `Delete`.
- `⌘⇧.` toggles hidden files.
- Dragging rows out exports the files; dropping files onto a panel copies them in.

## Navigation

- **Path bar** — clickable breadcrumbs, or `⌘L` to type a path directly. `~` works and
  expands to your real home folder. A button copies the current path.
- **Parent** — the `..` row, `⌘↑`, or `Delete`.
- **History** — back and forward per panel, `⌘[` and `⌘]`.
- **Favorites** — a menu of saved locations, defined in your configuration file.
- **Open Folder…** — `⌘⇧O`, which is also how you grant access to a folder outside the
  sandbox.

## File operations

Everything acts on the active panel's selection, with the other panel as the destination.

| Operation | Shortcut | Description |
|---|---|---|
| Copy | `F5` | Copy the selection to the other panel |
| Move | `F6` | Move the selection to the other panel |
| Move to Trash | `F8` | With confirmation |
| Delete permanently | `⌘⌫` | Bypasses the Trash, with confirmation |
| New folder | `F7` | Create a directory in the active panel |
| Rename | `Return` / `F2` | `Return` is Finder-style and only on non-enterable files, `F2` orthodox |
| View | `F3` / `Space` | Quick Look preview |
| Edit | `F4` | Open in the editor from `editor.default-app` |
| Refresh | `⌘R` | Reload the active panel |

- Destructive operations ask first.
- Long copies and moves show a progress overlay that can be cancelled part-way.
- When a file already exists at the destination, a dialog offers **overwrite**, **skip** or
  **rename** — and an *apply to all* toggle so a large batch needs answering once.
- Panels refresh themselves when their directory changes on disk, so an operation performed
  elsewhere shows up without a manual reload.

After an operation the cursor lands somewhere sensible rather than jumping to the top: on the
new item after a rename or a new folder, on the neighbouring row after a delete, and on the
directory you came from after going to a parent.

## Keyboard

Arrow keys move through the list, and typing plain characters jumps to the first matching
filename — the buffer clears after a second of silence.

| Shortcut | Action |
|---|---|
| `Tab` | Switch active panel |
| `Return` | Enter a directory or `.zip`, or rename any other focused **file** |
| `F2` | Rename the focused item (not `..`) |
| `Delete` / forward delete | Go to parent directory |
| `⌘↑` | Go to parent directory |
| `⌘↓` / double-click | Open file, enter directory |
| `⌘L` | Edit the path bar |
| `⌘⇧O` | Open Folder… |
| `⌘R` | Refresh panel |
| `⌘⇧.` | Toggle hidden files |
| `⌘[` / `⌘]` | History back / forward |
| `⌘A` | Select all (excludes `..`) |
| `⌘⇧A` | Collapse the selection to the focused row |
| `⌘⌥C` | Copy selected paths to the clipboard |
| `⌘⌫` | Delete permanently, with confirmation |
| `Space` / `F3` | Quick Look preview |
| `F4` | Open in the editor from `editor.default-app` |
| `F5` / `F6` | Copy / move to the other panel |
| `F7` | New folder |
| `F8` | Move to Trash |
| `Home` / `End` | First / last row |
| `⌘N` | New window |
| `⌘,` | Settings |
| Arrows | Move through the list |
| Any letter | Incremental filename search |

The command bar along the bottom labels the function keys — `F3 View`, `F5 Copy`, `F6 Move`,
`F7 Mkdir`, `F8 Delete` — in the manner of classic orthodox managers. The buttons are
clickable, and they grey out when they do not apply, so the bar doubles as a reminder of what
is currently possible.

Menu bar equivalents exist for navigation, selection and delete commands, so the standard
macOS discovery route works too.

## Folder access

The app is sandboxed, so it can only see folders you have explicitly allowed. This is
deliberately quiet:

- On first launch it asks once for your home folder, which covers most work.
- Navigating somewhere it cannot read prompts for exactly that folder, and continues where
  you left off once granted. Declining leaves the panel where it was rather than in an error
  state.
- **Grant Folder Access…** in the menu asks up front, without waiting for a failure.
- Grants persist across launches. You should never be asked twice for the same folder.

## Configuration

Settings are a [KDL 2.0](https://kdl.dev/) document — a human-friendly, node-based format.
Your file lives inside the app's sandbox container:

```
~/Library/Containers/com.xvir.LCdrData/Data/Library/Application Support/com.xvir.LCdrData/config.kdl
```

It is created the first time you apply a change, and deleting it restores every default.

```kdl
panel {
    show-hidden-files #false
    sort-by name
    sort-ascending #true
}

appearance {
    font-size 13
    date-format "yyyy-MM-dd HH:mm"
}

bookmarks {
    - "Projects|~/Projects"
    - "Downloads|~/Downloads"
}

editor {
    default-app "com.apple.TextEdit"
    open-folders #false
}
```

Each `bookmarks` entry is a `label|path` pair and becomes an item in the Favorites menu;
`~` expands to your home folder.

`editor.default-app` is the bundle identifier of the application `F4` opens files with. If it
names an application you do not have installed, `F4` falls back to the system default handler
rather than refusing to open the file. It applies to `F4` alone — `Return` and double-click
still open a file the way Finder would.

`editor.open-folders` extends `F4` to folders, which is what an editor that opens a project
directory wants. Off by default, so `F4` over a folder does nothing. Turn it on and `F4` hands
the folder — including `..`, the parent — to the same application. Folders **inside** a ZIP
stay excluded either way: the editor would only ever see an extracted copy, and edits to it
would never reach the archive.

### The settings window

`⌘,` opens a window laid out as two side-by-side panes, echoing the app's own dual-panel
metaphor:

1. **Left — the defaults, read-only.** The complete default configuration in KDL, syntax
   highlighted, listing every supported option with its built-in value. This is the
   reference for what the app assumes when you have not said otherwise.
2. **Right — your overrides, editable.** Only what you write here is saved. Anything you set
   overrides the corresponding default; anything you leave out keeps it.
3. **Apply** parses and validates your text, then applies the merged result to the running
   app immediately — no restart, and every open window updates — and closes the window. If the
   KDL does not parse, an inline message points at the problem, nothing is applied, and the
   window stays open so you can fix it.
4. **Cancel** discards unsaved edits and closes the window. Nothing you typed since the last
   Apply is kept, so reopening the window shows the last applied version again.

The window never auto-saves. Nothing takes effect until you click Apply.

## ZIP archives as folders

Activating a `.zip` file enters it in the current panel. Archive folders, `..`, `⌘↑`, and
back/forward history behave like directory navigation; nested zip members remain ordinary files.
The path bar shows the archive file followed by its internal path.

Copy, move, drag-and-drop, new folder, rename, and delete work across filesystem directories and
writable zip locations. Delete inside a zip removes the member permanently rather than using
Trash, and the confirmation says so. Existing-name conflicts use the same overwrite, skip, and
rename choices as filesystem operations. Mutating commands are disabled for a read-only zip.

Quick Look, F4, and dragging a member out extract that member to temporary storage first. Session
restore records only the real directory containing the zip; a new window opened with `⌘N` during
the same run still clones the current archive location.

## Not in scope yet

Deliberately absent from the current design, in rough order of appeal:

- **Tabs** — several directories per panel.
- **Remappable shortcuts** — the keyboard map above is currently fixed.
- **A toolbar** and a **volumes list**, for pointer-driven navigation.
- **An inline preview pane**, as an alternative to the Quick Look panel.
- **Search** beyond type-ahead — by name across a tree, or by content.
- **Other archive formats** — tar and formats other than zip.
