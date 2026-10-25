# Project instructions

## Documentation and versions

- Maintain both READMEs when affected: `README.md` is a short nontechnical guide (general info, installation, file types, essential usage, security-alert command); `README-technical.md` is the full power-user guide. Preserve their approved audiences and structure.
- For each completed app change set, use `scripts/version.py` to increment version/build once, synchronize both READMEs and bundle/About metadata, and prepend `versions.md`. List Added, Modified, Removed; use “None” for empty categories. Preserve prior entries. Minor bump for features; patch for fixes/small edits. Report the version in the final response.
- Release notes and release commit messages must list all changes since the previous published release, across every intervening commit and unreleased version. Review that complete range; do not summarize only the previous commit or refer readers to an unpublished version for details.
- Update current app/documentation copyright notices to the current year and J Kheradmand, including About fallback, bundle metadata, LICENSE, and READMEs. Preserve historical release entries and third-party notices.

## Screenshots and distribution

- Never capture or save app screenshots unless explicitly requested. Preserve existing screenshots.
- Use `scripts/build-dmg.sh` for DMGs named `LolaPlayer-<release version>-macOS-arm64.dmg`, using packaged metadata and matching checksum names. After successful creation/verification, move older DMGs to `dist/releases/old/` without overwriting archives. Do not build a DMG unless the task requires it.

## Efficient development

- Read only relevant files/sections; locate code with `rg`. Load only applicable skills. File/command map: `docs/CODEX-WORKFLOW.md` (read the relevant section only).
- Batch related edits; update version/docs and package once per completed set. Deliver the requested finished app; do not defer its build.
- When the user says “no test”, interpret it as focused verification only: test the behavior changed by the current prompt and skip tests for unrelated, unchanged parts of the app. Do not run a broad suite or full-app smoke test for that prompt.
- Use the smallest meaningful check: `scripts/check.sh metadata`, `core --filter Suite`, or `ui`. Add relevant native checks for interactions/playback. Expand testing for failures, shared behavior, or unresolved risks; use full checks for release preparation. Do not repeat passing checks without a reason.
- Batch independent inspections. Save verbose logs under `.build/`; return summaries or relevant failure excerpts. Wait 20–30 seconds between build-status checks; keep progress updates within 60 seconds.
- Prefer low reasoning and Standard speed for routine work; increase reasoning when complexity warrants it. Preserve necessary tests and safety checks.
- At feature boundaries suggest a fresh conversation using `docs/CODEX-HANDOFF.md`; keep transcripts/progress logs out of instructions. Ask only for missing information that changes the outcome.
- For artwork exploration, default to a comparison sheet or a few concepts unless the user requests a number. Separate concept selection from implementation when practical.

## Prepare release

When the user asks to “prepare release”, follow the ordered workflow in `docs/CODEX-WORKFLOW.md` under “Prepare release”. This request authorizes the distribution, commit, tag, and publish steps after successful verification. Preserve unrelated user changes and do not publish with unresolved failures.
