import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';

// ─────────────────────────────────────────────────────────────────────────────
// RULE ENGINE
//
// Wird VOR SpeechNormalizer + SpokenTaskParser aufgerufen.
// Prüft den Rohtext gegen alle aktiven Regeln aus learned_rules (Firestore).
// Regeln werden in Hive gecacht → Offline-fähig.
//
// Aufruf in tasks_screen.dart → _onRevealComplete():
//
//   final ruleMatch = await RuleEngine.instance.match(text);
//   if (ruleMatch != null) {
//     widget.onResult(ruleMatch);
//     // Bubble-Reset etc. wie gewohnt
//     return;
//   }
//   // Kein Treffer → normaler Pfad
//   final normalized = SpeechNormalizer.normalize(text);
//   final parsed = SpokenTaskParser.parse(normalized);
//   ...
//
// Matching-Strategie (in dieser Reihenfolge):
//   1. Exakter Match (lowercase, getrimmt)
//   2. Normalisierter Match (Sonderzeichen weg, mehrfache Leerzeichen kollabiert)
//   3. Fuzzy: Jedes Wort der Regel kommt im Input vor (Wortmenge-Subset)
//      → nur wenn Übereinstimmung ≥ 80 % der Regelwörter
// ─────────────────────────────────────────────────────────────────────────────

// Importiere den Parser-Output-Typ — Pfad ggf. anpassen wenn anders strukturiert
// ignore: depend_on_referenced_packages
import 'spoken_task_parser.dart'; // ParsedSpokenTask, TaskPriority, DateTimeComponents

class LearnedRule {
  final String id;
  final String originalText;
  final String title;
  final String? dateHint;
  final String? pattern;

  const LearnedRule({
    required this.id,
    required this.originalText,
    required this.title,
    this.dateHint,
    this.pattern,
  });

