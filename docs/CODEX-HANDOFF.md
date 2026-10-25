# Lola Player handoff

Use this file to start a fresh task-focused conversation; read `AGENTS.md` and the relevant file-map row. Read authoritative current version/build from `Resources/Info.plist` and newest `versions.md`, rather than relying on old chat messages.

- Native macOS player: SwiftUI/AppKit with bundled libmpv/FFmpeg. Runtime source normally lives in `Runtime/Frameworks/`.
- Deliverable: `dist/Lola Player.app`. Signing is ad hoc; no notarization claim.
- Preserve existing user changes. The worktree includes earlier uncommitted app work; do not reset or discard it.
- Keep the simple and technical README audiences distinct. Bump once per completed change set using `scripts/version.py`.
- No automatic screenshots. Current copyright holder: J Kheradmand; use the current year.
- Selected artwork: flat mint play symbol and three bars on charcoal. One-second click-feedback fade; shorter with Reduce Motion.
- Finder Quick Look recovered after restarting QuickLookUIService while Lola was fully quit; the original cause is unconfirmed. Do not assume Lola caused a later system preview failure.
- Choose focused checks via `scripts/check.sh`; package once after implementation. Runtime caching retains final signature verification.

Next objective: <state the requested change and acceptance criteria here>.
