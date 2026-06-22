import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SPEECH LOG
//
// Speichert jeden Sprachbefehl mit:
//   - rawText:     was der User gesagt hat (direkt von STT)
//   - normalized:  was SpeechNormalizer draus gemacht hat
//   - parsedTitle: was SpokenTaskParser als Titel erkannt hat
//   - hasDate:     hat der Parser ein Datum erkannt?
//   - success:     hat der Normalizer das Muster erkannt? (normalized != raw)
//   - timestamp:   wann es passiert ist
//
// Gespeichert in Hive-Box "speech_log" als JSON-Liste.
// Max. 200 Einträge (älteste werden automatisch gelöscht).
// ─────────────────────────────────────────────────────────────────────────────

class SpeechLogEntry {
  final String rawText;
  final String normalized;
  final String parsedTitle;
  final bool hasDate;
  final bool normalizerHit; // true wenn Normalizer ein Muster erkannt hat
  final DateTime timestamp;

  const SpeechLogEntry({
    required this.rawText,
    required this.normalized,
    required this.parsedTitle,
    required this.hasDate,
    required this.normalizerHit,
    required this.timestamp,
  });

  /// true = System hat alles erkannt (Normalizer + Parser haben Datum/Muster gefunden)
  /// false = irgendwas wurde nicht erkannt → interessant zum Analysieren
  bool get isFullSuccess => normalizerHit && hasDate;

  /// Kurze Status-Beschreibung für die UI
  String get statusLabel {
    if (isFullSuccess) return '✓ Vollständig';
    if (normalizerHit && !hasDate) return '~ Kein Datum';
    if (!normalizerHit) return '✗ Nicht erkannt';
    return '?';
  }

  Map<String, dynamic> toJson() => {
    'rawText': rawText,
    'normalized': normalized,
    'parsedTitle': parsedTitle,
    'hasDate': hasDate,
    'normalizerHit': normalizerHit,
    'timestamp': timestamp.toIso8601String(),
  };

  factory SpeechLogEntry.fromJson(Map<String, dynamic> j) => SpeechLogEntry(
    rawText: j['rawText'] as String? ?? '',
    normalized: j['normalized'] as String? ?? '',
    parsedTitle: j['parsedTitle'] as String? ?? '',
    hasDate: j['hasDate'] as bool? ?? false,
    normalizerHit: j['normalizerHit'] as bool? ?? false,
    timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
  );
}

class SpeechLog {
  SpeechLog._();

  static const _boxKey = 'speech_log';
  static const _dataKey = 'entries';
  static const _maxEntries = 200;

  /// Einen neuen Eintrag speichern. Wird von _onRevealComplete aufgerufen.
  static void record({
    required String raw,
    required String normalized,
    required String parsedTitle,
    required bool hasDate,
  }) {
    final normalizerHit = normalized != raw;

    final entry = SpeechLogEntry(
      rawText: raw,
      normalized: normalized,
      parsedTitle: parsedTitle,
      hasDate: hasDate,
      normalizerHit: normalizerHit,
      timestamp: DateTime.now(),
    );

    // Debug-Output für die Entwicklungskonsole
    debugPrint('────────────────────────────────');
    debugPrint('SPEECH_LOG [${entry.statusLabel}]');
    debugPrint('  RAW:        "$raw"');
    if (normalizerHit) {
      debugPrint('  NORMALIZED: "$normalized"');
    } else {
      debugPrint('  NORMALIZED: (kein Treffer — Original weitergegeben)');
    }
    debugPrint('  TITEL:      "$parsedTitle"');
    debugPrint('  DATUM:      ${hasDate ? "erkannt" : "nicht erkannt"}');
    debugPrint('────────────────────────────────');

    // In Hive speichern
    try {
      final box = Hive.box('einstellungen');
      final existing = _loadAll(box);
      existing.insert(0, entry); // neueste zuerst
      if (existing.length > _maxEntries) {
        existing.removeRange(_maxEntries, existing.length);
      }
      box.put(_dataKey, jsonEncode(existing.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('SPEECH_LOG Fehler beim Speichern: $e');
    }
  }

  /// Alle Einträge laden (neueste zuerst).
  static List<SpeechLogEntry> loadAll() {
    try {
      final box = Hive.box('einstellungen');
      return _loadAll(box);
    } catch (_) {
      return [];
    }
  }

  static List<SpeechLogEntry> _loadAll(Box box) {
    final raw = box.get(_dataKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => SpeechLogEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Log komplett leeren (für den Clear-Button im Log-Screen).
  static void clear() {
    try {
      final box = Hive.box('einstellungen');
      box.delete(_dataKey);
    } catch (_) {}
  }

  /// Statistiken für die Übersicht im Log-Screen.
  static Map<String, int> stats() {
    final entries = loadAll();
    final total = entries.length;
    final fullSuccess = entries.where((e) => e.isFullSuccess).length;
    final normalizerMiss = entries.where((e) => !e.normalizerHit).length;
    final noDate = entries.where((e) => e.normalizerHit && !e.hasDate).length;
    return {
      'total': total,
      'fullSuccess': fullSuccess,
      'normalizerMiss': normalizerMiss,
      'noDate': noDate,
    };
  }
}