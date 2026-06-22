// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v7 — Zwei definierte Eingabe-Muster, bombensicher
//
// Unterstützte Phrasen:
//
//   MUSTER 1 — "Füge-Muster":
//     "Füge die Aufgabe [TITEL] hinzu"
//     "Füge die Aufgabe [TITEL] mit Frist [DATUM] [UHRZEIT] hinzu"
//     "Füge die Aufgabe [TITEL] für [DATUM] [UHRZEIT] hinzu"
//     → Varianten: Füge/Füg/Trage/Trag/Ergänze/Neue Aufgabe/Task/Todo
//     → TITEL wird 1:1 übernommen (kein Kompositum-Mapping).
//     → Frist nur erkannt wenn explizit "mit Frist ..." oder "für ..." folgt.
//
//   MUSTER 2 — "Erinnere-Muster":
//     "Erinnere mich an: [TITEL]"
//     "Erinnere mich am [DATUM] um [UHRZEIT] an: [TITEL]"
//     → Alles zwischen "mich" und "an:" = optionales Datum/Uhrzeit-Fenster.
//     → Alles nach "an:" = Titel, wird 1:1 übernommen.
//
//   DRINGEND:
//     Wenn das Wort "dringend" (oder "DRINGEND:") irgendwo im Satz vorkommt
//     → priority = TaskPriority.urgent, Wort wird aus Titel entfernt.
//
// v2 Erweiterungen:
//   - Relative Datumsausdrücke: "morgen früh", "heute abend", "am Wochenende", "nächsten Monat"
//   - "in X Wochen/Monaten" Unterstützung
//   - _nextWeekday Hilfsfunktion
// ─────────────────────────────────────────────────────────────────────────────

class ParsedSpokenTask {
  final String title;
  final DateTime? date;
  final DateTimeComponents? time;
  final DateTimeComponents? endTime;
  final RecurrenceRule? recurrence;
  final TaskPriority priority;
  final Duration? estimatedDuration;
  final String rawText;

  const ParsedSpokenTask({
    required this.title,
    required this.rawText,
    this.date,
    this.time,
    this.endTime,
    this.recurrence,
    this.priority = TaskPriority.normal,
    this.estimatedDuration,
  });

  DateTime? get combinedDateTime {
    if (date == null && time == null) return null;
    final d = date ?? DateTime.now();
    if (time == null) return DateTime(d.year, d.month, d.day);
    return DateTime(d.year, d.month, d.day, time!.hour, time!.minute);
  }

  bool get hasTime => time != null;
  bool get isUrgent => priority == TaskPriority.urgent;
}

enum TaskPriority { normal, urgent }

class DateTimeComponents {
  final int hour;
  final int minute;
  const DateTimeComponents(this.hour, this.minute);

  @override
  String toString() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class RecurrenceRule {
  final RecurrenceFrequency frequency;
  final int? weekday;
  const RecurrenceRule(this.frequency, {this.weekday});
}

enum RecurrenceFrequency { daily, weekly, monthly }

// ─────────────────────────────────────────────────────────────────────────────
// Interne Hilfsklassen
// ─────────────────────────────────────────────────────────────────────────────

class _Span {
  final int start;
  final int end;
  const _Span(this.start, this.end);
}

class _TimeResult {
  final int hour;
  final int minute;
  final _Span span;
  final int? endHour;
  final int? endMinute;
  const _TimeResult(this.hour, this.minute, this.span,
      {this.endHour, this.endMinute});
}

class _DateTimeWindow {
  final DateTime? date;
  final DateTimeComponents? time;

  const _DateTimeWindow({this.date, this.time});
  bool get hasAnything => date != null || time != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// PARSER
// ─────────────────────────────────────────────────────────────────────────────

class SpokenTaskParser {
  SpokenTaskParser._();

  // ── Zahlwörter ──────────────────────────────────────────────────────────────

  static final Map<String, int> _numberWords = _buildNumberWords();

