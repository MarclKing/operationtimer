// ─────────────────────────────────────────────────────────────────────────────
// SPEECH NORMALIZER v2
// Wandelt natürliche Sprache in Muster um, die SpokenTaskParser versteht.
// Wird VOR SpokenTaskParser aufgerufen — der Parser selbst bleibt unverändert.
//
// Unterstützte natürliche Muster:
//   "Ich muss [noch] [dringend] TITEL [DATUM]"
//   "Ich sollte [noch] TITEL [DATUM]"
//   "Nicht vergessen: TITEL [DATUM]"
//   "Denk daran/dran [DATUM] TITEL"
//   "Kannst du mich [DATUM] an TITEL erinnern"
//   "Bitte erinnere mich [DATUM] an TITEL"
//   "[DATUM] TITEL machen/erledigen"
//
// v2 Erweiterungen:
//   - Füllwörter werden entfernt (bitte, mal, eben, kurz, schnell, ...)
//   - Erweiterte Datum-Token (nächsten Freitag, morgen früh, am Wochenende, in 2 Wochen, ...)
// ─────────────────────────────────────────────────────────────────────────────

class SpeechNormalizer {
  SpeechNormalizer._();

  /// Zentrale Datum-Token-Liste — wird in _buildFuegeAufgabe + _tryNurDatum verwendet.
  /// Reihenfolge wichtig: längere/spezifischere Ausdrücke zuerst!
  static const String _dateTokens =
    r'(?:nächsten?\s+)?(?:montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)'  // Wochentage + "nächsten"
    r'|übermorgen'
    r'|morgen\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)'                         // "morgen früh" etc.
    r'|morgen'
    r'|heute\s+(?:früh|vormittag|mittag|nachmittag|abend|nacht)'                          // "heute abend" etc.
    r'|heute'
    r'|nächste(?:n|r|s)?\s+(?:woche|monat|montag|dienstag|mittwoch|donnerstag|freitag|samstag|sonntag)'
    r'|am\s+wochenende'
    r'|dieses?\s+wochenende'
    r'|in\s+\d+\s+(?:tagen?|wochen?|monaten?)'                                            // "in 3 Tagen/Wochen"
    r'|\d{1,2}\.\s*\d{1,2}\.?(?:\s*\d{4})?(?:\s+um\s+\d{1,2}(?::\d{2})?\s*uhr?)?'     // "15.3." / "15.3.2026"
    r'|(?:\d{1,2})\.\s*(?:januar|februar|märz|april|mai|juni|juli|august|september|oktober|november|dezember)'; // "15. März"

