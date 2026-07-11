import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'sync_token_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SyncService
//
// Synchronisiert alle App-Daten bidirektional zwischen Hive (lokal) und
// Firestore (Cloud) unter dem Pfad /syncData/{token}/.
//
// Firestore-Struktur:
//   /syncData/{token}/
//     meta/info          → { lastSync, deviceCount }
//     arbeitszeiten/     → { dateKey: [ {...entry}, ... ], updatedAt: Timestamp }
//     schedule/          → { monthKey: { dateKey: shift, ... }, updatedAt }
//     fahrten/           → { monthKey: [ {...fahrt}, ... ], updatedAt }
//     notes/             → { dateKey: { phone, text }, updatedAt }
//     events/            → { monthKey: { dateKey: text, ... }, updatedAt }
//     colleagues/        → { monthKey: "json-string", updatedAt }
//
// Sync-Strategie: Last-Write-Wins per Dokument (updatedAt-Vergleich).
// Lokale Änderung → sofort nach Firestore pushen.
// Firestore-Änderung → sofort nach Hive ziehen (Realtime-Listener).
// ─────────────────────────────────────────────────────────────────────────────

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _tag = '🔄 SyncService';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _token;
  final List<StreamSubscription> _listeners = [];
  bool _initialized = false;
  bool _isSyncing = false; // verhindert Feedback-Loops

  // ── Öffentliche API ────────────────────────────────────────────────────────

  /// Beim App-Start aufrufen. Wenn ein Token vorhanden ist, startet der Sync.
  Future<void> init() async {
    final token = SyncTokenService.instance.localToken;
    if (token == null) {
      debugPrint('$_tag: Kein Token — Sync deaktiviert.');
      return;
    }
    await _startSync(token);
  }

  /// Aufrufen nachdem ein Token generiert oder verknüpft wurde.
  Future<void> onTokenSet(String token) async {
    await _stopSync();
    await _startSync(token);
  }

  /// Aufrufen nachdem der Token getrennt wurde.
  Future<void> onTokenUnlinked() async {
    await _stopSync();
  }

  /// Pusht einen einzelnen geänderten Eintrag sofort nach Firestore.
  /// Wird aus den jeweiligen Screens aufgerufen nach jedem Speichern.
  Future<void> pushArbeitszeit(String dateKey) async {
    if (_token == null) return;   // ← _isSyncing entfernt
    final box = Hive.box('arbeitszeiten');
    final data = box.get(dateKey);
    if (data == null) {
      await _delete('arbeitszeiten', dateKey);
    } else {
      await _push('arbeitszeiten', dateKey, data);
    }
  }

  Future<void> pushScheduleMonth(String monthKey) async {
    if (_token == null) return;   // ← _isSyncing entfernt
    final box = Hive.box('einstellungen');
    final data = box.get('schedule_$monthKey');
    await _push('schedule', monthKey, data);
  }

  Future<void> pushFahrtenMonth(String monthKey) async {
    if (_token == null) return;   // ← _isSyncing entfernt
    final box = Hive.box('einstellungen');
    final data = box.get('fahrten_$monthKey');
    await _push('fahrten', monthKey, data);
  }

  Future<void> pushNote(String dateKey) async {
    if (_token == null) return;   // ← _isSyncing entfernt
    final box = Hive.box('einstellungen');
    final data = box.get('schedule_note_$dateKey');
    await _push('notes', dateKey, data);
  }

  Future<void> pushColleagues(String monthKey) async {
    if (_token == null) return;
    final box = Hive.box('einstellungen');
    final data = box.get('colleagues_$monthKey');
    await _push('colleagues', monthKey, data);
  }

  Future<void> pushEvents(String monthKey) async {
    if (_token == null) return;
    final box = Hive.box('einstellungen');
    final data = box.get('events_$monthKey');
    await _push('events', monthKey, data);
  }

  // ── Interner Start/Stop ────────────────────────────────────────────────────

  Future<void> _startSync(String token) async {
    _token = token;
    _initialized = true;
    debugPrint('$_tag: Starte Sync mit Token ${token.substring(0, 6)}…');

    // 1) Initiales Push (Hive → Firestore) — sichert lokale Änderungen ab,
    //    die beim letzten App-Schließen evtl. nicht mehr fertig gepusht wurden,
    //    BEVOR wir irgendwas von Firestore pullen und lokal überschreiben.
    await _initialPush(token);

    // 2) Initiales Pull (Firestore → Hive) — jetzt sicher, da Firestore
    //    bereits den aktuellen lokalen Stand hat.
    await _initialPull(token);

    // 3) Realtime-Listener starten
    _startListeners(token);
  }

  Future<void> _stopSync() async {
    for (final sub in _listeners) {
      await sub.cancel();
    }
    _listeners.clear();
    _token = null;
    _initialized = false;
    debugPrint('$_tag: Sync gestoppt.');
  }

  // ── Initial Pull: Firestore → Hive ────────────────────────────────────────

  Future<void> _initialPull(String token) async {
    debugPrint('$_tag: Initial Pull…');
    try {
      final base = _db.collection('syncData').doc(token);
      final collections = ['arbeitszeiten', 'schedule', 'fahrten', 'notes', 'events', 'colleagues'];

      for (final col in collections) {
        final snap = await base.collection(col).get().timeout(
  const Duration(seconds: 5),
  onTimeout: () => throw TimeoutException('Pull timeout ($col)'),
);
        _isSyncing = true;
        for (final doc in snap.docs) {
          await _applyRemoteDoc(col, doc.id, doc.data());
        }
        _isSyncing = false;
      }
      debugPrint('$_tag: Initial Pull abgeschlossen.');
    } catch (e) {
      _isSyncing = false;
      debugPrint('$_tag: Initial Pull Fehler: $e');
    }
  }

  // ── Initial Push: Hive → Firestore ────────────────────────────────────────

  Future<void> _initialPush(String token) async {
    debugPrint('$_tag: Initial Push…');
    try {
      final zeitBox = Hive.box('arbeitszeiten');
      final settingsBox = Hive.box('einstellungen');

      // Arbeitszeiten
      for (final key in zeitBox.keys) {
        final data = zeitBox.get(key);
        if (data != null) {
          await _push('arbeitszeiten', key.toString(), data);
        }
      }

      // Settings-Keys kategorisieren und pushen
      for (final key in settingsBox.keys) {
        final k = key.toString();
        if (k.startsWith('schedule_') && !k.startsWith('schedule_note_') && !k.startsWith('schedule_changed_')) {
          final monthKey = k.substring('schedule_'.length);
          await _push('schedule', monthKey, settingsBox.get(key));
        } else if (k.startsWith('fahrten_')) {
          final monthKey = k.substring('fahrten_'.length);
          await _push('fahrten', monthKey, settingsBox.get(key));
        } else if (k.startsWith('schedule_note_')) {
          final dateKey = k.substring('schedule_note_'.length);
          await _push('notes', dateKey, settingsBox.get(key));
        } else if (k.startsWith('events_')) {
          final monthKey = k.substring('events_'.length);
          await _push('events', monthKey, settingsBox.get(key));
        } else if (k.startsWith('colleagues_') && !k.startsWith('colleagues_debug_')) {
          final monthKey = k.substring('colleagues_'.length);
          await _push('colleagues', monthKey, settingsBox.get(key));
        }
      }
      debugPrint('$_tag: Initial Push abgeschlossen.');
    } catch (e) {
      debugPrint('$_tag: Initial Push Fehler: $e');
    }
  }

  // ── Realtime-Listener ─────────────────────────────────────────────────────

  void _startListeners(String token) {
    final base = _db.collection('syncData').doc(token);
    final collections = ['arbeitszeiten', 'schedule', 'fahrten', 'notes', 'events', 'colleagues'];

    for (final col in collections) {
      final sub = base.collection(col).snapshots().listen(
        (snap) async {
          if (!_initialized) return;
          _isSyncing = true;
          for (final change in snap.docChanges) {
  final pushKey = '$col/${change.doc.id}';
  final lastPush = _lastLocalPushAt[pushKey];
  // Ignoriere eingehende Events für Dokumente, die wir selbst
  // gerade (innerhalb der letzten 8s) gepusht haben - vermeidet,
  // dass ein verspäteter/eigener Echo-Snapshot uns überschreibt.
  if (lastPush != null && DateTime.now().difference(lastPush) < const Duration(seconds: 8)) {
    continue;
  }
  if (change.type == DocumentChangeType.added ||
      change.type == DocumentChangeType.modified) {
    await _applyRemoteDoc(col, change.doc.id, change.doc.data() ?? {});
  }
}
          _isSyncing = false;
        },
        onError: (e) {
          _isSyncing = false;
          debugPrint('$_tag: Listener-Fehler ($col): $e');
        },
      );
      _listeners.add(sub);
    }
    debugPrint('$_tag: ${collections.length} Realtime-Listener aktiv.');
  }

  // ── Remote → Hive anwenden ────────────────────────────────────────────────

  Future<void> _applyRemoteDoc(String collection, String docId, Map<String, dynamic> data) async {
    final payload = data['payload'];
    if (payload == null) return;

    // LWW-Schutz: wenn wir lokal eine gleich neue oder neuere Version haben
    // als das, was von Firestore reinkommt, NICHT überschreiben.
    // Das schützt sowohl gegen den Initial-Pull-Race beim Start als auch
    // gegen verspätete Listener-Echos zur Laufzeit.
    final remoteClientTs = data['clientUpdatedAt'] as int?;
    final localTs = Hive.box('einstellungen').get('_syncver_$collection/$docId') as int?;
    if (remoteClientTs != null && localTs != null && localTs >= remoteClientTs) {
      debugPrint('$_tag: Remote-Update ignoriert ($collection/$docId) — lokal ist aktueller.');
      return;
    }

    try {
      switch (collection) {
        case 'arbeitszeiten':
          final box = Hive.box('arbeitszeiten');
          if (payload is List) {
            box.put(docId, List<dynamic>.from(payload));
          }
          break;

        case 'schedule':
          final box = Hive.box('einstellungen');
          if (payload is Map) {
            box.put('schedule_$docId', Map<String, dynamic>.from(payload));
          }
          break;

        case 'fahrten':
          final box = Hive.box('einstellungen');
          if (payload is List) {
            box.put('fahrten_$docId', List<dynamic>.from(payload));
          }
          break;

        case 'notes':
          final box = Hive.box('einstellungen');
          if (payload is Map) {
            box.put('schedule_note_$docId', Map<String, dynamic>.from(payload));
          }
          break;

        case 'events':
          final box = Hive.box('einstellungen');
          if (payload is Map) {
            box.put('events_$docId', jsonEncode(payload));
          } else if (payload is String) {
            box.put('events_$docId', payload);
          }
          break;

        case 'colleagues':
          final box = Hive.box('einstellungen');
          if (payload is String) {
            box.put('colleagues_$docId', payload);
          } else if (payload is Map) {
            box.put('colleagues_$docId', jsonEncode(payload));
          }
          break;
      }
    } catch (e) {
      debugPrint('$_tag: applyRemoteDoc Fehler ($collection/$docId): $e');
    }
  }

  // ── Hive → Firestore pushen ───────────────────────────────────────────────

  final Map<String, DateTime> _lastLocalPushAt = {};

