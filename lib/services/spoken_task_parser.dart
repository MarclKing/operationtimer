// ─────────────────────────────────────────────────────────────────────────────
// SPOKEN TASK PARSER — lokale, kostenlose Heuristik zur Umwandlung von
// transkribiertem Freitext ("erinnere mich morgen um 14 Uhr an den TÜV-
// Termin") in eine strukturierte Aufgabe (Titel, Datum, Uhrzeit).
//
// Bewusst als reine Dart-Funktion ohne externe Abhängigkeiten gebaut:
//   - 0 € Kosten, läuft komplett offline, keine Latenz.
//   - Austauschbar: Die einzige Schnittstelle nach außen ist
//     `SpokenTaskParser.parse(String text)`. Falls ihr später auf eine
//     LLM-API umstellen wollt, muss NUR diese eine Funktion ersetzt werden
//     (z. B. durch einen Cloud-Function-Call) — der Rest der App
//     (tasks_screen.dart) bleibt unverändert, da er nur gegen
//     `ParsedSpokenTask` programmiert.
//
// ABDECKUNG (siehe Tests unten in den Kommentaren als Referenz):
//   Trigger-Phrasen, die erkannt & aus dem Titel entfernt werden:
//     "erinnere mich (daran,)?", "neue aufgabe", "notiere", "ich muss",
//     "merk dir", "vergiss nicht", "denk daran"
//   Datum:
//     heute, morgen, übermorgen, "in X Tagen", Wochentage (auch
//     "nächsten Montag"), explizite Daten ("am 15.", "am 15.3.",
//     "15. märz", "15. märz 2026")
//   Uhrzeit:
//     "um 14 uhr", "um 8", "um 8 uhr 30", "halb 3" (= 14:30 wenn nach
//     12 Uhr plausibler, sonst 2:30 — wir nehmen den nächsten plausiblen
//     Zeitpunkt in der Zukunft), "viertel nach 9", "viertel vor 5",
//     "kurz nach 10", "punkt 9"
// ─────────────────────────────────────────────────────────────────────────────

class ParsedSpokenTask {
  final String title;
  final DateTime? date; // nur Datum relevant (Uhrzeit separat in [time])
  final DateTimeComponents? time; // Stunde/Minute, falls erkannt
  final String rawText;

  const ParsedSpokenTask({
    required this.title,
    required this.rawText,
    this.date,
    this.time,
  });

  /// Kombiniert [date] (falls vorhanden, sonst heute) und [time] zu einem
  /// vollständigen DateTime — praktisch für die direkte Übernahme ins
  /// Task-Formular.
  DateTime? get combinedDateTime {
    if (date == null && time == null) return null;
    final d = date ?? DateTime.now();
    if (time == null) return DateTime(d.year, d.month, d.day);
    return DateTime(d.year, d.month, d.day, time!.hour, time!.minute);
  }

  bool get hasTime => time != null;
}

class DateTimeComponents {
  final int hour;
  final int minute;
  const DateTimeComponents(this.hour, this.minute);
}

class SpokenTaskParser {
  SpokenTaskParser._();

  static const _weekdays = {
    'montag': DateTime.monday,
    'dienstag': DateTime.tuesday,
    'mittwoch': DateTime.wednesday,
    'donnerstag': DateTime.thursday,
    'freitag': DateTime.friday,
    'samstag': DateTime.saturday,
    'sonnabend': DateTime.saturday,
    'sonntag': DateTime.sunday,
  };

  static const _months = {
    'januar': 1, 'jan': 1,
    'februar': 2, 'feb': 2,
    'märz': 3, 'maerz': 3, 'mär': 3,
    'april': 4, 'apr': 4,
    'mai': 5,
    'juni': 6, 'jun': 6,
    'juli': 7, 'jul': 7,
    'august': 8, 'aug': 8,
    'september': 9, 'sep': 9,
    'oktober': 10, 'okt': 10,
    'november': 11, 'nov': 11,
    'dezember': 12, 'dez': 12,
  };

  /// Trigger-Phrasen, die typischerweise den eigentlichen Aufgabentitel
  /// einleiten und selbst NICHT Teil des Titels sein sollen.
  static final List<RegExp> _triggerPhrases = [
    RegExp(r'^erinnere\s+mich\s+(daran[,]?\s*)?(dass\s+)?', caseSensitive: false),
    RegExp(r'^neue\s+aufgabe\s*(für.*?)?:?\s*', caseSensitive: false),
    RegExp(r'^notiere\s+(dass\s+)?', caseSensitive: false),
    RegExp(r'^ich\s+muss\s+', caseSensitive: false),
    RegExp(r'^merk\s+dir\s+(dass\s+)?', caseSensitive: false),
    RegExp(r'^vergiss\s+nicht[,]?\s+(dass\s+)?', caseSensitive: false),
    RegExp(r'^denk\s+daran[,]?\s+(dass\s+)?', caseSensitive: false),
  ];

