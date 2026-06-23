// ─────────────────────────────────────────────────────────────────────────────
// RULE ENGINE PATTERN TEST RUNNER
//
// Testet NUR die Pattern→Regex-Konvertierung in RuleEngine._tryPatternMatch.
// Das ist eine zweite, unabhängige Fehlerquelle neben Normalizer/Parser —
// Patterns wie "Ich muss [noch] [TITEL]" werden zur Laufzeit in Regex
// umgewandelt. Das willst du separat testen, weil _tryPatternMatch nicht
// über SpeechNormalizer läuft, sondern direkt auf dem Rohtext arbeitet.
//
// PROBLEM: _tryPatternMatch ist private (Unterstrich). Du kannst es von
// außen nicht direkt aufrufen. Hier testen wir daher eine 1:1-Kopie der
// Logik (_simulatePatternMatch). WICHTIG: Wenn du _tryPatternMatch in
// rule_engine.dart änderst, MUSS diese Kopie synchron gehalten werden,
// sonst testest du Code, der so in der App nicht mehr existiert.
// Langfristig besser: _tryPatternMatch mit @visibleForTesting public
// machen, dann brauchst du keine Kopie mehr.
//
// AUSFÜHREN:
//   dart run test/rule_engine_pattern_test_runner.dart
// ─────────────────────────────────────────────────────────────────────────────

class PatternTestCase {
  final String pattern;
  final String input;
  final String? expectedTitle;
  final String? expectedDateRaw; // roher extrahierter [DATUM]-String, vor Parser
  final bool expectNoMatch;
  final String note;

  const PatternTestCase({
    required this.pattern,
    required this.input,
    this.expectedTitle,
    this.expectedDateRaw,
    this.expectNoMatch = false,
    this.note = '',
  });
}



final patternTestCases = <PatternTestCase>[
  PatternTestCase(
    pattern: 'Ich muss [noch] [TITEL]',
    input: 'Ich muss Auto waschen',
    expectedTitle: 'Auto waschen',
  ),
  PatternTestCase(
    pattern: 'Ich muss [noch] [TITEL]',
    input: 'Ich muss noch Auto waschen',
    expectedTitle: 'Auto waschen',
  ),
  PatternTestCase(
    pattern: 'Kannst du mich [DATUM] an [TITEL] erinnern',
    input: 'Kannst du mich morgen an Zahnarzttermin erinnern',
    expectedTitle: 'Zahnarzttermin',
    expectedDateRaw: 'morgen',
  ),
  PatternTestCase(
    pattern: 'Kannst du mich [DATUM] an [TITEL] erinnern',
    input: 'Kannst du mich an Zahnarzttermin erinnern',
    expectedTitle: 'Zahnarzttermin',
    note: 'Ohne Datum — [DATUM] muss leer/optional matchen können',
  ),
  PatternTestCase(
    pattern: 'Vergiss nicht [TITEL]',
    input: 'Vergiss nicht die Blumen zu gießen',
    expectedTitle: 'Die Blumen zu gießen',
    note: 'Prüfen ob "zu gießen" als Infinitiv noch im Titel klebt — evtl. unerwünscht',
  ),
];

/// Kopie der Logik aus RuleEngine._tryPatternMatch — siehe Hinweis oben.
/// WICHTIG: muss synchron zu rule_engine.dart._tryPatternMatch gehalten werden!
/// 
/// Transformation-Schritte (1:1 mit rule_engine.dart):
/// 1. [DATUM] mit Leerzeichen → (?:\s+(?<datum>.+?))?\s+
/// 2. [DATUM] ohne Leerzeichen → (?<datum>.+?)?
/// 3. [TITEL] → (?<titel>.+?)
/// 4. Optionale []-Teile → (?:... )?
/// 5. Mehrfache Leerzeichen → \s+
Map<String, String?>? _simulatePatternMatch(String input, String pattern) {
  try {
    var regexStr = pattern;

    // Schritt 1: [DATUM] mit umgebenden Leerzeichen → optionaler Datumsblock
    regexStr = regexStr.replaceAllMapped(
      RegExp(r' \[DATUM\] '),
      (_) => r'(?:\s+(?<datum>.+?))?\s+',
    );
    // Schritt 2: [DATUM] ohne Leerzeichen → optional
    regexStr = regexStr.replaceAll('[DATUM]', r'(?<datum>.+?)?');
    // Schritt 3: [TITEL] → Named Group
    regexStr = regexStr.replaceAll('[TITEL]', r'(?<titel>.+?)');
    // Schritt 4: Optionale []-Teile → (?:... )?
    regexStr = regexStr.replaceAllMapped(
  RegExp(r' \[([^\]]+)\]'),
  (m) => r'(?:\s+' + RegExp.escape(m.group(1)!) + r')?',
);
    // Schritt 5: Mehrfache Leerzeichen → \s+
    regexStr = regexStr.replaceAll(RegExp(r' +'), r'\s+');

    final rx = RegExp('^$regexStr\$', caseSensitive: false);
    final m = rx.firstMatch(input.trim());
    if (m == null) return null;

    String? titel;
    String? datum;
    try {
      titel = m.namedGroup('titel')?.trim();
    } catch (_) {}
    try {
      datum = m.namedGroup('datum')?.trim();
    } catch (_) {}

    if (titel == null || titel.isEmpty) return null;
    titel = titel[0].toUpperCase() + titel.substring(1);

    return {
      'title': titel,
      'date': datum?.isNotEmpty == true ? datum : null,
    };
  } catch (e) {
    return {'__error__': e.toString()};
  }
}

