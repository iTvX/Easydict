# Easydict (Fork with Google Voice Enhancements)

This repository is a maintained fork of [Easydict](https://github.com/tisfeng/Easydict), focused on practical improvements for Google TTS voice control while keeping the original macOS dictionary and translation workflow.

## Fork Notice

- Base project: [tisfeng/Easydict](https://github.com/tisfeng/Easydict)
- This fork keeps upstream core capabilities:
  - Dictionary lookup
  - Multi-service translation
  - OCR screenshot translation
  - Input/select/screenshot translation workflows
- This fork adds and maintains Google Voice related enhancements for daily use.

## What This Fork Adds

### 1. Google TTS Mode in Advanced Settings

Google TTS configuration is moved to **Settings -> Advanced** with clear mode selection:

- `Google Web TTS (Default)`
- `Google Cloud TTS (API Key)`

### 2. Direct Cloud Voice Configuration

When `Google Cloud TTS (API Key)` is selected, you can configure:

- Google Cloud API key
- Custom Google Cloud voice name (for example, `en-US-Chirp3-HD-Charon`)

### 3. Better Voice Matching for Real-World Language Codes

This fork includes a fix for voice matching behavior:

- Generic language codes (for example, `en`) can correctly use regional voices (for example, `en-US-Chirp3-HD-*`).
- Request `voice.languageCode` is aligned with selected voice prefix when needed.
- This avoids silent fallback to default web voice and makes voice changes actually audible.

### 4. Lower Idle CPU Usage for Auto-Select Monitoring

This fork also includes event-monitor performance optimizations for mouse selection workflows:

- High-frequency pointer events (`mouseMoved`, `scrollWheel`) now use a lightweight hot path.
- Pointer monitors are enabled only when needed (for example, when the pop button is visible).
- Duplicate focus checks in the selection workflow are removed.
- Pop button behavior and trigger logic remain unchanged.

## Quick Start

1. Download the latest release from the [Releases](https://github.com/iTvX/Easydict/releases) page.
2. Move `Easydict.app` to `/Applications`.
3. Launch the app and grant required permissions.

If macOS shows a verification warning such as "Move to Trash", clear quarantine:

```bash
xattr -dr com.apple.quarantine /Applications/Easydict.app
```

## Configure Google Cloud Voice

Go to **Settings -> Advanced**:

1. Set **Default TTS Service** to `Google`.
2. Set **Google TTS Mode** to `Google Cloud TTS (API Key)`.
3. Enter your Google Cloud TTS API key.
4. Enter a voice name, for example:
   - `en-US-Chirp3-HD-Charon`
   - `en-US-Chirp3-HD-Orus`
   - `en-US-Chirp3-HD-Fenrir`
5. Test with a full sentence for clearer voice difference.

## Notes About Permissions

Easydict relies on macOS Accessibility permission for some select-text workflows.

If permission prompts repeat:

1. Open `System Settings -> Privacy & Security -> Accessibility`
2. Remove old Easydict entries
3. Add `/Applications/Easydict.app` again
4. Re-enable permission and relaunch app

## Upstream and Contribution

- Upstream sync and targeted fork improvements are both welcome.
- For issues or enhancement requests specific to this fork, please open an issue in this repository.
- For broader upstream discussions, please also consider upstream issue threads.

## License

This project remains under [GPL-3.0](https://github.com/iTvX/Easydict/blob/main/LICENSE), following upstream licensing requirements.

Please keep license and attribution information when redistributing or modifying the code.
