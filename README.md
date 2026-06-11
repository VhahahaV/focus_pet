# Focus Pet

Focus Pet is a local macOS productivity desktop pet. It uses local system signals to classify the user into four states: focus, distracted, break, and away.

## MVP Scope

- macOS menu bar app and desktop `NSPanel` pet.
- Local signal collection: frontmost app, bundle id, window title classification, input idle time, and app switch frequency.
- Four-state engine with priority: away, break, focus, distracted.
- State segments, app usage segments, focus sessions, break sessions, nudges, and daily summary.
- Five dashboard tabs: 今日, 时间分布, 专注会话, 规则, 设置.
- Resource pack parsing, validation, bundled pack loading, and pet action fallback.
- Local-only storage with clean MVP schema reset.

## Architecture

SwiftPM targets:

- `FocusPetCore`: pure domain logic, state engine, time tracking, nudges, settings, summaries.
- `FocusPetStorage`: local JSON store, export, delete, and retention bootstrap.
- `FocusPetResources`: pet pack manifests, validation, fallback, bundled pack catalog.
- `FocusPetRenderer`: desktop pet panel and SwiftUI renderer.
- `FocusPetMac`: macOS app entry, menu bar, monitors, model, and dashboard UI.

## Build And Test

```bash
swift build
swift test
swift run FocusPetCoreChecks
./scripts/package-macos-app.sh
```

The packaged app is written to `.build/FocusPet.app`.
