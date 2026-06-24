// ─────────────────────────────────────────────────────────────────────────────
// PARSER TEST RUNNER
//
// Eigenständiges Dart-Skript — KEIN Flutter, KEIN Mikrofon, KEINE App nötig.
// Testet SpeechNormalizer + SpokenTaskParser direkt, Satz für Satz.
//
// AUSFÜHREN:
//   dart run test/parser_test_runner.dart
//
// (oder Klick auf "Run" über main() in deiner IDE)
//
// WICHTIG: Pass die zwei Imports unten an deine echten Dateipfade an.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:OpTimes/services/speech_normalizer.dart';
import 'package:OpTimes/services/spoken_task_parser.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TESTFALL-DEFINITION
// ─────────────────────────────────────────────────────────────────────────────

class TestCase {
  final String input;
  final String? expectedTitleContains; // Titel muss diesen Substring enthalten
  final int? expectedHour; // erwartete Stunde (24h, null = "keine Prüfung")
  final int? expectedMinute;
  final int? expectedDateOffsetDays; // Tage relativ zu HEUTE (0 = heute, 1 = morgen, ...)
  final bool expectDateNull; // true = es darf explizit KEIN Datum erkannt werden
  final bool expectTimeNull; // true = es darf explizit KEINE Uhrzeit erkannt werden
  final String note;