  static Map<String, int> _buildNumberWords() {
    final ones = {
      'null': 0,
      'ein': 1,
      'eins': 1,
      'eine': 1,
      'zwei': 2,
      'drei': 3,
      'vier': 4,
      'fünf': 5,
      'sechs': 6,
      'sieben': 7,
      'acht': 8,
      'neun': 9,
      'zehn': 10,
      'elf': 11,
      'zwölf': 12,
      'dreizehn': 13,
      'vierzehn': 14,
      'fünfzehn': 15,
      'sechzehn': 16,
      'siebzehn': 17,
      'achtzehn': 18,
      'neunzehn': 19,
    };
    final tens = {
      'zwanzig': 20,
      'dreißig': 30,
      'vierzig': 40,
      'fünfzig': 50,
    };
    final onesForCompound = {
      1: 'ein',
      2: 'zwei',
      3: 'drei',
      4: 'vier',
      5: 'fünf',
      6: 'sechs',
      7: 'sieben',
      8: 'acht',
      9: 'neun',
    };
    final words = <String, int>{};
    words.addAll(ones);
    for (final entry in tens.entries) {
      words[entry.key] = entry.value;
      for (final val in onesForCompound.keys) {
        final ow = onesForCompound[val]!;
        words['$ow${entry.key}'] = entry.value + val;
        words['${ow}und${entry.key}'] = entry.value + val;
      }
    }
    return words;
  }

  static int? _toNum(String token) {
    final t = token.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(t)) return int.parse(t);
    return _numberWords[t];
  }

  static String get _numTok {
    final keys = _numberWords.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    return r'\d{1,2}|' + keys.map(RegExp.escape).join('|');
  }

  // ── Wochentage ──────────────────────────────────────────────────────────────
  static const Map<String, int> _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonnabend': DateTime.saturday,
    'sonntag': DateTime.sunday,
  };

  // ── Monate ──────────────────────────────────────────────────────────────────
  static const Map<String, int> _months = {
    'januar': 1, 'jan': 1, 'jan.': 1,
    'februar': 2, 'feb': 2, 'feb.': 2,
    'märz': 3, 'maerz': 3, 'mär': 3, 'mär.': 3,
    'april': 4, 'apr': 4, 'apr.': 4,
    'mai': 5,
    'juni': 6, 'jun': 6, 'jun.': 6,
    'juli': 7, 'jul': 7, 'jul.': 7,
    'august': 8, 'aug': 8, 'aug.': 8,
    'september': 9, 'sep': 9, 'sep.': 9, 'sept': 9,
    'oktober': 10, 'okt': 10, 'okt.': 10,
    'november': 11, 'nov': 11, 'nov.': 11,
    'dezember': 12, 'dez': 12, 'dez.': 12,
  };

  // ─────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ─────────────────────────────────────────────────────────────────────────

  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();

    // ── Dringend-Flag: VOR allem anderen prüfen und aus dem Text entfernen ──
    final urgentRx = RegExp(
      r'\bdringend[:\s]*',
      caseSensitive: false,
    );
    final isUrgent = urgentRx.hasMatch(original);
    // Für weiteres Parsen das "dringend" rauswerfen
    final cleaned = original.replaceAll(urgentRx, '').replaceAll(RegExp(r'\s+'), ' ').trim();

    // ── Muster 2 zuerst: "Erinnere mich ... an: TITEL" ──────────────────────
    // Spezifischer Marker "an:" macht dieses Muster eindeutig → höchste Prio.
    final erinnereResult = _tryParseErinnere(cleaned, original);
    if (erinnereResult != null) {
      return ParsedSpokenTask(
        title: erinnereResult.title,
        rawText: original,
        date: erinnereResult.date,
        time: erinnereResult.time,
        priority: isUrgent ? TaskPriority.urgent : TaskPriority.normal,
      );
    }

