import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
// Gespeichert in Hive-Box "speech_log" als JSON-Liste (lokal, für die
// Statistik-Anzeige im SpeechLogScreen).
//
// NEU: Wenn ein Eintrag NICHT vollständig erkannt wurde (isFullSuccess ==
// false), wird er zusätzlich automatisch nach Firestore (speech_logs)
// hochgeladen — das ist die Grundlage für die spätere Gemini-Analyse +
// lernende Regeln. Der Upload läuft im Hintergrund (fire-and-forget),
// blockiert die UI nicht und schlägt niemals sichtbar fehl (z.B. wenn
// kein Internet da ist — dann geht der Eintrag einfach nicht hoch, ohne
// Fehlermeldung für den Nutzer).
// ─────────────────────────────────────────────────────────────────────────────

class SpeechLogEntry {
  final String rawText;
  final String normalized;
  final String parsedTitle;
  final bool hasDate;
  final bool normalizerHit; // true wenn Normalizer ein Muster erkannt hat
  final DateTime timestamp;
  String? taskId; // verknüpft den Log-Eintrag mit dem erzeugten Task — nicht final, wird nachträglich gesetzt
  final bool wentToReview; // true = needsReview hat angeschlagen
  bool wasEdited; // nicht final — wird nachträglich gesetzt, siehe markEdited()
  int? editedWithinSeconds; // wie schnell nach Erstellung die Änderung kam

  SpeechLogEntry({
    required this.rawText,
    required this.normalized,
    required this.parsedTitle,
    required this.hasDate,
    required this.normalizerHit,
    required this.timestamp,
    this.taskId,
    this.wentToReview = false,
    this.wasEdited = false,
    this.editedWithinSeconds,
  });

  /// true = System hat alles erkannt (Normalizer + Parser haben Datum/Muster gefunden)
  /// false = irgendwas wurde nicht erkannt → interessant zum Analysieren
  bool get isFullSuccess => normalizerHit && hasDate;

  /// Wortanzahl des Originaltexts — Basis für die Schwellwert-Kalibrierung.
  int get wordCount => rawText.trim().isEmpty
      ? 0
      : rawText.trim().split(RegExp(r'\s+')).length;

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
    'taskId': taskId,
    'wentToReview': wentToReview,
    'wasEdited': wasEdited,
    'editedWithinSeconds': editedWithinSeconds,
  };

  factory SpeechLogEntry.fromJson(Map<String, dynamic> j) => SpeechLogEntry(
    rawText: j['rawText'] as String? ?? '',
    normalized: j['normalized'] as String? ?? '',
    parsedTitle: j['parsedTitle'] as String? ?? '',
    hasDate: j['hasDate'] as bool? ?? false,
    normalizerHit: j['normalizerHit'] as bool? ?? false,
    timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
    taskId: j['taskId'] as String?,
    wentToReview: j['wentToReview'] as bool? ?? false,
    wasEdited: j['wasEdited'] as bool? ?? false,
    editedWithinSeconds: j['editedWithinSeconds'] as int?,
  );
}

class SpeechLog {
  SpeechLog._();

  static const _boxKey = 'speech_log';
  static const _dataKey = 'entries';
  static const _maxEntries = 200;

