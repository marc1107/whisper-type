# WhisperType

Local speech-to-text dictation for macOS — fully offline, powered by whisper.cpp.

> **Deutsche Version:** Siehe [README.de.md](README.de.md)

## Features

- **100% Local** — No data leaves your Mac. No internet needed after model download.
- **German & English** — Automatic language detection, mixed-language support (e.g. German sentences with English technical terms)
- **Global Hotkey** — Works in any app. Configurable keyboard shortcut.
- **Filler Word Filter** — Automatically removes "um", "uh", "like", "you know", etc.
- **Native macOS App** — Menubar app, no dock icon, minimal resource usage

## System Requirements

- macOS 14 (Sonoma) or later
- Apple Silicon (M1/M2/M3) recommended — Intel is supported but slower
- At least 8 GB RAM (16 GB recommended for large-v3-turbo model)
- ~3 GB free disk space for the Whisper model

## Installation

### DMG Download (recommended)

1. Download the latest version from the [Releases page](../../releases/latest)
2. Open the `.dmg` file
3. Drag WhisperType to your Applications folder
4. Launch WhisperType — the Whisper model will be downloaded on first launch (~1.5 GB)

### Homebrew

```bash
brew tap marc1107/tap
brew install --cask whisper-type
```

### Build from Source

1. Install Xcode 15+ and Homebrew
2. Clone the repository:
   ```bash
   git clone --recursive https://github.com/marc1107/whisper-type.git
   cd whisper-type
   ```
3. Build:
   ```bash
   brew install cmake xcodegen
   make build
   ```
4. Run the app:
   ```bash
   open build/Release/WhisperType.app
   ```

### Setting Up Permissions

After first launch, WhisperType needs to be granted permissions in System Settings:
1. **Microphone:** Automatically prompted
2. **Accessibility:** System Settings > Privacy & Security > Accessibility > Enable WhisperType

## Usage

1. WhisperType appears as a microphone icon in the menubar
2. Click into any text field (browser, editor, chat, IDE...)
3. Press the hotkey (default: Fn+Control)
4. Speak your text
5. Release (Push-to-Talk) or press again (Toggle mode)
6. The transcribed text is automatically inserted

## Settings

Via the menubar icon > Settings:
- Change hotkey
- Push-to-Talk or Toggle mode
- Switch Whisper model
- Set language or use automatic detection
- Configure filler word filter
- Change app language (English/German)

## Supported Whisper Models

| Model | Size | RAM Required | Speed | Quality |
|-------|------|-------------|-------|---------|
| tiny | 75 MB | ~1 GB | Very fast | Basic |
| base | 142 MB | ~1 GB | Fast | Good |
| small | 466 MB | ~2 GB | Medium | Very good |
| medium | 1.5 GB | ~5 GB | Slower | Excellent |
| large-v3-turbo | 1.5 GB | ~5 GB | Medium | Excellent |

**Recommendation for M1 16GB:** `large-v3-turbo` — best balance of quality and speed.

## License

MIT License
