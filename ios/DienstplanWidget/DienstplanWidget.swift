import WidgetKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// SHIELD LIQUID GLASS — Design Tokens
// Spiegelt AppSkin "shield" aus app_theme.dart
// ─────────────────────────────────────────────────────────────────────────────

private enum Shield {
    // Hintergründe
    static let bgBase    = Color(hex: "#0A0B0F")
    static let bgCard    = Color(hex: "#14161D")

    // Akzent
    static let primary   = Color(hex: "#2D6CFF")
    static let secondary = Color(hex: "#1746B8")

    // Dienst-Farben (identisch zu shiftColor() unten)
    static let neutral   = Color(hex: "#7A8699")   // U, DA, X
    static let danger    = Color(hex: "#EF5B5B")   // VK

    // Glas-Schichten
    static let glassBorder   = Color.white.opacity(0.10)
    static let glassHighCard = Color.white.opacity(0.06)
    static let glassTileAct  = Color(hex: "#2D6CFF").opacity(0.12)
    static let glassTileIdle = Color.white.opacity(0.04)

    // Text
    static let textPrimary = Color.white
    static let textMuted   = Color.white.opacity(0.35)
    static let textHint    = Color.white.opacity(0.20)
}

// Hex-Initializer für Color
private extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: h).scanHexInt64(&rgb)
        self.init(
            red:   Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >>  8) & 0xFF) / 255,
            blue:  Double( rgb        & 0xFF) / 255
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Datenmodell (unverändert)
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Provider (unverändert — nur loadEntry bleibt gleich)
// ─────────────────────────────────────────────────────────────────────────────

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> DienstplanTimelineEntry {
        DienstplanTimelineEntry(date: Date(), shifts: [
            ShiftEntry(date: "2026-06-18", shift: "F",  hasNote: false),
            ShiftEntry(date: "2026-06-19", shift: "P",  hasNote: false),
            ShiftEntry(date: "2026-06-20", shift: "U",  hasNote: false),
            ShiftEntry(date: "2026-06-21", shift: "P1", hasNote: false),
            ShiftEntry(date: "2026-06-22", shift: "DA", hasNote: false),
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (DienstplanTimelineEntry) -> Void) {
        UserDefaults(suiteName: "group.de.marcel.optimes")?.synchronize()
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DienstplanTimelineEntry>) -> Void) {
        UserDefaults(suiteName: "group.de.marcel.optimes")?.synchronize()
        let entry = loadEntry()
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadEntry() -> DienstplanTimelineEntry {
        let defaults = UserDefaults(suiteName: "group.de.marcel.optimes")
        let json     = defaults?.string(forKey: "schedule_entries") ?? "[]"
        let data     = json.data(using: .utf8) ?? Data()
        let decoded  = (try? JSONSerialization.jsonObject(with: data) as? [[String: String]]) ?? []
        let fmt      = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let today    = Calendar.current.startOfDay(for: Date())

        let filtered = decoded
            .compactMap { dict -> ShiftEntry? in
                guard let dateStr = dict["date"],
                      let shift   = dict["shift"],
                      let d       = fmt.date(from: dateStr),
                      d >= today else { return nil }
                return ShiftEntry(date: dateStr, shift: shift, hasNote: dict["hasNote"] == "true")
            }
            .sorted { $0.date < $1.date }

        return DienstplanTimelineEntry(date: Date(), shifts: filtered)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hilfsfunktion: Dienstfarbe (Shield-Palette)
// ─────────────────────────────────────────────────────────────────────────────

private func shiftColor(_ shift: String) -> Color {
    switch shift.uppercased() {
    case "U", "DA", "X": return Shield.neutral
    case "VK":           return Shield.danger
    default:             return Shield.primary
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// DayTile — Glass-Kachel (Medium & Large)
// ─────────────────────────────────────────────────────────────────────────────

struct DayTile: View {
    let entry:   ShiftEntry
    let isToday: Bool

    // ── Wochentag-Kürzel (de) ─────────────────────────────────────────
    private var dayName: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale     = Locale(identifier: "de_DE")
        guard let d = fmt.date(from: entry.date) else { return "" }
        let df = DateFormatter()
        df.locale     = Locale(identifier: "de_DE")
        df.dateFormat = "EEE"
        return String(df.string(from: d).prefix(2)).uppercased()
    }

    private var dayNum: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: entry.date) else { return "" }
        let df = DateFormatter(); df.dateFormat = "dd"
        return df.string(from: d)
    }

    var body: some View {
        let color   = shiftColor(entry.shift)
        let isEmpty = entry.shift.isEmpty

        ZStack {
            // ── Hintergrund-Schicht ──────────────────────────────────
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday
                    ? color.opacity(0.85)                  // aktiver Tag: volle Akzentfarbe
                    : (isEmpty
                        ? Shield.glassTileIdle             // kein Dienst: dunkel & leer
                        : Shield.glassTileAct))            // Dienst vorhanden: Akzent-Tint

            // ── Border-Schicht (Liquid-Glass-Kante) ──────────────────
            RoundedRectangle(cornerRadius: 10)
                .stroke(isToday
                    ? Color.clear
                    : (isEmpty
                        ? Shield.glassBorder               // subtile weiße Linie
                        : color.opacity(0.28)),            // farbige Kante bei Dienst
                    lineWidth: 1)

            // ── Inhalt ───────────────────────────────────────────────
            VStack(spacing: 2) {
                Text(dayName)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(isToday
                        ? .white.opacity(0.75)
                        : Shield.textMuted)

                Text(dayNum)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(isToday ? .white : Shield.textPrimary)

                Text(isEmpty ? "–" : entry.shift)
                    .font(.system(size: 13, weight: .heavy))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundColor(isToday
                        ? .white
                        : (isEmpty ? Shield.textHint : color))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL WIDGET — Schnellstart Fahrtenbuch
// ─────────────────────────────────────────────────────────────────────────────

   struct SmallWidgetView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {

            // ── Straße (rein SwiftUI) ─────────────────────────────
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                let cx = w / 2

                ZStack {
                    // Horizont-Glühen
                    RadialGradient(
                        colors: [
                            Color(hex: "#4488FF").opacity(0.55),
                            Color(hex: "#1A3A8A").opacity(0.25),
                            Color.clear
                        ],
                        center: UnitPoint(x: 0.5, y: 0.28),
                        startRadius: 0,
                        endRadius: h * 0.65
                    )

                    // Straßen-Fläche
                    Path { p in
                        p.move(to: CGPoint(x: cx - 8, y: h * 0.42))
                        p.addLine(to: CGPoint(x: cx + 8, y: h * 0.42))
                        p.addLine(to: CGPoint(x: w * 0.92, y: h))
                        p.addLine(to: CGPoint(x: w * 0.08, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "#0D1B4B").opacity(0.0),
                                Color(hex: "#0D1B4B").opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    // Linke Straßenlinie
                    Path { p in
                        p.move(to: CGPoint(x: cx - 6, y: h * 0.42))
                        p.addLine(to: CGPoint(x: w * 0.14, y: h))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Shield.primary.opacity(0.9), Shield.primary.opacity(0.2)],
                            startPoint: .bottom, endPoint: .top
                        ),
                        lineWidth: 1.2
                    )

                    // Rechte Straßenlinie
                    Path { p in
                        p.move(to: CGPoint(x: cx + 6, y: h * 0.42))
                        p.addLine(to: CGPoint(x: w * 0.86, y: h))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Shield.primary.opacity(0.9), Shield.primary.opacity(0.2)],
                            startPoint: .bottom, endPoint: .top
                        ),
                        lineWidth: 1.2
                    )

                    // Mittellinie (gestrichelt)
                    Path { p in
                        let segments = 6
                        for i in 0..<segments {
                            let t0 = Double(i) / Double(segments)
                            let t1 = t0 + 0.042
                            let y0 = h * 0.44 + CGFloat(t0) * h * 0.56
                            let y1 = h * 0.44 + CGFloat(t1) * h * 0.56
                            let spread = CGFloat(t0) * 5.0
                            p.move(to: CGPoint(x: cx - spread, y: y0))
                            p.addLine(to: CGPoint(x: cx + spread, y: y0))
                            p.move(to: CGPoint(x: cx - spread, y: y1 - 2))
                            p.addLine(to: CGPoint(x: cx + spread, y: y1 - 2))
                        }
                    }
                    .stroke(Shield.primary.opacity(0.7), lineWidth: 1.5)

                    // Diagonale Licht-Streifen oben links
                    Path { p in
                        p.move(to: CGPoint(x: -10, y: h * 0.05))
                        p.addLine(to: CGPoint(x: w * 0.65, y: h * 0.30))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.clear, Shield.primary.opacity(0.45), Color.clear],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        lineWidth: 2.5
                    )

                    Path { p in
                        p.move(to: CGPoint(x: -10, y: h * 0.10))
                        p.addLine(to: CGPoint(x: w * 0.55, y: h * 0.28))
                    }
                    .stroke(
                        LinearGradient(
                            colors: [Color.clear, Shield.primary.opacity(0.22), Color.clear],
                            startPoint: .leading, endPoint: .trailing
                        ),
                        lineWidth: 1.2
                    )
                }
            }

            // ── Unterer Schatten-Gradient für Text-Lesbarkeit ─────
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.75)],
                startPoint: UnitPoint(x: 0.5, y: 0.35),
                endPoint: .bottom
            )

            // ── Inhalt unten links ────────────────────────────────
            VStack(alignment: .leading, spacing: 4) {

                // Auto-Icon mit Scan-Rahmen
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Shield.primary.opacity(0.8), lineWidth: 1.5)
                        .frame(width: 36, height: 36)

                    // Scan-Ecken
                    ScanCorners(size: 36, color: Shield.primary)

                    Image(systemName: "car.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Shield.primary)
                }

                Spacer().frame(height: 2)

                Text("Fahrt\nstarten")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineSpacing(1)

                Text("KM SCANNEN")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Shield.primary)
                    .tracking(1.5)

                // Unterstrich-Akzent
                Rectangle()
                    .fill(Shield.primary.opacity(0.7))
                    .frame(width: 28, height: 1.5)
                    .cornerRadius(1)
            }
            .padding(.leading, 12)
            .padding(.bottom, 14)
        }
        .widgetURL(URL(string: "optimes://fahrtenbuch/neue-fahrt/scan-km-start"))
        .modifier(SmallBackgroundModifier())
    }
}

