import WidgetKit
import SwiftUI

// ── Datenmodell ───────────────────────────────────────────────────
struct ShiftEntry: Identifiable {
    let id = UUID()
    let date: String
    let shift: String
    let hasNote: Bool
}

struct DienstplanTimelineEntry: TimelineEntry {
    let date: Date
    let shifts: [ShiftEntry]
}

// ── Provider ──────────────────────────────────────────────────────
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DienstplanTimelineEntry {
    DienstplanTimelineEntry(date: Date(), shifts: [
        ShiftEntry(date: "2026-06-08", shift: "P", hasNote: false),
        ShiftEntry(date: "2026-06-09", shift: "F", hasNote: false),
        ShiftEntry(date: "2026-06-10", shift: "U", hasNote: false),
        ShiftEntry(date: "2026-06-11", shift: "P1", hasNote: false),
        ShiftEntry(date: "2026-06-12", shift: "DA", hasNote: false),
    ])
}

    func getSnapshot(in context: Context, completion: @escaping (DienstplanTimelineEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DienstplanTimelineEntry>) -> Void) {
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> DienstplanTimelineEntry {
        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let json = defaults?.string(forKey: "schedule_entries") ?? "[]"
        let data = json.data(using: .utf8) ?? Data()
        let decoded = (try? JSONSerialization.jsonObject(with: data) as? [[String: String]]) ?? []

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let today = Calendar.current.startOfDay(for: Date())

        let filtered = decoded
    .compactMap { dict -> ShiftEntry? in
        guard let dateStr = dict["date"],
              let shift = dict["shift"],
              let d = fmt.date(from: dateStr),
              d >= today else { return nil }
        let hasNote = dict["hasNote"] == "true"
        return ShiftEntry(date: dateStr, shift: shift, hasNote: hasNote)
    }
    .sorted { $0.date < $1.date }

        return DienstplanTimelineEntry(date: Date(), shifts: filtered)
    }
}

// ── Farben ────────────────────────────────────────────────────────
func shiftColor(_ shift: String) -> Color {
    switch shift.uppercased() {
    case "U", "DA", "X":
        return Color(.systemGray)
    case "VK":
        return Color(red: 0.94, green: 0.36, blue: 0.36)
    default:
        return Color(red: 0.36, green: 0.55, blue: 0.94)
    }
}

// ── Einzelne Tageskachel ──────────────────────────────────────────
struct DayTile: View {
    let entry: ShiftEntry
    let isToday: Bool

    var dayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "de_DE")
        guard let d = fmt.date(from: entry.date) else { return "" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEE"
        return String(df.string(from: d).prefix(2)).uppercased()
    }

    var dayNum: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: entry.date) else { return "" }
        let df = DateFormatter()
        df.dateFormat = "dd"
        return df.string(from: d)
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(dayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(isToday ? .white.opacity(0.8) : .secondary)

            Text(dayNum)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(isToday ? .white : .primary)

            Text(entry.shift.isEmpty ? "—" : entry.shift)
                .font(.system(size: 14, weight: .heavy))
                .foregroundColor(isToday ? .white : shiftColor(entry.shift))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday
                    ? shiftColor(entry.shift).opacity(0.85)
                    : shiftColor(entry.shift).opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isToday
                    ? Color.clear
                    : shiftColor(entry.shift).opacity(0.25),
                        lineWidth: 1)
        )
    }
}

// ── Small Widget ──────────────────────────────────────────────────
// ── Small Widget ──────────────────────────────────────────────────
struct SmallWidgetView: View {
    let shifts: [ShiftEntry]

    var todayEntry: ShiftEntry? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        return shifts.first { $0.date == todayStr }
    }

    var todayLabel: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEE dd.MM"
        return df.string(from: Date())
    }

    var todayDateKey: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Heute")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(todayLabel)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if let t = todayEntry {
                HStack(spacing: 4) {
                    Text(t.shift.isEmpty ? "—" : t.shift)
                        .font(.system(size: 32, weight: .heavy))
                        .foregroundColor(shiftColor(t.shift))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    if t.hasNote {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                }
            } else {
                Text("—")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: todayEntry?.hasNote == true
            ? "optimes://dienstplan/note/\(todayDateKey)"
            : "optimes://dienstplan"))
    }
}

