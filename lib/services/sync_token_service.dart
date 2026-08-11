import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'sync_service.dart';

/// SyncTokenService
///
/// Ein Sync-Token ist eine kryptografisch starke, 22-stellige Base58-ID,
/// die lokal in Hive gespeichert und in Firestore unter /syncTokens/{token}
/// registriert wird.
///
/// NEU (Haupt-/Kopiergerät-Semantik):
///  - Das Token-Dokument trägt zusätzlich `originalConnected: bool`.
///  - Trennt sich das ORIGINAL-Gerät vom Token, wird dieses Flag auf
///    `false` gesetzt. Jedes Kopiergerät (role == 'reader') beobachtet
///    dieses Flag per Live-Listener und trennt sich automatisch, sobald
///    das Original weg ist — es darf danach keinerlei Zugriff mehr haben.
///  - Beim Trennen (egal ob explizit oder erzwungen) werden alle Daten,
///    die nachweislich vom jeweils ANDEREN Gerät stammen, lokal entfernt;
///    rein lokale Daten bleiben erhalten.
class SyncTokenService {
  static final SyncTokenService instance = SyncTokenService._();
  SyncTokenService._();

  static const _hiveKey = 'sync_token';
  static const _roleKey = 'sync_role';
  static const _base58Chars =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  static const _syncedCollections = [
    'arbeitszeiten', 'schedule', 'fahrten', 'notes', 'events',
    'colleagues', 'tasks', 'calendar_events', 'event_groups', 'vehicle_memory',
  ];

  StreamSubscription? _presenceSub;

  // ── Lokalen Token abrufen (null = noch keiner generiert / verknüpft) ───────

  String? get localToken {
    final box = Hive.box('einstellungen');
    final t = box.get(_hiveKey) as String?;
    return (t != null && t.isNotEmpty) ? t : null;
  }

  static String? get role {
    final box = Hive.box('einstellungen');
    return box.get(_roleKey) as String?;
  }

  // ── Token generieren & in Firestore registrieren ─────────────────────────

  Future<String> generateAndRegister() async {
    final token = _generateBase58Token(22);
    await _registerInFirestore(token, isNew: true);
    await Hive.box('einstellungen').put(_hiveKey, token);
    await Hive.box('einstellungen').put(_roleKey, 'original');
    // NEU: NICHT mehr awaiten — _startSync() setzt _token synchron als
    // ALLERERSTES (vor jedem await), SyncService ist also sofort korrekt
    // "bereit". Der aufwändige initiale Push+Pull läuft im Hintergrund
    // weiter, ohne dass die UI auf ihn warten muss, um den Token zu zeigen.
    unawaited(SyncService.instance.onTokenSet(token));
    debugPrint('🔑 SyncToken generiert: $token');
    return token;
  }

  // ── Fremden Token verknüpfen ──────────────────────────────────────────────

