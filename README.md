# Habit Tracker (macOS, SwiftUI)

A lightweight native macOS habit tracker with:

- **Pomodoro-style session tracker** (work/rest, pause/resume, configurable durations)
- **Menu bar countdown badge + quick popup**
- **Session manager window + full habit dashboard window**
- **Session logging to JSON + CSV**
- **Optional daily planner import** from markdown (`YYYY-MM-DD.md`)
- **Habit tracking** with yes/no or numeric metrics, colors, and calendar visualization

## Build & run

### Prerequisites

- macOS 13+
- Xcode 15+ (or Swift 5.8+ toolchain)

### Terminal

```bash
swift run
```

### Open in Xcode

```bash
open Package.swift
```

Then run the `HabitTracker` executable target.

## Window model

- **Menu bar popup**: compact quick controls (name, labels, start/pause/resume, complete).
- **Session Manager window**: the default app window for timer flow and window navigation.
- **Habit Dashboard window**: full session + habits UI.

You can open both windows from the menu bar popup.

## Planner markdown format

The Session Tracker can load a day's chores from a directory. It looks for either:

- `YYYY-MM-DD.md`
- `YYYY-MM-DD`

Example:

```md
## Day planner
- [ ] 09:00-10:00 Startup
- [ ] 10:00-11:00 Startup work
- [ ] 11:15-12:15 Deep focus #paper
- [ ] 12:15-13:15 Deep focus #code
- [ ] 13:15-14:30 Lunch + long rest #rest #meal
```

## Data storage

Saved in:

`~/Library/Application Support/HabitTracker/`

Files:

- `snapshot.json` (settings, current state, habits, habit logs)
- `session_logs.json` (session history)
- `session_logs.csv` (session history for spreadsheets)