  /// Hauptfunktion: gibt den normalisierten Text zurück.
  /// Falls kein Muster erkannt wird, kommt der Originaltext zurück —
  /// der Parser versucht es dann trotzdem (Fallback bleibt bestehen).
  static String normalize(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;

    // Dringend-Flag rausziehen, damit es die Mustererkennung nicht stört
    // (SpokenTaskParser erkennt "dringend" selbst später wieder)
    final hasDringend = RegExp(r'\bdringend\b', caseSensitive: false).hasMatch(trimmed);
    final withoutDringend = trimmed
        .replaceAll(RegExp(r'\bdringend[:\s]*', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Füllwörter entfernen bevor Muster geprüft werden
    final withoutFillers = _stripFillers(withoutDringend);

    // Muster der Reihe nach probieren
    final result =
        _tryIchMuss(withoutFillers) ??
        _tryIchSollte(withoutFillers) ??
        _tryNichtVergessen(withoutFillers) ??
        _tryDenkDaran(withoutFillers) ??
        _tryKannstDuErinnern(withoutFillers) ??
        _tryBitteErinnere(withoutFillers) ??
        _tryNurDatum(withoutFillers);

    if (result == null) return trimmed; // nichts erkannt → Original zurück

    // Dringend wieder vorne einfügen, damit SpokenTaskParser es findet
    return hasDringend ? 'dringend $result' : result;
  }

  // ── Muster 1: "Ich muss [noch] TITEL [für/am DATUM]" ──────────────────────
  // Beispiele:
  //   "Ich muss morgen Auto waschen"
  //   "Ich muss noch Dienstplan erstellen"
  //   "Ich muss Freitag um 9 Marcel anrufen"
  static String? _tryIchMuss(String text) {
    final rx = RegExp(
      r'^ich\s+(?:muss|müsste|müss)\s+(?:noch\s+|mal\s+|unbedingt\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    final rest = m.group(1)!.trim();
    return _buildFuegeAufgabe(rest);
  }

  // ── Muster 2: "Ich sollte [noch] TITEL" ────────────────────────────────────
  static String? _tryIchSollte(String text) {
    final rx = RegExp(
      r'^ich\s+(?:sollte|solle|soll)\s+(?:noch\s+|mal\s+|unbedingt\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(m.group(1)!.trim());
  }

  // ── Muster 3: "Nicht vergessen: TITEL" / "Vergiss nicht TITEL" ─────────────
  static String? _tryNichtVergessen(String text) {
    final rx = RegExp(
      r'^(?:nicht\s+vergessen[:\s]+|vergiss\s+(?:nicht\s+|es\s+nicht\s+)(?:den\s+|die\s+|das\s+)?)(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    return _buildFuegeAufgabe(m.group(1)!.trim());
  }

  // ── Muster 4: "Denk daran/dran [DATUM] TITEL" ─────────────────────────────
  // Beispiele:
  //   "Denk daran den Zahnarzt anzurufen"
  //   "Denk dran Freitag Steuer machen"
  static String? _tryDenkDaran(String text) {
    final rx = RegExp(
      r'^denk\s+dra(?:n|ran)\s+(?:an\s+)?(?:den\s+|die\s+|das\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;
    final rest = m.group(1)!.trim();
    // "anzurufen" / "zu machen" → Infinitiv-Endung entfernen für saubereren Titel
    final cleaned = _stripInfinitive(rest);
    return _buildFuegeAufgabe(cleaned);
  }

  // ── Muster 5: "Kannst du mich [am DATUM] an TITEL erinnern" ────────────────
  // Beispiele:
  //   "Kannst du mich an den Zahnarzt erinnern"
  //   "Kannst du mich morgen an Marcel erinnern"
  static String? _tryKannstDuErinnern(String text) {
    final rx = RegExp(
      r'^(?:kannst\s+du\s+mich|könntest\s+du\s+mich)\s+(.+?)\s+(?:daran\s+)?(?:an\s+(?:den\s+|die\s+|das\s+)?)(.+?)\s+erinnern\??$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m != null) {
      final dateWindow = m.group(1)!.trim();
      final titel = m.group(2)!.trim();
      if (_looksLikeDateOrEmpty(dateWindow)) {
        final datePart = dateWindow.isNotEmpty ? ' für $dateWindow' : '';
        return 'Füge die Aufgabe $titel$datePart hinzu';
      }
    }
    // Simpler Fallback ohne Datum-Splitting
    final simple = RegExp(
      r'^(?:kannst\s+du\s+mich|könntest\s+du\s+mich)\s+(?:daran\s+)?(?:an\s+(?:den\s+|die\s+|das\s+)?)(.+?)\s+erinnern\??$',
      caseSensitive: false,
    ).firstMatch(text);
    if (simple != null) {
      return 'Erinnere mich an: ${simple.group(1)!.trim()}';
    }
    return null;
  }

  // ── Muster 6: "Bitte erinnere mich [DATUM] an TITEL" ──────────────────────
  // Beispiele:
  //   "Bitte erinnere mich an die Versicherung"
  //   "Bitte erinnere mich morgen an den Zahnarzt"
  static String? _tryBitteErinnere(String text) {
    final rx = RegExp(
      r'^(?:bitte\s+)?erinnere?\s+(?:mich\s+)?(?:bitte\s+)?(.+?)\s+an[:\s]+(?:den\s+|die\s+|das\s+)?(.+)$',
      caseSensitive: false,
    );
    final m = rx.firstMatch(text);
    if (m == null) return null;

    final dateWindow = m.group(1)!.trim();
    final titel = m.group(2)!.trim();

    // Prüfen ob dateWindow wirklich ein Datum ist (nicht "mich")
    if (dateWindow == 'mich' || dateWindow.isEmpty) {
      return 'Erinnere mich an: $titel';
    }
    if (_looksLikeDateOrEmpty(dateWindow)) {
      return 'Erinnere mich $dateWindow an: $titel';
    }
    return 'Erinnere mich an: ${m.group(1)!.trim()} ${titel}';
  }

  // ── Muster 7: Satz beginnt mit Datum → Aufgabe dahinter ───────────────────
  // Beispiele:
  //   "Morgen Zahnarzt"
  //   "Freitag um 9 Marcel anrufen"
  //   "Nächste Woche Steuer machen"
  //   "morgen früh Auto waschen"
  //   "am Wochenende Dienstplan erstellen"
  //   "in 2 Wochen Steuer machen"
  static String? _tryNurDatum(String text) {
    final dateStartRx = RegExp(
      r'^($_dateTokens)(?:\s+um\s+\d{1,2}(?::\d{2})?\s*uhr?)?\b\s*(.+)?$',
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
  // Hilfsfunktionen
  // ─────────────────────────────────────────────────────────────────────────

  /// Entfernt typische Füllwörter die das Mustererkennen stören.
  static String _stripFillers(String text) {
    return text
      .replaceAll(RegExp(
        r'\b(?:bitte|mal|eben|kurz|schnell|eigentlich|vielleicht|halt|'
        r'einfach|irgendwie|eigentlich|doch|auch|noch\s+kurz|'
        r'wirklich|unbedingt|auf\s+jeden\s+fall|auf\s+keinen\s+fall)\b',
        caseSensitive: false,
      ), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  }

  /// Baut "Füge die Aufgabe TITEL hinzu" mit optionalem Datum-Extrakt.
  /// Wenn der Rest selbst schon ein Datum am Anfang hat ("morgen Auto waschen"),
  /// wird es korrekt als "für morgen" angehängt.
  static String _buildFuegeAufgabe(String rest) {
    // Datum am Anfang ("morgen früh Auto waschen")
    final dateStartRx = RegExp(
      r'^($_dateTokens)(?:\s+um\s+\d{1,2}(?::\d{2})?\s*uhr?)?\s+(.+)$',
      caseSensitive: false,
    );
    final m = dateStartRx.firstMatch(rest);
    if (m != null) {
      final datePart = m.group(1)!.trim();
      final titel = _stripInfinitive(m.group(2)!.trim());
      return 'Füge die Aufgabe $titel für $datePart hinzu';
    }

    // Datum am Ende ("Auto waschen morgen früh")
    final dateEndRx = RegExp(
      r'^(.+?)\s+($_dateTokens)(?:\s+um\s+\d{1,2}(?::\d{2})?\s*uhr?)?$',
      caseSensitive: false,
    );
    final mEnd = dateEndRx.firstMatch(rest);
    if (mEnd != null) {
      final titel = _stripInfinitive(mEnd.group(1)!.trim());
      final datePart = mEnd.group(2)!.trim();
      return 'Füge die Aufgabe $titel für $datePart hinzu';
    }

    return 'Füge die Aufgabe ${_stripInfinitive(rest)} hinzu';
  }

  /// Prüft ob ein String wie ein Datum/Zeitangabe aussieht
  static bool _looksLikeDateOrEmpty(String s) {
    if (s.isEmpty) return true;
    return RegExp(
      r'^(?:' + _dateTokens + r')',
      caseSensitive: false,
    ).hasMatch(s);
  }

  /// Entfernt typische Infinitiv-Konstruktionen am Ende ("zu machen",
  /// "anzurufen", "erledigen", "machen") — für sauberere Titel.
  static String _stripInfinitive(String s) {
    return s
        .replaceFirst(RegExp(r'\s+(?:zu\s+)?(?:machen|erledigen|tun|fertig\s+machen|fertigmachen)\s*$', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+an(?:zu)?rufen\s*$', caseSensitive: false), ' anrufen') // "anzurufen" → "anrufen"
        .trim();
  }
}