  /// Einen neuen Eintrag speichern. Wird von _onRevealComplete aufgerufen.
  /// Gibt die generierte Eintrags-ID (= timestamp in Millisekunden) zurück,
  /// damit der Aufrufer sie via setTaskId() mit dem erzeugten Task verknüpfen
  /// kann, sobald die Task-ID feststeht.
  static String record({
    required String raw,
    required String normalized,
    required String parsedTitle,
    required bool hasDate,
    bool wentToReview = false,
  }) {
    final normalizerHit = normalized != raw;
    final now = DateTime.now();

    final entry = SpeechLogEntry(
      rawText: raw,
      normalized: normalized,
      parsedTitle: parsedTitle,
      hasDate: hasDate,
      normalizerHit: normalizerHit,
      timestamp: now,
      wentToReview: wentToReview,
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

    // In Hive speichern (lokal, für die Statistik-Anzeige)
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

    // NEU: Bei unvollständiger Erkennung zusätzlich nach Firestore hochladen.
    // Fire-and-forget — wir warten nicht auf das Ergebnis und zeigen dem
    // Nutzer nie einen Fehler, falls z.B. kein Internet verfügbar ist.
    if (!entry.isFullSuccess) {
      _uploadToFirestore(entry);
    }

    // Rückgabewert: Zeitstempel in ms als simple, eindeutige Referenz auf
    // diesen Log-Eintrag — der Aufrufer nutzt das, um per setTaskId() später
    // die Task-ID nachzutragen.
    return now.millisecondsSinceEpoch.toString();
  }

  /// Trägt nachträglich die Task-ID in den zuletzt erstellten Log-Eintrag
  /// ein. Wird direkt nach TaskStore.add() aufgerufen, weil die Task-ID erst
  /// dort entsteht (record() lief vorher und kennt sie noch nicht).
  static void linkLastEntryToTask(String logRefMs, String taskId) {
    try {
      final box = Hive.box('einstellungen');
      final entries = _loadAll(box);
      final refTimestamp = int.tryParse(logRefMs);
      if (refTimestamp == null) return;
      final idx = entries.indexWhere(
          (e) => e.timestamp.millisecondsSinceEpoch == refTimestamp);
      if (idx == -1) return;
      entries[idx].taskId = taskId; // hmm — siehe Hinweis unten
      box.put(_dataKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('SPEECH_LOG linkLastEntryToTask Fehler: $e');
    }
  }

  static Future<void> _uploadToFirestore(SpeechLogEntry entry) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('speech_logs').add({
        'rawText': entry.rawText,
        'normalized': entry.normalized,
        'parsedTitle': entry.parsedTitle,
        'hasDate': entry.hasDate,
        'normalizerHit': entry.normalizerHit,
        'status': 'pending', // wird später von der Cloud Function bearbeitet
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint('SPEECH_LOG → Firestore Upload erfolgreich');
    } catch (e) {
      // Bewusst stumm nach außen — kein SnackBar, kein Crash, nur Debug-Log.
      // Typische Gründe: kein Internet, Firestore Rules verweigern Schreiben.
      debugPrint('SPEECH_LOG → Firestore Upload fehlgeschlagen: $e');
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

/// Markiert den Log-Eintrag, der zu [taskId] gehört, als "wurde bearbeitet".
  /// Wird von TasksScreenState aufgerufen, sobald ein Task verändert/gelöscht
  /// wird (siehe tasks_screen.dart → _commitInlineEdit, _editTaskFull,
  /// _deleteTaskImmediate). Wirkt nur, wenn die Bearbeitung innerhalb eines
  /// kurzen Zeitfensters nach Erstellung passiert — spätere, normale Edits
  /// (Wochen später) sagen nichts über die Erkennungsqualität aus.
  static const _editWindowSeconds = 300; // 5 Minuten

  static void markEdited(String taskId, DateTime taskCreatedAt) {
    final secondsSinceCreation =
        DateTime.now().difference(taskCreatedAt).inSeconds;
    if (secondsSinceCreation > _editWindowSeconds) return;

    try {
      final box = Hive.box('einstellungen');
      final entries = _loadAll(box);
      final idx = entries.indexWhere((e) => e.taskId == taskId);
      if (idx == -1) return;
      entries[idx].wasEdited = true;
      entries[idx].editedWithinSeconds = secondsSinceCreation;
      box.put(_dataKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('SPEECH_LOG markEdited Fehler: $e');
    }
  }

  /// Berechnet den Median der Wortanzahl getrennt für "wurde bearbeitet"
  /// vs. "blieb unverändert". Die Mitte zwischen beiden Werten ist ein guter
  /// Kandidat für die wordCount-Schwellen in _onRevealComplete.
  ///
  /// Gibt null zurück, wenn zu wenig Daten vorhanden sind (siehe minSamples),
  /// damit man nicht versehentlich Schwellen aus 2-3 Einträgen ableitet.
  static MedianCalibrationResult? calibrateWordCountThreshold({int minSamples = 8}) {
    final entries = loadAll().where((e) => e.taskId != null).toList();
    final edited = entries.where((e) => e.wasEdited).map((e) => e.wordCount).toList()..sort();
    final clean = entries.where((e) => !e.wasEdited).map((e) => e.wordCount).toList()..sort();

    if (edited.length < minSamples || clean.length < minSamples) return null;

    double median(List<int> xs) {
      final mid = xs.length ~/ 2;
      if (xs.length % 2 == 1) return xs[mid].toDouble();
      return (xs[mid - 1] + xs[mid]) / 2.0;
    }

    final editedMedian = median(edited);
    final cleanMedian = median(clean);

    return MedianCalibrationResult(
      editedMedianWordCount: editedMedian,
      cleanMedianWordCount: cleanMedian,
      suggestedThreshold: ((editedMedian + cleanMedian) / 2).round(),
      editedSampleCount: edited.length,
      cleanSampleCount: clean.length,
    );
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

/// Ergebnis der Median-Kalibrierung — siehe SpeechLog.calibrateWordCountThreshold().
class MedianCalibrationResult {
  final double editedMedianWordCount;
  final double cleanMedianWordCount;
  final int suggestedThreshold;
  final int editedSampleCount;
  final int cleanSampleCount;

  const MedianCalibrationResult({
    required this.editedMedianWordCount,
    required this.cleanMedianWordCount,
    required this.suggestedThreshold,
    required this.editedSampleCount,
    required this.cleanSampleCount,
  });

  @override
  String toString() =>
      'Median (bearbeitet): $editedMedianWordCount Wörter (n=$editedSampleCount)\n'
      'Median (unverändert): $cleanMedianWordCount Wörter (n=$cleanSampleCount)\n'
      '→ Vorschlag für wordCount-Schwelle: $suggestedThreshold';
}