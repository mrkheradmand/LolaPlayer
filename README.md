# Lola Player

A video and audio player for Mac. Save and name your favorite moments with bookmarks, find them across your files, and jump straight back to them. Keep the player on top while a video plays; it returns to normal when paused.

A Player with **named bookmarks at any video timestamp** and **Float on Top that follows playback**. 

> **Save a moment. Name it. Find it again.** Bookmark the selected time in any playable video and give the bookmark a meaningful name. Lola keeps bookmarks from all your videos in a separate, searchable **Bookmarks** list—even after you open another file or restart the app. Search by bookmark name or filename, then click a bookmark to reopen the video and start playback at the exact saved time.

**[Download Lola Player for Mac](https://github.com/mrkheradmand/LolaPlayer/releases/latest)** · Apple Silicon · macOS 27 or later

<p align="center">
  <img src="app.png" alt="Lola Player welcome screen" width="950">
</p>

## Install

1. Download the latest **.dmg** from the link above.
2. Open it and drag **Lola Player** to **Applications**.
3. Eject the disk image and open Lola Player from Applications.

The app isn't notarized, so macOS may block the first launch. Go to **System Settings → Privacy & Security → Open Anyway**, or run this command in Terminal after moving the app to Applications:

```sh
xattr -dr com.apple.quarantine "/Applications/Lola Player.app"
```

Installation instructions are also included in **Install Notes.txt** inside the disk image. No extra playback software is needed.

<p align="center">
  <img src="app-bookmark.png" alt="Lola Player bookmark list" width="950">
</p>

## Features

- Named, searchable bookmarks that stay saved when you close the app.
- Float on Top during playback, full screen, and adjustable window sizes.
- Media-only view with a progress bar (**2**); restore the full interface with **1**.
- Drag the player to move its window; click once to play/pause and twice for full screen.
- Hover over the progress bar to see the time and a thumbnail for local video files.
- Playlists, playback history, shuffle, repeat, and A–B looping. With **Repeat Off**, playback stops at the end of the current file, even if Shuffle is on.
- Playback speed from **0.25× to 4×**, frame stepping, and chapter navigation.
- Audio and subtitle selection, external subtitles, and timing adjustments.
- Mac media keys and Now Playing controls.
- Notifications when a new GitHub release is available.

## Supported file types

| Type | Formats |
| --- | --- |
| Video | MP4, MKV, MOV, AVI, WebM, M4V, WMV, FLV, MPEG/MPG, TS, 3GP/3G2, F4V, ASF, DIVX, M2TS/MTS/M2T, VOB/EVO, MXF, DV, Y4M, IVF, RM/RMVB, OGV/OGM, WTV, DAV, BIK/SMK, VVC/H266 |
| Audio | MP3, M4A, FLAC, WAV, OGG, Opus, AAC, MKA, OGA, WEBA, AIF/AIFF/AIFC, CAF, AU/SND, APE, WV, MPC, TTA, TAK, SHN, AMR, SPX, WMA, AC3/EAC3, DTS/DTSHD, THD/MLP, DSF/DFF, RA |
| MIDI | MID, MIDI (requires the Mac's built-in MIDI instrument) |
| Playlists | M3U, M3U8 |
| Subtitles | SRT, ASS, SSA, VTT, SUB (some SUB files need companion files) |
| Online media | Direct media links and compatible HTTP/HTTPS, RTSP, and RTMP streams |

Playback depends on the codecs used inside each file; not every variation has been tested. Live streams may not support seeking. Protected streaming services and video webpage links such as YouTube aren't supported.

Unencrypted Blu-ray folders and ISO images have limited support, without disc menus. DVD folders/images aren't supported by the current playback engine, but individual VOB files can play. Flash/SWF and tracker music files aren't supported.

## Quick controls

Open a file with **⌘O** or drag it onto the player. You can also open folders and playlists.

Click and hold on the media, then move the mouse to drag the window. A click without dragging plays or pauses. Hovering over the progress bar previews a moment without seeking; click or drag the bar to seek.

| Action | Shortcut |
| --- | --- |
| Show full interface | 1 |
| Media only with progress bar | 2 |
| Play / pause | Space |
| Bookmark the current moment | ⌘B |
| Browse all bookmarks | ⇧⌘B |
| Toggle Float on Top | ⌥⌘T |

Press **1** or **2** while the player is active and you aren’t typing in a text box.

Use the **Bookmarks** tab to name, search, and replay saved moments. The **Playlist** and **History** tabs help you return to your media.

## Updates

Lola checks for new releases when it opens and once a day while running. When an update is available, click **View Release** in the notice to open the download page.

To turn automatic checks off, uncheck **Automatically check for updates** in **Lola Player → Settings…**. You can still choose **Lola Player → Check for Updates…** at any time. Updates are downloaded and installed manually.

## Version

| App | Release |
| --- | --- |
| Version | 1.5.0, build 21 |


See [release notes](versions.md) for what's changed.
See [Technical README](README-technical.md) for advanced users.