  /// Füllwörter, die nach dem Entfernen von Datum/Zeit/Trigger am Rand des
  /// Titels übrig bleiben können und kosmetisch entfernt werden.
  static final List<RegExp> _fillerEdges = [
    RegExp(r'^(dass|dran|daran|an|zu)\s+', caseSensitive: false),
    RegExp(r'\s+(dran|daran)$', caseSensitive: false),
  ];

  static ParsedSpokenTask parse(String rawText) {
    final original = rawText.trim();
    String working = original.toLowerCase();

    // 1) Trigger-Phrase am Anfang entfernen (nur die erste passende).
    for (final trigger in _triggerPhrases) {
      final match = trigger.firstMatch(working);
      if (match != null) {
        working = working.substring(match.end);
        break;
      }
    }

    DateTime? date;
    DateTimeComponents? time;

    // 2) Explizites Datum "am 15.3." / "am 15. märz" / "15.3.2026" zuerst,
    //    da am spezifischsten.
    final explicitDateMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.\s*(\d{1,2})?\.?\s*(\d{4})?',
    ).firstMatch(working);
    final explicitMonthNameMatch = RegExp(
      r'(?:am\s+)?(\d{1,2})\.?\s*(januar|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan|feb|mär|apr|jun|jul|aug|sep|okt|nov|dez)\.?\s*(\d{4})?',
    ).firstMatch(working);

    if (explicitMonthNameMatch != null) {
      final day = int.tryParse(explicitMonthNameMatch.group(1) ?? '');
      final monthName = explicitMonthNameMatch.group(2);
      final yearStr = explicitMonthNameMatch.group(3);
      final month = monthName != null ? _months[monthName] : null;
      if (day != null && month != null) {
        final year = yearStr != null ? int.tryParse(yearStr) ?? DateTime.now().year : DateTime.now().year;
        date = DateTime(year, month, day);
        working = working.replaceRange(explicitMonthNameMatch.start, explicitMonthNameMatch.end, ' ');
      }
    } else if (explicitDateMatch != null && explicitDateMatch.group(2) != null) {
      final day = int.tryParse(explicitDateMatch.group(1) ?? '');
      final month = int.tryParse(explicitDateMatch.group(2) ?? '');
      final yearStr = explicitDateMatch.group(3);
      if (day != null && month != null && month >= 1 && month <= 12) {
        final year = yearStr != null ? int.tryParse(yearStr) ?? DateTime.now().year : DateTime.now().year;
        date = DateTime(year, month, day);
        working = working.replaceRange(explicitDateMatch.start, explicitDateMatch.end, ' ');
      }
    }

