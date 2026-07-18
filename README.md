# CoverCheck

Native **macOS app** with a built-in SwiftUI GUI that scans a folder of music files, verifies album artwork, lets you **update covers**, and remember albums you’ve marked as correct.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-orange)

## What it does

CoverCheck walks a music directory, reads tags and embedded art from each track, groups files into albums, then checks whether the artwork looks correct:

| Check | Result |
| --- | --- |
| Missing art | Tracks have no embedded cover |
| Inconsistent art | Tracks in the same album use different images |
| Folder mismatch | Embedded art differs from `cover.jpg` / `folder.jpg` |
| Likely wrong | Embedded art does not match an online reference cover |
| Approved | You marked this cover as correct |
| OK / Unverified | Art looks consistent, or no reference was found |

Online reference covers are fetched from the **iTunes Search API**, with **Cover Art Archive** as a fallback. No API keys are required.

## Update covers

From an album’s detail view you can:

- **Apply** the folder cover or online reference cover to every track
- **Choose Image…** and embed a custom image
- Automatically refresh `cover.jpg` in the album folder

Embedding is supported for **MP3** (ID3v2 APIC) and **M4A/MP4** (AVFoundation). Other formats still get an updated folder cover.

## Mark as correct

If CoverCheck flags an album but you know the art is right:

1. Open the album
2. Click **Mark as Correct**

That approval is saved (tied to the album + current artwork hash) and future scans show the album as **Approved** instead of an issue. If the embedded art changes later, the approval no longer applies. Use **Clear Approval** or Settings → **Clear All Approvals** to reset.

## GUI

1. **Welcome screen** — choose a music folder and start a scan  
2. **Progress banner** — live tag-reading, verification, and apply progress  
3. **Results workspace** — searchable album list and status filters  
4. **Album detail** — Embedded / Folder / Reference artwork, apply actions, Mark as Correct, findings, per-track status  
5. **Settings** — verification options and approval reset  

Keyboard shortcuts:

- `⌘O` — Choose music folder  
- `⌘R` — Start scan  
- `⌘.` — Cancel scan  

## Requirements

- macOS 14 Sonoma or later  
- Xcode 15 or later  

## Open & run

```bash
open CoverCheck/CoverCheck.xcodeproj
```

In Xcode:

1. Select the **CoverCheck** scheme  
2. Choose **My Mac** as the run destination  
3. Press **Run** (`⌘R`)  

On first launch, use **Choose Music Folder**, then **Start Scan**.

## Supported audio formats

Scan/read: `mp3`, `m4a`, `aac`, `alac`, `flac`, `aiff`/`aif`, `wav`, `caf`, `ogg`, `wma`

Embed artwork: `mp3`, `m4a`, `mp4`, `aac`, `alac` (folder `cover.jpg` is written for all albums when applying)

## Project layout

```
CoverCheck/
├── CoverCheck.xcodeproj
└── CoverCheck/
    ├── CoverCheckApp.swift
    ├── Theme.swift
    ├── Models/
    ├── Services/     # Scan, extract, hash, lookup, verify, write, approvals
    ├── Views/
    ├── Assets.xcassets
    └── CoverCheck.entitlements
```

## Privacy & sandbox

CoverCheck is sandboxed. It reads and writes only within folders you select, and uses outbound network access solely for optional reference-cover lookups. Approvals are stored locally in UserDefaults.