  const TestCase({
    required this.input,
    this.expectedTitleContains,
    this.expectedHour,
    this.expectedMinute,
    this.expectedDateOffsetDays,
    this.expectDateNull = false,
    this.expectTimeNull = false,
    this.note = '',
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// TESTFÄLLE — hier erweiterst du einfach die Liste
// ─────────────────────────────────────────────────────────────────────────────

final testCases = <TestCase>[
  // ── Die 3-Uhr-Regel (Kernanforderung) ─────────────────────────────────────
  TestCase(
    input: 'Erinnere mich um 3 Uhr an: Medikamente nehmen',
    expectedHour: 3,
    expectedMinute: 0,
    note: '3 Uhr MUSS 3 Uhr bleiben, nicht 15 Uhr',
  ),
  TestCase(
    input: 'Erinnere mich um 15 Uhr an: Meeting',
    expectedHour: 15,
    expectedMinute: 0,
    note: '15 Uhr MUSS 15 Uhr bleiben',
  ),
  TestCase(
    input: 'Erinnere mich um 7 Uhr an: Aufstehen',
    expectedHour: 7,
    expectedMinute: 0,
    note: 'Früher Morgen, kein PM-Shift',
  ),
  TestCase(
    input: 'Erinnere mich um 19 Uhr an: Tochter abholen',
    expectedHour: 19,
    expectedMinute: 0,
  ),
  TestCase(
    input: 'Erinnere mich halb 3 an: Tee aufsetzen',
    expectedHour: 2,
    expectedMinute: 30,
    note: '"halb 3" = 2:30, nicht 14:30',
  ),
  TestCase(
    input: 'Erinnere mich viertel vor 3 an: Anruf',
    expectedHour: 2,
    expectedMinute: 45,
  ),

  // ── Kern-Muster 1: "Füge die Aufgabe ... hinzu" ──────────────────────────
  TestCase(
    input: 'Füge die Aufgabe Auto waschen hinzu',
    expectedTitleContains: 'Auto waschen',
    expectDateNull: true,
  ),
  TestCase(
    input: 'Füge die Aufgabe Steuererklärung für morgen hinzu',
    expectedTitleContains: 'Steuererklärung',
    expectedDateOffsetDays: 1,
  ),
  TestCase(
    input: 'Füge die Aufgabe Zahnarzttermin mit Frist nächsten Montag hinzu',
    expectedTitleContains: 'Zahnarzttermin',
    note: 'mit-Frist-Variante — Datum-Offset variiert je Wochentag, daher kein offset-check',
  ),

  // ── Kern-Muster 2: "Erinnere mich an: ..." ───────────────────────────────
  TestCase(
    input: 'Erinnere mich an: Wäsche aufhängen',
    expectedTitleContains: 'Wäsche aufhängen',
    expectDateNull: true,
  ),
  TestCase(
    input: 'Erinnere mich an Wäsche aufhängen',
    expectedTitleContains: 'Wäsche aufhängen',
    note: 'ohne Doppelpunkt — häufiger Sprachfehler',
  ),
  TestCase(
    input: 'Erinnere mich morgen an: Steuern zahlen',
    expectedTitleContains: 'Steuern zahlen',
    expectedDateOffsetDays: 1,
  ),

  // ── Natürliche Sprache über Normalizer ───────────────────────────────────
  TestCase(
    input: 'Ich muss noch Auto waschen',
    expectedTitleContains: 'Auto waschen',
  ),
  TestCase(
    input: 'Ich muss morgen früh Auto waschen',
    expectedTitleContains: 'Auto waschen',
    expectedDateOffsetDays: 1,
  ),
  TestCase(
    input: 'Ich sollte unbedingt die Wohnung putzen',
    expectedTitleContains: 'Wohnung putzen',
  ),
  TestCase(
    input: 'Nicht vergessen: Geburtstagsgeschenk kaufen',
    expectedTitleContains: 'Geburtstagsgeschenk kaufen',
  ),
  TestCase(
    input: 'Denk daran morgen die Reifen zu wechseln',
    expectedDateOffsetDays: 1,
    note: 'Infinitiv "zu wechseln" sollte gestrippt werden — Titel manuell prüfen',
  ),
  TestCase(
    input: 'Kannst du mich morgen an den Zahnarzttermin erinnern',
    expectedTitleContains: 'Zahnarzttermin',
    expectedDateOffsetDays: 1,
  ),
  TestCase(
    input: 'Bitte erinnere mich übermorgen an die Steuererklärung',
    expectedTitleContains: 'Steuererklärung',
    expectedDateOffsetDays: 2,
  ),
  TestCase(
    input: 'Ruf morgen Marcel an',
    expectedTitleContains: 'Marcel anrufen',
    expectedDateOffsetDays: 1,
    note: 'Imperativ-Muster — Titel-Form genau prüfen, ggf. "Marcel an" statt "Marcel anrufen"',
  ),
  TestCase(
    input: 'Kaufe Milch',
    expectedTitleContains: 'Milch',
  ),

  // ── Benannte Uhrzeiten ────────────────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich abends an: Blumen gießen',
    expectedHour: 19,
    note: '"abends" → 19 Uhr laut Normalizer-Mapping',
  ),
  TestCase(
    input: 'Erinnere mich mittags an: Mittagessen vorbereiten',
    expectedHour: 12,
  ),
  TestCase(
    input: 'Erinnere mich gegen 3 an: Kaffee aufsetzen',
    expectedHour: 3,
    note: '"gegen 3" → Normalizer macht "um 3 Uhr" → MUSS 3 bleiben, nicht 15',
  ),

  // ── Datum-Formate ─────────────────────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich am 15. März an: Versicherung kündigen',
    expectedTitleContains: 'Versicherung kündigen',
    note: 'Datum exakt prüfen: 15. März des laufenden oder nächsten Jahres',
  ),
  TestCase(
    input: 'Erinnere mich am Monatsende an: Miete überweisen',
    expectedTitleContains: 'Miete überweisen',
    note: 'Datum = letzter Tag des aktuellen Monats',
  ),
  TestCase(
    input: 'Erinnere mich übernächste Woche an: Projektplan abgeben',
    expectedDateOffsetDays: 14,
  ),
  TestCase(
    input: 'Erinnere mich nächsten Freitag an: Bericht abgeben',
    note: 'Wochentag-Logik — Offset hängt vom aktuellen Wochentag ab, manuell prüfen',
  ),

  // ── Edge Cases / Overflow-Schutz ─────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich am 31. Februar an: Unmögliches Datum',
    expectDateNull: true,
    note: 'MUSS null sein statt falsch auf März zu überlaufen',
  ),
  TestCase(
    input: 'Erinnere mich am 30. Februar an: Auch unmöglich',
    expectDateNull: true,
  ),
  TestCase(
    input: 'Erinnere mich in 11 Monaten an: Langzeitplanung',
    note: 'Jahreswechsel-Overflow prüfen, falls aktueller Monat + 11 über Dezember läuft',
  ),