Future<void> _push(String collection, String docId, dynamic data) async {
  if (_token == null || data == null) return;
  final pushKey = '$collection/$docId';
  _lastLocalPushAt[pushKey] = DateTime.now();

  // Lokale Versionsmarke SOFORT persistieren — noch bevor das Netzwerk
  // überhaupt angefragt wird. Das ist der Zeitstempel, gegen den beim
  // nächsten Pull/Listener-Event verglichen wird. Dieser Schreibvorgang
  // dauert Millisekunden statt Sekunden (wie der Netzwerk-Push) und
  // schließt damit das Race-Fenster fast vollständig.
  final localTs = DateTime.now().millisecondsSinceEpoch;
  final metaBox = Hive.box('einstellungen');
  await metaBox.put('_syncver_$pushKey', localTs);
  await metaBox.flush();

  try {
    await _db
        .collection('syncData')
        .doc(_token)
        .collection(collection)
        .doc(docId)
        .set({
      'payload': _serialize(data),
      'updatedAt': FieldValue.serverTimestamp(),
      'clientUpdatedAt': localTs,
    }, SetOptions(merge: false))
        .timeout(const Duration(seconds: 5));
  } catch (e) {
    debugPrint('$_tag: Push-Fehler ($collection/$docId): $e');
  }
}

Future<void> _delete(String collection, String docId) async {
    if (_token == null) return;
    final pushKey = '$collection/$docId';
    final localTs = DateTime.now().millisecondsSinceEpoch;
    final metaBox = Hive.box('einstellungen');
    await metaBox.put('_syncver_$pushKey', localTs);
    await metaBox.flush();
    try {
      await _db
          .collection('syncData')
          .doc(_token)
          .collection(collection)
          .doc(docId)
          .delete()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('$_tag: Delete-Fehler ($collection/$docId): $e');
    }
  }

  /// Konvertiert Hive-Daten in Firestore-kompatible Typen.
  dynamic _serialize(dynamic data) {
    if (data == null) return null;
    if (data is String || data is num || data is bool) return data;
    if (data is List) {
      return data.map((e) => _serialize(e)).toList();
    }
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), _serialize(v)));
    }
    // Fallback: JSON-String
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
}