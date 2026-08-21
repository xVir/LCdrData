# Parity Report — Bazel vs Tuist

Phase 7 of [BAZEL_MIGRATION.md](../BAZEL_MIGRATION.md). Compares the Bazel-built
bundle against the Tuist baseline captured in Phase 0 (see
[README.md](README.md)).

Run 2026-08-20 at commit `582fb81`, Xcode 26.6, Bazel 9.2.0.

**Verdict: at parity.** Every difference is explained and intended. Items 1, 2, 3
and 5 pass. Item 4, the manual sandbox smoke test, is outstanding and needs a
human — see the last section.

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

## 4. Manual sandbox smoke test — OUTSTANDING

This is the one item that cannot be automated, and it is the one that matters
most: an entitlements mistake does not fail the build, it fails at runtime as a
permission denial.

The app to test is `/tmp/parity/release/LCdrData.app` (or rebuild with
`bazel build //:LCdrData --config=release`). Use the **release** build, since it
has the minimal entitlement set and is therefore the one that can actually break.

> **Reset the container first.** The Bazel and Tuist apps share bundle ID
> `com.xvir.LCdrData`, so they share one container, `BookmarkStore` and
> `UserDefaults`. Without a reset you will be testing against folder grants the
> Tuist build already made, and the first-launch paths will not be exercised:
>
> ```bash
> rm -rf ~/Library/Containers/com.xvir.LCdrData
> ```

Checklist, drawn from the flows in [CONTEXT.md](../../CONTEXT.md):

- [ ] **Startup Home prompt.** On first launch with no bookmark covering `~`, the
      app prompts for Home access.
- [ ] **Granting works.** Accepting the `NSOpenPanel` grants access and the panel
      lists the directory contents.
- [ ] **Tilde expansion.** `~` resolves to the real home directory, not the
      sandbox container path — the specific bug fixed in `a87d015`.
- [ ] **Reactive grant prompt.** Navigating to a directory no stored bookmark
      covers triggers the prompt via the bookmark-coverage gate.
- [ ] **Bookmark restore across launches.** Quit and relaunch: previously granted
      directories are accessible with no re-prompt, confirming
      `AppEnvironment.start()` resolved the stored bookmarks and called
      `startAccessingSecurityScopedResource()`.
- [ ] **Session resume.** The previous run's panel directories are restored
      (`PanelSessionStore`, from `230f1db`). Note this requires a real quit —
      killing the process skips it by design.
- [ ] **File operations write successfully** into a granted directory, exercising
      `files.user-selected.read-write` rather than just read access.

If any item fails, compare against the same flow in the Tuist build before
concluding the Bazel bundle is at fault — several of these depend on container
state rather than on entitlements.
