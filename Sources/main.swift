import SwiftUI
import AppKit

@main
struct HabitTrackerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Habit Tracker") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 920, minHeight: 620)
        }
        .defaultSize(width: 1024, height: 700)

        MenuBarExtra {
            SessionMenuView()
                .environmentObject(state)
                .frame(width: 300)
        } label: {
            Text(state.menuBarTitle)
                .monospacedDigit()
        }
    }
}

final class AppState: ObservableObject {
    @Published var settings = SessionSettings(workMinutes: 50, restMinutes: 10)
    @Published var sessionState = SessionState()
    @Published var choreDirectoryPath: String = ""
    @Published var chores: [Chore] = []
    @Published var habits: [Habit] = []
    @Published var habitLogs: [HabitLog] = []

    private var timer: Timer?
    private let persistence = Persistence()

    init() {
        loadPersistedData()
        loadTodaysChoresIfPossible()
        restartTimerIfNeeded()
    }

    var menuBarTitle: String {
        if sessionState.mode == .idle {
            return "⏱ Idle"
        }
        return "\(sessionState.mode.badge) \(formattedTimeRemaining)"
    }

    var formattedTimeRemaining: String {
        let s = max(0, sessionState.secondsRemaining)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func startTimer() {
        if sessionState.mode == .idle {
            sessionState.mode = .work
            sessionState.secondsRemaining = settings.workMinutes * 60
            sessionState.sessionStartedAt = Date()
        }
        sessionState.isPaused = false
        restartTimerIfNeeded()
        persist()
    }

    func pauseTimer() {
        sessionState.isPaused.toggle()
        restartTimerIfNeeded()
        persist()
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
        sessionState = SessionState()
        persist()
    }

    func completeCurrentSession(name: String, labels: [String]) {
        guard sessionState.mode != .idle else { return }
        let end = Date()
        let start = sessionState.sessionStartedAt ?? end
        let log = SessionLog(
            id: UUID(),
            mode: sessionState.mode,
            name: name.isEmpty ? sessionState.mode.defaultName : name,
            labels: labels,
            start: start,
            end: end,
            configuredMinutes: sessionState.mode == .work ? settings.workMinutes : settings.restMinutes
        )
        persistence.appendSessionLog(log)

        switchMode()
        persist()
    }

    func addHabit(_ habit: Habit) {
        habits.append(habit)
        persist()
    }

    func removeHabits(at offsets: IndexSet) {
        habits.remove(atOffsets: offsets)
        habitLogs.removeAll { log in
            !habits.contains(where: { $0.id == log.habitID })
        }
        persist()
    }

    func logHabit(habit: Habit, date: Date, boolValue: Bool?, numberValue: Double?) {
        let normalized = Calendar.current.startOfDay(for: date)
        habitLogs.removeAll { $0.habitID == habit.id && Calendar.current.isDate($0.date, inSameDayAs: normalized) }
        let entry = HabitLog(id: UUID(), habitID: habit.id, date: normalized, boolValue: boolValue, numberValue: numberValue)
        habitLogs.append(entry)
        persist()
    }

    func habitLog(habitID: UUID, date: Date) -> HabitLog? {
        habitLogs.first {
            $0.habitID == habitID && Calendar.current.isDate($0.date, inSameDayAs: date)
        }
    }

    func loadTodaysChoresIfPossible() {
        guard !choreDirectoryPath.isEmpty else {
            chores = []
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let fileName = formatter.string(from: Date())

        let directory = URL(fileURLWithPath: choreDirectoryPath, isDirectory: true)
        let candidates = ["\(fileName).md", fileName]

        for candidate in candidates {
            let url = directory.appendingPathComponent(candidate)
            if let parsed = MarkdownPlannerParser.parse(fileURL: url), !parsed.isEmpty {
                chores = parsed
                return
            }
        }

        chores = []
    }

    private func restartTimerIfNeeded() {
        timer?.invalidate()
        guard sessionState.mode != .idle, !sessionState.isPaused else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.sessionState.secondsRemaining > 0 {
                self.sessionState.secondsRemaining -= 1
            } else {
                self.completeCurrentSession(name: self.sessionState.mode.defaultName, labels: [])
            }
        }
    }

    private func switchMode() {
        if sessionState.mode == .work {
            sessionState.mode = .rest
            sessionState.secondsRemaining = settings.restMinutes * 60
        } else {
            sessionState.mode = .work
            sessionState.secondsRemaining = settings.workMinutes * 60
        }
        sessionState.sessionStartedAt = Date()
        sessionState.isPaused = false
        restartTimerIfNeeded()
    }

    private func loadPersistedData() {
        let snapshot = persistence.loadSnapshot()
        settings = snapshot.settings
        sessionState = snapshot.sessionState
        choreDirectoryPath = snapshot.choreDirectoryPath
        habits = snapshot.habits
        habitLogs = snapshot.habitLogs
    }

    private func persist() {
        persistence.saveSnapshot(
            settings: settings,
            sessionState: sessionState,
            choreDirectoryPath: choreDirectoryPath,
            habits: habits,
            habitLogs: habitLogs
        )
    }
}

struct RootView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            SessionTrackerView()
                .tabItem { Label("Session Tracker", systemImage: "timer") }
            HabitsView()
                .tabItem { Label("Habits", systemImage: "checklist") }
        }
        .padding()
    }
}

