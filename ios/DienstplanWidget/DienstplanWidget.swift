import WidgetKit
import SwiftUI

// ── Datenmodell ───────────────────────────────────────────────────
struct ShiftEntry: Identifiable {
    let id = UUID()
    let date: String
    let shift: String
}

// ── Timeline Entry ────────────────────────────────────────────────
struct DienstplanTimelineEntry: TimelineEntry {
    let date: Date
    let shifts: [ShiftEntry]
}

// ── Provider ──────────────────────────────────────────────────────
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DienstplanTimelineEntry {
        DienstplanTimelineEntry(date: Date(), shifts: [
            ShiftEntry(date: "2025-06-07", shift: "F"),
            ShiftEntry(date: "2025-06-08", shift: "U"),
            ShiftEntry(date: "2025-06-09", shift: "P"),
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
        let shifts = decoded.map { ShiftEntry(date: $0["date"] ?? "", shift: $0["shift"] ?? "") }
        return DienstplanTimelineEntry(date: Date(), shifts: shifts)
    }
}

// ── View ──────────────────────────────────────────────────────────
struct DienstplanWidgetView: View {
    var entry: DienstplanTimelineEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Dienstplan")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)

            ForEach(entry.shifts.prefix(4)) { s in
                HStack {
                    Text(formatDate(s.date))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(s.shift.isEmpty ? "—" : s.shift)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(shiftColor(s.shift))
                }
            }
            Spacer()
        }
        .padding()
        .widgetURL(URL(string: "optimes://dienstplan"))
    }

    func formatDate(_ s: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: s) else { return s }
        fmt.dateFormat = "EE dd.MM"
        fmt.locale = Locale(identifier: "de_DE")
        return fmt.string(from: d)
    }

    func shiftColor(_ shift: String) -> Color {
        switch shift.uppercased() {
        case "U", "DA", "X": return .secondary
        case "VK": return Color(red: 0.94, green: 0.36, blue: 0.36)
        default: return Color(red: 0.36, green: 0.55, blue: 0.94)
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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}