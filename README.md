# CoverCheck

Native **macOS app** with a built-in SwiftUI GUI that scans a folder of music files and verifies album artwork.

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
| OK / Unverified | Art looks consistent, or no reference was found |

Online reference covers are fetched from the **iTunes Search API**, with **Cover Art Archive** as a fallback. No API keys are required.

## GUI

The app is a full desktop UI (not a CLI):

1. **Welcome screen** — choose a music folder and start a scan  
2. **Progress banner** — live tag-reading and verification progress, with cancel  
3. **Results workspace** — searchable album list, status filters, issue counts  
4. **Album detail** — side-by-side Embedded / Folder / Reference artwork, findings, and per-track art status  
5. **Settings** — online lookup, folder comparison, similarity threshold, minimum resolution  

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

`mp3`, `m4a`, `aac`, `alac`, `flac`, `aiff`/`aif`, `wav`, `caf`, `ogg`, `wma`

Artwork is read through AVFoundation metadata. Folder images recognized include `cover.jpg`, `folder.jpg`, `album.png`, `front.jpg`, and `Artwork.jpg` (plus common variants).

## Project layout

```
CoverCheck/
├── CoverCheck.xcodeproj
└── CoverCheck/
    ├── CoverCheckApp.swift          # App entry + menus
    ├── Theme.swift                  # Visual system + artwork views
    ├── Models/
    ├── Services/                    # Scan, extract, hash, lookup, verify
    ├── Views/                       # Welcome, results, detail, settings
    ├── Assets.xcassets
    └── CoverCheck.entitlements      # Sandbox + user-selected files + network
```

## Privacy & sandbox

CoverCheck is sandboxed. It only reads folders you select in the open panel, and uses outbound network access solely for optional reference-cover lookups.
