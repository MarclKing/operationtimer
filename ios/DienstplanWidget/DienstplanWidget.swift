import WidgetKit
import SwiftUI

// ── Datenmodell ───────────────────────────────────────────────────
struct ShiftEntry: Identifiable {
    let id = UUID()
    let date: String
    let shift: String
}

struct DienstplanTimelineEntry: TimelineEntry {
    let date: Date
    let shifts: [ShiftEntry]
}

// ── Provider ──────────────────────────────────────────────────────
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DienstplanTimelineEntry {
        DienstplanTimelineEntry(date: Date(), shifts: [
            ShiftEntry(date: "2026-06-08", shift: "P"),
            ShiftEntry(date: "2026-06-09", shift: "F"),
            ShiftEntry(date: "2026-06-10", shift: "U"),
            ShiftEntry(date: "2026-06-11", shift: "P1"),
            ShiftEntry(date: "2026-06-12", shift: "DA"),
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
                return ShiftEntry(date: dateStr, shift: shift)
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
struct SmallWidgetView: View {
    let shifts: [ShiftEntry]

    var tomorrow: ShiftEntry? {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let tmr = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return nil }
        let tmrStr = fmt.string(from: tmr)
        return shifts.first { $0.date == tmrStr }
    }

    var tomorrowLabel: String {
        guard let d = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return "Morgen" }
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "EEE dd.MM"
        return df.string(from: d)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Morgen")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)

            Text(tomorrowLabel)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            if let t = tomorrow {
                Text(t.shift.isEmpty ? "—" : t.shift)
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(shiftColor(t.shift))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── Medium/Large Widget View ──────────────────────────────────────
struct DienstplanWidgetView: View {
    var entry: DienstplanTimelineEntry
    @Environment(\.widgetFamily) var family

    var dayCount: Int {
        switch family {
        case .systemSmall:  return 2
        case .systemMedium: return 5
        case .systemLarge:  return 10
        default:            return 5
        }
    }

    var todayStr: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: Date())
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                SmallWidgetView(shifts: entry.shifts)
            } else {
                let visible = Array(entry.shifts.prefix(dayCount))
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
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            ForEach(Array(visible.prefix(5))) { s in
                                DayTile(entry: s, isToday: s.date == todayStr)
                            }
                        }
                        if visible.count > 5 {
                            HStack(spacing: 6) {
                                ForEach(Array(visible.dropFirst(5))) { s in
                                    DayTile(entry: s, isToday: s.date == todayStr)
                                }
                            }
                        }
                    }
                    .padding(10)
                } else {
                    HStack(spacing: 6) {
                        ForEach(visible) { s in
                            DayTile(entry: s, isToday: s.date == todayStr)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .widgetURL(URL(string: "optimes://dienstplan"))
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
