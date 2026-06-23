// ─────────────────────────────────────────────────────────────────────────────
// SPEECH NORMALIZER v3
// Wandelt natürliche Sprache in Muster um, die SpokenTaskParser versteht.
// Wird VOR SpokenTaskParser aufgerufen — der Parser selbst bleibt unverändert.
//
// Zwei Kern-Ausgabe-Muster (Parser versteht nur diese sicher):
//   A) "Füge die Aufgabe [TITEL] für [DATUM] hinzu"
//   B) "Erinnere mich [DATUM] an: [TITEL]"
//
// Unterstützte Eingabe-Muster:
//   "Ich muss [noch] TITEL [DATUM]"
//   "Ich sollte [noch] TITEL [DATUM]"
//   "Nicht vergessen: TITEL [DATUM]"
//   "Denk daran/dran TITEL [DATUM]"
//   "Kannst du mich [DATUM] an TITEL erinnern"
//   "Bitte erinnere mich [DATUM] an TITEL"
//   "Erinnere mich [DATUM] an TITEL"         ← direktes Erinnere ohne "bitte"
//   "[DATUM] TITEL machen/erledigen"
//   "Ruf [DATUM] X an" / "Schreib X" / Imperativ-Sätze
//
// v3 Änderungen:
//   - Kern-Muster "Füge/Erinnere" robuster (mehr Trigger-Varianten, optionaler Doppelpunkt)
//   - Uhrzeit-Tokens direkt im Datum-Block: "mittags", "abends", "morgens", "gegen X"
//   - Datum-Format: "Ende des Monats", "Monatsende", "übernächste Woche"
//   - Imperativ-Muster: "Ruf X an", "Schreib X", "Kauf X", "Bestell X"
//   - _looksLikeDateOrEmpty robuster gegen false positives
// ─────────────────────────────────────────────────────────────────────────────

class SpeechNormalizer {
  SpeechNormalizer._();

  // ─────────────────────────────────────────────────────────────────────────
  // DATUM-TOKEN-LISTE
  // Reihenfolge: längere/spezifischere Ausdrücke zuerst!
  // ─────────────────────────────────────────────────────────────────────────
  static const String _dateTokens =
    // Wochentage mit "nächsten/übernächsten"
    r'(?:(?<![a-zA-ZäöüßÄÖÜ])übernächsten?\s+)?(?:nächsten?\s+)?(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)'
    r'|(?<![a-zA-ZäöüßÄÖÜ])übermorgen(?![a-zA-ZäöüßÄÖÜ])'
    // "morgen früh" etc. — spezifisch VOR bloßem "morgen"
    r'|morgen\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)'
    r'|morgen'
    // "heute abend" etc. — spezifisch VOR bloßem "heute"
    r'|heute\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)'
    r'|heute'
    // nächste Woche / übernächste Woche / nächsten Monat
    r'|(?<![a-zA-ZäöüßÄÖÜ])übernächste\s+woche(?![a-zA-ZäöüßÄÖÜ])'
    r'|nächste(?:n|r|s)?\s+(?:woche|monat|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)'
    // Wochenende
    r'|am\s+wochenende'
    r'|dieses?\s+wochenende'
    // Monatsende
    r'|(?:am\s+)?(?:monatsende|ende\s+des\s+monats)'
    // "in X Tagen/Wochen/Monaten"
    r'|in\s+\d+\s+(?:tagen?|wochen?|monaten?)'
    // Datum mit Monatsnamen: "15. März [2026]"
    r'|\d{1,2}\.\s*(?:januar|februar|märz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|'
    r'jan\.?|feb\.?|mär\.?|apr\.?|jun\.?|jul\.?|aug\.?|sep\.?|sept\.?|okt\.?|nov\.?|dez\.?)(?:\s*\d{4})?'
    // Datum numerisch: "15.3." / "15.3.2026"
    r'|\d{1,2}\.\s*\d{1,2}\.?(?:\s*\d{4})?(?:\s+um\s+\d{1,2}(?::\d{2})?\s*uhr?)?'
    // Nur Tag: "am 15." / "den 15."
    r'|(?:am|den)\s+\d{1,2}\.';

// ─────────────────────────────────────────────────────────────────────────
  // UHRZEIT-AUSDRÜCKE (zur Erkennung, ob ein Fenster eine Zeitangabe ist)
  // Wird von _looksLikeDateOrEmpty genutzt, damit "um 3 Uhr", "halb 3" etc.
  // im Datum/Zeit-Fenster zwischen "mich" und "an" erkannt werden.
  // ─────────────────────────────────────────────────────────────────────────
  static const String _timeTokens =
      r'um\s+\d{1,2}(?::\d{2})?\s*uhr?'
      r'|\d{1,2}:\d{2}\s*uhr?'
      r'|halb\s+\d{1,2}'
      r'|viertel\s+(?:nach|vor)\s+\d{1,2}'
      r'|dreiviertel\s+\d{1,2}'
      r'|\d{1,2}\s+uhr';

