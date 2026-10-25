# Contributing to Lola Player

Thanks for helping improve Lola Player.

## Before starting

- For substantial features or behavior changes, open an issue first.
- Keep changes focused and preserve unrelated work.
- Read `AGENTS.md` and the relevant sections of
  `docs/CODEX-WORKFLOW.md`.
- Never include personal media, bookmarks, library databases,
  credentials, or private file paths in contributions.

## Development setup

Lola Player is a native macOS app built with Swift, SwiftUI,
AppKit, and libmpv.

Use a compatible macOS and Swift toolchain. See
`README-technical.md` for current requirements and playback-runtime
setup.

Build the signed local app from the repository root:

    zsh scripts/build-app.sh

The resulting app is:

    dist/Lola Player.app

## Verification

Run checks appropriate to the change:

    zsh scripts/check.sh metadata
    zsh scripts/check.sh core --filter SuiteName
    zsh scripts/check.sh ui

For changes to Python helpers:

    python3 -m unittest discover -s Tests -p 'test_*.py'

For playback, keyboard, window, or interaction changes, also run
relevant native checks documented in `README-technical.md`.

Save verbose logs under `.build/`. Report failures and skipped
checks honestly. Do not capture or replace app screenshots unless
requested.

## Versioning and change notes

Check the last committed version before changing version metadata.

- Create one new version/build for the next uncommitted change set.
- If an uncommitted version already exists, retain it and update
  its notes with all accumulated changes.
- Do not create another version for each edit, prompt, or rebuild.
- Use a minor bump for features and a patch bump for fixes.
- Use `scripts/version.py` when creating the new version.
- Keep `Resources/Info.plist`, both README version rows, and the
  newest `versions.md` entry synchronized.
- Include Added, Modified, and Removed sections; use “None” for
  empty categories.
- Preserve committed historical entries unless explicitly directed
  otherwise.

Validate consistency with:

    python3 scripts/version.py check

## Documentation

Update documentation when behavior changes:

- `README.md`: short, nontechnical installation and usage guide.
- `README-technical.md`: detailed behavior, settings, shortcuts,
  development, and troubleshooting.

Preserve their different audiences and structure.

## Pull requests

Explain:

- The problem being solved.
- The resulting behavior.
- Relevant verification and any skipped checks.
- Material limitations or compatibility changes.

Add meaningful regression coverage for behavior changes. Avoid
unrelated refactoring and generated artifacts unless required by
the repository’s packaging workflow.

## Releases

Release preparation and publication are maintainer responsibilities.
Do not publish releases, push version tags, or build distribution
DMGs as part of an ordinary contribution.

Follow the “Prepare release” workflow in
`docs/CODEX-WORKFLOW.md` when explicitly preparing a release.
Release notes must cover every change since the previous published
release.

## License

Contributions are provided under this repository’s MIT License.
Preserve third-party licenses and copyright notices.