/// Debug-Funktion: Zeigt die Regex-Transformation für ein Pattern an
/// und testet es mit einigen Beispiel-Inputs.
void debugPatternTransform(String pattern) {
  var regexStr = pattern;

  // Schritt 1: [DATUM] mit umgebenden Leerzeichen → optionaler Datumsblock
  regexStr = regexStr.replaceAllMapped(
    RegExp(r' \[DATUM\] '),
    (_) => r'(?:\s+(?<datum>.+?))?\s+',
  );
  // Schritt 2: [DATUM] ohne Leerzeichen → optional
  regexStr = regexStr.replaceAll('[DATUM]', r'(?<datum>.+?)?');
  // Schritt 3: [TITEL] → Named Group
  regexStr = regexStr.replaceAll('[TITEL]', r'(?<titel>.+?)');
  // Schritt 4: Optionale []-Teile → (?:... )?
  regexStr = regexStr.replaceAllMapped(
  RegExp(r' \[([^\]]+)\]'),
  (m) => r'(?:\s+' + RegExp.escape(m.group(1)!) + r')?',
);
  // Schritt 5: Mehrfache Leerzeichen → \s+
  regexStr = regexStr.replaceAll(RegExp(r' +'), r'\s+');

  print('╔═══════════════════════════════════════════════════════════════════');
  print('║ PATTERN: $pattern');
  print('║ REGEX:   ^$regexStr\$');
  print('╚═══════════════════════════════════════════════════════════════════');

  final rx = RegExp('^$regexStr\$', caseSensitive: false);
  
  // Test-Inputs
  final testInputs = [
    'Kannst du mich morgen an Zahnarzttermin erinnern',
    'Kannst du mich an Zahnarzttermin erinnern',
    'Kannst du mich am Wochenende an Zahnarzttermin erinnern',
  ];
  
  for (final inp in testInputs) {
    final m = rx.firstMatch(inp);
    print('  📝 "$inp"');
    if (m == null) {
      print('     ❌ KEIN MATCH');
    } else {
      final titel = m.namedGroup('titel');
      final datum = m.namedGroup('datum');
      print('     ✅ titel="$titel" datum="$datum"');
    }
  }
  print('');
}

void main() {
  print('═' * 70);
  print('DEBUG PATTERN TRANSFORM');
  print('═' * 70);
  print('');
  
  // ── Teste die Pattern-Transformation ──
  debugPatternTransform('Kannst du mich [DATUM] an [TITEL] erinnern');
  
  print('═' * 70);
  print('RULE ENGINE PATTERN TEST RUN — ${patternTestCases.length} Testfälle');
  print('═' * 70);

  int passed = 0;
  int failed = 0;

  for (final tc in patternTestCases) {
    final result = _simulatePatternMatch(tc.input, tc.pattern);
    final problems = <String>[];

    if (result != null && result.containsKey('__error__')) {
      failed++;
      print('');
      print('✗ REGEX-FEHLER bei Pattern: "${tc.pattern}"');
      print('  Input: "${tc.input}"');
      print('  Fehler: ${result['__error__']}');
      continue;
    }

    if (tc.expectNoMatch) {
      if (result != null) {
        problems.add('Erwartet KEIN Match, aber bekommen: $result');
      }
    } else {
      if (result == null) {
        problems.add('Kein Match, aber Match erwartet');
      } else {
        if (tc.expectedTitle != null && result['title'] != tc.expectedTitle) {
          problems.add(
            'Titel erwartet: "${tc.expectedTitle}", bekommen: "${result['title']}"',
          );
        }
        if (tc.expectedDateRaw != null && result['date'] != tc.expectedDateRaw) {
          problems.add(
            'Datum-Rohstring erwartet: "${tc.expectedDateRaw}", bekommen: "${result['date']}"',
          );
        }
      }
    }

    if (problems.isEmpty) {
      passed++;
      print('✓ Pattern "${tc.pattern}" + Input "${tc.input}"');
      print('    → $result');
    } else {
      failed++;
      print('');
      print('✗ Pattern "${tc.pattern}" + Input "${tc.input}"');
      print('    → $result');
      for (final p in problems) print('    ⚠ $p');
      if (tc.note.isNotEmpty) print('    ℹ ${tc.note}');
    }
  }

  print('');
  print('═' * 70);
  print('ERGEBNIS: $passed bestanden, $failed fehlgeschlagen von ${patternTestCases.length}');
  print('═' * 70);
}