  Future<SyncTokenLinkResult> linkExistingToken(String rawInput) async {
    final token = rawInput.trim();

    if (token.length != 22) return SyncTokenLinkResult.invalidFormat;
    if (!_isValidBase58(token)) return SyncTokenLinkResult.invalidFormat;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .get();

      if (!doc.exists) return SyncTokenLinkResult.notFound;

      // Ein bereits getrenntes Original darf nicht erneut verknüpft werden.
      final originalConnected = doc.data()?['originalConnected'] as bool? ?? true;
      if (!originalConnected) return SyncTokenLinkResult.notFound;

      final oldToken = localToken;

      await Hive.box('einstellungen').put(_hiveKey, token);
      await Hive.box('einstellungen').put(_roleKey, 'reader');
      // NEU: siehe generateAndRegister() — _initialSyncAsReader ist sogar
      // noch aufwändiger (zusätzliche Remote-ID-Abgleiche). Nicht mehr
      // blockierend awaiten.
      unawaited(SyncService.instance.onTokenSet(token));

      await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .update({'deviceCount': FieldValue.increment(1)});

      if (oldToken != null && oldToken != token) {
        await _decrementDeviceCountAndCleanupIfEmpty(oldToken);
      }

      _startOriginalPresenceWatch(token);

      debugPrint('🔗 SyncToken verknüpft: $token (war: $oldToken)');
      return SyncTokenLinkResult.success;
    } on FirebaseException catch (e) {
      debugPrint('❌ Firestore-Fehler beim Token-Link: ${e.code} ${e.message}');
      return SyncTokenLinkResult.networkError;
    } catch (e) {
      debugPrint('❌ Unbekannter Fehler beim Token-Link: $e');
      return SyncTokenLinkResult.networkError;
    }
  }

  // ── Token zurücksetzen (neuen generieren) ─────────────────────────────────

  Future<String> resetToken() async {
    final oldToken = localToken;
    stopPresenceWatch();
    await Hive.box('einstellungen').delete(_hiveKey);
    await Hive.box('einstellungen').delete(_roleKey);
    if (oldToken != null) {
      await _decrementDeviceCountAndCleanupIfEmpty(oldToken);
    }
    return generateAndRegister();
  }

  // ── Token trennen (dieses Gerät aus Sync entfernen) ──────────────────────

  /// Explizites Trennen durch den Nutzer. Trennt sich das ORIGINAL, wird
  /// das Kopiergerät automatisch mit-getrennt (siehe [_startOriginalPresenceWatch]).
  /// In jedem Fall werden lokal Daten entfernt, die nachweislich vom jeweils
  /// anderen Gerät stammen — eigene lokale Daten bleiben erhalten.
  Future<void> unlinkToken() async {
    stopPresenceWatch();
    final token = localToken;
    final wasRole = role; // VOR dem Löschen der Keys erfassen!

    await Hive.box('einstellungen').delete(_hiveKey);
    await Hive.box('einstellungen').delete(_roleKey);
    await SyncService.instance.onTokenUnlinked();

    // NEU: wipeForeignOwnedData ist rein lokal (Hive) und braucht KEIN
    // Netzwerk — deshalb sofort ausführen, statt erst hinter den beiden
    // sequentiellen Firestore-Roundtrips (originalConnected-Flag +
    // Device-Count-Transaktion) zu warten. Genau diese Reihenfolge war
    // der Grund für die spürbare Verzögerung, bis Aufgaben/Kalender/
    // Lesemodus lokal wirklich zurückgesetzt waren.
    await SyncService.instance.wipeForeignOwnedData(wasRole);
    debugPrint('🔓 SyncToken lokal entfernt (war: $wasRole)');

    // Netzwerk-Aufräumarbeiten laufen jetzt im Hintergrund weiter, ohne
    // dass die lokale Löschung noch länger darauf wartet.
    if (token != null) {
      unawaited(_cleanupNetworkAfterUnlink(token, wasRole));
    }
  }

  Future<void> _cleanupNetworkAfterUnlink(String token, String? wasRole) async {
    if (wasRole == 'original') {
      // NEU: Ohne Original ist der Token tot. Bisher wartete der Cleanup
      // brav darauf, dass sich AUCH das Kopiergerät irgendwann sauber
      // trennt — ist es offline/deinstalliert, bleibt der Token für immer
      // mit deviceCount>=1 verwaist in Firestore stehen. Da ein Token ohne
      // Original ohnehin nutzlos ist, räumen wir jetzt sofort vollständig
      // auf. Ein noch aktives Kopiergerät bekommt das über seinen
      // Presence-Listener mit (Dokument verschwindet) und trennt sich
      // automatisch selbst.
      try {
        await FirebaseFirestore.instance
            .collection('syncTokens')
            .doc(token)
            .set({'originalConnected': false}, SetOptions(merge: true));
      } catch (e) {
        debugPrint('⚠️ originalConnected-Flag setzen fehlgeschlagen: $e');
      }
      await _deleteAllSyncDataForToken(token);
      return;
    }
    // Kopiergerät trennt sich: nur eigene Teilnahme abmelden, Original
    // bleibt unberührt.
    await _decrementDeviceCountAndCleanupIfEmpty(token);
}

  // ── Präsenz-Überwachung: Original-Gerät online? ──────────────────────────

  /// Nur relevant für Kopiergeräte. Beobachtet syncTokens/{token} live und
  /// trennt dieses Gerät automatisch, sobald das Original weg ist.
  void _startOriginalPresenceWatch(String token) {
    _presenceSub?.cancel();
    _presenceSub = FirebaseFirestore.instance
        .collection('syncTokens')
        .doc(token)
        .snapshots()
        .listen((doc) {
      if (role != 'reader') return;
      final connected = doc.data()?['originalConnected'] as bool? ?? true;
      if (!doc.exists || !connected) {
        _presenceSub?.cancel();
        _presenceSub = null;
        _forceDisconnectAsReader();
      }
    }, onError: (e) => debugPrint('⚠️ Presence-Watch Fehler: $e'));
  }

  /// Wird von SyncService beim (Neu-)Start des Syncs aufgerufen — startet
  /// die Überwachung nur, wenn dieses Gerät tatsächlich Kopiergerät ist.
  void watchOriginalPresenceIfNeeded(String token) {
    if (role == 'reader') _startOriginalPresenceWatch(token);
  }

  void stopPresenceWatch() {
    _presenceSub?.cancel();
    _presenceSub = null;
  }

  Future<void> _forceDisconnectAsReader() async {
    final token = localToken;
    await Hive.box('einstellungen').delete(_hiveKey);
    await Hive.box('einstellungen').delete(_roleKey);
    await SyncService.instance.onTokenUnlinked();

    // NEU: siehe unlinkToken() — lokaler Reset zuerst, Netzwerk-Cleanup
    // (Device-Count-Transaktion) läuft danach unabhängig im Hintergrund.
    await SyncService.instance.wipeForeignOwnedData('reader');
    debugPrint('🚫 Original hat Token getrennt — dieses Gerät wurde automatisch getrennt.');

    if (token != null) {
      unawaited(_decrementDeviceCountAndCleanupIfEmpty(token));
    }
  }

  // ── Auto-Cleanup-Hilfsmethoden ────────────────────────────────────────────

  Future<void> _decrementDeviceCountAndCleanupIfEmpty(String token) async {
    final docRef = FirebaseFirestore.instance.collection('syncTokens').doc(token);
    try {
      final remaining = await FirebaseFirestore.instance.runTransaction<int>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return 0;
        final current = (snap.data()?['deviceCount'] as int?) ?? 1;
        final updated = (current - 1).clamp(0, 999999);
        tx.update(docRef, {'deviceCount': updated});
        return updated;
      });
      if (remaining <= 0) {
        await _deleteAllSyncDataForToken(token);
      }
    } catch (e) {
      debugPrint('⚠️ Cleanup-Check fehlgeschlagen: $e');
    }
  }

  Future<void> _deleteAllSyncDataForToken(String token) async {
    final base = FirebaseFirestore.instance.collection('syncData').doc(token);

    for (final col in _syncedCollections) {
      try {
        final snap = await base.collection(col).get();
        for (final doc in snap.docs) {
          try {
            await doc.reference.delete();
          } catch (e) {
            debugPrint('⚠️ Löschen von $col/${doc.id} fehlgeschlagen: $e');
          }
        }
      } catch (e) {
        debugPrint('⚠️ Lesen von Collection $col fehlgeschlagen: $e');
      }
    }

    try {
      await base.collection('meta').doc('calendar_sync').delete();
    } catch (e) {
      debugPrint('⚠️ Löschen von meta/calendar_sync fehlgeschlagen: $e');
    }

    try {
      await base.delete();
    } catch (e) {
      debugPrint('⚠️ Löschen von syncData/$token fehlgeschlagen: $e');
    }

    try {
      await FirebaseFirestore.instance.collection('syncTokens').doc(token).delete();
      debugPrint('🧹 syncTokens/$token gelöscht — letztes Gerät hat getrennt.');
    } catch (e) {
      debugPrint('❌ Löschen von syncTokens/$token fehlgeschlagen: $e');
    }
  }

  // ── Interne Hilfsmethoden ─────────────────────────────────────────────────

  String _generateBase58Token(int length) {
    final rng = Random.secure();
    return List.generate(
      length,
      (_) => _base58Chars[rng.nextInt(_base58Chars.length)],
    ).join();
  }

  bool _isValidBase58(String s) =>
      s.split('').every((c) => _base58Chars.contains(c));

  Future<void> _registerInFirestore(String token, {required bool isNew}) async {
    try {
      await FirebaseFirestore.instance
          .collection('syncTokens')
          .doc(token)
          .set({
        'createdAt': FieldValue.serverTimestamp(),
        'deviceCount': 1,
        'originalConnected': true,
      }, SetOptions(merge: !isNew));
    } on FirebaseException catch (e) {
      debugPrint('⚠️ Firestore-Registrierung fehlgeschlagen: ${e.code}');
    }
  }
}

// ── Ergebnis-Enum für linkExistingToken ──────────────────────────────────────

enum SyncTokenLinkResult {
  success,
  invalidFormat,
  notFound,
  networkError,
}

extension SyncTokenLinkResultMessage on SyncTokenLinkResult {
  String get userMessage {
    switch (this) {
      case SyncTokenLinkResult.success:
        return 'Gerät erfolgreich verknüpft ✓';
      case SyncTokenLinkResult.invalidFormat:
        return 'Ungültiger Token-Code. Bitte prüfe die Eingabe.';
      case SyncTokenLinkResult.notFound:
        return 'Token nicht gefunden oder nicht mehr verbunden.';
      case SyncTokenLinkResult.networkError:
        return 'Netzwerkfehler. Bitte prüfe deine Verbindung.';
    }
  }

  bool get isSuccess => this == SyncTokenLinkResult.success;
}