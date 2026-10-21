# Lola Player versions

## 1.6.2 (build 24) — 2026-10-21

### Added

- None.

### Modified

- Media-only mode now fits the window to the video aspect ratio and progress strip, with previous size restored by 1. Added scrubbing previews and faster cached response through persistent decoders, progressive warmup, immediate cached fallback, and coalesced requests without hover debounce. Updated both README guides and regression checks.

### Removed

- None.

## 1.6.1 (build 23) — 2026-10-21

### Added

- MIT License for original Lola Player code and documentation, copyright 2026 J Kheradmand.

### Modified

- About displays Copyright © 2026 J Kheradmand and a MIT License link. App packaging includes the license, bundle metadata includes the copyright, and both README guides explain license scope.

### Removed

- None.

## 1.6.0 (build 22) — 2026-10-21

### Added

- Live update status beside the version/build in About: Latest Version or a clickable New version available! release link, plus a manual Check for Updates button.

### Modified

- Replaced the static About panel with an observable panel retaining the app icon and credits. Shared update-result state survives banner dismissal, distinguishes pending/failed/unchecked checks, and respects automatic-check preferences when About opens. Updated both README guides and added About status and app checks.

### Removed

- None.

## 1.5.0 (build 21) — 2026-10-21

### Added

- Drag the window from the media area while preserving single-click play/pause and double-click full screen. Progress-bar hover cards show timestamps and in-memory local-video thumbnails in normal and media-only views.

### Modified

- Added a separate silent thumbnail decoder, bounded memory cache, hover debounce, stale-request cancellation, and timestamp-only fallback for audio, network, MIDI, and disc inputs. Updated both README guides and added gesture, timeline-position, and real-media preview checks.

### Removed

- None.

## 1.4.1 (build 20) — 2026-10-21

### Added

- None.

### Modified

- Repeat Off now stops and pauses at the end of the current file, even with additional queued files and Shuffle enabled; manual navigation remains available and the other three repeat modes retain their behavior. Updated both README guides and added app regression checks for all four repeat modes.

### Removed

- None.

## 1.4.0 (build 19) — 2026-10-21

### Added

- GitHub release checks at launch and daily, with a persistent update notice and release-page link; saved checkbox to disable automatic checks and manual Check for Updates actions.

### Modified

- Update checks compare numeric stable versions, respect dismissed notices, handle timeouts and API errors, cancel when disabled, and avoid networking in smoke mode. Settings now scrolls to keep all options reachable on smaller screens. Updated both README guides and added release-response, request, preference, and notification checks.

### Removed

- None.

## 1.3.3 (build 18) — 2026-10-21

### Added

- None.

### Modified

- Audited both READMEs against current source and scripts; refreshed navigation, media-only feature summary, runtime/build/test instructions, Git tracking details, bookmark import limits, release tagging, and version-maintenance guidance.

### Removed

- Removed repository links to ignored local research files and outdated release-tag examples.

## 1.3.2 (build 17) — 2026-10-21

### Added

- None.

### Modified

- Added the missing 1/2 view shortcuts to the technical README shortcut table and clarified their activation and typing safeguards in both READMEs.

### Removed

- None.

## 1.3.1 (build 16) — 2026-10-21

### Added

- None.

### Modified

- Updated technical README validation results to distinguish the successful 1.3.0 checks from historical 1.1.0 format coverage, and corrected the outdated smoke-run limitation.

### Removed

- None.

## 1.3.0 (build 15) — 2026-10-21

### Added

- Media-only view: press 2 to remove the title bar, library, and bottom controls while retaining the seek bar; press 1 to restore the full interface and previous library visibility.

### Modified

- Added View and video context-menu actions and shortcut help; number shortcuts respect text editing, settings, and modal dialogs.

### Removed

- None.

## 1.2.6 (build 14) — 2026-10-21

### Added

- None.

### Modified

- Centered the existing images in both README files and updated the technical README image link to the current app.png asset.

### Removed

- None.

## 1.2.5 (build 13) — 2026-10-21

### Added

- None.

### Modified

- Library search now releases keyboard focus and its blue border when clicking outside the field, preserving the search text and normal click actions.

### Removed

- None.

## 1.2.4 (build 12) — 2026-10-21

### Added

- None.

### Modified

- Shortened the README for everyday users, keeping installation and macOS security-alert instructions, app features, supported file types, and essential controls.

### Removed

- Removed developer build, testing, release automation, and internal implementation details from the README.

## 1.2.3 (build 11) — 2026-10-20

### Added

- Regression coverage for drafts absent from tag lookup, later-page draft discovery, and visible API verification failures while preserving upload and checksum protections.

### Modified

- Fixed draft-release verification and publication to use the numeric release ID instead of the published-release-only tag endpoint.
- Draft retries search all release pages; release creation verifies the tag exists and preserves the returned ID. API failures now report their endpoint and GitHub error text.

### Removed

- None.

## 1.2.2 (build 10) — 2026-10-20

### Added

- Swift 6.4.x compiler guard and regression tests reject Swift 6.3.3 and other unvalidated compiler versions before CI compilation.

### Modified

