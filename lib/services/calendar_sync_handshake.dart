import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'sync_token_service.dart';

enum CalendarSyncState { off, waitingForApproval, active }

class CalendarSyncHandshake {
  CalendarSyncHandshake._();
  static final CalendarSyncHandshake instance = CalendarSyncHandshake._();

  static const _tag = '🔗 CalendarSyncHandshake';

  StreamSubscription? _sub;
  final ValueNotifier<CalendarSyncState> state = ValueNotifier(CalendarSyncState.off);
  final ValueNotifier<DateTime?> pairingEndedAt = ValueNotifier(null);
  bool _requestedByReader = false;
  bool _approvedByOriginal = false;

  /// Wird von SyncService gesetzt, um bei Aktivierung neu zu pushen/pullen.
  Future<void> Function()? onBecameActive;

  bool get isReader => SyncTokenService.role == 'reader';
  bool get isOriginal => SyncTokenService.role == 'original';
  bool get isActive => state.value == CalendarSyncState.active;
  bool get requestedByReader => _requestedByReader;

  DocumentReference<Map<String, dynamic>> _docRef(String token) => FirebaseFirestore.instance
      .collection('syncData').doc(token).collection('meta').doc('calendar_sync');

  Future<void> start(String token) async {
    await _sub?.cancel();
    _sub = _docRef(token).snapshots().listen((doc) {
      final data = doc.data();
      _requestedByReader = data?['requestedByReader'] as bool? ?? false;
      _approvedByOriginal = data?['approvedByOriginal'] as bool? ?? false;
      final endedTs = data?['pairingEndedAt'];
      if (endedTs is Timestamp) {
        pairingEndedAt.value = endedTs.toDate();
      }
      _recompute();
    }, onError: (e) => debugPrint('$_tag: $e'));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _requestedByReader = false;
    _approvedByOriginal = false;
    state.value = CalendarSyncState.off;
  }

  void _recompute() {
    final wasActive = state.value == CalendarSyncState.active;
    if (_requestedByReader && _approvedByOriginal) {
      state.value = CalendarSyncState.active;
      if (!wasActive) onBecameActive?.call();
    } else if (_requestedByReader) {
      state.value = CalendarSyncState.waitingForApproval;
    } else {
      state.value = CalendarSyncState.off;
    }
  }

  Future<void> setReaderRequest(String token, bool requested) async {
    await _docRef(token).set({'requestedByReader': requested}, SetOptions(merge: true));
  }

  Future<void> setOriginalApproval(String token, bool approved) async {
    await _docRef(token).set({'approvedByOriginal': approved}, SetOptions(merge: true));
  }

  /// Trennt die Verbindung vollständig — egal von welcher Seite aufgerufen,
  /// beide Flags gehen auf false, sodass beide Geräte aus dem Pairing raus
  /// fallen (statt nur die eigene Seite zurückzusetzen).
  Future<void> disconnect(String token) async {
    await _docRef(token).set({
      'requestedByReader': false,
      'approvedByOriginal': false,
      'pairingEndedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}