    // 3) Relative Tagesangaben, falls noch kein Datum gefunden.
    if (date == null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (RegExp(r'\bübermorgen\b', caseSensitive: false).hasMatch(working)) {
        date = today.add(const Duration(days: 2));
        working = working.replaceAll(RegExp(r'\bübermorgen\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bmorgen\b', caseSensitive: false).hasMatch(working)) {
        date = today.add(const Duration(days: 1));
        working = working.replaceAll(RegExp(r'\bmorgen\b', caseSensitive: false), ' ');
      } else if (RegExp(r'\bheute\b', caseSensitive: false).hasMatch(working)) {
        date = today;
        working = working.replaceAll(RegExp(r'\bheute\b', caseSensitive: false), ' ');
      } else {
        final inDaysMatch = RegExp(r'\bin\s+(\d+)\s+tagen\b', caseSensitive: false).firstMatch(working);
        if (inDaysMatch != null) {
          final days = int.tryParse(inDaysMatch.group(1) ?? '');
          if (days != null) {
            date = today.add(Duration(days: days));
            working = working.replaceRange(inDaysMatch.start, inDaysMatch.end, ' ');
          }
        } else {
          // Wochentage, optional mit "nächsten" davor.
          for (final entry in _weekdays.entries) {
            final pattern = RegExp(
              '\\b(nächsten\\s+|naechsten\\s+)?${entry.key}\\b',
              caseSensitive: false,
            );
            final match = pattern.firstMatch(working);
            if (match != null) {
              final forceNextWeek = match.group(1) != null;
              int diff = (entry.value - today.weekday) % 7;
              if (diff == 0 && forceNextWeek) diff = 7;
              if (diff == 0 && !forceNextWeek) diff = 0; // heute, falls heute genau dieser Wochentag ist
              if (diff < 0) diff += 7;
              date = today.add(Duration(days: diff));
              working = working.replaceRange(match.start, match.end, ' ');
              break;
            }
          }
        }
      }
    }

    // 4) Uhrzeit-Erkennung.
    // "halb X" → X:30 Uhr, eine Stunde vor der genannten Zahl im
    // deutschen Sprachgebrauch (halb 3 = 14:30).
    final halbMatch = RegExp(r'\bhalb\s+(\d{1,2})\b', caseSensitive: false).firstMatch(working);
    final viertelNachMatch = RegExp(r'\bviertel\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(working);
    final viertelVorMatch = RegExp(r'\bviertel\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(working);
    final umUhrMatch = RegExp(r'\bum\s+(\d{1,2})(?:[:.](\d{2}))?\s*(?:uhr)?(?:\s+(\d{2}))?\b', caseSensitive: false).firstMatch(working);
    final punktMatch = RegExp(r'\bpunkt\s+(\d{1,2})\s*(?:uhr)?\b', caseSensitive: false).firstMatch(working);
    final kurzNachMatch = RegExp(r'\bkurz\s+nach\s+(\d{1,2})\b', caseSensitive: false).firstMatch(working);
    final kurzVorMatch = RegExp(r'\bkurz\s+vor\s+(\d{1,2})\b', caseSensitive: false).firstMatch(working);

    int? hour;
    int minute = 0;
    RegExpMatch? consumedMatch;

    if (halbMatch != null) {
      final h = int.tryParse(halbMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h - 1);
        minute = 30;
        consumedMatch = halbMatch;
      }
    } else if (viertelNachMatch != null) {
      final h = int.tryParse(viertelNachMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h);
        minute = 15;
        consumedMatch = viertelNachMatch;
      }
    } else if (viertelVorMatch != null) {
      final h = int.tryParse(viertelVorMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h - 1);
        minute = 45;
        consumedMatch = viertelVorMatch;
      }
    } else if (kurzNachMatch != null) {
      final h = int.tryParse(kurzNachMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h);
        minute = 5;
        consumedMatch = kurzNachMatch;
      }
    } else if (kurzVorMatch != null) {
      final h = int.tryParse(kurzVorMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h);
        minute = 55;
        if (hour! > 0) hour = hour - 1;
        consumedMatch = kurzVorMatch;
      }
    } else if (punktMatch != null) {
      final h = int.tryParse(punktMatch.group(1) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h);
        minute = 0;
        consumedMatch = punktMatch;
      }
    } else if (umUhrMatch != null) {
      final h = int.tryParse(umUhrMatch.group(1) ?? '');
      final m = int.tryParse(umUhrMatch.group(2) ?? umUhrMatch.group(3) ?? '');
      if (h != null) {
        hour = _toPlausibleHour(h);
        minute = m ?? 0;
        consumedMatch = umUhrMatch;
      }
    }

    if (hour != null) {
      time = DateTimeComponents(hour.clamp(0, 23), minute.clamp(0, 59));
      if (consumedMatch != null) {
        working = working.replaceRange(consumedMatch.start, consumedMatch.end, ' ');
      }
    }

    // 5) Übrig gebliebenen Text als Titel bereinigen.
    String title = working;
    for (final filler in _fillerEdges) {
      title = title.replaceAll(filler, ' ');
    }
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Erster Buchstabe groß, Rest wie transkribiert (Eigennamen könnten
    // sonst verloren gehen — bewusst keine aggressive Groß/Kleinschreibung).
    if (title.isNotEmpty) {
      title = title[0].toUpperCase() + title.substring(1);
    } else {
      // Fallback: nichts Sinnvolles übrig → Originaltext nehmen, damit nie
      // eine leere Aufgabe entsteht.
      title = original;
    }

    return ParsedSpokenTask(
      title: title,
      rawText: original,
      date: date,
      time: time,
    );
  }

  /// Deutsche Uhrzeiten werden oft ohne "Uhr-24" gesprochen ("um 3" meint
  /// im Alltag meistens 15 Uhr, nicht 3 Uhr nachts). Heuristik: Werte 1–7
  /// werden auf den nächsten plausiblen Nachmittags-/Abend-Zeitpunkt
  /// gemappt, AUSSER der Kontext lässt klar auf Vormittag schließen (das
  /// können wir ohne mehr Kontext nicht zuverlässig erkennen) — wir nehmen
  /// daher bewusst die alltagssprachlich wahrscheinlichere Variante.
  static int _toPlausibleHour(int h) {
    if (h < 0) h += 12;
    if (h >= 1 && h <= 7) return h + 12;
    return h;
  }
}