  // ─────────────────────────────────────────────────────────────────────────
  // UHRZEIT-TOKENS (für Normalizer — nicht für Parser)
  // Benannte Zeiten die der Parser nicht direkt kennt
  // ─────────────────────────────────────────────────────────────────────────
  static const Map<String, String> _namedTimes = {
  r'\bfrüh\s+morgens?\b':   'um 7 Uhr',
  r'\bmittags?\b':          'um 12 Uhr',
  r'\babends?\b':           'um 19 Uhr',
  r'\bmorgens\b':           'um 8 Uhr',   // "morgens" (mit s) = Uhrzeit, NICHT "morgen" (Tag)
  r'\bnachts?\b':           'um 22 Uhr',
  r'\bzur\s+mittagszeit\b': 'um 12 Uhr',
};

  // ─────────────────────────────────────────────────────────────────────────
  // HAUPTFUNKTION
  // ─────────────────────────────────────────────────────────────────────────

  static String normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    // Dringend-Flag sichern
    final hasDringend = RegExp(r'\bdringend\b', caseSensitive: false).hasMatch(trimmed);
    var working = trimmed
        .replaceAll(RegExp(r'\bdringend[:\s]*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Benannte Uhrzeiten normalisieren ("abends" → "um 19 Uhr")
    working = _expandNamedTimes(working);

    // Füllwörter entfernen
    working = _stripFillers(working);

    // ── Kern-Muster zuerst: direkte Parser-Eingaben durchlassen ─────────────
    // Wenn jemand schon "Füge die Aufgabe X hinzu" oder "Erinnere mich an: X"
    // sagt, direkt durchleiten ohne Umwandlung — nur normalisieren.
    final kernResult = _tryKernMuster(working);
    if (kernResult != null) {
      return hasDringend ? 'dringend $kernResult' : kernResult;
    }

    // Andere Muster der Reihe nach
    final result =
        _tryIchMuss(working) ??
        _tryIchSollte(working) ??
        _tryNichtVergessen(working) ??
        _tryDenkDaran(working) ??
        _tryKannstDuErinnern(working) ??
        _tryBitteErinnere(working) ??
        _tryImperativ(working) ??
        _tryNurDatum(working);

    if (result == null) return trimmed;

    return hasDringend ? 'dringend $result' : result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KERN-MUSTER — direkte Eingaben robuster durchleiten
  // "Füge die Aufgabe X hinzu" und "Erinnere mich an: X"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryKernMuster(String text) {
    // ── Füge-Varianten ────────────────────────────────────────────────────
    // Erkennt alle Trigger-Varianten und normalisiert auf kanonische Form
    final fuegeRx = RegExp(
      r'^(?:füg(?:e)?|trag(?:e)?|ergänze?|add)\s+'
      r'(?:(?:die|eine?|meine|den)\s+)?'
      r'(?:aufgabe|task|todo|erinnerung|notiz|reminder|punkt)?\s*'
      r'(?:(?:die|eine?)\s+)?'
      r'(.+?)'
      r'(?:\s+(?:hinzu|ein|hinzufügen|eintragen|dazu))?\s*$',
      caseSensitive: false,
    );
    final fuegeM = fuegeRx.firstMatch(text);
    if (fuegeM != null) {
      final inner = fuegeM.group(1)!.trim();
      if (inner.isNotEmpty) {
        // Datum am Ende suchen und korrekt einbauen
        return _buildFuegeAufgabe(inner);
      }
    }

    // ── Erinnere-Varianten ────────────────────────────────────────────────
    // "Erinnere mich [DATUM] an[:]  TITEL"
    // "Erinnere mich an TITEL" (ohne Doppelpunkt — häufiger Sprachfehler)
    final erinnereRx = RegExp(
      r'^erinnere?\s+mich\s+(.+?)\s+an\s*:?\s*(.+)$',
      caseSensitive: false,
    );
    final erinnereM = erinnereRx.firstMatch(text);
    if (erinnereM != null) {
      final between = erinnereM.group(1)!.trim(); // zwischen "mich" und "an"
      final titel = erinnereM.group(2)!.trim();
      if (titel.isNotEmpty) {
        // "mich" allein → kein Datum
        if (between == 'mich' || between.isEmpty) {
          return 'Erinnere mich an: $titel';
        }
        if (_looksLikeDateOrEmpty(between)) {
          return 'Erinnere mich $between an: $titel';
        }
        // between ist kein Datum → alles als Titel behandeln
        return 'Erinnere mich an: $between $titel';
      }
    }

    // Kurze Form: "Erinnere mich an X" (kein Datum möglich hier)
    final erinnereSimpleRx = RegExp(
      r'^erinnere?\s+mich\s+an\s*:?\s*(.+)$',
      caseSensitive: false,
    );
    final erinnereSimpleM = erinnereSimpleRx.firstMatch(text);
    if (erinnereSimpleM != null) {
      final titel = erinnereSimpleM.group(1)!.trim();
      if (titel.isNotEmpty) {
        return 'Erinnere mich an: $titel';
      }
    }

    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 1: "Ich muss [noch/mal/unbedingt] TITEL [DATUM]"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryIchMuss(String text) {
    final rx = RegExp(
      r'^ich\s+(?:muss|müsste|müss|wollte|wollte\s+noch)\s+'
      r'(?:noch\s+|mal\s+|unbedingt\s+|dringend\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(m.group(1)!.trim());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 2: "Ich sollte [noch] TITEL"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryIchSollte(String text) {
    final rx = RegExp(
      r'^ich\s+(?:sollte|solle|soll)\s+(?:noch\s+|mal\s+|unbedingt\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(m.group(1)!.trim());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 3: "Nicht vergessen: TITEL" / "Vergiss nicht TITEL"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryNichtVergessen(String text) {
    final rx = RegExp(
      r'^(?:nicht\s+vergessen[:\s]+|vergiss\s+(?:nicht\s+|es\s+nicht\s+)'
      r'(?:den\s+|die\s+|das\s+)?)(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(m.group(1)!.trim());
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 4: "Denk daran/dran [DATUM] TITEL"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryDenkDaran(String text) {
    final rx = RegExp(
      r'^denk\s+(?:daran|dran)\s+(?:an\s+)?(?:den\s+|die\s+|das\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(_stripInfinitive(m.group(1)!.trim()));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 5: "Kannst du mich [am DATUM] an TITEL erinnern"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryKannstDuErinnern(String text) {
    // Mit Datum-Fenster
    final rx = RegExp(
      r'^(?:kannst\s+du\s+mich|könntest\s+du\s+mich|kannst\s+du\s+mich\s+bitte)\s+'
      r'(.+?)\s+(?:daran\s+)?(?:an\s+(?:den\s+|die\s+|das\s+)?)(.+?)\s+erinnern\??$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m != null) {
      final dateWindow = m.group(1)!.trim();
      final titel = m.group(2)!.trim();
      if (_looksLikeDateOrEmpty(dateWindow)) {
        final datePart = dateWindow.isNotEmpty ? ' $dateWindow' : '';
        return 'Erinnere mich$datePart an: $titel';
      }
    }
    // Ohne Datum
    final simple = RegExp(
      r'^(?:kannst\s+du\s+mich|könntest\s+du\s+mich)\s+'
      r'(?:daran\s+)?(?:an\s+(?:den\s+|die\s+|das\s+)?)(.+?)\s+erinnern\??$',
      caseSensitive: false,
    ).firstMatch(text);
    if (simple != null) {
      return 'Erinnere mich an: ${simple.group(1)!.trim()}';
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 6: "Bitte erinnere mich [DATUM] an TITEL"
  // (direktes "Erinnere" ohne "bitte" wird von _tryKernMuster abgedeckt)
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryBitteErinnere(String text) {
    final rx = RegExp(
      r'^bitte\s+erinnere?\s+(?:mich\s+)?(?:bitte\s+)?(.+?)\s+an[:\s]+(?:den\s+|die\s+|das\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;

    final dateWindow = m.group(1)!.trim();
    final titel = m.group(2)!.trim();

    if (dateWindow == 'mich' || dateWindow.isEmpty) {
      return 'Erinnere mich an: $titel';
    }
    if (_looksLikeDateOrEmpty(dateWindow)) {
      return 'Erinnere mich $dateWindow an: $titel';
    }
    return 'Erinnere mich an: $dateWindow $titel';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 7: Imperativ-Sätze
  // "Ruf X an", "Schreib X", "Kauf X", "Bestell X", "Buch X"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryImperativ(String text) {
    final rx = RegExp(
      r'^(ruf(?:e)?|schreib(?:e)?|kauf(?:e)?|bestell(?:e)?|buch(?:e)?|'
      r'schick(?:e)?|send(?:e)?|mach(?:e)?|erledig(?:e)?|bereite?\s+vor|'
      r'plan(?:e)?|organisiere?|bereite?)\s+(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;

    final verb = m.group(1)!.trim();
    var rest = m.group(2)!.trim();

    // "Ruf X an" — "an" am Ende als Teil des Verbs behandeln
    final istAnrufen = verb.toLowerCase().startsWith('ruf') &&
        rest.endsWith(' an');
    if (istAnrufen) {
      rest = rest.substring(0, rest.length - 3).trim();
      return _buildFuegeAufgabe('$rest anrufen');
    }

    return _buildFuegeAufgabe(rest);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MUSTER 8: Satz beginnt mit Datum
  // "Morgen Zahnarzt", "Freitag um 9 Marcel anrufen"
  // ─────────────────────────────────────────────────────────────────────────

  static String? _tryNurDatum(String text) {
    final dateStartRx = RegExp(
      '^($_dateTokens)(?:\\s+um\\s+\\d{1,2}(?::\\d{2})?\\s*uhr?)?\\b\\s*(.+)?\$',
      caseSensitive: false,
    );
    final m = dateStartRx.firstMatch(text);
    if (m == null) return null;
    final datePart = m.group(1)!.trim();
    final rest = (m.group(2) ?? '').trim();
    if (rest.isEmpty) return null;
    final cleaned = _stripInfinitive(rest);
    return 'Füge die Aufgabe $cleaned für $datePart hinzu';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HILFSFUNKTIONEN
  // ─────────────────────────────────────────────────────────────────────────

  /// Benannte Uhrzeiten in Parser-verständliche Formate umwandeln.
  /// "abends" → "um 19 Uhr", "mittags" → "um 12 Uhr", etc.
  static String _expandNamedTimes(String text) {
    var result = text;
    for (final entry in _namedTimes.entries) {
      result = result.replaceAll(
        RegExp(entry.key, caseSensitive: false),
        entry.value,
      );
    }
    // "gegen X [Uhr]" → "um X Uhr " (mit Leerzeichen danach, da \b im
    // Suchmuster bei direkt folgendem Wort wie "an:" das Trennzeichen
    // verschluckt und im Replacement sonst keins mehr übrig bleibt)
    result = result.replaceAllMapped(
      RegExp(r'\bgegen\s+(\d{1,2}(?::\d{2})?)\s*(?:uhr)?\b', caseSensitive: false),
      (m) => 'um ${m.group(1)} Uhr ',
    );
    // "so gegen X" → "um X Uhr "
    result = result.replaceAllMapped(
      RegExp(r'\bso\s+gegen\s+(\d{1,2}(?::\d{2})?)\s*(?:uhr)?\b', caseSensitive: false),
      (m) => 'um ${m.group(1)} Uhr ',
    );
    // Doppelte Leerzeichen, die durch das obige Anhängen entstehen können,
    // werden weiter unten in normalize() ohnehin wieder kollabiert.
    return result;
  }

  /// Füllwörter entfernen.
  static String _stripFillers(String text) {
    return text
      .replaceAll(RegExp(
        r'\b(?:bitte|mal|eben|kurz|schnell|eigentlich|vielleicht|halt|'
        r'einfach|irgendwie|doch|auch|wirklich|unbedingt|'
        r'auf\s+jeden\s+fall|auf\s+keinen\s+fall|'
        r'einmal|nochmal|nochmals|ggf|gegebenenfalls)\b',
        caseSensitive: false,
      ), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  }

  /// Baut "Füge die Aufgabe TITEL [für DATUM] hinzu".
  /// Sucht Datum am Anfang oder Ende des Rests.
  static String _buildFuegeAufgabe(String rest) {
    // Datum am Anfang ("morgen früh Auto waschen")
    final dateStartRx = RegExp(
      '^($_dateTokens)(?:\\s+um\\s+\\d{1,2}(?::\\d{2})?\\s*uhr?)?\\s+(.+)\$',
      caseSensitive: false,
    );
    final mStart = dateStartRx.firstMatch(rest);
    if (mStart != null) {
      final datePart = mStart.group(1)!.trim();
      final titel = _stripInfinitive(mStart.group(2)!.trim());
      if (titel.isNotEmpty) {
        return 'Füge die Aufgabe $titel für $datePart hinzu';
      }
    }

    // Datum am Ende ("Auto waschen morgen früh")
    final dateEndRx = RegExp(
      '^(.+?)\\s+($_dateTokens)(?:\\s+um\\s+\\d{1,2}(?::\\d{2})?\\s*uhr?)?\$',
      caseSensitive: false,
    );
    final mEnd = dateEndRx.firstMatch(rest);
    if (mEnd != null) {
      final titel = _stripInfinitive(mEnd.group(1)!.trim());
      final datePart = mEnd.group(2)!.trim();
      if (titel.isNotEmpty && datePart.isNotEmpty) {
        return 'Füge die Aufgabe $titel für $datePart hinzu';
      }
    }

    return 'Füge die Aufgabe ${_stripInfinitive(rest)} hinzu';
  }

  /// Prüft ob ein String wie ein Datum aussieht (oder leer ist).
  /// Absichtlich konservativ — lieber false negative als false positive.
  static bool _looksLikeDateOrEmpty(String s) {
    if (s.isEmpty) return true;
    // Muss mit einem Datum- ODER Uhrzeit-Token beginnen, und darf nicht zu
    // lang sein (lange Strings sind meist Titel, keine Daten/Zeiten).
    if (s.split(' ').length > 6) return false;
    return RegExp(
      r'^(?:(?:' + _dateTokens + r')(?:\s+(?:' + _timeTokens + r'))?'
      r'|(?:' + _timeTokens + r')(?:\s+(?:' + _dateTokens + r'))?)',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// Entfernt Infinitiv-Konstruktionen am Ende für sauberere Titel.
  static String _stripInfinitive(String s) {
    return s
        .replaceFirst(
          RegExp(
            r'\s+(?:zu\s+)?(?:machen|erledigen|tun|fertig\s+machen|fertigmachen)\s*$',
            caseSensitive: false,
          ), '')
        .replaceFirst(
          RegExp(r'\s+an(?:zu)?rufen\s*$', caseSensitive: false),
          ' anrufen',
        )
        .trim();
  }
}