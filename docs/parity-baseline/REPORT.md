# Parity Report — Bazel vs Tuist

Phase 7 of [BAZEL_MIGRATION.md](../BAZEL_MIGRATION.md). Compares the Bazel-built
bundle against the Tuist baseline captured in Phase 0 (see
[README.md](README.md)).

Run 2026-08-20 at commit `582fb81`, Xcode 26.6, Bazel 9.2.0.

**Verdict: at parity.** All five items pass and every difference is explained and
intended.

## How the bundles were produced

```bash
bazel build //:LCdrData                    # debug  (fastbuild)
bazel build //:LCdrData --config=release   # release (opt)
```

Both configurations were checked, because the entitlements are behind a
`select()` and a `select()` with only one arm exercised is how a broken release
build ships. Staging was validated before comparing: the two apps have 5 vs 2
entitlement keys and non-identical binaries, confirming `bazel-bin` repointed
between builds rather than yielding the same zip twice.

## 1. Info.plist — one intended difference

Both configurations differ from the baseline by exactly one key:

```diff
- "NSMainStoryboardFile" => "Main"
```

Intended, per finding 2.6: the app is pure SwiftUI with `@main` on `LCdrDataApp`
and no storyboard anywhere in the tree. The key was inert Tuist boilerplate.

Everything else matches exactly, including `CFBundleIdentifier`, `CFBundleName`,
`CFBundleVersion`, `CFBundleShortVersionString`, `LSMinimumSystemVersion` (26.4),
`NSPrincipalClass`, `CFBundleIconFile`/`CFBundleIconName`, and all `DT*`
toolchain keys — the last because both builders used the same Xcode.

## 2. Entitlements — correct in both configurations

| Configuration | Keys |
|---|---|
| `release` (opt) | `app-sandbox`, `files.user-selected.read-write` |
| debug (fastbuild) | the above, plus `get-task-allow` and the two `temporary-exception` entries |

The release set is exactly the baseline minus `get-task-allow`, which is what a
shipping build should carry. This mirrors Xcode, whose Debug build also carries
`get-task-allow`.

The debug additions are not a convenience: without them an app-hosted
`macos_unit_test` cannot bootstrap, because the sandboxed host is refused a
connection to `testmanagerd`.

## 3. Bundle contents — two intended absences

Both configurations differ from the baseline by exactly two entries, and nothing
is present in the Bazel bundle that is absent from the baseline:

```diff
- LCdrData.app/Contents/MacOS/LCdrData.debug.dylib
- LCdrData.app/Contents/MacOS/__preview.dylib
```

Both are Xcode-only artifacts: the debug dylib Xcode uses to speed up
incremental debug builds, and the previews stub. Bazel links a single
self-contained binary instead, which the sizes corroborate — the baseline's
`Contents/MacOS/LCdrData` is a 58 KB stub that loads the dylib, where Bazel's is
4.8 MB (debug) or 2.9 MB (release) of actual program.

All expected artifacts are present in both:

| Artifact | Baseline | Bazel debug | Bazel release |
|---|---|---|---|
| `MacOS/LCdrData` | 58,928 | 4,817,856 | 2,886,144 |
| `Resources/Assets.car` | 2,503,688 | 5,450,840 | 5,450,840 |
| `Resources/AppIcon.icns` | 198,742 | 131,636 | 131,636 |
| `Resources/DefaultConfig.kdl` | 363 | 363 | 363 |

`DefaultConfig.kdl` is byte-identical to the source file and sits at
`Contents/Resources/DefaultConfig.kdl`, which is where `ConfigurationService`
looks it up. This was the highest-risk resource question in the migration and it
is settled.

The two icon artifacts differ in size because the Bazel build compiles an Icon
Composer `.icon` bundle rather than the `.appiconset` (see Phase 3). `Assets.car`
is larger because Icon Composer emits light, dark and tinted renditions where the
`.appiconset` emitted one; `AppIcon.icns` is smaller because it is generated from
different source geometry. Both were visually verified via `ictool` renders.

Both configurations are ad-hoc signed (`Signature=adhoc`), and
`codesign --verify --deep --strict` passes.

## 5. Unit tests — exact match

| Runner | Command | Result |
|---|---|---|
| Bazel | `bazel test //:LCdrDataTests --nocache_test_results` | `Test run with 193 tests in 23 suites passed` |
| Tuist | `tuist test "LCdrData" --skip-ui-tests --no-selective-testing` | 193 cases, 0 failures |

**193 = 193, zero failures on both.** `--nocache_test_results` and
`--no-selective-testing` are load-bearing: without them either side will happily
report success without running anything.

## 4. Manual sandbox smoke test — PASS

This is the item that cannot be automated, and the one that matters most: an
entitlements mistake does not fail the build, it fails at runtime as a permission
denial.

Tested against the **release** build (`/tmp/parity/release/LCdrData.app`), chosen
because it carries the minimal two-key entitlement set and is therefore the
configuration that can actually break. Verified the running process was the Bazel
binary rather than a Tuist copy — both share bundle ID `com.xvir.LCdrData`, so
`open` can otherwise activate the wrong one.

The container was reset first, to a genuinely empty `BookmarkStore`. All seven
flows from [CONTEXT.md](../../CONTEXT.md) pass:

- [x] **Startup Home prompt** — fires on first launch when no bookmark covers `~`.
- [x] **Granting works** — accepting the `NSOpenPanel` grants access and the panel
      lists contents.
- [x] **Tilde expansion** — `~` resolves to the real home, not the sandbox
      container path, so the `a87d015` fix holds under Bazel. Corroborated by the
      stored bookmark being `/Users/<user>` rather than the container path.
- [x] **Reactive grant prompt** — navigating to an uncovered directory prompts via
      the bookmark-coverage gate.
- [x] **Bookmark restore across launches** — no re-prompt after quit and relaunch,
      confirming `AppEnvironment.start()` resolved the stored bookmarks and called
      `startAccessingSecurityScopedResource()`.
- [x] **Session resume** — the previous run's panel directories are restored
      (`PanelSessionStore`, `230f1db`).
- [x] **File operations write successfully** into a granted directory, exercising
      `files.user-selected.read-write` rather than read-only access.

Ending state: 15 bookmarks accumulated across the run, from an empty start.

### Resetting the container, for future runs

`rm -rf ~/Library/Containers/com.xvir.LCdrData` reports
`Operation not permitted` for `.com.apple.containermanagerd.metadata.plist` and
for the container directory itself. Both are protected by SIP, and `sudo` does
**not** help — do not reach for it.

That error is nonetheless harmless: the command still deletes `Data/`, which is
where the bookmarks and `UserDefaults` live, and `containermanagerd` recreates
`Data/` on the next launch. The reset works despite the error text.

Confirm the reset actually took effect rather than trusting the exit code:

```bash
defaults read com.xvir.LCdrData bookmarks    # expect: does not exist
```

Note that `defaults read ... | head` is not a valid check — `head` exits 0 on
empty input, so it reports success either way. Compare byte counts instead.
