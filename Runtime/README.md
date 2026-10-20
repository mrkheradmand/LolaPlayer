# Playback runtime source

Use `python3 scripts/import-runtime.py '/path/to/IINA.app'` to stage a compatible newer libmpv runtime here. An official IINA 1.5.0 disk image can also be imported; its checksum is verified before mounting. The installed IINA app is not modified. Only open-source playback libraries are used; IINA's UI, code, assets and updater are not included.

`Frameworks/` contains local packaging inputs and is ignored by Git. The final app embeds its dependency closure and runs without this directory or IINA installed. Build-time probing writes actual versions/capabilities into the app's `RuntimeCapabilities.json`; a newer FFmpeg must accompany a compatible libmpv, rather than replacing FFmpeg dylibs in an older runtime.

Tracker modules are intentionally excluded at the user’s request. MIDI uses the macOS General MIDI synthesizer. The current staged runtime comes from the official IINA 1.5.0 package: mpv 0.41.0 / FFmpeg 9.0.1.
