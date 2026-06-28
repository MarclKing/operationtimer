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
    
    func blendedDim() -> Color {
        Color(hex: "#1B1E2A")
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
// SMALL WIDGET — Fahrtenbuch KM-Scan Schnellstart
// Tacho-Design mit Punkt-Skala und Nadel
// ─────────────────────────────────────────────────────────────────────────────

struct SmallWidgetView: View {
    var progress: Double = 0.36   // 0.0 – 1.0, aus echten KM-Daten

    // ── Tacho-Geometrie ─────────────────────────────────────────────
    // 0° = rechts (3 Uhr), Uhrzeigersinn
    // Lücke unten: 225° bis 315° (kurzer Weg = 90°)
    // Arc läuft:   225° → 315° (langer Weg = 270°, sweep=1)
    private let startDeg: Double = 225
    private let sweepDeg: Double = 270

    private var endDeg: Double { startDeg + sweepDeg * progress }

    // Polar → kartesisch, center-relativ
    private func pt(angleDeg: Double, r: CGFloat, cx: CGFloat, cy: CGFloat) -> CGPoint {
        let rad = angleDeg * .pi / 180
        return CGPoint(x: cx + r * cos(rad), y: cy + r * sin(rad))
    }

    var body: some View {
        Canvas { context, size in
            let cx = size.width  / 2
            let cy = size.height / 2
            let r: CGFloat   = min(size.width, size.height) * 0.41   // Ring-Radius

            // ── Innerer Kreis (Tiefe) ────────────────────────────────
            let innerCircle = Path(ellipseIn: CGRect(
                x: cx - r * 0.85, y: cy - r * 0.85,
                width: r * 1.70,  height: r * 1.70))
            context.fill(innerCircle, with: .color(Color(hex: "#1c1f2e")))

            // ── Basis-Ring (grau, volle 270°) ────────────────────────
            var basePath = Path()
            basePath.addArc(
                center:     CGPoint(x: cx, y: cy),
                radius:     r,
                startAngle: .degrees(startDeg),
                endAngle:   .degrees(startDeg + sweepDeg),
                clockwise:  false)
            context.stroke(basePath,
                with: .color(Color(hex: "#1e2540")),
                style: StrokeStyle(lineWidth: 3, lineCap: .butt))

            // ── Ticks ────────────────────────────────────────────────
            let majorAngles: [Double] = stride(
                from: startDeg, through: startDeg + sweepDeg, by: 30).map { $0 }
            for angleDeg in majorAngles {
                let outer = pt(angleDeg: angleDeg, r: r,        cx: cx, cy: cy)
                let inner = pt(angleDeg: angleDeg, r: r - 14,   cx: cx, cy: cy)
                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(tick,
                    with: .color(.white.opacity(0.22)),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            let minorAngles: [Double] = stride(
                from: startDeg + 10, to: startDeg + sweepDeg, by: 10)
                .filter { !majorAngles.contains($0) }
            for angleDeg in minorAngles {
                let outer = pt(angleDeg: angleDeg, r: r,        cx: cx, cy: cy)
                let inner = pt(angleDeg: angleDeg, r: r - 8,    cx: cx, cy: cy)
                var tick = Path()
                tick.move(to: outer)
                tick.addLine(to: inner)
                context.stroke(tick,
                    with: .color(.white.opacity(0.10)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round))
            }

            // ── Progress-Arc ─────────────────────────────────────────
            // endDeg ist der EINZIGE Wert — Arc, Leuchtdot und Nadel
            // teilen sich dieselbe Berechnung, kein Drift möglich.
            guard progress > 0 else { return }

            var arcPath = Path()
            arcPath.addArc(
                center:     CGPoint(x: cx, y: cy),
                radius:     r,
                startAngle: .degrees(startDeg),
                endAngle:   .degrees(endDeg),
                clockwise:  false)

            // Glow-Schicht
            context.stroke(arcPath,
                with: .color(Color(hex: "#2D6CFF").opacity(0.30)),
                style: StrokeStyle(lineWidth: 10, lineCap: .round))

            // Haupt-Arc (hellblau)
            context.stroke(arcPath,
                with: .color(Color(hex: "#6BAAFF")),
                style: StrokeStyle(lineWidth: 3.2, lineCap: .round))

            // Heller Kern-Strich
            context.stroke(arcPath,
                with: .color(Color(hex: "#A8CBFF")),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

            // ── Arc-Endpunkt Leuchtdot ────────────────────────────────
            // Dieselbe pt()-Funktion mit endDeg → sitzt exakt auf Arc-Ende
            let arcEnd = pt(angleDeg: endDeg, r: r, cx: cx, cy: cy)

            // Äußerer Glow
            context.fill(Path(ellipseIn: CGRect(
                x: arcEnd.x - 8, y: arcEnd.y - 8, width: 16, height: 16)),
                with: .color(Color(hex: "#2D6CFF").opacity(0.35)))
            // Weißer Dot
            context.fill(Path(ellipseIn: CGRect(
                x: arcEnd.x - 3, y: arcEnd.y - 3, width: 6, height: 6)),
                with: .color(.white))

            // ── Nadel ─────────────────────────────────────────────────
            // Spitze = arcEnd (gleiche Koordinate!)
            // Basis  = pt mit kleinerem Radius nahe Zentrum
            let needleBase = pt(angleDeg: endDeg, r: r * 0.17, cx: cx, cy: cy)

            var needle = Path()
            needle.move(to: needleBase)
            needle.addLine(to: arcEnd)

            // Glow
            context.stroke(needle,
                with: .color(.white.opacity(0.15)),
                style: StrokeStyle(lineWidth: 6, lineCap: .round))
            // Weiß
            context.stroke(needle,
                with: .color(.white),
                style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            // Blauer Kern
            context.stroke(needle,
                with: .color(Color(hex: "#7AB4FF")),
                style: StrokeStyle(lineWidth: 1.0, lineCap: .round))

            // ── Pivot-Ring ────────────────────────────────────────────
            context.fill(Path(ellipseIn: CGRect(
                x: cx - 6, y: cy - 6, width: 12, height: 12)),
                with: .color(Color(hex: "#0d0f18")))
            context.stroke(Path(ellipseIn: CGRect(
                x: cx - 6, y: cy - 6, width: 12, height: 12)),
                with: .color(Color(hex: "#2D6CFF").opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.5))
            context.fill(Path(ellipseIn: CGRect(
                x: cx - 2.5, y: cy - 2.5, width: 5, height: 5)),
                with: .color(Color(hex: "#2D6CFF").opacity(0.8)))
        }
        .overlay(alignment: .center) {
            VStack(spacing: 0) {
                Image(systemName: "car.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundColor(.white)

                Spacer().frame(height: 14)

                Text("Fahrt starten")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Text("KM scannen")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#5A8CFF"))
            }
            .offset(y: 22)
        }
        .widgetURL(URL(string: "optimes://fahrtenbuch/neue-fahrt/scan-km-start"))
        .modifier(SmallBackgroundModifier())
    }
}

    // ── Hilfsfunktionen (unverändert) ──────────────────────────────────────

    private func drawTick(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                           angleDeg: Double, innerR: CGFloat, outerR: CGFloat,
                           color: Color, lineWidth: CGFloat) {
        let rad = angleDeg * .pi / 180
        let inner = CGPoint(x: cx + innerR * cos(rad), y: cy + innerR * sin(rad))
        let outer = CGPoint(x: cx + outerR * cos(rad), y: cy + outerR * sin(rad))
        var path = Path()
        path.move(to: inner)
        path.addLine(to: outer)
        context.stroke(path, with: .color(color),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
    }

    private func drawDot(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                          angleDeg: Double, radius: CGFloat, size: CGFloat,
                          color: Color, glow: Bool) {
        let rad = angleDeg * .pi / 180
        let point = CGPoint(x: cx + radius * cos(rad), y: cy + radius * sin(rad))
        let rect = CGRect(x: point.x - size, y: point.y - size,
                           width: size * 2, height: size * 2)
        if glow {
            context.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)),
                          with: .color(color.opacity(0.35)))
        }
        context.fill(Path(ellipseIn: rect), with: .color(color))
    }

    private func drawLabel(context: GraphicsContext, cx: CGFloat, cy: CGFloat,
                            r: CGFloat, angleDeg: Double, text: String,
                            radiusOffset: CGFloat) {
        let rad = angleDeg * .pi / 180
        let labelR = r - radiusOffset
        let point = CGPoint(x: cx + labelR * cos(rad), y: cy + labelR * sin(rad))
        context.draw(
            Text(text)
                .font(.system(size: 8.5, weight: .regular))
                .foregroundColor(Shield.secondary.opacity(0.8)),
            at: point
        )
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
                        // Trennlinie mit Verlauf
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
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hintergrund-Modifier — Shield bgBase + Glasrand oben
// ─────────────────────────────────────────────────────────────────────────────

struct ShieldBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                ZStack(alignment: .top) {
                    // Basis: tiefes Dunkel
                    Shield.bgBase

                    // Obere Glas-Schimmer-Schicht
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
// Widget-Definition
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