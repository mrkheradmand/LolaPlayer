# Lola Player

A video and audio player for Mac. Save and name your favorite moments with bookmarks, find them across your files, and jump straight back to them. Keep the player on top while a video plays; it returns to normal when paused.

A Player with **named bookmarks at any video timestamp** and **Float on Top that follows playback**. 

> **Save a moment. Name it. Find it again.** Bookmark the selected time in any playable video and give the bookmark a meaningful name. Lola keeps bookmarks from all your videos in a separate, searchable **Bookmarks** list—even after you open another file or restart the app. Search by bookmark name or filename, then click a bookmark to reopen the video and start playback at the exact saved time.

**[Download Lola Player for Mac](https://github.com/mrkheradmand/LolaPlayer/releases/latest)** · Apple Silicon · macOS 27 or later

![Lola Player welcome screen](app.jpg)

## Install

1. Download the latest **.dmg** from the link above.
2. Open it and drag **Lola Player** to **Applications**.
3. Eject the disk image and open Lola Player from Applications.

The app isn't notarized, so macOS may block the first launch. Go to **System Settings → Privacy & Security → Open Anyway**, or run this command in Terminal after moving the app to Applications:

```sh
xattr -dr com.apple.quarantine "/Applications/Lola Player.app"
```

Installation instructions are also included in **Install Notes.txt** inside the disk image. No extra playback software is needed.

## Features

- Named, searchable bookmarks that stay saved when you close the app.
- Float on Top during playback, full screen, and adjustable window sizes.
- Playlists, playback history, shuffle, repeat, and A–B looping.
- Playback speed from **0.25× to 4×**, frame stepping, and chapter navigation.
- Audio and subtitle selection, external subtitles, and timing adjustments.
- Mac media keys and Now Playing controls.

## Supported file types

| Type | Formats |
| --- | --- |
| Video | MP4, MKV, MOV, AVI, WebM, M4V, WMV, FLV, MPEG/MPG, TS, 3GP/3G2, F4V, ASF, DIVX, M2TS/MTS/M2T, VOB/EVO, MXF, DV, Y4M, IVF, RM/RMVB, OGV/OGM, WTV, DAV, BIK/SMK |
| Audio | MP3, M4A, FLAC, WAV, OGG, Opus, AAC, MKA, OGA, WEBA, AIF/AIFF/AIFC, CAF, AU/SND, APE, WV, MPC, TTA, TAK, SHN, AMR, SPX, WMA, AC3/EAC3, DTS/DTSHD, THD/MLP, DSF/DFF, RA |
| MIDI | MID, MIDI (requires the Mac's built-in MIDI instrument) |
| Playlists | M3U, M3U8 |
| Subtitles | SRT, ASS, SSA, VTT, SUB (some SUB files need companion files) |
| Online media | Direct media links and compatible HTTP/HTTPS, RTSP, and RTMP streams |

Playback depends on the codecs used inside each file; not every variation has been tested. Live streams may not support seeking. Protected streaming services and video webpage links such as YouTube aren't supported.

Unencrypted Blu-ray folders and ISO images have limited support, without disc menus. DVD folders/images aren't supported by the current playback engine, but individual VOB files can play. Flash/SWF and tracker music files aren't supported.

## Quick controls

Open a file with **⌘O** or drag it onto the player. You can also open folders and playlists.

| Action | Shortcut |
| --- | --- |
| Play / pause | Space |
| Bookmark the current moment | ⌘B |
| Browse all bookmarks | ⇧⌘B |
| Toggle Float on Top | ⌥⌘T |

Use the **Bookmarks** tab to name, search, and replay saved moments. The **Playlist** and **History** tabs help you return to your media.

## Version

| App | Release |
| --- | --- |
| Version | 1.2.4, build 12 |

See [release notes](versions.md) for what's changed.
See [Technical README](README-technical.md) for advanced users.