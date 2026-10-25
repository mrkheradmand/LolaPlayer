# Focused development for Lola Player

## File map

| Work | Start here |
| --- | --- |
| Menus, keyboard focus, window sizing | `Sources/PlayerApp/Application.swift` |
| Playback state, repeat, preferences | `Sources/PlayerApp/PlayerModel.swift`, `Sources/PlayerCore/PlaybackOrder.swift` |
| Player UI, timeline controls | `Sources/PlayerApp/PlayerView.swift` |
| Mouse clicks, drag, wheel volume | `Sources/PlayerApp/PlayerMouseView.swift` |
| Click play/pause icon | `Sources/PlayerApp/PlaybackClickFeedback.swift` |
| Timeline thumbnails | `Sources/PlayerApp/TimelinePreview.swift` |
| Detached Library | `Sources/PlayerApp/LibraryView.swift`, `LibraryWindow.swift` |
| Settings / About / updates | `SettingsView.swift`, `AboutWindow.swift`, `PlayerModel+Updates.swift` in `Sources/PlayerApp/` |
| Core tests / native app regression | `Tests/PlayerCoreTests/`, `Sources/PlayerApp/SmokeTest.swift` |
| Version and bundle metadata | `scripts/version.py`, `Resources/Info.plist`, `versions.md` |
| Icon master / packaging | `Resources/LolaPlayerIcon.png`, `scripts/build-app.sh`, `scripts/bundle-runtime.py` |

## Select verification

When the user says “no test”, interpret it as focused verification only: test the behavior changed by the current prompt and skip tests for unrelated, unchanged parts of the app. Do not run a broad suite or full-app smoke test for that prompt.

Run from the repository root. Redirect long output to `.build/<task>.log`; inspect its result and only the useful failure excerpt. Create `.build` if absent.

- Documentation or metadata: `zsh scripts/check.sh metadata`.
- Core behavior: `zsh scripts/check.sh core --filter PlaybackOrderTests` (replace the suite as appropriate). Without a filter this runs all Swift tests.
- Swift UI compilation: `zsh scripts/check.sh ui`. Add relevant native smoke checks for focus, gestures, window, or playback changes; compilation alone cannot establish interactive correctness.
- Python packaging/version helpers: `python3 -m unittest discover -s Tests -p 'test_*.py'`.
- Finished local app: after affected checks, `zsh scripts/build-app.sh` once.
- Release preparation: `zsh scripts/check.sh release` runs existing CI checks and packages once. Release format/native checks remain applicable when playback or UI changes require them.

Do not repeat a successful broad suite unless new edits, failures, or unresolved concerns justify it. Preserve user changes and existing screenshots. Do not generate a DMG unless requested or required by the release task.

## Runtime cache

The bundler hashes the full resolved source-library closure, bundler/cache/probe code, OS and compiler identity, and selected developer directory. Successful cold builds cache rewritten, signed libraries and capability results under `.build/runtime-cache/`. Hits rehash every cached library before reuse; missing or damaged entries rebuild. Compatibility policy applies on both paths. The final app is still signed and strictly verified every time.

`LOLA_RUNTIME_CACHE=0 zsh scripts/build-app.sh` bypasses cache reads and writes for a fresh runtime inspection. Deleting `.build/` is safe while no builds are running; it removes caches, not source or `dist/`.

## Codex session setup

Project-local `.codex/config.toml` keeps Standard speed and low reasoning, caps tool-output/catalog context, disables REA for ordinary source work, and disables unrelated local skills without uninstalling them. Retain native computer-use access for UI investigation. Restart/reopen Codex for configuration changes to take effect; managed settings may override local preferences. Re-enable REA or a disabled skill if a later task needs it. Client-managed plugins may require the client's settings UI; local config cannot guarantee their removal from an already-running session.

## Batch prompt

“Implement these related changes. Keep scope focused, run relevant checks, update version/docs once, and package once at completion. Save verbose logs to files and report results and unresolved issues.”

For a new conversation, paste a short handoff and the next objective. The handoff is a starting point, not a transcript or permanent progress log.

## Prepare release

When the user asks to “prepare release”, complete these steps in order:

1. Run `zsh scripts/check.sh release`: Python and Swift tests, metadata/format checks, and a rebuilt signed app. Save verbose output under `.build/`.
2. Run the native app smoke test with the MP4/MKV fixtures and invocation documented in `README-technical.md`. Review results for playback, Settings layouts, shortcuts, Library, bookmarks, and window behavior; report skips separately.
3. Manually verify the changed behavior in the built app. For the Settings switch alignment change, open General, Playback, and Bookmarks; check consistent right-edge switch alignment, clean description wrapping, mouse and keyboard operation, and preference persistence after restarting. For later changes, adapt this manual check to the actual change. Do not capture screenshots unless explicitly requested.
4. Review intended release contents: uncommitted changes, both READMEs, release notes, bundle metadata, and About version. Identify the previous published release tag and review all changes from that tag through the intended release, including intervening commits, unreleased versions, and uncommitted work. Write the published release notes and release commit message to list that complete set of changes, not just the latest commit; spell out changes from unpublished versions instead of referring readers to them. Review the cumulative notes generated from all `versions.md` entries since the previous published stable release; preserve historical entries because the publishing scripts merge that range into Added, Modified, and Removed sections. Preserve historical entries and unrelated changes, and resolve release-blocking issues before proceeding.
5. Create the distribution using `scripts/build-dmg.sh`. Verify the checksum, mount the DMG, copy the app out to an isolated test location, and launch that copy. Use `LolaPlayer-<release version>-macOS-arm64.dmg` and matching checksum names. After successful creation/verification, archive older DMGs under `dist/releases/old/` without overwriting archives.
6. Commit the intended release changes, tag the matching version from packaged metadata, and push the commit and version tag to trigger the configured GitHub release workflow. Verify the workflow and published assets. The user's “prepare release” request authorizes these steps; do not publish with unresolved failures.

Do not bump the version solely for verification or rebuilding an unchanged change set. If fixes are needed, follow the normal change-set version policy and repeat affected checks before proceeding.