    // ── Muster 1: "Füge die Aufgabe TITEL hinzu" ─────────────────────────────
    final fuegeResult = _tryParseFuege(cleaned, original);
    if (fuegeResult != null) {
      return ParsedSpokenTask(
        title: fuegeResult.title,
        rawText: original,
        date: fuegeResult.date,
        time: fuegeResult.time,
        priority: isUrgent ? TaskPriority.urgent : TaskPriority.normal,
      );
    }

    // ── Fallback: gesamten (bereinigten) Text als Titel übernehmen ───────────
    // Kein bekanntes Muster → Titel = gesamter Text, kein Datum.
    final fallbackTitle = _capitalizeFirst(cleaned);
    return ParsedSpokenTask(
      title: fallbackTitle.isEmpty ? original : fallbackTitle,
      rawText: original,
      priority: isUrgent ? TaskPriority.urgent : TaskPriority.normal,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 2 — "Erinnere mich [am DATUM um UHRZEIT] an: TITEL"
  //
  // Satzbau:
  //   "Erinnere mich an: Auto waschen"
  //   "Erinnere mich am 23.10. um 18:30 Uhr an: Auto waschen"
  //   "Erinnere mich morgen um 9 Uhr an: Zahnarzt"
  //
  // Regel:
  //   - Trigger: "erinnere mich" am Anfang
  //   - Trennmarker: "an:" (mit Doppelpunkt) = Ende des Datum/Zeit-Fensters
  //   - Alles NACH "an:" = Titel (1:1, nur trim + Großschreibung)
  //   - Alles ZWISCHEN "mich " und "an:" = optionales Datum/Uhrzeit-Fenster
  // ─────────────────────────────────────────────────────────────────────────

  static _ParseResult? _tryParseErinnere(String cleaned, String original) {
    // Trigger: beginnt mit "erinnere mich"
    final triggerRx = RegExp(r'^erinnere\s+mich\s+', caseSensitive: false);
    final triggerM = triggerRx.firstMatch(cleaned);
    if (triggerM == null) return null;

    final afterTrigger = cleaned.substring(triggerM.end);

    // Suche nach "an:" als hartem Trennmarker
    // Auch "an :" mit Leerzeichen tolerieren
    final markerWithColonRx = RegExp(r'\ban\s*:\s*', caseSensitive: false);
    final markerBareRx = RegExp(r'\ban\s+', caseSensitive: false);

    String? titleRaw;
    String? dateTimeWindow;

    final markerM = markerWithColonRx.firstMatch(afterTrigger) 
                   ?? markerBareRx.allMatches(afterTrigger).lastOrNull;

    if (markerM != null) {
      dateTimeWindow = afterTrigger.substring(0, markerM.start).trim();
      titleRaw = afterTrigger.substring(markerM.end).trim();
    } else {
      return null;
    }

    if (titleRaw == null || titleRaw.isEmpty) return null;

    // Datum/Zeit aus dem Fenster extrahieren (falls vorhanden)
    _DateTimeWindow dtw = const _DateTimeWindow();
    if (dateTimeWindow != null && dateTimeWindow.isNotEmpty) {
      dtw = _extractDateTimeFromWindow(dateTimeWindow);
    }

    return _ParseResult(
      title: _capitalizeFirst(titleRaw),
      date: dtw.date,
      time: dtw.time,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 1 — "Füge die Aufgabe TITEL [mit Frist / für DATUM UHRZEIT] hinzu"
  //
  // Satzbau:
  //   "Füge die Aufgabe Auto Liste hinzu"
  //   "Füge die Aufgabe Marcel schreiben für 23.10. 15 Uhr hinzu"
  //   "Füge die Aufgabe Dienstplan erstellen mit Frist 15.3. 9 Uhr hinzu"
  //
  // Trigger-Varianten (alle gleichwertig):
  //   Füge [die] [Aufgabe/Task/Todo/Erinnerung] ...
  //   Füg [die] [Aufgabe/...] ...
  //   Trage [die] [Aufgabe/...] ... ein
  //   Trag [die] [Aufgabe/...] ... ein
  //   Ergänze [die] [Aufgabe/...] ...
  //   Neue Aufgabe: ...
  //   Todo: ...
  //   Task: ...
  //
  // Frist-Einleiter (MUSS explizit da stehen, sonst kein Datum):
  //   "mit Frist [DATUM] [UHRZEIT]"
  //   "für [DATUM] [UHRZEIT]"
  //
  // Abschluss-Wörter (werden ignoriert/entfernt):
  //   "hinzu", "ein", "hinzufügen", "eintragen"
  // ─────────────────────────────────────────────────────────────────────────

  static _ParseResult? _tryParseFuege(String cleaned, String original) {
    // ── Trigger-Pattern ──────────────────────────────────────────────────────
    // Matcht alle Varianten und entfernt den Befehlsteil am Anfang.
    final triggerRx = RegExp(
      r'^(?:'
      // "Füge [die/eine] [Aufgabe/Task/Todo/Erinnerung] [die/eine]"
      r'(?:füg|füge|trage?|ergänze?)\s+(?:(?:die|eine?|meine)\s+)?(?:aufgabe|task|todo|erinnerung|notiz)?\s*(?:(?:die|eine?)\s+)?'
      r'|'
      // "Neue Aufgabe:" / "Neuer Task:"
      r'neue?\s+(?:aufgabe|task|todo|erinnerung)\s*[:\-]?\s*'
      r'|'
      // "Todo:" / "Task:" / "Aufgabe:"
      r'(?:todo|task|aufgabe|notiz)\s*[:\-]\s*'
      r')',
      caseSensitive: false,
    );

    final triggerM = triggerRx.firstMatch(cleaned);
    if (triggerM == null) return null;

    String rest = cleaned.substring(triggerM.end).trim();

    // ── Abschluss-Wörter am Ende entfernen ("hinzu", "ein", etc.) ───────────
    // WICHTIG: erst NACH der Frist-Extraktion, damit "hinzu" nach dem
    // Datum-Block korrekt entfernt wird. Daher zweistufig:
    // 1) Frist/Für-Block am Ende suchen
    // 2) dann Rest-Trailing entfernen

    // ── Frist-Block suchen ────────────────────────────────────────────────────
    // Erkennt "mit Frist ..." oder "für ..." direkt vor optionalem "hinzu/ein"
    // am Ende des Strings.
    //
    // Strategie: wir suchen das letzte Vorkommen von "mit Frist" oder "für"
    // und prüfen, ob danach Datum/Uhrzeit-Tokens folgen (kein Wort-Wirrwarr).
    // So wird "für Dienstag" erkannt, aber "Aufgabe für Kunden" NICHT
    // (weil "Kunden" kein Datum-Token ist).

    DateTime? date;
    DateTimeComponents? time;

    final fristMarkerRx = RegExp(
      r'(?:\s+mit\s+frist\s+|\s+für\s+)(.+?)(?:\s+(?:hinzu|ein|hinzufügen|eintragen))?\s*$',
      caseSensitive: false,
    );
    final fristM = fristMarkerRx.firstMatch(rest);

    if (fristM != null) {
      final dateTimeCandidate = fristM.group(1)?.trim() ?? '';
      final dtw = _extractDateTimeFromWindow(dateTimeCandidate);

      if (dtw.hasAnything) {
        // Frist erkannt: aus dem Rest herausschneiden
        date = dtw.date;
        time = dtw.time;
        // Titel = alles VOR dem Frist-Marker
        rest = rest.substring(0, fristM.start).trim();
      }
      // Falls kein gültiges Datum erkannt → Frist-Marker stehen lassen
      // (unbekannter Text wird in den Titel mit übernommen — besser als
      // Datumsfragmente im Titel zu haben)
    }

    // ── Abschluss-Wörter vom Ende des Titels entfernen ───────────────────────
    final trailingRx = RegExp(
      r'\s+(?:hinzu|hinzufügen|eintragen|ein)\s*$',
      caseSensitive: false,
    );
    rest = rest.replaceFirst(trailingRx, '').trim();

    // ── Trailing-Satzzeichen entfernen ───────────────────────────────────────
    rest = rest.replaceFirst(RegExp(r'[.,!?]+$'), '').trim();

    if (rest.isEmpty) return null;

    return _ParseResult(
      title: _capitalizeFirst(rest),
      date: date,
      time: time,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATUM & UHRZEIT aus einem begrenzten Fenster-String extrahieren
  //
  // Dieser Helfer arbeitet auf einem isolierten Teilstring (z.B. dem Bereich
  // zwischen "mich" und "an:" oder dem Bereich nach "mit Frist").
  // Dadurch kann er aggressiver matchen, ohne den Titel zu beschädigen.
  // ─────────────────────────────────────────────────────────────────────────

  static _DateTimeWindow _extractDateTimeFromWindow(String window) {
    final w = window.toLowerCase().trim();
    if (w.isEmpty) return const _DateTimeWindow();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? date;
    DateTimeComponents? time;

    // ── 1) Uhrzeit zuerst extrahieren ─────────────────────────────────────
    final clk = _parseClockTime(w);
    if (clk != null) {
      time = DateTimeComponents(
        clk.hour.clamp(0, 23),
        clk.minute.clamp(0, 59),
      );
    }

    // ── 2) Datum extrahieren ───────────────────────────────────────────────

    // 2a) "am 15. März [2026]" / "15. März"
    final expMonthRx = RegExp(
      r'(?:am\s+|den\s+)?(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    );
    final expMonthM = expMonthRx.firstMatch(w);

    // 2b) "15.3." / "15.3.2026" / "am 15.3."
    final expDateRx = RegExp(
      r'(?:am\s+|den\s+)?(\d{1,2})\.\s*(\d{1,2})\.?\s*(\d{4})?',
    );
    final expDateM = expDateRx.firstMatch(w);

    // 2c) "den 24." / "am 24." — nur Tag ohne Monat
    final onlyDayRx = RegExp(r'(?:den\s+|am\s+)?(\d{1,2})\.\s*(?:$|(?!\d))');
    final onlyDayM = onlyDayRx.firstMatch(w);

    if (expMonthM != null) {
      final day = int.tryParse(expMonthM.group(1) ?? '');
      final rawMonth = (expMonthM.group(2) ?? '').replaceAll('.', '').trim().toLowerCase();
      final month = _months[rawMonth];
      final year = int.tryParse(expMonthM.group(3) ?? '') ?? now.year;
      if (day != null && month != null) {
        var d = DateTime(year, month, day);
        if (d.isBefore(today) && expMonthM.group(3) == null) {
          d = DateTime(year + 1, month, day);
        }
        date = d;
      }
    } else if (expDateM != null && expDateM.group(2) != null) {
      final day = int.tryParse(expDateM.group(1) ?? '');
      final month = int.tryParse(expDateM.group(2) ?? '');
      final year = int.tryParse(expDateM.group(3) ?? '') ?? now.year;
      if (day != null && month != null && month >= 1 && month <= 12) {
        var d = DateTime(year, month, day);
        if (d.isBefore(today) && expDateM.group(3) == null) {
          d = DateTime(year + 1, month, day);
        }
        date = d;
      }
    } else if (onlyDayM != null) {
      final day = int.tryParse(onlyDayM.group(1) ?? '');
      if (day != null && day >= 1 && day <= 31) {
        var d = DateTime(now.year, now.month, day);
        if (d.isBefore(today)) d = DateTime(now.year, now.month + 1, day);
        date = d;
      }
    }

    // 2d) Relative Ausdrücke — nur wenn noch kein Datum
    if (date == null) {
      final relPatterns = <(RegExp, DateTime)>[
        // Übermorgen zuerst (vor "morgen"!)
        (RegExp(r'\bübermorgen\b'), today.add(const Duration(days: 2))),
        // "morgen früh/vormittag/mittag/nachmittag/abend/nacht" — spezifisch zuerst
        (RegExp(r'\bmorgen\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)\b'), today.add(const Duration(days: 1))),
        (RegExp(r'\bmorgen\b'), today.add(const Duration(days: 1))),
        // "heute abend" etc.
        (RegExp(r'\bheute\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)\b'), today),
        (RegExp(r'\bheute\b'), today),
        // Nächste Woche = nächster Montag
        (RegExp(r'\bnächste\s+woche\b'), today.add(Duration(days: 8 - today.weekday))),
        // Nächsten Monat = 1. des nächsten Monats
        (RegExp(r'\bnächsten\s+monat\b'), DateTime(today.year, today.month + 1, 1)),
        // Am Wochenende / dieses Wochenende = nächster Samstag
        (RegExp(r'\b(?:am|dieses?)\s+wochenende\b'), _nextWeekday(today, DateTime.saturday)),
      ];
      for (final (rx, target) in relPatterns) {
        if (rx.hasMatch(w)) {
          date = target;
          break;
        }
      }
    }

    // 2e) Wochentage — nur wenn noch kein Datum
    if (date == null) {
      for (final entry in _weekdays.entries) {
        final rx = RegExp('\\b(?:nächsten?\\s+)?${entry.key}\\b', caseSensitive: false);
        final m = rx.firstMatch(w);
        if (m != null) {
          final forceNext = m.group(0)?.toLowerCase().contains('nächst') ?? false;
          int diff = (entry.value - today.weekday) % 7;
          if (diff == 0 || forceNext) diff = diff == 0 ? 7 : diff;
          if (diff < 0) diff += 7;
          date = today.add(Duration(days: diff));
          break;
        }
      }
    }

    // 2f) "in X Tagen / Wochen / Monaten"
    if (date == null) {
      final inUnitRx = RegExp(
        r'\bin\s+(\d{1,2})\s+(tagen?|wochen?|monaten?)\b',
        caseSensitive: false,
      );
      final m = inUnitRx.firstMatch(w);
      if (m != null) {
        final n = int.tryParse(m.group(1) ?? '');
        final unit = (m.group(2) ?? '').toLowerCase();
        if (n != null) {
          if (unit.startsWith('tag')) {
            date = today.add(Duration(days: n));
          } else if (unit.startsWith('woch')) {
            date = today.add(Duration(days: n * 7));
          } else if (unit.startsWith('monat')) {
            date = DateTime(today.year, today.month + n, today.day);
          }
        }
      }
    }

    return _DateTimeWindow(date: date, time: time);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UHRZEIT-ERKENNUNG (innerhalb eines Fenster-Strings)
  // ─────────────────────────────────────────────────────────────────────────

  static _TimeResult? _parseClockTime(String w) {
    final numTok = _numTok;

    // "HH:MM Uhr" / "HH.MM"  — mit "um" davor
    final umHHMM = RegExp(
      r'\bum\s+(\d{1,2})[:.h](\d{2})\s*(?:uhr)?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umHHMM != null) {
      final h = int.tryParse(umHHMM.group(1)!);
      final m = int.tryParse(umHHMM.group(2)!);
      if (h != null && m != null) {
        return _TimeResult(_ph(h), m, _Span(umHHMM.start, umHHMM.end));
      }
    }

    // "um X Uhr Y" / "um 8 Uhr 30"
    final umUhrMM = RegExp(
      r'\bum\s+($numTok)\s+uhr\s+($numTok)\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umUhrMM != null) {
      final h = _toNum(umUhrMM.group(1)!);
      final m = _toNum(umUhrMM.group(2)!);
      if (h != null && m != null) {
        return _TimeResult(_ph(h), m, _Span(umUhrMM.start, umUhrMM.end));
      }
    }

    // "um 14 Uhr"
    final umUhr = RegExp(
      r'\bum\s+($numTok)\s*uhr\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umUhr != null) {
      final h = _toNum(umUhr.group(1)!);
      if (h != null) return _TimeResult(_ph(h), 0, _Span(umUhr.start, umUhr.end));
    }

    // "um 14" (ohne Uhr)
    final umBare = RegExp(
      r'\bum\s+($numTok)\b(?!\s*(?:uhr\s+\d|stück|mal|euro))',
      caseSensitive: false,
    ).firstMatch(w);
    if (umBare != null) {
      final h = _toNum(umBare.group(1)!);
      if (h != null) return _TimeResult(_ph(h), 0, _Span(umBare.start, umBare.end));
    }

    // "HH:MM" ohne "um" — z.B. "15:30" / "9:00"
    final bareHHMM = RegExp(r'\b(\d{1,2}):(\d{2})\s*(?:uhr)?\b').firstMatch(w);
    if (bareHHMM != null) {
      final h = int.tryParse(bareHHMM.group(1)!);
      final m = int.tryParse(bareHHMM.group(2)!);
      if (h != null && m != null && h <= 23 && m <= 59) {
        return _TimeResult(_ph(h), m, _Span(bareHHMM.start, bareHHMM.end));
      }
    }

    // "X Uhr" ohne "um" — z.B. "15 Uhr" / "9 Uhr"
    final bareUhr = RegExp(r'\b($numTok)\s+uhr\b', caseSensitive: false).firstMatch(w);
    if (bareUhr != null) {
      final h = _toNum(bareUhr.group(1)!);
      if (h != null) return _TimeResult(_ph(h), 0, _Span(bareUhr.start, bareUhr.end));
    }

    // "halb X" → X-1:30
    final halb = RegExp(r'\bhalb\s+($numTok)\b', caseSensitive: false).firstMatch(w);
    if (halb != null) {
      final num = _toNum(halb.group(1)!);
      if (num != null) return _TimeResult(_ph(num - 1), 30, _Span(halb.start, halb.end));
    }

    // "viertel nach X" → X:15
    final viertelN = RegExp(r'\bviertel\s+nach\s+($numTok)\b', caseSensitive: false).firstMatch(w);
    if (viertelN != null) {
      final num = _toNum(viertelN.group(1)!);
      if (num != null) return _TimeResult(_ph(num), 15, _Span(viertelN.start, viertelN.end));
    }

    // "viertel vor X" → X-1:45
    final viertelV = RegExp(r'\bviertel\s+vor\s+($numTok)\b', caseSensitive: false).firstMatch(w);
    if (viertelV != null) {
      final num = _toNum(viertelV.group(1)!);
      if (num != null) {
        final h = _ph(num) - 1;
        return _TimeResult(h < 0 ? 23 : h, 45, _Span(viertelV.start, viertelV.end));
      }
    }

    // "dreiviertel X" → X-1:45
    final dreiV = RegExp(r'\bdreiviertel\s+($numTok)\b', caseSensitive: false).firstMatch(w);
    if (dreiV != null) {
      final num = _toNum(dreiV.group(1)!);
      if (num != null) {
        return _TimeResult(_ph(num - 1), 45, _Span(dreiV.start, dreiV.end));
      }
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hilfsfunktionen
  // ─────────────────────────────────────────────────────────────────────────

  // PM-Konvertierung: 1–6 → 13–18 (nachmittags ohne AM/PM-Angabe)
  static int _ph(int h) => (h >= 1 && h <= 6) ? h + 12 : h;

  static String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Gibt das Datum des nächsten [weekday] zurück (1=Mo … 7=So).
  /// Ist heute bereits dieser Wochentag, wird die nächste Woche genommen.
  static DateTime _nextWeekday(DateTime from, int weekday) {
    int diff = (weekday - from.weekday) % 7;
    if (diff == 0) diff = 7;
    return from.add(Duration(days: diff));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internes Ergebnis-Objekt (Parser-intern, nicht nach außen)
// ─────────────────────────────────────────────────────────────────────────────

class _ParseResult {
  final String title;
  final DateTime? date;
  final DateTimeComponents? time;

  const _ParseResult({
    required this.title,
    this.date,
    this.time,
  });
}