- Pinned both GitHub workflows to the Apple Silicon xcode-27 runner and Xcode 27.0 instead of the macOS 26 default compiler that crashed in PlayerView.swift.
- Documented the supported build toolchain and the need for a new version tag when fixing workflow or source failures.

### Removed

- None.

## 1.2.1 (build 9) — 2026-10-20

### Added

- None.

### Modified

- README consistently states macOS 27 or later as the documented system requirement and removes stale macOS 14 guidance.

### Removed

- None.

## 1.2.0 (build 8) — 2026-10-20

### Added

- GitHub Actions checks on branch pushes and pull requests, plus automatic tested macOS arm64 DMG releases on matching version-tag pushes.
- Pinned, checksum-verified official playback runtime downloads for independent GitHub builds.
- Release tooling extracts version-specific notes, verifies local and uploaded asset digests, publishes only complete drafts, supports retrying failed drafts, and protects published releases from replacement.

### Modified

- Documented release tagging, Actions permissions, failure recovery, runtime updates and local archive behavior; disk-image imports share the runtime pin.

### Removed

- None.

## 1.1.4 (build 7) — 2026-10-20

### Added

- None.

### Modified

- DMG filenames include the app release version, macOS, and arm64; verified packaging archives older images with checksums under dist/releases/old without overwriting existing archives.
- README download links use the latest release page to support versioned asset filenames; saved the DMG naming and archiving rule in project instructions.

### Removed

- None.

## 1.1.3 (build 6) — 2026-10-20

### Added

- Install Notes.txt inside the DMG with installation and first-launch instructions.

### Modified

- README documents Open Anyway and the app-specific quarantine-removal command after copying Lola Player to Applications.

### Removed

- None.

## 1.1.2 (build 5) — 2026-10-20

### Added

- DMG distribution packaging with an Applications shortcut and SHA-256 checksum.

### Modified

- README includes a prominent latest-release DMG download link and installation steps.

### Removed

- None.

## 1.1.1 (build 4) — 2026-10-20

### Added

- None.

### Modified

- README highlights named timestamp bookmarks, the dedicated searchable bookmark list across videos, and playback from the exact saved time.

### Removed

- None.

## 1.1.0 (build 3) — 2026-10-20

### Added

- Expanded media extensions in Finder, folder import and folder repeat.
- Native MIDI synthesis with playback, pause, seek, volume, tempo, bookmarks, repeat and media controls.
- Local HLS manifest handling, DVD/Blu-ray folder detection, explicit disc-image type selection and numeric disc-title navigation. Disc bookmarks retain title identity, and disc records can be relocated to folders.
- Newest-first versions.md, version-bump/check tooling and a persistent rule to bump and report every completed app edit.

### Modified

- About version comes from bundle metadata; README and release notes are checked during packaging.
- Help → Playback Support reports actual engine versions and optional decoder availability; unavailable components produce clear errors.
- Upgraded playback from mpv 0.35 / FFmpeg 6.0 to mpv 0.41.0 / FFmpeg 9.0.1. Runtime import/probing and staged packaging prevent incompatible FFmpeg swaps and preserve the previous app on build failure. Libraries are packaged for arm64 only.
- Ordinary playlists handle whitespace, absolute paths, nested playlist loops and allowed URL schemes.

### Removed

- Planned tracker-module support/registrations (MOD, XM, IT, S3M, MTM, UMX) removed at the user’s request; no libopenmpt dependency is added.
- No encoding, conversion or transcoding features added.

### Validation and remaining work

- 22 core tests and 24 synthetic decoder/container/HLS checks passed. All 24 decoder checks were rerun successfully against the upgraded mpv 0.41.0 / FFmpeg 9.0.1 bundle. Version-sync regression checks pass.
- Upgraded the bundled engine to mpv 0.41.0 / FFmpeg 9.0.1 using the official IINA 1.5.0 package supplied locally. Registered VVC and ProRes RAW decoders are confirmed; newer AAC decoding is supplied by FFmpeg 9. Specific VVC/xHE-AAC/ProRes RAW files still need sample-level validation. Tracker modules remain intentionally excluded.
- All 15 real-app smoke checks passed on the new runtime, including MP4/MKV, bookmarks across files/relaunch, playback-aware floating, HLS, cycle rejection and native MIDI pause/resume/seek/bookmarks. The missing-MIDI-component error path was separately tested in the restricted shell environment. Physical listening and every instrument/program variant are not certified.
- Disc routing, numeric title selection and title-aware bookmark persistence are implemented and unit-tested. The new runtime includes Blu-ray reading but lacks a native DVD reader; individual VOB playback passes. Actual Blu-ray media/ISO navigation remains unverified. Interactive menus/decryption are not implemented.

## 1.0 (build 2) — Existing baseline

### Added

- Native player with persistent cross-file bookmarks, history, playlists, repeat, shuffle, playback-aware floating, macOS media commands, a nature welcome image, and the Lola Player icon.
- About text and clickable project link.

### Modified

- Bundle identifier changed to `local.lolaplayer.app`, with migration from the previous preference domain.

### Removed

- Extra right-side title-bar buttons. Standard macOS window controls remain.

Earlier edits did not have individual version records; this is the recorded baseline, not a reconstructed release timeline.