struct SessionTrackerView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedChore: Chore?
    @State private var customName: String = ""
    @State private var customLabels: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                timerCard
                choresCard
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Pomodoro Session Tracker")
                    .font(.title2.bold())
                Text("Alternating work/rest cycles with structured session logging.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(state.menuBarTitle)
                .font(.title3.monospacedDigit())
                .padding(8)
                .background(.blue.opacity(0.14), in: Capsule())
        }
    }

    private var timerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Timer") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(state.sessionState.mode.displayName)
                            .font(.headline)
                        Spacer()
                        Text(state.formattedTimeRemaining)
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }

                    HStack {
                        Stepper("Work: \(state.settings.workMinutes) min", value: $state.settings.workMinutes, in: 5...180, step: 5)
                        Stepper("Rest: \(state.settings.restMinutes) min", value: $state.settings.restMinutes, in: 5...90, step: 5)
                    }

                    HStack {
                        Button(state.sessionState.mode == .idle ? "Start" : "Restart") {
                            state.stopTimer()
                            state.startTimer()
                        }
                        .buttonStyle(.borderedProminent)

                        Button(state.sessionState.isPaused ? "Resume" : "Pause") {
                            state.pauseTimer()
                        }
                        .disabled(state.sessionState.mode == .idle)

                        Button("Stop") {
                            state.stopTimer()
                        }
                        .disabled(state.sessionState.mode == .idle)
                    }
                }
                .padding(6)
            }

            GroupBox("Session Metadata") {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Session name", text: $customName)
                    TextField("Labels (comma separated)", text: $customLabels)

                    Button("Complete current session") {
                        let chosenName = selectedChore?.title ?? customName
                        let labels = if let chosenChore = selectedChore, !chosenChore.labels.isEmpty {
                            chosenChore.labels
                        } else {
                            customLabels
                                .split(separator: ",")
                                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                                .filter { !$0.isEmpty }
                        }
                        state.completeCurrentSession(name: chosenName, labels: labels)
                    }
                    .disabled(state.sessionState.mode == .idle)
                }
                .padding(6)
            }
        }
    }

    private var choresCard: some View {
        GroupBox("Today's Planner Chores") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    TextField("Planner directory", text: $state.choreDirectoryPath)
                    Button("Load") {
                        state.loadTodaysChoresIfPossible()
                    }
                }

                if state.chores.isEmpty {
                    Text("No matching planner markdown for today. You can still use custom names and labels.")
                        .foregroundStyle(.secondary)
                } else {
                    List(state.chores, selection: $selectedChore) { chore in
                        VStack(alignment: .leading) {
                            Text(chore.title)
                                .font(.headline)
                            if !chore.timeRange.isEmpty {
                                Text(chore.timeRange)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !chore.labels.isEmpty {
                                Text(chore.labels.map { "#\($0)" }.joined(separator: " "))
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(6)
        }
    }
}

struct SessionMenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session")
                .font(.headline)
            Text("\(state.sessionState.mode.displayName): \(state.formattedTimeRemaining)")
                .monospacedDigit()
            HStack {
                Button("Start") { state.startTimer() }
                Button(state.sessionState.isPaused ? "Resume" : "Pause") { state.pauseTimer() }
                    .disabled(state.sessionState.mode == .idle)
                Button("Stop") { state.stopTimer() }
                    .disabled(state.sessionState.mode == .idle)
            }
        }
        .padding()
    }
}

struct HabitsView: View {
    @EnvironmentObject private var state: AppState
    @State private var draft = HabitDraft()
    @State private var selectedDate = Date()

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Habit Builder")
                    .font(.title3.bold())
                HabitEditor(draft: $draft) {
                    state.addHabit(draft.toHabit())
                    draft = HabitDraft()
                }
                Divider()
                List {
                    ForEach(state.habits) { habit in
                        HabitRow(habit: habit, selectedDate: $selectedDate)
                            .environmentObject(state)
                    }
                    .onDelete(perform: state.removeHabits)
                }
            }
            .frame(maxWidth: 420)

            CalendarHeatmapView(date: $selectedDate)
                .environmentObject(state)
        }
    }
}

