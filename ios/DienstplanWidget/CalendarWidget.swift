import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Datenmodell
// ─────────────────────────────────────────────────────────────────────────────

struct CalWidgetEvent: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let colorHex: String?
}

struct CalendarDayData: Identifiable {
    let id = UUID()
    let date: Date
    let dateStr: String
    let shiftCode: String?
    let events: [CalWidgetEvent]
}

struct CalendarWidgetTimelineEntry: TimelineEntry {
    let date: Date
    let days: [CalendarDayData]
}

// NEU: Lesemodus-Flag aus dem App Group Storage lesen
func isReadOnlyModeActive() -> Bool {
    UserDefaults(suiteName: "group.de.marcel.optimes")?.bool(forKey: "read_only_mode") ?? false
}

// NEU: Ersatzansicht für das Fahrtenbuch-Quick-Start-Widget im Lesemodus
struct ReadOnlyDisabledSmallView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 22))
                .foregroundColor(Shield.textMuted)
            Text("Lesemodus")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Shield.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(SmallBackgroundModifier())
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider — teilt sich Datenquelle mit beiden neuen Widgets
// ─────────────────────────────────────────────────────────────────────────────

struct CalendarWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarWidgetTimelineEntry {
        CalendarWidgetTimelineEntry(date: Date(), days: [
            CalendarDayData(date: Date(), dateStr: "today", shiftCode: "F",
                events: [CalWidgetEvent(title: "Teambesprechung", start: Date(), end: Date(), allDay: false, colorHex: "#2D6CFF")])
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarWidgetTimelineEntry) -> Void) {
        UserDefaults(suiteName: "group.de.marcel.optimes")?.synchronize()
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarWidgetTimelineEntry>) -> Void) {
        UserDefaults(suiteName: "group.de.marcel.optimes")?.synchronize()
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> CalendarWidgetTimelineEntry {
        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFmtNoFrac = ISO8601DateFormatter()

        // NEU: Fallback für Dart's lokale (nicht-UTC) toIso8601String()-Strings
        // ohne Zeitzonen-Suffix — genau das war der Grund, warum bisher ALLE
        // Termine beim Parsen verworfen wurden und die Widgets leer blieben.
        // Die Zeit wird 1:1 als Gerätezeitzone interpretiert — exakt das, was
        // Dart gemeint hat, da beide auf demselben Gerät laufen.
        let localFmt = DateFormatter()
        localFmt.locale = Locale(identifier: "en_US_POSIX")
        localFmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        localFmt.timeZone = TimeZone.current

        func parseDate(_ s: String) -> Date? {
            isoFmt.date(from: s) ?? isoFmtNoFrac.date(from: s) ?? localFmt.date(from: s)
        }

        // ── Dienst-Codes: nutzt DIESELBEN "schedule_entries", die schon
        // fürs Dienstplan-Widget gepusht werden — keine zusätzliche
        // Dart-Anbindung nötig, nur zusätzlich ausgelesen.
        var shiftByDate: [String: String] = [:]
        if let json = defaults?.string(forKey: "schedule_entries"),
           let data = json.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: String]] {
            for dict in arr {
                if let d = dict["date"], let s = dict["shift"] { shiftByDate[d] = s }
            }
        }

        // ── Termine: NEUER Key, von CalendarEventStore gepusht.
        var rawEvents: [CalWidgetEvent] = []
        if let json = defaults?.string(forKey: "calendar_widget_events"),
           let data = json.data(using: .utf8),
           let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] {
            for dict in arr {
                guard let title = dict["title"] as? String,
                      let startStr = dict["start"] as? String,
                      let endStr = dict["end"] as? String,
                      let start = parseDate(startStr),
                      let end = parseDate(endStr) else { continue }
                let allDay = (dict["allDay"] as? Bool) ?? false
                let colorHex = dict["colorHex"] as? String
                rawEvents.append(CalWidgetEvent(title: title, start: start, end: end, allDay: allDay, colorHex: colorHex))
            }
        }

        let dayFmt = DateFormatter(); dayFmt.dateFormat = "yyyy-MM-dd"

        var days: [CalendarDayData] = []
        for offset in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let dateStr = dayFmt.string(from: day)
            let dayEnd = cal.date(byAdding: .day, value: 1, to: day)!
            let eventsForDay = rawEvents
                .filter { $0.start < dayEnd && $0.end > day }
                .sorted { $0.start < $1.start }

            // Heute wird IMMER aufgenommen (auch ohne Termine), alle
            // folgenden Tage nur, wenn tatsächlich etwas eingetragen ist.
            if offset == 0 || !eventsForDay.isEmpty {
                days.append(CalendarDayData(
                    date: day, dateStr: dateStr,
                    shiftCode: shiftByDate[dateStr],
                    events: eventsForDay
                ))
            }
        }

        return CalendarWidgetTimelineEntry(date: Date(), days: days)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kleine dezente Dienst-Badge — bewusst unauffällig, nur zur Einordnung
// ─────────────────────────────────────────────────────────────────────────────

