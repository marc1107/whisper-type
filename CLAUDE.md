# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

WhisperType is a macOS menu bar app that provides system-wide speech-to-text dictation using a local on-device Whisper model (whisper.cpp), with no cloud API calls.

## Tech Stack

- **Language**: Swift 5.9, C++ (whisper.cpp submodule)
- **UI**: SwiftUI + AppKit interop (`NSWindow`, `NSHostingView`, `NSApplicationDelegateAdaptor`)
- **Audio**: AVFoundation — records and resamples to 16 kHz mono Float32
- **Speech engine**: whisper.cpp (git submodule), bridged via `WhisperType/BridgingHeader.h`
- **Project generation**: XcodeGen (`project.yml`) — `.xcodeproj` is generated, not committed
- **Build system**: CMake for whisper.cpp (Metal GPU backend), Xcode for the Swift app
- **Deployment target**: macOS 14.0

## Commands

Prerequisites: Xcode 15+, `brew install xcodegen swiftlint`

- **Setup** (first time or after submodule changes): `make xcode` — builds whisper.cpp with CMake and regenerates the `.xcodeproj`
- **Build**: `make build`
- **Test**: `make test`
- **Clean**: `make clean`
- **Run**: `make run`

Single test class: `xcodebuild -project WhisperType.xcodeproj -scheme WhisperTypeTests -destination 'platform=macOS' test`

The CI workflows (`.github/workflows/`) require `submodules: recursive` on checkout and CMake build before XcodeGen/xcodebuild steps.

## Architecture

`AppState` (`WhisperType/App/AppState.swift`) is the sole `@MainActor ObservableObject` coordinator. All services are owned and wired here; services have no awareness of each other.

**Hotkey → transcription flow:**
1. `HotkeyManager` (CGEvent tap) fires `onHotkeyDown`/`onHotkeyUp` callbacks
2. `AppState` starts/stops `AudioRecorder` based on `hotkeyMode`
3. On stop: `AudioRecorder.stopRecording()` → `WhisperEngine.transcribe()` (detached Task) → `TextPostProcessor.process()` → `TextInjector.inject()`
4. `status` enum transitions update the `OverlayWindowController` (floating HUD) and menu bar icon via Combine

**Key types:**
- `AppSettings.shared` — `@AppStorage`-backed singleton; all layers read directly from it
- `WhisperEngine` — loads/runs GGML model files via whisper.cpp C bridge
- `ModelManager` — downloads/deletes GGML model files from HuggingFace
- `TextInjector` — two strategies: clipboard paste (Cmd+V simulation) or character-by-character CGEvent keyboard simulation
- `TextPostProcessor` — regex-based filler word removal and capitalization

## Conventions

- `final class` for all service types — no inheritance
- `@MainActor` isolation on state-holding types; `Task.detached` for off-main transcription work
- `NSLock` for thread safety on `WhisperEngine` and `AudioRecorder`
- Prefer `NSLocalizedString("key", comment: "")` for user-facing UI and error strings. Localizations in `Resources/en.lproj/` and `Resources/de.lproj/`. Some existing labels (e.g. certain language/model names in settings metadata) are still hardcoded and should be localized when touched.
- Errors are typed enums conforming to `LocalizedError` with `errorDescription` using `NSLocalizedString`
- No third-party Swift dependencies — only Apple frameworks and whisper.cpp

## Testing

- **Framework**: XCTest, target `WhisperTypeTests`
- Currently only `TextPostProcessorTests.swift` exists — tests the pure-logic post-processing layer
- No mocks, no UI tests, no snapshot tests

## Linting

- **SwiftLint** runs automatically after every `.swift` file edit via PostToolUse hook (configured in `.claude/settings.json`)
- Config: `.swiftlint.yml` — excludes `whisper.cpp`, `build`, `DerivedData`, `WhisperType.xcodeproj`
- Run manually: `swiftlint lint` (project-wide) or `swiftlint lint --path <file>` (single file)

## Development Workflow

Use `/develop-feature` to start working on any feature or bugfix. This skill orchestrates specialized subagents defined in `.claude/agents/`:

| Agent | Model | Color | When to dispatch |
|-------|-------|-------|-----------------|
| swift-engineer | Sonnet | blue | Core Swift changes (services, models, audio, transcription, whisper.cpp bridge) |
| ui-engineer | Sonnet | magenta | SwiftUI/AppKit UI changes |
| test-engineer | Sonnet | green | Writing/updating XCTests (always after implementation) |
| app-tester | Sonnet | yellow | Testing the running .app via native macOS Computer Use |
| code-reviewer | Sonnet | cyan | Code quality review (always before commit) |
| security-scanner | Sonnet | red | Security + whisper.cpp dependency checks (always) |
| i18n-checker | Haiku | magenta | Localization verification (when strings affected) |

**Workflow:** Analyse → Branch → Implement → Test → Verify (parallel) → Auto-commit if all pass.

The security-scanner reports available whisper.cpp updates but does NOT auto-update. Dependency updates are handled as separate issues.