  // ── Leere / kaputte Eingaben ──────────────────────────────────────────────
  TestCase(
    input: '',
    note: 'Leerer String darf nicht crashen',
  ),
  TestCase(
    input: 'Erinnere mich an:',
    note: 'Leerer Titel nach "an:" — darf nicht crashen, Titel evtl. leer/Fallback',
  ),
  TestCase(
    input: 'asdf jkl;',
    note: 'Kompletter Kauderwelsch — sollte in den Fallback-Pfad laufen',
  ),

  // ── Neue Fälle aus Sprach-Log (KORRIGIERT) ──────────────────────────────
  TestCase(
    input: 'Füge für heute Sport zu meinen Erinnerungen hinzu',
    expectedTitleContains: 'Sport',
    expectedDateOffsetDays: 0, // heute
    note: 'Füge-Variante mit "zu meinen Erinnerungen" statt "die Aufgabe"',
  ),
  TestCase(
    input: 'Füge die Aufgabe Waffenkammer hinzu mit Frist 6. Juli',
    expectedTitleContains: 'Waffenkammer',
    note: '"mit Frist" nach "hinzu" — Reihenfolge anders als Parser erwartet',
  ),
  TestCase(
    input: 'Erinnere mich morgen daran den Dienstplan zu schreiben',
    expectedTitleContains: 'Dienstplan',
    expectedDateOffsetDays: 1,
    note: '"daran" nach Datum bricht Erinnere-Muster',
  ),

  // ── Neue Fälle aus Sprach-Log 2026-06-23 ──────────────────────────────────

  // "daran"-Varianten — Normalizer kennt das Muster nicht
  TestCase(
    input: 'Erinnere mich morgen daran das Auto zu waschen',
    expectedTitleContains: 'Auto waschen',
    expectedDateOffsetDays: 1,
    note: '"daran" nach Datum — Normalizer-Bug',
  ),
  TestCase(
    input: 'Erinnere mich morgen Mittag daran den Autoschlüssel zu übergeben',
    expectedTitleContains: 'Autoschlüssel übergeben',
    expectedDateOffsetDays: 1,
    expectedHour: 12,
    expectedMinute: 0,
    note: '"daran" nach Datum+Uhrzeit',
  ),
  TestCase(
    input: 'Erinnere mich morgen daran den Duden mitzunehmen',
    expectedTitleContains: 'Duden mitnehmen',
    expectedDateOffsetDays: 1,
    note: '"daran" + Infinitiv mit "mit-"',
  ),
  TestCase(
    input: 'Erinnere mich daran morgen an meinen Schlüssel zu denken',
    expectedTitleContains: 'Schlüssel',
    expectedDateOffsetDays: 1,
    note: '"daran" VOR Datum — andere Wortstellung',
  ),
  TestCase(
    input: 'Erinnere mich daran die Wäsche zu waschen',
    expectedTitleContains: 'Wäsche',
    expectDateNull: true,
    note: '"daran" ohne Datum',
  ),

  // "Erinner" statt "Erinnere" — Spracherkennungsvariante
  TestCase(
    input: 'Erinner mich am Freitag an Blumen für Carina',
    expectedTitleContains: 'Blumen für Carina',
    note: '"Erinner" ohne -e am Ende — Datum variiert je Wochentag',
  ),
  TestCase(
    input: 'Erinner mich am Mittwoch an meine Karte',
    expectedTitleContains: 'Karte',
    note: '"Erinner" + Possessivpronomen im Titel — Datum variiert je Wochentag',
  ),