struct ShiftDezentBadge: View {
    let code: String
    var body: some View {
        Text(code)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundColor(Shield.textMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Shield.glassBorder, lineWidth: 0.6)
            )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// EVENT ROW — kompakte einzeilige Termin-Darstellung
// ─────────────────────────────────────────────────────────────────────────────

struct CalWidgetEventRow: View {
    let event: CalWidgetEvent
    let compact: Bool

    private var color: Color {
        guard let hex = event.colorHex else { return Shield.primary }
        return Color(hex: hex)
    }

    private var timeLabel: String {
        if event.allDay { return "ganztägig" }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: event.start)
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(event.title)
                .font(.system(size: compact ? 10.5 : 12, weight: .medium))
                .foregroundColor(Shield.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(timeLabel)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                .foregroundColor(Shield.textMuted)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET 1 — MEDIUM: heute links, nächste 2 Tage mit Terminen rechts
// ─────────────────────────────────────────────────────────────────────────────

struct CalendarNextDaysView: View {
    let entry: CalendarWidgetTimelineEntry

    private var today: CalendarDayData? { entry.days.first }
    private var upcoming: [CalendarDayData] { Array(entry.days.dropFirst().prefix(2)) }

    private func weekdayShort(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "EEE"
        return String(f.string(from: d).prefix(2)).uppercased()
    }
    private func dayNum(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "d"; return f.string(from: d)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // ── HEUTE ──────────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("HEUTE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Shield.primary)
                        .tracking(1.0)
                    if let s = today?.shiftCode { ShiftDezentBadge(code: s) }
                }
                if let t = today {
                    Text(dayNum(t.date))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(Shield.textPrimary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let t = today, !t.events.isEmpty {
                        ForEach(t.events.prefix(3)) { ev in
                            CalWidgetEventRow(event: ev, compact: true)
                        }
                    } else {
                        Text("Keine Termine")
                            .font(.system(size: 10.5))
                            .foregroundColor(Shield.textHint)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle().fill(Shield.glassBorder).frame(width: 0.6)

            // ── NÄCHSTE TAGE MIT TERMINEN ────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {
                if upcoming.isEmpty {
                    Text("Keine weiteren Termine")
                        .font(.system(size: 10.5))
                        .foregroundColor(Shield.textHint)
                } else {
                    ForEach(upcoming) { day in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(weekdayShort(day.date))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(Shield.textMuted)
                                Text(dayNum(day.date))
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(Shield.textPrimary)
                                if let s = day.shiftCode { ShiftDezentBadge(code: s) }
                            }
                            ForEach(day.events.prefix(2)) { ev in
                                CalWidgetEventRow(event: ev, compact: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .widgetURL(URL(string: "optimes://kalender"))
        .modifier(ShieldBackgroundModifier())
    }
}

struct CalendarNextDaysWidget: Widget {
    let kind: String = "CalendarNextDaysWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarWidgetProvider()) { entry in
            CalendarNextDaysView(entry: entry)
        }
        .configurationDisplayName("Kalender · Nächste Tage")
        .description("Zeigt heute und die nächsten Tage mit Terminen.")
        .supportedFamilies([.systemMedium])
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET 2 — LARGE: chronologische Liste, heute rot hervorgehoben
// ─────────────────────────────────────────────────────────────────────────────

struct CalendarChronoView: View {
    let entry: CalendarWidgetTimelineEntry

    private func headerLabel(_ day: CalendarDayData, isToday: Bool) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE")
        f.dateFormat = isToday ? "EEEE, d. MMMM" : "EEEE, d. MMM"
        return f.string(from: day.date).uppercased()
    }

    // NEU: Widgets unterstützen kein ScrollView (führte zum gelben
    // Fehler-Platzhalter) — feste Auswahl der ersten Tage stattdessen.
    private var visibleDays: [CalendarDayData] { Array(entry.days.prefix(6)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(visibleDays.enumerated()), id: \.element.id) { idx, day in
                let isToday = idx == 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(headerLabel(day, isToday: isToday))
                            .font(.system(size: isToday ? 11.5 : 10, weight: .bold))
                            .foregroundColor(isToday ? Color(hex: "#EF5B5B") : Shield.textMuted)
                            .tracking(0.6)
                        if let s = day.shiftCode { ShiftDezentBadge(code: s) }
                    }
                    if day.events.isEmpty {
                        Text("Keine Termine")
                            .font(.system(size: 11))
                            .foregroundColor(Shield.textHint)
                    } else {
                        ForEach(day.events.prefix(3)) { ev in
                            CalWidgetEventRow(event: ev, compact: false)
                        }
                    }
                }
                if idx < visibleDays.count - 1 {
                    Rectangle().fill(Shield.glassBorder).frame(height: 0.6)
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .widgetURL(URL(string: "optimes://kalender"))
        .modifier(ShieldBackgroundModifier())
    }
}

struct CalendarChronoWidget: Widget {
    let kind: String = "CalendarChronoWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarWidgetProvider()) { entry in
            CalendarChronoView(entry: entry)
        }
        .configurationDisplayName("Kalender · Übersicht")
        .description("Chronologische Übersicht kommender Termine.")
        .supportedFamilies([.systemLarge])
    }
}