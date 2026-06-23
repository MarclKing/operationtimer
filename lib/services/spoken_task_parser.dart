// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER v8
//
// Änderungen gegenüber v7:
//   - Datum-Overflow-Fix: ungültige Daten (z.B. 31. Februar) werden sicher
//     abgefangen statt lautlos zu crashen / falsches Datum zu erzeugen.
//   - _safeDate() als zentrale Absicherung für alle DateTime-Konstruktionen.
//   - Uhrzeit: "mittags", "abends", "morgens" werden vom Normalizer bereits
//     aufgelöst — Parser muss das nicht extra kennen.
//   - "gegen X Uhr" → bereits vom Normalizer zu "um X Uhr" umgewandelt.
//   - "Monatsende" / "Ende des Monats" → letzter Tag des aktuellen Monats.
//   - "übernächste Woche" → +2 Wochen.
//   - _ph() robuster: gibt Stunde unverändert zurück wenn > 12 (klar PM).
//   - Zwei-Muster-Logik bleibt vollständig erhalten.
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
      'null': 0, 'ein': 1, 'eins': 1, 'eine': 1,
      'zwei': 2, 'drei': 3, 'vier': 4, 'fünf': 5,
      'sechs': 6, 'sieben': 7, 'acht': 8, 'neun': 9,
      'zehn': 10, 'elf': 11, 'zwölf': 12,
      'dreizehn': 13, 'vierzehn': 14, 'fünfzehn': 15,
      'sechzehn': 16, 'siebzehn': 17, 'achtzehn': 18, 'neunzehn': 19,
    };
    final tens = {
      'zwanzig': 20, 'dreißig': 30, 'vierzig': 40, 'fünfzig': 50,
    };
    final onesForCompound = {
      1: 'ein', 2: 'zwei', 3: 'drei', 4: 'vier', 5: 'fünf',
      6: 'sechs', 7: 'sieben', 8: 'acht', 9: 'neun',
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
  // DATUM-OVERFLOW-SCHUTZ
  // Zentrale Funktion für alle DateTime-Konstruktionen im Parser.
  // Gibt null zurück wenn Tag/Monat außerhalb des gültigen Bereichs liegt,
  // statt einen falschen Overflow-Wert zu erzeugen (z.B. 31. Feb → 3. März).
  // ─────────────────────────────────────────────────────────────────────────

  static DateTime? _safeDate(int year, int month, int day) {
    // Monatsbereich prüfen
    if (month < 1 || month > 12) return null;
    // Tagesbereich prüfen (grob — DateTime selbst korrigiert Overflow)
    if (day < 1 || day > 31) return null;
    try {
      final d = DateTime(year, month, day);
      // Overflow-Check: wenn DateTime den Tag "korrigiert" hat, war er ungültig
      if (d.month != month || d.day != day) return null;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// Wie _safeDate, aber springt automatisch ins nächste Jahr wenn das
  /// Datum bereits vergangen ist und kein explizites Jahr angegeben wurde.
  static DateTime? _safeDateAutoYear(
      int year, int month, int day, DateTime today,
      {bool hasExplicitYear = false}) {
    final d = _safeDate(year, month, day);
    if (d == null) return null;
    if (!hasExplicitYear && d.isBefore(today)) {
      return _safeDate(year + 1, month, day);
    }
    return d;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ─────────────────────────────────────────────────────────────────────────

  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();

    // Dringend-Flag
    final urgentRx = RegExp(r'\bdringend[:\s]*', caseSensitive: false);
    final isUrgent = urgentRx.hasMatch(original);
    final cleaned = original
        .replaceAll(urgentRx, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Muster 2 zuerst (spezifischer Marker "an:")
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

    // Muster 1
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

    // Fallback
    final fallbackTitle = _capitalizeFirst(cleaned);
    return ParsedSpokenTask(
      title: fallbackTitle.isEmpty ? original : fallbackTitle,
      rawText: original,
      priority: isUrgent ? TaskPriority.urgent : TaskPriority.normal,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 2 — "Erinnere mich [am DATUM um UHRZEIT] an: TITEL"
  // ─────────────────────────────────────────────────────────────────────────

  static _ParseResult? _tryParseErinnere(String cleaned, String original) {
    final triggerRx = RegExp(r'^erinnere\s+mich\s+', caseSensitive: false);
    final triggerM = triggerRx.firstMatch(cleaned);
    if (triggerM == null) return null;

    final afterTrigger = cleaned.substring(triggerM.end);

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

    _DateTimeWindow dtw = const _DateTimeWindow();
    if (dateTimeWindow != null && dateTimeWindow.isNotEmpty) {
      dtw = _extractDateTimeFromWindow(dateTimeWindow);
    }

    var cleanTitle = titleRaw
        .replaceFirst(RegExp(r'^(?:meine[mnrs]?\s+|mein\s+)', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^(?:den\s+|die\s+|das\s+|der\s+)', caseSensitive: false), '');

    return _ParseResult(
      title: _capitalizeFirst(cleanTitle.isEmpty ? titleRaw : cleanTitle),
      date: dtw.date,
      time: dtw.time,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 1 — "Füge die Aufgabe TITEL [für DATUM UHRZEIT] hinzu"
  // ─────────────────────────────────────────────────────────────────────────

  static _ParseResult? _tryParseFuege(String cleaned, String original) {
    final triggerRx = RegExp(
      r'^(?:'
      r'(?:füg|füge|trage?|ergänze?)\s+(?:(?:die|eine?|meine)\s+)?(?:aufgabe|task|todo|erinnerung|notiz)?\s*(?:(?:die|eine?)\s+)?'
      r'|'
      r'neue?\s+(?:aufgabe|task|todo|erinnerung)\s*[:\-]?\s*'
      r'|'
      r'(?:todo|task|aufgabe|notiz)\s*[:\-]\s*'
      r')',
      caseSensitive: false,
    );

    final triggerM = triggerRx.firstMatch(cleaned);
    if (triggerM == null) return null;

    String rest = cleaned.substring(triggerM.end).trim();

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
        date = dtw.date;
        time = dtw.time;
        rest = rest.substring(0, fristM.start).trim();
      }
    }

    final trailingRx = RegExp(
      r'\s+(?:hinzu|hinzufügen|eintragen|ein)\s*$',
      caseSensitive: false,
    );
    rest = rest.replaceFirst(trailingRx, '').trim();
    rest = rest.replaceFirst(RegExp(r'[.,!?]+$'), '').trim();

    if (rest.isEmpty) return null;

    return _ParseResult(
      title: _capitalizeFirst(rest),
      date: date,
      time: time,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATUM & UHRZEIT — Fenster-Extraktion
  // ─────────────────────────────────────────────────────────────────────────

  static _DateTimeWindow _extractDateTimeFromWindow(String window) {
    final w = window.toLowerCase().trim();
    if (w.isEmpty) return const _DateTimeWindow();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    DateTime? date;
    DateTimeComponents? time;

    // 1) Uhrzeit zuerst
    final clk = _parseClockTime(w);
    if (clk != null) {
      time = DateTimeComponents(
        clk.hour.clamp(0, 23),
        clk.minute.clamp(0, 59),
      );
    }

    // 2a) "am 15. März [2026]" / "15. März"
    final expMonthRx = RegExp(
      r'(?:am\s+|den\s+)?(\d{1,2})\.?\s*(januar|jänner|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)\s*\.?\s*(\d{4})?',
      caseSensitive: false,
    );
    final expMonthM = expMonthRx.firstMatch(w);

    // 2b) "15.3." / "15.3.2026"
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
      final yearStr = expMonthM.group(3);
      final year = int.tryParse(yearStr ?? '') ?? now.year;
      if (day != null && month != null) {
        date = _safeDateAutoYear(year, month, day, today,
            hasExplicitYear: yearStr != null);
      }
    } else if (expDateM != null && expDateM.group(2) != null) {
      final day = int.tryParse(expDateM.group(1) ?? '');
      final month = int.tryParse(expDateM.group(2) ?? '');
      final yearStr = expDateM.group(3);
      final year = int.tryParse(yearStr ?? '') ?? now.year;
      if (day != null && month != null) {
        date = _safeDateAutoYear(year, month, day, today,
            hasExplicitYear: yearStr != null);
      }
    } else if (onlyDayM != null) {
      final day = int.tryParse(onlyDayM.group(1) ?? '');
      if (day != null && day >= 1 && day <= 31) {
        // Versuche aktuellen Monat, dann nächsten
        date = _safeDate(now.year, now.month, day);
        if (date == null || date.isBefore(today)) {
          // Nächster Monat — mit Overflow-Schutz
          final nextMonth = now.month == 12 ? 1 : now.month + 1;
          final nextYear = now.month == 12 ? now.year + 1 : now.year;
          date = _safeDate(nextYear, nextMonth, day);
        }
      }
    }

    // 2d) Relative Ausdrücke
    if (date == null) {
      final relPatterns = <(RegExp, DateTime?)>[
        (RegExp(r'(?<![a-zA-ZäöüßÄÖÜ])übermorgen(?![a-zA-ZäöüßÄÖÜ])'), today.add(const Duration(days: 2))),
        (RegExp(r'\bmorgen\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)\b'), today.add(const Duration(days: 1))),
        (RegExp(r'\bmorgen\b'), today.add(const Duration(days: 1))),
        (RegExp(r'\bheute\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)\b'), today),
        (RegExp(r'\bheute\b'), today),
        // NEU: übernächste Woche
        (RegExp(r'(?<![a-zA-ZäöüßÄÖÜ])übernächste\s+woche(?![a-zA-ZäöüßÄÖÜ])'), today.add(const Duration(days: 14))),
        (RegExp(r'\bnächste\s+woche\b'), today.add(Duration(days: 8 - today.weekday))),
        (RegExp(r'\bnächsten\s+monat\b'), _safeDate(now.year, now.month + 1, 1) ?? _safeDate(now.year + 1, 1, 1)!),
        (RegExp(r'\b(?:am|dieses?)\s+wochenende\b'), _nextWeekday(today, DateTime.saturday)),
        // NEU: Monatsende
        (RegExp(r'\b(?:monatsende|ende\s+des\s+monats)\b'), _lastDayOfMonth(today)),
      ];
      for (final (rx, target) in relPatterns) {
        if (rx.hasMatch(w) && target != null) {
          date = target;
          break;
        }
      }
    }

    // 2e) Wochentage
    if (date == null) {
      for (final entry in _weekdays.entries) {
        final rxAlt = RegExp(
          '(?:übernächsten?\\s+)?(?:nächsten?\\s+)?${RegExp.escape(entry.key)}',
          caseSensitive: false,
        );
        final m = rxAlt.firstMatch(w);
        if (m != null) {
          final matchedStr = m.group(0)?.toLowerCase() ?? '';
          final forceNextNext = matchedStr.contains('übernächst');
          final forceNext = matchedStr.contains('nächst');
          int diff = (entry.value - today.weekday) % 7;
          if (forceNextNext) {
            if (diff == 0) diff = 14;
            else diff += 7;
          } else if (diff == 0 || forceNext) {
            diff = diff == 0 ? 7 : diff;
          }
          if (diff < 0) diff += 7;
          date = today.add(Duration(days: diff));
          break;
        }
      }
    }

    // 2f) "in X Tagen / Wochen / Monaten"
    if (date == null) {
      final inUnitRx = RegExp(
  r'\bin\s+(einer?|einem|\d{1,2})\s+(tagen?|wochen?|monaten?)\b',
  caseSensitive: false,
);
      final m = inUnitRx.firstMatch(w);
      if (m != null) {
        final raw = m.group(1) ?? '';
final n = int.tryParse(raw) ?? (raw.startsWith('eine') ? 1 : null);
        final unit = (m.group(2) ?? '').toLowerCase();
        if (n != null) {
          if (unit.startsWith('tag')) {
            date = today.add(Duration(days: n));
          } else if (unit.startsWith('woch')) {
            date = today.add(Duration(days: n * 7));
          } else if (unit.startsWith('monat')) {
            // Mit Overflow-Schutz
            final targetMonth = today.month + n;
            final targetYear = today.year + (targetMonth - 1) ~/ 12;
            final normalizedMonth = ((targetMonth - 1) % 12) + 1;
            date = _safeDate(targetYear, normalizedMonth, today.day)
                ?? _safeDate(targetYear, normalizedMonth + 1, 1); // Monatsende-Overflow → 1. nächsten Monat
          }
        }
      }
    }

    return _DateTimeWindow(date: date, time: time);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UHRZEIT-ERKENNUNG
  // ─────────────────────────────────────────────────────────────────────────

  static _TimeResult? _parseClockTime(String w) {
    final numTok = _numTok;

    // "HH:MM Uhr" / "HH.MM" — mit "um" davor
    final umHHMM = RegExp(
      r'\bum\s+(\d{1,2})[:.h](\d{2})\s*(?:uhr)?\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umHHMM != null) {
      final h = int.tryParse(umHHMM.group(1)!);
      final m = int.tryParse(umHHMM.group(2)!);
      if (h != null && m != null) {
        return _TimeResult(h, m, _Span(umHHMM.start, umHHMM.end));
      }
    }

    // "um X Uhr Y" / "um 8 Uhr 30"
    final umUhrMM = RegExp(
      '\\bum\\s+($numTok)\\s+uhr\\s+($numTok)\\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umUhrMM != null) {
      final h = _toNum(umUhrMM.group(1)!);
      final m = _toNum(umUhrMM.group(2)!);
      if (h != null && m != null) {
        return _TimeResult(h, m, _Span(umUhrMM.start, umUhrMM.end));
      }
    }

    // "um 14 Uhr"
    final umUhr = RegExp(
      '\\bum\\s+($numTok)\\s*uhr\\b',
      caseSensitive: false,
    ).firstMatch(w);
    if (umUhr != null) {
      final h = _toNum(umUhr.group(1)!);
      if (h != null) return _TimeResult(h, 0, _Span(umUhr.start, umUhr.end));
    }

    // "um 14" (ohne Uhr)
    final umBare = RegExp(
      '\\bum\\s+($numTok)\\b(?!\\s*(?:uhr\\s+\\d|stück|mal|euro))',
      caseSensitive: false,
    ).firstMatch(w);
    if (umBare != null) {
      final h = _toNum(umBare.group(1)!);
      if (h != null) return _TimeResult(h, 0, _Span(umBare.start, umBare.end));
    }

    // "HH:MM" ohne "um"
    final bareHHMM = RegExp(r'\b(\d{1,2}):(\d{2})\s*(?:uhr)?\b').firstMatch(w);
    if (bareHHMM != null) {
      final h = int.tryParse(bareHHMM.group(1)!);
      final m = int.tryParse(bareHHMM.group(2)!);
      if (h != null && m != null && h <= 23 && m <= 59) {
        return _TimeResult(h, m, _Span(bareHHMM.start, bareHHMM.end));
      }
    }

    // "X Uhr" ohne "um"
    final bareUhr = RegExp('\\b($numTok)\\s+uhr\\b', caseSensitive: false).firstMatch(w);
    if (bareUhr != null) {
      final h = _toNum(bareUhr.group(1)!);
      if (h != null) return _TimeResult(h, 0, _Span(bareUhr.start, bareUhr.end));
    }

    // "halb X" → X-1:30
final halb = RegExp('\\bhalb\\s+($numTok)\\b', caseSensitive: false).firstMatch(w);
if (halb != null) {
  final num = _toNum(halb.group(1)!);
  if (num != null) {
    final h = (num - 1) < 0 ? 23 : num - 1;
    return _TimeResult(h, 30, _Span(halb.start, halb.end));
  }
}

// "viertel nach X" → X:15
final viertelN = RegExp('\\bviertel\\s+nach\\s+($numTok)\\b', caseSensitive: false).firstMatch(w);
if (viertelN != null) {
  final num = _toNum(viertelN.group(1)!);
  if (num != null) return _TimeResult(num, 15, _Span(viertelN.start, viertelN.end));
}

// "viertel vor X" → X-1:45
final viertelV = RegExp('\\bviertel\\s+vor\\s+($numTok)\\b', caseSensitive: false).firstMatch(w);
if (viertelV != null) {
  final num = _toNum(viertelV.group(1)!);
  if (num != null) {
    final h = (num - 1) < 0 ? 23 : num - 1;
    return _TimeResult(h, 45, _Span(viertelV.start, viertelV.end));
  }
}

// "dreiviertel X" → X-1:45
final dreiV = RegExp('\\bdreiviertel\\s+($numTok)\\b', caseSensitive: false).firstMatch(w);
if (dreiV != null) {
  final num = _toNum(dreiV.group(1)!);
  if (num != null) {
    final h = (num - 1) < 0 ? 23 : num - 1;
    return _TimeResult(h, 45, _Span(dreiV.start, dreiV.end));
  }
}

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Hilfsfunktionen
  // ─────────────────────────────────────────────────────────────────────────

  static String _capitalizeFirst(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  /// Nächster [weekday] ab [from] (1=Mo … 7=So).
  static DateTime _nextWeekday(DateTime from, int weekday) {
    int diff = (weekday - from.weekday) % 7;
    if (diff == 0) diff = 7;
    return from.add(Duration(days: diff));
  }

  /// Letzter Tag des aktuellen Monats — mit Overflow-Schutz.
  static DateTime _lastDayOfMonth(DateTime from) {
    // Erster Tag des nächsten Monats minus 1 Tag
    final nextMonth = from.month == 12
        ? DateTime(from.year + 1, 1, 1)
        : DateTime(from.year, from.month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internes Ergebnis-Objekt
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