  // Possessivpronomen im Titel — sollen rausgefiltert werden
  TestCase(
    input: 'Erinnere mich morgen an meinen grünen Anzug',
    expectedTitleContains: 'Grünen Anzug',
    expectedDateOffsetDays: 1,
    note: '"meinen" soll aus Titel entfernt werden',
  ),
  TestCase(
    input: 'Erinnere mich morgen an mein Haustier',
    expectedTitleContains: 'Haustier',
    expectedDateOffsetDays: 1,
    note: '"mein" soll aus Titel entfernt werden',
  ),
  TestCase(
    input: 'Erinnere mich morgen an meinen Schlüssel',
    expectedTitleContains: 'Schlüssel',
    expectedDateOffsetDays: 1,
    note: '"meinen" soll aus Titel entfernt werden',
  ),
  TestCase(
    input: 'Erinnere mich übermorgen an meinen PC',
    expectedTitleContains: 'PC',
    expectedDateOffsetDays: 2,
    note: '"meinen" soll aus Titel entfernt werden',
  ),

  // "mit Frist" nach "hinzu" — falsche Reihenfolge
  TestCase(
    input: 'Füge die Aufgabe Sportschuhe mit Frist in einer Woche hinzu',
    expectedTitleContains: 'Sportschuhe',
    expectedDateOffsetDays: 7,
    note: '"in einer Woche" als Datum — RelativDatum-Variante',
  ),
  // ── Datum + Uhrzeit kombiniert ────────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich morgen um 14:30 an: Meeting',
    expectedTitleContains: 'Meeting',
    expectedDateOffsetDays: 1,
    expectedHour: 14,
    expectedMinute: 30,
    note: 'Datum + exakte Uhrzeit mit Doppelpunkt',
  ),
  TestCase(
    input: 'Erinnere mich übermorgen abends an: Zahnarzt',
    expectedTitleContains: 'Zahnarzt',
    expectedDateOffsetDays: 2,
    expectedHour: 19,
    note: '"abends" nach Datum',
  ),

  // ── daran + Datum + Uhrzeit ───────────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich morgen Abend daran den Vertrag zu unterschreiben',
    expectedTitleContains: 'Vertrag unterschreiben',
    expectedDateOffsetDays: 1,
    expectedHour: 19,
    note: '"daran" nach Datum+Uhrzeit, Infinitiv mit Umlaut-Verb',
  ),

  // ── _stripInfinitive Grenzfälle ───────────────────────────────────────────
  TestCase(
    input: 'Erinnere mich morgen daran die Wohnung aufzuräumen',
    expectedTitleContains: 'Wohnung aufräumen',
    expectedDateOffsetDays: 1,
    note: 'Infinitiv mit Umlaut: "aufzuräumen"',
  ),
  TestCase(
    input: 'Ich muss die Küche zu erledigen',
    expectedTitleContains: 'Küche',
    note: '"zu erledigen" soll gestrippt werden',
  ),

  // ── _buildFuegeAufgabe Datum am Ende ─────────────────────────────────────
  TestCase(
    input: 'Ich muss Sport treiben morgen früh',
    expectedTitleContains: 'Sport treiben',
    expectedDateOffsetDays: 1,
    note: 'Datum nach Titel in _buildFuegeAufgabe',
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// TEST RUNNER
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  final today = DateTime.now();
  final todayMidnight = DateTime(today.year, today.month, today.day);

  int passed = 0;
  int failed = 0;
  final failures = <String>[];

  print('═' * 70);
  print('PARSER TEST RUN — ${testCases.length} Testfälle');
  print('Heute: ${todayMidnight.toIso8601String().split('T').first}');
  print('═' * 70);

  for (final tc in testCases) {
    final problems = <String>[];

    String normalized;
    dynamic parsed; // ParsedSpokenTask, dynamic hier nur falls Import-Pfad variiert

    try {
      normalized = SpeechNormalizer.normalize(tc.input);
      parsed = SpokenTaskParser.parse(normalized);
    } catch (e, st) {
      failed++;
      print('');
      print('✗ CRASH bei Input: "${tc.input}"');
      print('  Fehler: $e');
      print('  ${tc.note.isNotEmpty ? "Hinweis: ${tc.note}" : ""}');
      failures.add('"${tc.input}" → CRASH: $e');
      continue;
    }

    // Titel prüfen
    if (tc.expectedTitleContains != null) {
      final titleLower = (parsed.title as String).toLowerCase();
      final expectedLower = tc.expectedTitleContains!.toLowerCase();
      if (!titleLower.contains(expectedLower)) {
        problems.add(
          'Titel erwartet enthält "${tc.expectedTitleContains}", '
          'bekommen: "${parsed.title}"',
        );
      }
    }

    // Datum: null erwartet?
    if (tc.expectDateNull && parsed.date != null) {
      problems.add('Datum sollte null sein, war aber: ${parsed.date}');
    }

    // Datum-Offset prüfen
    if (tc.expectedDateOffsetDays != null) {
      if (parsed.date == null) {
        problems.add('Datum erwartet (Offset ${tc.expectedDateOffsetDays} Tage), war aber null');
      } else {
        final expectedDate =
            todayMidnight.add(Duration(days: tc.expectedDateOffsetDays!));
        final gotDate = DateTime(
          (parsed.date as DateTime).year,
          (parsed.date as DateTime).month,
          (parsed.date as DateTime).day,
        );
        if (gotDate != expectedDate) {
          problems.add(
            'Datum erwartet: ${expectedDate.toIso8601String().split('T').first} '
            '(Offset ${tc.expectedDateOffsetDays}), '
            'bekommen: ${gotDate.toIso8601String().split('T').first}',
          );
        }
      }
    }

    // Uhrzeit: null erwartet?
    if (tc.expectTimeNull && parsed.time != null) {
      problems.add('Uhrzeit sollte null sein, war aber: ${parsed.time}');
    }

    // Stunde prüfen — HIER liegt die 3-Uhr/15-Uhr-Regel
    if (tc.expectedHour != null) {
      if (parsed.time == null) {
        problems.add('Uhrzeit erwartet (${tc.expectedHour} Uhr), war aber null');
      } else if (parsed.time.hour != tc.expectedHour) {
        problems.add(
          'STUNDE FALSCH: erwartet ${tc.expectedHour} Uhr, '
          'bekommen ${parsed.time.hour} Uhr  ← PRÜFE _ph()-FIX!',
        );
      }
    }

    // Minute prüfen
    if (tc.expectedMinute != null) {
      if (parsed.time == null) {
        problems.add('Minute erwartet (${tc.expectedMinute}), Uhrzeit war aber null');
      } else if (parsed.time.minute != tc.expectedMinute) {
        problems.add(
          'Minute falsch: erwartet ${tc.expectedMinute}, bekommen ${parsed.time.minute}',
        );
      }
    }

    if (problems.isEmpty) {
      passed++;
      print('✓ "${tc.input}"');
      print('    → Titel: "${parsed.title}" | Datum: ${parsed.date} | Zeit: ${parsed.time}');
    } else {
      failed++;
      print('');
      print('✗ "${tc.input}"');
      print('    Normalisiert zu: "$normalized"');
      print('    → Titel: "${parsed.title}" | Datum: ${parsed.date} | Zeit: ${parsed.time}');
      for (final p in problems) {
        print('    ⚠ $p');
      }
      if (tc.note.isNotEmpty) print('    ℹ ${tc.note}');
      failures.add('"${tc.input}" → ${problems.join("; ")}');
    }
  }

  print('');
  print('═' * 70);
  print('ERGEBNIS: $passed bestanden, $failed fehlgeschlagen von ${testCases.length}');
  print('═' * 70);

  if (failures.isNotEmpty) {
    print('');
    print('ZUSAMMENFASSUNG DER FEHLER:');
    for (final f in failures) {
      print('  - $f');
    }
  }
}