// ── Large Widget View ─────────────────────────────────────────────
struct LargeWidgetView: View {
    let entry: DienstplanTimelineEntry
    let todayStr: String

    private var today: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var shiftDict: [String: String] {
        Dictionary(uniqueKeysWithValues: entry.shifts.map { ($0.date, $0.shift) })
    }

    private var weeks: [[Date]] {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        let thisMonday = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (0..<4).map { weekOffset in
            let monday = cal.date(byAdding: .weekOfYear, value: weekOffset, to: thisMonday)!
            return (0..<7).map { dayOffset in
                cal.date(byAdding: .day, value: dayOffset, to: monday)!
            }
        }
    }

    private var fmt: DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

var body: some View {
    VStack(spacing: 5) {
        ForEach(0..<weeks.count, id: \.self) { wi in
            let weekDates = weeks[wi]
            let firstDate = weekDates.first!
            let isMonthBoundaryWeek: Bool = {
                if wi == 0 { return false }
                let prevWeekLastDate = weeks[wi - 1].last!
                return Calendar.current.component(.month, from: firstDate) !=
                       Calendar.current.component(.month, from: prevWeekLastDate)
            }()

            if isMonthBoundaryWeek {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color(.systemGray2), Color.clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 2)
                }
                .padding(.vertical, 3)
            }

            HStack(spacing: 4) {
                ForEach(weekDates, id: \.self) { date in
                    let dateStr = fmt.string(from: date)
                    let shift = shiftDict[dateStr]
                    let isToday = dateStr == todayStr
                    let isPast = date < today
                    let isFirstOfMonth = Calendar.current.component(.day, from: date) == 1

                    if shift != nil || isToday {
                        DayTile(
                            entry: ShiftEntry(date: dateStr, shift: shift ?? "", hasNote: false),
                            isToday: isToday
                        )
                        .overlay(
                            isFirstOfMonth && !isToday ?
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.3)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                            : nil
                        )
                    } else if isPast {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6).opacity(0.15))
                            .overlay(
                                isFirstOfMonth ?
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.2)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                : nil
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6).opacity(0.25))
                            .overlay(
                                isFirstOfMonth ?
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(
                                        LinearGradient(
                                            colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.3)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                                : nil
                            )
                    }
                }
            }
        }
    }
    .padding(10)
}
}

// ── Medium/Large Widget View ──────────────────────────────────────
struct DienstplanWidgetView: View {
    var entry: DienstplanTimelineEntry
    @Environment(\.widgetFamily) var family

    // NEU:
var dayCount: Int {
    switch family {
    case .systemSmall:  return 2
    case .systemMedium: return 7
    case .systemLarge:  return 10
    default:            return 7
    }
}

    var todayStr: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var body: some View {
        if family == .systemSmall {
            SmallWidgetView(shifts: entry.shifts)
                .modifier(WidgetBackgroundModifier())
        } else {
            let visible = Array(entry.shifts.prefix(dayCount))
            Group {
                if visible.isEmpty {
                    VStack {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("Kein Dienstplan")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if family == .systemLarge {
                    LargeWidgetView(entry: entry, todayStr: todayStr)
                } else {
                    HStack(spacing: 6) {
                        ForEach(visible) { s in
                            DayTile(entry: s, isToday: s.date == todayStr)
                        }
                    }
                    .padding(10)
                }
            }
            .modifier(WidgetBackgroundModifier())
            .widgetURL(URL(string: "optimes://dienstplan"))
        }
    }
    }

struct WidgetBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(.systemBackground)
            }
        } else {
            content.background(Color(.systemBackground))
        }
    }
}

// ── Widget Definition ─────────────────────────────────────────────
struct DienstplanWidget: Widget {
    let kind: String = "DienstplanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            DienstplanWidgetView(entry: entry)
        }
        .configurationDisplayName("Dienstplan")
        .description("Zeigt deine nächsten Dienste.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}