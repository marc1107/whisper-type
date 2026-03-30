# WhisperType

Lokale Sprache-zu-Text Diktierfunktion für macOS – komplett offline, powered by whisper.cpp.

## Features

- **100% Lokal** – Keine Daten verlassen deinen Mac. Kein Internet nötig nach dem Modell-Download.
- **Deutsch & Englisch** – Automatische Spracherkennung, Mischsprachen-Support (z.B. deutsche Sätze mit englischen Fachbegriffen)
- **Globaler Hotkey** – Funktioniert in jeder App. Einstellbare Tastenkombination.
- **Füllwort-Filter** – Entfernt automatisch "ähm", "also", "uhm" etc.
- **Native macOS App** – Menübar-App, kein Dock-Icon, minimaler Ressourcenverbrauch

## Systemanforderungen

- macOS 14 (Sonoma) oder neuer
- Apple Silicon (M1/M2/M3) empfohlen – Intel wird unterstützt aber langsamer
- Mindestens 8 GB RAM (16 GB empfohlen für large-v3-turbo Modell)
- ~3 GB freier Speicher für das Whisper-Modell

## Installation

### Aus Source bauen

1. Xcode 15+ installieren
2. Repository klonen:
   ```bash
   git clone https://github.com/DEIN-USERNAME/WhisperType.git
   cd WhisperType
   ```
3. In Xcode öffnen und bauen:
   ```bash
   open WhisperType.xcodeproj
   ```
   Oder via Command Line:
   ```bash
   xcodebuild -scheme WhisperType -configuration Release
   ```
4. App starten – beim ersten Start wird das Whisper-Modell heruntergeladen (~1.5 GB)

### Berechtigungen einrichten

Nach dem ersten Start muss WhisperType in den Systemeinstellungen freigegeben werden:
1. **Mikrofon:** Wird automatisch angefragt
2. **Bedienungshilfen:** Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen → WhisperType aktivieren

## Benutzung

1. WhisperType startet als Mikrofon-Icon in der Menüleiste
2. Klicke in ein beliebiges Textfeld (Browser, Editor, Chat, IDE...)
3. Drücke den Hotkey (Standard: Option+D)
4. Sprich deinen Text
5. Lasse los (Push-to-Talk) oder drücke erneut (Toggle-Modus)
6. Der transkribierte Text wird automatisch eingefügt

## Einstellungen

Über das Menübar-Icon → Einstellungen:
- Hotkey ändern
- Push-to-Talk oder Toggle-Modus
- Whisper-Modell wechseln
- Sprache festlegen oder automatisch erkennen lassen
- Füllwort-Filter konfigurieren

## Unterstützte Whisper-Modelle

| Modell | Größe | RAM-Bedarf | Geschwindigkeit | Qualität |
|--------|-------|------------|-----------------|----------|
| tiny | 75 MB | ~1 GB | Sehr schnell | Basis |
| base | 142 MB | ~1 GB | Schnell | Gut |
| small | 466 MB | ~2 GB | Mittel | Sehr gut |
| medium | 1.5 GB | ~5 GB | Langsamer | Exzellent |
| large-v3-turbo | 1.5 GB | ~5 GB | Mittel | Exzellent |

**Empfehlung für M1 16GB:** `large-v3-turbo` – beste Balance aus Qualität und Geschwindigkeit.

## Lizenz

MIT License
