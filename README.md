# Habit Tracker (macOS, SwiftUI)

A lightweight native macOS habit tracker with:

- **Pomodoro-style session tracker** (work/rest, pause/resume, configurable durations)
- **Menu bar countdown badge**
- **Session logging to JSON + CSV**
- **Optional daily planner import** from markdown (`YYYY-MM-DD.md`)
- **Habit tracking** with yes/no or numeric metrics, colors, and calendar visualization

## Build & run

### Prerequisites

- macOS 13+
- Xcode 15+ (or Swift 5.9+ toolchain)

### Terminal

```bash
swift run
```

### Generate Xcode project-style opening

```bash
open Package.swift
```

Then run the `HabitTracker` executable target.

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

## Notes

- If no planner file is found for today, the app falls back to manual names/labels.
- Session completion can use a chore title/labels or manual metadata.
- Structure is intentionally modular for adding features later.