  factory LearnedRule.fromMap(String id, Map<String, dynamic> data) {
    return LearnedRule(
      id: id,
      originalText: data['originalText'] as String? ?? '',
      title: data['title'] as String? ?? '',
      dateHint: data['dateHint'] as String?,
      pattern: data['pattern'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'originalText': originalText,
        'title': title,
        'dateHint': dateHint,
        'pattern': pattern,
      };
}

class RuleMatchData {
  final LearnedRule rule;
  final String normalizedText;
  final Set<String> words;
  final RegExp? patternRegex;

  const RuleMatchData({
    required this.rule,
    required this.normalizedText,
    required this.words,
    required this.patternRegex,
  });
}

class RuleEngine {
  RuleEngine._();
  static final instance = RuleEngine._();

  static const _hiveBox = 'einstellungen';
  static const _hiveCacheKey = 'learned_rules_cache';

  List<LearnedRule> _rules = [];
  List<RuleMatchData> _ruleMatchCache = [];
  bool _initialized = false;
  StreamSubscription<QuerySnapshot>? _rulesSub;

  // ── Init: Firestore-Listener + Hive-Fallback ─────────────────────────────

  /// Einmalig beim App-Start aufrufen (z.B. in main() nach Firebase.init).
  /// Lädt sofort den Hive-Cache, dann startet ein Realtime-Listener auf
  /// Firestore, der bei Änderungen automatisch den Cache aktualisiert.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Sofort aus Hive laden → Parser kann in der ersten Session offline arbeiten
    _loadFromHive();

    // Realtime-Listener: aktualisiert _rules + Hive bei jeder Änderung
    _rulesSub = FirebaseFirestore.instance
        .collection('learned_rules')
        .where('status', isEqualTo: 'active')
        .snapshots()
        .listen(
      (snapshot) {
        final rules = snapshot.docs
            .map((doc) => LearnedRule.fromMap(doc.id, doc.data()))
            .toList();
        _rules = rules;
        _ruleMatchCache = buildRuleMatchCache(rules);
        _saveToHive(rules);
      },
      onError: (e) {
        // Kein Internet / Fehler → Hive-Cache bleibt aktiv, kein Crash
        debugLog('RuleEngine: Firestore-Fehler, nutze Cache. $e');
      },
    );
  }

  /// Beendet den Firestore-Listener. Für Logout oder Re-Init nützlich.
  Future<void> dispose() async {
    await _rulesSub?.cancel();
    _rulesSub = null;
    _ruleMatchCache = [];
    _initialized = false;
  }

  // ── Hive-Cache ────────────────────────────────────────────────────────────

  void _loadFromHive() {
    try {
      final box = Hive.box(_hiveBox);
      final raw = box.get(_hiveCacheKey);
      if (raw is List) {
        _rules = raw
            .whereType<Map>()
            .map((m) => LearnedRule.fromMap(
                  m['id'] as String? ?? '',
                  Map<String, dynamic>.from(m),
                ))
            .where((r) => r.id.isNotEmpty && r.originalText.isNotEmpty)
            .toList();
        _ruleMatchCache = buildRuleMatchCache(_rules);
        debugLog('RuleEngine: ${_rules.length} Regeln aus Cache geladen.');
      }
    } catch (e) {
      debugLog('RuleEngine: Hive-Ladefehler. $e');
    }
  }

  void _saveToHive(List<LearnedRule> rules) {
    try {
      final box = Hive.box(_hiveBox);
      box.put(
        _hiveCacheKey,
        rules.map((r) => r.toMap()).toList(),
      );
    } catch (e) {
      debugLog('RuleEngine: Hive-Speicherfehler. $e');
    }
  }

  // ── Match ─────────────────────────────────────────────────────────────────

  /// Gibt ein [ParsedSpokenTask] zurück wenn eine Regel greift, sonst null.
  /// Ist synchron (keine async nötig, da _rules bereits im Speicher).
  ParsedSpokenTask? match(String rawText) {
    if (_ruleMatchCache.isEmpty) return null;

    final input = rawText.trim();
    final inputNorm = _normalizeInternal(input);
    final inputWords = _words(inputNorm);

    LearnedRule? bestRule;
    _MatchQuality bestQuality = _MatchQuality.none;
    String? bestExtractedTitle;
    String? bestExtractedDate;

    for (final cachedRule in _ruleMatchCache) {
      final rule = cachedRule.rule;
      if (rule.originalText.isEmpty || rule.title.isEmpty) continue;

      String? extractedTitle;
      String? extractedDate;
      _MatchQuality quality;

      // ── Pattern-Match (höchste Prio wenn Pattern vorhanden) ──────────────
      if (cachedRule.patternRegex != null) {
        final patternResult = _tryPatternMatch(input, rule, cachedRule.patternRegex);
        if (patternResult != null) {
          extractedTitle = patternResult['title'];
          extractedDate = patternResult['date'];
          quality = _MatchQuality.pattern;
          if (quality.index > bestQuality.index) {
            bestQuality = quality;
            bestRule = rule;
            bestExtractedTitle = extractedTitle;
            bestExtractedDate = extractedDate;
          }
          continue;
        }
      }

      // ── Bisheriges Matching (Fallback) ────────────────────────────────────
      final ruleNorm = cachedRule.normalizedText;
      final ruleWords = cachedRule.words;

      if (inputNorm == ruleNorm) {
        quality = _MatchQuality.exact;
      } else if (inputNorm.contains(ruleNorm) && ruleNorm.length > 4) {
        quality = _MatchQuality.contains;
      } else if (ruleWords.isNotEmpty) {
        final matched = ruleWords.where((w) => inputWords.contains(w)).length;
        final ratio = matched / ruleWords.length;
        if (ratio >= 0.80 && matched >= 2) {
          quality = _MatchQuality.fuzzy;
        } else {
          continue;
        }
      } else {
        continue;
      }

      if (quality.index > bestQuality.index) {
        bestQuality = quality;
        bestRule = rule;
        bestExtractedTitle = null;
        bestExtractedDate = null;
        if (bestQuality == _MatchQuality.exact) break;
      }
    }

    if (bestRule == null) return null;

    debugLog('RuleEngine: Treffer (${bestQuality.name}) → „${bestExtractedTitle ?? bestRule.title}"');

    final finalTitle = bestExtractedTitle ?? bestRule.title;
    final finalDateHint = bestExtractedDate ?? bestRule.dateHint;
    final dateHintParsed = _parseDateHint(finalDateHint);

    return ParsedSpokenTask(
      title: finalTitle,
      rawText: rawText,
      date: dateHintParsed?.date,
      time: dateHintParsed?.time,
    );
  }
  // ── Hilfsfunktionen ───────────────────────────────────────────────────────

  /// Lowercase + Sonderzeichen/Satzzeichen entfernen + Leerzeichen normalisieren.
  /// Public, damit auch außerhalb (z.B. Duplikat-Check in tasks_screen.dart)
  /// dieselbe Normalisierung für Titel-Vergleiche genutzt werden kann.
  static String normalizeForCompare(String s) => _normalizeInternal(s);

  @visibleForTesting
  static List<RuleMatchData> buildRuleMatchCache(List<LearnedRule> rules) {
    return rules
        .where((rule) => rule.originalText.isNotEmpty && rule.title.isNotEmpty)
        .map((rule) {
          return RuleMatchData(
            rule: rule,
            normalizedText: _normalizeInternal(rule.originalText),
            words: _words(_normalizeInternal(rule.originalText)),
            patternRegex: _compilePatternRegex(rule.pattern),
          );
        })
        .toList(growable: false);
  }

  /// Versucht den Input gegen das Pattern der Regel zu matchen.
  /// Pattern-Format: "Ich muss [noch] [TITEL]" oder "Kannst du mich [DATUM] an [TITEL] erinnern"
  /// Gibt Map mit 'title' und optional 'date' zurück, oder null wenn kein Match.
  Map<String, String?>? _tryPatternMatch(String input, LearnedRule rule, [RegExp? compiledRegex]) {
    if (rule.pattern == null) return null;

    try {
      final rx = compiledRegex ?? _compilePatternRegex(rule.pattern);
      if (rx == null) return null;

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

      // Titel aufräumen
      titel = titel[0].toUpperCase() + titel.substring(1);

      return {
        'title': titel,
        'date': datum?.isNotEmpty == true ? datum : null,
      };
    } catch (e) {
      debugLog('RuleEngine: Pattern-Match Fehler: $e');
      return null;
    }
  }

  static String _normalizeInternal(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\säöüß]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static RegExp? _compilePatternRegex(String? pattern) {
    if (pattern == null || !pattern.contains('[TITEL]')) return null;

    try {
      var regexStr = pattern;

      // A: [DATUM] mit umgebenden Leerzeichen als Einheit — kontextsensitiv per RegExp
      regexStr = regexStr.replaceAllMapped(
        RegExp(r' \[DATUM\] '),
        (_) => r'(?:\s+(?<datum>.+?))?\s+',
      );
      // Fallback: [DATUM] ohne Leerzeichen-Kontext (Anfang/Ende des Patterns)
      regexStr = regexStr.replaceAll('[DATUM]', r'(?<datum>.+?)?');

      // B: [TITEL]
      regexStr = regexStr.replaceAll('[TITEL]', r'(?<titel>.+?)');

      // C: optionale Literalwörter [wort] — alle noch verbleibenden [...]-Blöcke
      regexStr = regexStr.replaceAllMapped(
        RegExp(r' \[([^\]]+)\]'),
        (m) => r'(?:\s+' + RegExp.escape(m.group(1)!) + r')?',
      );
      // D: alle Literal-Leerzeichen → \s+ (erst jetzt, nachdem alle Platzhalter weg sind)
      regexStr = regexStr.replaceAll(RegExp(r' +'), r'\s+');

      return RegExp('^$regexStr\$', caseSensitive: false);
    } catch (e) {
      debugLog('RuleEngine: Pattern-Regex Fehler: $e');
      return null;
    }
  }

  /// Wortliste aus normalisiertem String, Stoppwörter herausfiltern
  static Set<String> _words(String normalized) {
    const stopwords = {
      'ich', 'du', 'er', 'sie', 'wir', 'ihr', 'ein', 'eine', 'einer',
      'einen', 'einem', 'eines', 'der', 'die', 'das', 'den', 'dem',
      'des', 'und', 'oder', 'aber', 'mit', 'ohne', 'von', 'zu', 'an',
      'auf', 'in', 'für', 'bei', 'nach', 'über', 'unter', 'vor',
      'mich', 'mir', 'dich', 'dir', 'ihn', 'ihm', 'uns', 'euch',
      'bitte', 'mal', 'noch', 'auch', 'schon', 'ja', 'nein',
    };
    return normalized
        .split(' ')
        .where((w) => w.length > 2 && !stopwords.contains(w))
        .toSet();
  }

  // ── DateHint → Datum/Zeit ─────────────────────────────────────────────────
  // Delegiert an SpokenTaskParsers internen _extractDateTimeFromWindow.
  // Da diese Methode private ist, bauen wir hier einen Mini-Wrapper:
  // wir konstruieren einfach einen "Erinnere mich [dateHint] an: x"-String
  // und lassen den Parser ran.

  static _HintResult? _parseDateHint(String? hint) {
    if (hint == null || hint.isEmpty) return null;
    // Wir parsen via SpokenTaskParser: "Erinnere mich [hint] an: placeholder"
    // Der Parser gibt uns date + time, den Titel ignorieren wir.
    try {
      final fakeInput = 'Erinnere mich $hint an: placeholder';
      final result = SpokenTaskParser.parse(fakeInput);
      if (result.date != null || result.time != null) {
        return _HintResult(date: result.date, time: result.time);
      }
    } catch (_) {}
    return null;
  }

  // ── Debug-Log (nur im Debug-Mode) ─────────────────────────────────────────
  static void debugLog(String msg) {
    debugPrint('[RuleEngine] $msg');
  }
}

enum _MatchQuality { none, fuzzy, contains, exact, pattern }

class _HintResult {
  final DateTime? date;
  final DateTimeComponents? time;
  const _HintResult({this.date, this.time});
}