// Scan-Ecken Helper
struct ScanCorners: View {
    let size: CGFloat
    let color: Color
    private let len: CGFloat = 8
    private let thick: CGFloat = 2

    var body: some View {
        ZStack {
            // oben links
            Path { p in
                p.move(to: CGPoint(x: 0, y: len))
                p.addLine(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: len, y: 0))
            }.stroke(color, lineWidth: thick)
            // oben rechts
            Path { p in
                p.move(to: CGPoint(x: size - len, y: 0))
                p.addLine(to: CGPoint(x: size, y: 0))
                p.addLine(to: CGPoint(x: size, y: len))
            }.stroke(color, lineWidth: thick)
            // unten links
            Path { p in
                p.move(to: CGPoint(x: 0, y: size - len))
                p.addLine(to: CGPoint(x: 0, y: size))
                p.addLine(to: CGPoint(x: len, y: size))
            }.stroke(color, lineWidth: thick)
            // unten rechts
            Path { p in
                p.move(to: CGPoint(x: size - len, y: size))
                p.addLine(to: CGPoint(x: size, y: size))
                p.addLine(to: CGPoint(x: size, y: size - len))
            }.stroke(color, lineWidth: thick)
        }
        .frame(width: size, height: size)
    }
}

struct SmallBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(hex: "#0A0B0F")
            }
        } else {
            content.background(Color(hex: "#0A0B0F"))
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEDIUM WIDGET — Nächste 7 Tage
// ─────────────────────────────────────────────────────────────────────────────

struct MediumWidgetView: View {
    let entry:    DienstplanTimelineEntry
    let todayStr: String

    private var visible: [ShiftEntry] { Array(entry.shifts.prefix(7)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ── Header ───────────────────────────────────────────────
            HStack {
                Text("DIENSTPLAN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Shield.primary)
                    .tracking(1.2)

                Spacer()

                Text(weekLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Shield.textMuted)
            }

            if visible.isEmpty {
                // Leerzustand
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "calendar.badge.exclamationmark")
                            .foregroundColor(Shield.textMuted)
                        Text("Kein Dienstplan")
                            .font(.caption)
                            .foregroundColor(Shield.textMuted)
                    }
                    Spacer()
                }
            } else {
                // ── 7 Kacheln ────────────────────────────────────────
                HStack(spacing: 4) {
                    ForEach(visible) { s in
                        DayTile(entry: s, isToday: s.date == todayStr)
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14))
        .widgetURL(URL(string: "optimes://dienstplan"))
    }

    private var weekLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        guard let first = visible.first, let d = fmt.date(from: first.date) else { return "" }
        let cal = Calendar.current
        let kw  = cal.component(.weekOfYear, from: d)
        return "KW \(kw)"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// LARGE WIDGET — 4-Wochen-Kalender
// ─────────────────────────────────────────────────────────────────────────────

struct LargeWidgetView: View {
    let entry:    DienstplanTimelineEntry
    let todayStr: String

    private var today: Date { Calendar.current.startOfDay(for: Date()) }

    private var shiftDict: [String: String] {
        Dictionary(uniqueKeysWithValues: entry.shifts.map { ($0.date, $0.shift) })
    }

    // ISO-Kalender: 4 Wochen ab dieser Montag
    private var weeks: [[Date]] {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        let thisMonday = cal.date(
            from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: today))!
        return (0..<4).map { wOffset in
            let monday = cal.date(byAdding: .weekOfYear, value: wOffset, to: thisMonday)!
            return (0..<7).map { dOffset in
                cal.date(byAdding: .day, value: dOffset, to: monday)!
            }
        }
    }

    private let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ── Header ───────────────────────────────────────────────
            HStack {
                Text("DIENSTPLAN")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Shield.primary)
                    .tracking(1.2)
                Spacer()
                Text(monthRangeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Shield.textMuted)
            }

            // ── 4 Wochen ─────────────────────────────────────────────
            ForEach(0..<weeks.count, id: \.self) { wi in
                let weekDates = weeks[wi]

                // Monatsgrenze: dünne Trennlinie
                if wi > 0 {
                    let prevLast  = weeks[wi - 1].last!
                    let thisFirst = weekDates.first!
                    if Calendar.current.component(.month, from: thisFirst) !=
                       Calendar.current.component(.month, from: prevLast) {
                        // Trennlinie mit Verlauf (simuliert glasige Tiefe)
                        Rectangle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.clear,
                                             Shield.primary.opacity(0.35),
                                             Color.clear],
                                    startPoint: .leading,
                                    endPoint:   .trailing
                                )
                            )
                            .frame(height: 1)
                            .padding(.vertical, 2)
                    }
                }

                // Wochenzeile
                HStack(spacing: 3) {
                    ForEach(weekDates, id: \.self) { date in
                        let dateStr     = fmt.string(from: date)
                        let shift       = shiftDict[dateStr] ?? ""
                        let isToday     = dateStr == todayStr
                        let isPast      = date < today
                        let isFirstOfMonth = Calendar.current.component(.day, from: date) == 1

                        DayTile(
                            entry: ShiftEntry(date: dateStr, shift: shift, hasNote: false),
                            isToday: isToday
                        )
                        // Vergangene Tage ohne Eintrag: stark ausgeblendet
                        .opacity(isPast && shift.isEmpty ? 0.25 : 1.0)
                        // Erster des Monats: blauer Ring-Akzent
                        .overlay(
                            isFirstOfMonth && !isToday
                            ? RoundedRectangle(cornerRadius: 10)
                                .stroke(Shield.primary.opacity(0.55), lineWidth: 1.5)
                            : nil
                        )
                    }
                }
            }
        }
        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
        .widgetURL(URL(string: "optimes://dienstplan"))
    }

    private var monthRangeLabel: String {
        let allDates = weeks.flatMap { $0 }
        guard let first = allDates.first, let last = allDates.last else { return "" }
        let mf = DateFormatter(); mf.dateFormat = "MMM"; mf.locale = Locale(identifier: "de_DE")
        let yf = DateFormatter(); yf.dateFormat = "yyyy"
        let m1 = mf.string(from: first).capitalized
        let m2 = mf.string(from: last).capitalized
        let y  = yf.string(from: first)
        return m1 == m2 ? "\(m1) \(y)" : "\(m1) / \(m2) \(y)"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Haupt-View — Router für die drei Größen
// ─────────────────────────────────────────────────────────────────────────────

struct DienstplanWidgetView: View {
    var entry: DienstplanTimelineEntry
    @Environment(\.widgetFamily) var family

    private var todayStr: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    var body: some View {
    Group {
        switch family {
        case .systemSmall:
    SmallWidgetView()

        case .systemMedium:
            MediumWidgetView(entry: entry, todayStr: todayStr)
                .modifier(ShieldBackgroundModifier())

        case .systemLarge:
            LargeWidgetView(entry: entry, todayStr: todayStr)
                .modifier(ShieldBackgroundModifier())

        default:
            MediumWidgetView(entry: entry, todayStr: todayStr)
                .modifier(ShieldBackgroundModifier())
        }
    }
   } // ← .modifier weg von hier
}

// ─────────────────────────────────────────────────────────────────────────────
// Hintergrund-Modifier — Shield bgBase + Glasrand oben
// Ersetzt WidgetBackgroundModifier
// ─────────────────────────────────────────────────────────────────────────────

struct ShieldBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                ZStack(alignment: .top) {
                    // Basis: tiefes Dunkel
                    Shield.bgBase

                    // Obere Glas-Schimmer-Schicht (simuliert BackdropFilter)
                    LinearGradient(
                        colors: [Shield.primary.opacity(0.10), Color.clear],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                    .frame(height: 80)
                }
            }
        } else {
            content.background(
                ZStack(alignment: .top) {
                    Shield.bgBase
                    LinearGradient(
                        colors: [Shield.primary.opacity(0.10), Color.clear],
                        startPoint: .top,
                        endPoint:   .bottom
                    )
                    .frame(height: 80)
                }
            )
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget-Definition (unverändert)
// ─────────────────────────────────────────────────────────────────────────────

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