struct HabitEditor: View {
    @Binding var draft: HabitDraft
    var onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Habit name", text: $draft.name)
            Picker("Frequency", selection: $draft.frequency) {
                ForEach(HabitFrequency.allCases) { freq in
                    Text(freq.rawValue.capitalized).tag(freq)
                }
            }
            Picker("Type", selection: $draft.metric) {
                ForEach(HabitMetric.allCases) { metric in
                    Text(metric.displayName).tag(metric)
                }
            }
            ColorPicker("Color", selection: $draft.color)
            Button("Add habit", action: onCreate)
                .buttonStyle(.borderedProminent)
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

struct HabitRow: View {
    @EnvironmentObject private var state: AppState
    let habit: Habit
    @Binding var selectedDate: Date
    @State private var numberValue: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(habit.color.swiftUIColor).frame(width: 10, height: 10)
                Text(habit.name).bold()
                Spacer()
                Text(habit.frequency.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if habit.metric == .yesNo {
                Toggle("Completed on selected day", isOn: Binding(
                    get: { state.habitLog(habitID: habit.id, date: selectedDate)?.boolValue ?? false },
                    set: { newValue in
                        state.logHabit(habit: habit, date: selectedDate, boolValue: newValue, numberValue: nil)
                    }
                ))
            } else {
                HStack {
                    TextField("Value", text: $numberValue)
                        .onAppear {
                            if let existing = state.habitLog(habitID: habit.id, date: selectedDate)?.numberValue {
                                numberValue = String(existing)
                            }
                        }
                    Button("Save") {
                        if let v = Double(numberValue) {
                            state.logHabit(habit: habit, date: selectedDate, boolValue: nil, numberValue: v)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct CalendarHeatmapView: View {
    @EnvironmentObject private var state: AppState
    @Binding var date: Date

    private let columns = Array(repeating: GridItem(.flexible(minimum: 24, maximum: 60), spacing: 6), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar")
                .font(.title3.bold())
            DatePicker("Selected date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.compact)

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(currentMonthDates(), id: \.self) { day in
                    dayCell(day)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dayCell(_ day: Date) -> some View {
        let logs = state.habitLogs.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
        let achievedCount = logs.filter { ($0.boolValue == true) || (($0.numberValue ?? 0) > 0) }.count
        let intensity = min(Double(achievedCount) / max(1, Double(state.habits.count)), 1.0)

        return VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.caption)
            RoundedRectangle(cornerRadius: 4)
                .fill(.green.opacity(0.15 + intensity * 0.75))
                .frame(height: 14)
        }
        .padding(2)
        .background(Calendar.current.isDate(day, inSameDayAs: date) ? .blue.opacity(0.18) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onTapGesture { date = day }
    }

    private func currentMonthDates() -> [Date] {
        let calendar = Calendar.current
        let now = date
        guard let monthInterval = calendar.dateInterval(of: .month, for: now) else { return [] }

        var days: [Date] = []
        var cursor = monthInterval.start
        while cursor < monthInterval.end {
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? monthInterval.end
        }
        return days
    }
}

struct SessionSettings: Codable {
    var workMinutes: Int
    var restMinutes: Int
}

struct SessionState: Codable {
    var mode: SessionMode = .idle
    var secondsRemaining: Int = 0
    var isPaused: Bool = false
    var sessionStartedAt: Date?
}

enum SessionMode: String, Codable {
    case idle
    case work
    case rest

    var displayName: String {
        switch self {
        case .idle: "Idle"
        case .work: "Work"
        case .rest: "Rest"
        }
    }

    var badge: String {
        switch self {
        case .idle: "⏱"
        case .work: "🧠"
        case .rest: "☕"
        }
    }

    var defaultName: String {
        switch self {
        case .work: "Work Session"
        case .rest: "Rest Session"
        case .idle: "Session"
        }
    }
}

struct SessionLog: Codable {
    let id: UUID
    let mode: SessionMode
    let name: String
    let labels: [String]
    let start: Date
    let end: Date
    let configuredMinutes: Int
}

struct Chore: Identifiable, Hashable {
    let id = UUID()
    let timeRange: String
    let title: String
    let labels: [String]
}

enum HabitFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly

    var id: String { rawValue }
}

enum HabitMetric: String, Codable, CaseIterable, Identifiable {
    case yesNo
    case number

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yesNo: "Yes / No"
        case .number: "Numeric"
        }
    }
}

struct HabitColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    static let fallback = HabitColor(red: 0.2, green: 0.58, blue: 0.94, opacity: 1)
}

struct Habit: Codable, Identifiable {
    let id: UUID
    let name: String
    let frequency: HabitFrequency
    let metric: HabitMetric
    let color: HabitColor
}

struct HabitLog: Codable, Identifiable {
    let id: UUID
    let habitID: UUID
    let date: Date
    let boolValue: Bool?
    let numberValue: Double?
}

struct HabitDraft {
    var name: String = ""
    var frequency: HabitFrequency = .daily
    var metric: HabitMetric = .yesNo
    var color: Color = .blue

    func toHabit() -> Habit {
        let ns = NSColor(color)
        return Habit(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            frequency: frequency,
            metric: metric,
            color: HabitColor(
                red: Double(ns.redComponent),
                green: Double(ns.greenComponent),
                blue: Double(ns.blueComponent),
                opacity: Double(ns.alphaComponent)
            )
        )
    }
}

enum MarkdownPlannerParser {
    static func parse(fileURL: URL) -> [Chore]? {
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { return nil }
        let lines = content.components(separatedBy: .newlines)
        var chores: [Chore] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [") else { continue }

            let cleaned = trimmed
                .replacingOccurrences(of: "- [ ]", with: "")
                .trimmingCharacters(in: .whitespaces)

            let parts = cleaned.components(separatedBy: " ")
            guard let first = parts.first else { continue }

            let timeRange = first.contains("-") ? first : ""
            let titleStart = timeRange.isEmpty ? 0 : 1
            let titleAndTags = parts.dropFirst(titleStart).joined(separator: " ")

            let tags = titleAndTags
                .split(separator: " ")
                .compactMap { token -> String? in
                    guard token.hasPrefix("#") else { return nil }
                    return String(token.dropFirst())
                }

            let title = titleAndTags
                .split(separator: " ")
                .filter { !$0.hasPrefix("#") }
                .map(String.init)
                .joined(separator: " ")

            chores.append(Chore(timeRange: timeRange, title: title, labels: tags))
        }

        return chores
    }
}

struct PersistedSnapshot: Codable {
    var settings = SessionSettings(workMinutes: 50, restMinutes: 10)
    var sessionState = SessionState()
    var choreDirectoryPath: String = ""
    var habits: [Habit] = []
    var habitLogs: [HabitLog] = []
}

final class Persistence {
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSnapshot() -> PersistedSnapshot {
        guard let data = try? Data(contentsOf: snapshotURL),
              let decoded = try? decoder.decode(PersistedSnapshot.self, from: data)
        else {
            return PersistedSnapshot()
        }
        return decoded
    }

    func saveSnapshot(settings: SessionSettings, sessionState: SessionState, choreDirectoryPath: String, habits: [Habit], habitLogs: [HabitLog]) {
        let snapshot = PersistedSnapshot(
            settings: settings,
            sessionState: sessionState,
            choreDirectoryPath: choreDirectoryPath,
            habits: habits,
            habitLogs: habitLogs
        )
        guard let data = try? encoder.encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? data.write(to: snapshotURL)
    }

    func appendSessionLog(_ log: SessionLog) {
        var existing = loadSessionLogs()
        existing.append(log)

        guard let data = try? encoder.encode(existing) else { return }
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? data.write(to: sessionJSONURL)

        let csvLine = [
            log.id.uuidString,
            log.mode.rawValue,
            log.name,
            log.labels.joined(separator: "|"),
            iso(log.start),
            iso(log.end),
            String(log.configuredMinutes)
        ].map(csvEscape).joined(separator: ",") + "\n"

        if !FileManager.default.fileExists(atPath: sessionCSVURL.path) {
            let header = "id,mode,name,labels,start,end,configuredMinutes\n"
            try? header.write(to: sessionCSVURL, atomically: true, encoding: .utf8)
        }
        if let handle = try? FileHandle(forWritingTo: sessionCSVURL) {
            try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(csvLine.utf8))
            try? handle.close()
        }
    }

    private func loadSessionLogs() -> [SessionLog] {
        guard let data = try? Data(contentsOf: sessionJSONURL),
              let decoded = try? decoder.decode([SessionLog].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private var storageDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("HabitTracker", isDirectory: true)
    }

    private var snapshotURL: URL { storageDirectory.appendingPathComponent("snapshot.json") }
    private var sessionJSONURL: URL { storageDirectory.appendingPathComponent("session_logs.json") }
    private var sessionCSVURL: URL { storageDirectory.appendingPathComponent("session_logs.csv") }

    private func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: date)
    }

    private func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
