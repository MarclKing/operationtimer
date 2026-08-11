import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'sync_token_service.dart';
import '../screens/tasks_screen.dart' show TaskStore, Task;
import '../models/calendar_event.dart';
import '../services/event_group_store.dart';
import 'calendar_sync_handshake.dart';
import 'apple_calendar_sync_service.dart';

/// Einfaches Datenobjekt für einen offenen Sync-Konflikt (nur für die
/// Monats-Blob-Collections fahrten/schedule/arbeitszeiten — siehe
/// [SyncService._conflictProtected]).
class SyncConflictItem {
  final String collection;
  final String docId;
  final dynamic payload;
  /// Name aus den Profil-Einstellungen des Geräts, das diese Änderung
  /// eingebracht hat (aktuell immer das Kopiergerät).
  final String? authorName;
  SyncConflictItem({
    required this.collection,
    required this.docId,
    required this.payload,
    this.authorName,
  });
}

class _PendingRemoteChange {
  _PendingRemoteChange({
    required this.collection,
    required this.docId,
    required this.type,
    required this.data,
  });

  final String collection;
  final String docId;
  final DocumentChangeType type;
  final Map<String, dynamic> data;
}

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  static const _tag = '🔄 SyncService';

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  String? _token;
  final List<StreamSubscription> _listeners = [];
  final Map<String, _PendingRemoteChange> _pendingRemoteChanges = {};
  Timer? _remoteBatchTimer;
  final Map<String, DateTime> _lastIgnoredRemoteLogAt = {};
  bool _initialized = false;
  bool _isSyncing = false;

  bool get _isReadOnly =>
      Hive.box('einstellungen').get('read_only_mode', defaultValue: false) as bool;

  static const _isolatedInReadOnly = {'tasks', 'calendar_events', 'event_groups'};

  /// Monats-Blob-Collections: hier führt ein blindes Überschreiben zum
  /// Verlust ganzer Zeiträume (Fahrten/Dienstplan/Arbeitszeiten eines
  /// Monats). Änderungen, die vom Kopiergerät kommen, werden hier auf dem
  /// Original NICHT automatisch übernommen, sondern als Konflikt zur
  /// Bestätigung vorgelegt.// NEU: 'schedule' bewusst NICHT geschützt — anders als bei Fahrten/
  // Arbeitszeiten/Tasks gibt es hier keine sinnvolle Einzel-Freigabe (nur
  // ganze Monate), und vom Kopiergerät wird der Dienstplan nie bewusst
  // "vorgeschlagen". Schedule läuft daher stumpf im Last-Write-Wins-Modus
  // wie notes/events/colleagues — das Kopiergerät zeigt immer sofort den
  // aktuellen Stand des Originals, ohne Zurückhalten oder Konflikt-Anfrage.
  static const _conflictProtected = {'fahrten', 'arbeitszeiten', 'tasks', 'calendar_events'};
  

  static const _pendingConflictsKey = '_pending_sync_conflicts';
  static const _ownerMapKey = '_item_owner_map';

  /// Anzahl offener Konflikte — für ein Badge in den Einstellungen.
  final ValueNotifier<int> pendingConflictsCount = ValueNotifier(0);

  /// Wird gepingt, sobald Dienstplan-, Fahrtenbuch-, Notiz- oder
  /// Arbeitszeiten-Daten durch Sync verändert wurden (Pull, Konflikt-
  /// Auflösung, Trennen). ScheduleScreen/FahrtenbuchScreen hören darauf,
  /// um sich ohne manuellen Monatswechsel zu aktualisieren.
  final ValueNotifier<int> scheduleDataChanged = ValueNotifier(0);

  // ── NEU: true während des initialen Push/Pull beim (Neu-)Verknüpfen — UI
  // kann darauf reagieren, um bis dahin KEINE (auch keine teilweisen) Daten
  // zu zeigen, sondern einen Ladezustand.
  final ValueNotifier<bool> initialSyncInProgress = ValueNotifier(false);

  // ── NEU: Zurückhalten eigener Vorschläge auf dem Kopiergerät ────────────
  //
  // Bringt ein Kopiergerät (role == 'reader') eine Änderung an einem
  // geschützten Datensatz (tasks/schedule/fahrten/arbeitszeiten) ein, darf
  // diese Änderung WEDER auf dem Original NOCH auf dem Kopiergerät selbst
  // sichtbar sein, bevor das Original sie im Konflikte-Screen bestätigt
  // oder verwirft. Dafür merkt sich das Kopiergerät zusätzlich zum neuen
  // (noch unbestätigten) lokalen Stand immer den letzten BESTÄTIGTEN Stand
  // als "Schatten" — die Anzeige nutzt so lange den Schatten, bis vom
  // Original eine Antwort (Bestätigung oder Ablehnung) eintrifft.
  static const _pendingOwnKey = '_pending_own_docs';
  static const _shadowPrefix = '_pending_shadow_';

  Set<String> _loadPendingOwnSet() {
    final raw = Hive.box('einstellungen').get(_pendingOwnKey);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  void _savePendingOwnSet(Set<String> s) {
    Hive.box('einstellungen').put(_pendingOwnKey, s.toList());
  }

  /// true, wenn für diesen Datensatz gerade ein eigener (Kopiergerät-)
  /// Vorschlag auf eine Antwort des Originals wartet.
  bool isPendingOwn(String collection, String docId) =>
      _loadPendingOwnSet().contains('$collection/$docId');

  void _markPendingOwn(String collection, String docId) {
    final s = _loadPendingOwnSet();
    s.add('$collection/$docId');
    _savePendingOwnSet(s);
    scheduleDataChanged.value++;
    TaskStore.changesSignal.value++;
  }

  void _clearPendingOwn(String collection, String docId) {
    final s = _loadPendingOwnSet();
    if (s.remove('$collection/$docId')) {
      _savePendingOwnSet(s);
    }
    Hive.box('einstellungen').delete('$_shadowPrefix${collection}_$docId');
    scheduleDataChanged.value++;
    TaskStore.changesSignal.value++;
  }

  void _updateShadow(String collection, String docId, dynamic payload) {
    Hive.box('einstellungen').put('$_shadowPrefix${collection}_$docId', payload);
  }

  /// Letzter BESTÄTIGTER Stand dieses Datensatzes (für die Anzeige während
  /// eine eigene Änderung noch aussteht).
  dynamic shadowFor(String collection, String docId) =>
      Hive.box('einstellungen').get('$_shadowPrefix${collection}_$docId');

  /// Zentrale Anzeige-Weiche für Monats-/Tages-Blob-Collections (schedule,
  /// fahrten, arbeitszeiten): liefert live-Daten, AUSSER dieses Gerät ist
  /// ein Kopiergerät und wartet für genau diesen Datensatz noch auf eine
  /// Antwort des Originals — dann wird stattdessen der letzte bestätigte
  /// Schatten geliefert (ggf. null, wenn der Datensatz komplett neu ist).
  dynamic visibleValueFor(String collection, String docId, dynamic liveValue) {
    if (SyncTokenService.role != 'reader') return liveValue;
    if (!isPendingOwn(collection, docId)) return liveValue;
    return shadowFor(collection, docId);
  }

  /// Blendet für die Anzeige Aufgaben aus, deren aktuelle Fassung ein noch
  /// unbestätigter eigener Vorschlag des Kopiergeräts ist — bis das
  /// Original zugestimmt oder abgelehnt hat, erscheint stattdessen der
  /// letzte bestätigte Stand (oder gar nichts, falls die Aufgabe neu ist).
  List<Task> filterPendingTasks(List<Task> tasks) {
    if (SyncTokenService.role != 'reader') return tasks;
    final result = <Task>[];
    for (final t in tasks) {
      if (!isPendingOwn('tasks', t.id)) {
        result.add(t);
        continue;
      }
      final shadow = shadowFor('tasks', t.id);
      if (shadow is Map) {
        try {
          result.add(Task.fromJson(Map<String, dynamic>.from(shadow)));
        } catch (_) {}
      }
      // kein Schatten vorhanden → Aufgabe ist komplett neu und bleibt bis
      // zur Bestätigung durch das Original unsichtbar.
    }
    return result;
  }

  /// Blendet für die Anzeige Kalender-Ereignisse aus, deren aktuelle
  /// Fassung ein noch unbestätigter eigener Vorschlag des Kopiergeräts ist
  /// (beim Erst-Verknüpfen mitgebracht) — bis das Original zugestimmt oder
  /// abgelehnt hat, bleibt der Eintrag für die Anzeige unsichtbar (anders
  /// als bei Tasks gibt es hier keinen "letzten bestätigten Stand", da das
  /// Ereignis für das Original komplett neu ist).
  List<CalendarEvent> filterPendingCalendarEvents(List<CalendarEvent> events) {
    if (SyncTokenService.role != 'reader') return events;
    return events.where((e) => !isPendingOwn('calendar_events', e.id)).toList();
  }

  List<String> _activeCollections() {
    // WICHTIG: 'event_groups' steht bewusst VOR 'calendar_events' — beim
    // initialen Pull werden Collections sequentiell abgearbeitet, und die
    // Scope-Filterung für Termine (siehe _writeLocal, Fall
    // 'calendar_events') braucht bereits bekannte, lokal gespeicherte
    // Gruppen, um "Sync" korrekt zu erkennen.
    const all = [
      'arbeitszeiten', 'schedule', 'fahrten', 'notes', 'events',
      'colleagues', 'tasks', 'event_groups', 'calendar_events', 'vehicle_memory',
    ];
    if (!_isReadOnly) return all;
    // Im Lesemodus grundsätzlich isoliert (kein Listener) — AUSSER der
    // Kalender-Sync-Handshake ist aktiv, dann bleiben calendar_events &
    // event_groups live verbunden. Tasks bleiben davon immer unberührt.
    final handshakeActive = CalendarSyncHandshake.instance.isActive;
    return all.where((c) {
      if (!_isolatedInReadOnly.contains(c)) return true;
      if ((c == 'calendar_events' || c == 'event_groups') && handshakeActive) return true;
      return false;
    }).toList();
  }

  // ── Öffentliche API ────────────────────────────────────────────────────────

  Future<void> init() async {
    _refreshPendingConflictsCount();
    final token = SyncTokenService.instance.localToken;
    if (token == null) {
      debugPrint('$_tag: Kein Token — Sync deaktiviert.');
      return;
    }
    await _startSync(token);
  }

  Future<void> onTokenSet(String token) async {
    await _stopSync();
    await _startSync(token);
  }

  Future<void> onTokenUnlinked() async {
  final token = _token;
  if (token != null) {
    await CalendarSyncHandshake.instance.disconnect(token);
  }
  await _stopSync();
}

  /// Muss aufgerufen werden, sobald sich der Lesemodus-Status ändert.
  /// Ohne das bleibt ein bereits laufender Listener aus der Zeit VOR dem
  /// Lesemodus (voller Spiegel) aktiv und kann Fremd-Daten — allen voran
  /// die standardmäßig sync-gescopte "Privat"-Gruppe — sofort wieder in
  /// das gerade zurückgesetzte Gerät zurückschreiben.
  void onReadOnlyModeChanged() => _restartListeners();

  // ── Push-Methoden (unverändert in der Signatur) ───────────────────────────

  Future<void> pushArbeitszeit(String dateKey) async {
    if (_token == null) return;
    final box = Hive.box('arbeitszeiten');
    final data = box.get(dateKey);
    if (data == null) {
      await _delete('arbeitszeiten', dateKey);
    } else {
      // NEU: Laufende Änderungen (nach dem Verknüpfen) werden von beiden
      // gleichberechtigten Geräten IMMER direkt gepusht — kein
      // Zurückhalten mehr. Nur beim allerersten Verknüpfen mitgebrachte
      // Altdaten laufen über _reconcileProtectedDoc durch den
      // Konflikte-Screen.
      await _push('arbeitszeiten', dateKey, data);
    }
  }

  Future<void> pushScheduleMonth(String monthKey) async {
    if (_token == null) return;
    final box = Hive.box('einstellungen');
    final data = box.get('schedule_$monthKey');
    // WICHTIG: 'schedule' ist bewusst NICHT konfliktgeschützt — hier NIE
    // _markPendingOwn aufrufen, sonst bleibt der eigene Upload für immer
    // hinter einem nie aufgelösten Schatten versteckt.
    await _push('schedule', monthKey, data);
  }

  Future<void> pushFahrtenMonth(String monthKey) async {
    if (_token == null) return;
    final box = Hive.box('einstellungen');
    final data = box.get('fahrten_$monthKey');
    // NEU: Laufende Änderungen (nach dem Verknüpfen) werden von beiden
    // gleichberechtigten Geräten IMMER direkt gepusht — kein
    // Zurückhalten mehr. Nur beim allerersten Verknüpfen mitgebrachte
    // Altdaten laufen über _reconcileProtectedDoc durch den
    // Konflikte-Screen.
    await _push('fahrten', monthKey, data);
  }

  Future<void> pushNote(String dateKey) async {
    if (_token == null) return;
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

  Future<void> pushTask(String taskId) async {
    if (_token == null || _isReadOnly) return;
    final all = TaskStore.loadAllRaw();
    final idx = all.indexWhere((t) => t.id == taskId);
    if (idx == -1) {
      await _delete('tasks', taskId);
    } else {
      // NEU: Kein _markPendingOwn mehr — Aufgaben sind im Lesemodus ohnehin
      // komplett isoliert (Guard ganz oben), und als vollwertiges Zweitgerät
      // (Lesemodus aus) synct eine Aufgabe sofort ohne Zurückhalten. Die
      // alte Markierung blieb für 'tasks' sonst für immer hängen.
      await _push('tasks', taskId, all[idx].toJson());
    }
  }

  Future<void> pushCalendarEvent(String id) async {
    if (_token == null) return;
    if (_isReadOnly && !CalendarSyncHandshake.instance.isActive) return;

    final e = CalendarEventStore.byId(id);
    if (e == null) {
      await _delete('calendar_events', id);
      return;
    }
    // NEU: Der Sync/Lokal-Scope einer Gruppe entscheidet nur im Lesemodus
    // (Handshake-Feature) darüber, ob ein Termin geteilt wird. Als
    // vollwertiges Zweitgerät (Lesemodus aus) ist der Kalender ein
    // 1:1-Spiegel — dort syncen ausnahmslos ALLE Termine.
    if (_isReadOnly && !_eventIsSyncScoped(e)) {
      await _delete('calendar_events', id);
      return;
    }
    await _push('calendar_events', id, e.toJson());
  }

  bool _eventIsSyncScoped(CalendarEvent e) {
    for (final key in e.groupKeys) {
      try {
        if (EventGroupStore.byKey(key).isSync) return true;
      } catch (_) {}
    }
    return false;
  }

  /// Wie _eventIsSyncScoped, aber OHNE den Fallback-auf-erste-Gruppe von
  /// EventGroupStore.byKey. Der ist hier gefährlich: eine lokal (noch)
  /// unbekannte Gruppe des Originals — weil sie bewusst NICHT als "Sync"
  /// gepullt wurde — darf niemals als "sync" durchgehen, nur weil sie
  /// zufällig auf die erste lokal vorhandene Gruppe zurückfällt.
  bool _hasKnownLocalSyncGroup(List<String> groupKeys) {
    final all = EventGroupStore.loadAll();
    for (final key in groupKeys) {
      final match = all.where((g) => g.key == key);
      if (match.isNotEmpty && match.first.isSync) return true;
    }
    return false;
  }

  Future<void> pushEventGroup(String key) async {
    if (_token == null) return;
    if (_isReadOnly && !CalendarSyncHandshake.instance.isActive) return;

    final all = EventGroupStore.loadAll();
    final idx = all.indexWhere((g) => g.key == key);
    final g = idx == -1 ? null : all[idx];
    if (g == null) {
      await _delete('event_groups', key);
      return;
    }
    // NEU (Punkt 6): Ist eine Gruppe hier lokal NICHT sync-gescoped, wird
    // sie einfach NICHT gepusht — das entfernte Dokument darf NICHT
    // gelöscht werden. Der Schlüsselraum (z.B. Standard-Gruppen wie
    // "dienstlich"/"sonstiges") ist über BEIDE Geräte hinweg geteilt, aber
    // jedes Gerät hat für denselben Schlüssel einen eigenständigen,
    // unabhängigen Scope. Ein Löschen hier hätte sonst die eigenständige,
    // ggf. sync-gescopte Fassung des JEWEILS ANDEREN Geräts unter demselben
    // Schlüssel zerstört. Eine ECHTE Löschung läuft ausschließlich über
    // EventGroupStore.delete() (siehe g == null-Zweig oben).
    if (_isReadOnly && !g.isSync) {
      return;
    }
    await _push('event_groups', key, g.toJson());
  }

  Future<void> pushVehicleMemory(String kennzeichen) async {
    if (_token == null) return;
    final box = Hive.box('einstellungen');
    final all = Map<String, dynamic>.from(box.get('fahrtenbuch_km_memory', defaultValue: {}) as Map);
    final entry = all[kennzeichen];
    if (entry == null) {
      await _delete('vehicle_memory', kennzeichen);
    } else {
      await _push('vehicle_memory', kennzeichen, entry);
    }
  }

  Future<void> republishCalendarForHandshake() async {
    if (_token == null) return;
    for (final g in EventGroupStore.loadAll()) {
      await pushEventGroup(g.key);
    }
    for (final e in CalendarEventStore.loadAllRaw()) {
      await pushCalendarEvent(e.id);
    }
  }

  Future<void> restoreFullMirrorAfterReadOnlyDisabled() async {
    final token = _token;
    if (token == null) return;
    final base = _db.collection('syncData').doc(token);

    try {
      final snap = await base.collection('tasks').get().timeout(const Duration(seconds: 8));
      final tasks = snap.docs
          .map((d) => d.data()['payload'])
          .whereType<Map>()
          .map((m) => Task.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      TaskStore.saveAll(tasks);
      TaskStore.changesSignal.value++;
    } catch (e) { debugPrint('$_tag: Restore tasks Fehler: $e'); }

    try {
      final snap = await base.collection('calendar_events').get().timeout(const Duration(seconds: 8));
      final events = snap.docs
          .map((d) => d.data()['payload'])
          .whereType<Map>()
          .map((m) => CalendarEvent.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      await CalendarEventStore.saveAllExternal(events);
    } catch (e) { debugPrint('$_tag: Restore calendar_events Fehler: $e'); }

    try {
      final snap = await base.collection('event_groups').get().timeout(const Duration(seconds: 8));
      final groups = snap.docs
          .map((d) => d.data()['payload'])
          .whereType<Map>()
          .map((m) => EventGroupDef.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      if (groups.isNotEmpty) EventGroupStore.applyRemote(groups);
    } catch (e) { debugPrint('$_tag: Restore event_groups Fehler: $e'); }

    final metaBox = Hive.box('einstellungen');
    for (final key in metaBox.keys.toList()) {
      final k = key.toString();
      if (k.startsWith('_syncver_tasks/') ||
          k.startsWith('_syncver_calendar_events/') ||
          k.startsWith('_syncver_event_groups/')) {
        metaBox.delete(key);
      }
    }

    await _stopSync();
    await _startSync(token);
  }

  // ── NEU (Punkt 1): Kalender vollständig zurücksetzen (nur Admin) ─────────
  Future<void> resetCalendarCompletely() async {
    // NEU: eigenen Zeitstempel VOR dem Signal-Push merken, damit der eigene
    // Listener das Signal nicht nochmal auf sich selbst anwendet.
    final ownTs = DateTime.now().millisecondsSinceEpoch;
    await Hive.box('einstellungen').put('_last_calendar_reset_at', ownTs);

    // NEU (Punkt 1): Apple-Verknüpfungen VOR dem lokalen Reset komplett
    // auflösen — sonst blieben Mappings zu inzwischen gelöschten Gruppen
    // hängen und von der App angelegte Apple-Kalender wurden nie geräumt.
    await AppleCalendarSyncService.instance.wipeEverything();

    final oldEvents = CalendarEventStore.loadAllRaw();
    final oldGroups = EventGroupStore.loadAll();

    for (final e in oldEvents) {
      await _delete('calendar_events', e.id);
    }
    for (final g in oldGroups) {
      await _delete('event_groups', g.key);
    }

    CalendarEventStore.resetLocal();
  EventGroupStore.resetToDefaultsLocal();
  await _clearCalendarSyncverMeta(); // NEU

  for (final g in EventGroupStore.loadAll()) {
    await pushEventGroup(g.key);
  }
  await _pushCalendarResetSignal(ownTs);
  scheduleDataChanged.value++;
}

  // ── NEU: Signalisiert allen anderen Geräten "Kalender wurde komplett
  // zurückgesetzt" — löst dort dieselbe lokale Routine aus wie der Button
  // selbst (inkl. eigener Apple-Verknüpfung), statt sich auf Dokument-Diffs
  // zu verlassen (unzuverlässig wegen der Gruppen-Kollisions-Remap-Logik).
  Future<void> _pushCalendarResetSignal(int clientAt) async {
    if (_token == null) return;
    try {
      await _db.collection('syncData').doc(_token).collection('meta').doc('calendar_reset').set({
        'at': FieldValue.serverTimestamp(),
        'clientAt': clientAt,
      });
    } catch (e) {
      debugPrint('$_tag: Reset-Signal Fehler: $e');
    }
  }

  void _startCalendarResetListener(String token) {
    final docRef = _db.collection('syncData').doc(token).collection('meta').doc('calendar_reset');
    final sub = docRef.snapshots().listen((snap) async {
      if (!_initialized || !snap.exists) return;
      final remoteAt = snap.data()?['clientAt'] as int?;
      if (remoteAt == null) return;
      final localAt = Hive.box('einstellungen').get('_last_calendar_reset_at') as int?;
      // Eigenes Signal (durch resetCalendarCompletely() bereits verarbeitet)
      // nicht nochmal auf sich selbst anwenden.
      if (localAt != null && localAt >= remoteAt) return;
      await Hive.box('einstellungen').put('_last_calendar_reset_at', remoteAt);
      await _applyIncomingCalendarReset();
    });
    _listeners.add(sub);
  }

  /// NEU: Macht auf dem EMPFANGENDEN Gerät exakt das, was der Button lokal
  /// auslöst — nur ohne erneutes Löschen/Pushen der Remote-Dokumente (das hat
  /// der Auslöser bereits erledigt).
  Future<void> _applyIncomingCalendarReset() async {
  debugPrint('$_tag: Eingehendes Kalender-Reset-Signal — räume lokal auf…');
  try {
    await AppleCalendarSyncService.instance.wipeEverything();
  } catch (e) {
    debugPrint('$_tag: Apple-Wipe (Reset-Signal) Fehler: $e');
  }
  CalendarEventStore.resetLocal();
  EventGroupStore.resetToDefaultsLocal();
  await _clearCalendarSyncverMeta(); // NEU
  scheduleDataChanged.value++;
}

// NEU: Entfernt alle gemerkten "letzte lokale Version"-Zeitstempel für
// Kalender-Termine und -Gruppen. Ohne das würde ein späterer, in
// Wahrheit neuerer Remote-Stand für dieselbe Dokument-ID fälschlich als
// "älter als mein (längst gelöschter) lokaler Stand" verworfen werden —
// genau das Symptom aus der Konsole ("lokal ist aktueller").
Future<void> _clearCalendarSyncverMeta() async {
  final metaBox = Hive.box('einstellungen');
  final keysToRemove = metaBox.keys.where((k) {
    final s = k.toString();
    return s.startsWith('_syncver_calendar_events/') ||
        s.startsWith('_syncver_event_groups/');
  }).toList();
  for (final k in keysToRemove) {
    await metaBox.delete(k);
  }
}

  // ── NEU: Fremd-Daten beim Trennen entfernen ───────────────────────────────

  /// Entfernt aus tasks/calendar_events/event_groups alle Items, die
  /// nachweislich vom jeweils ANDEREN Gerät stammen. Eigene lokale
  /// Einträge (inkl. solcher ohne Owner-Markierung, z.B. aus der Zeit
  /// vor diesem Feature) bleiben unangetastet.
  Future<void> wipeForeignOwnedData(String? formerRole) async {
    if (formerRole == null) return;
    final foreignRole = formerRole == 'original' ? 'reader' : 'original';

    final tasks = TaskStore.loadAllRaw();
    final keptTasks = tasks.where((t) => _ownerOf('tasks', t.id) != foreignRole).toList();
    if (keptTasks.length != tasks.length) {
      TaskStore.saveAll(keptTasks);
      TaskStore.changesSignal.value++;
    }

   final events = CalendarEventStore.loadAllRaw();
    final keptEvents = events.where((e) => _ownerOf('calendar_events', e.id) != foreignRole).toList();
    if (keptEvents.length != events.length) {
      CalendarEventStore.saveAllExternal(keptEvents);
    }

    final groups = EventGroupStore.loadAll();
    final keptGroups = groups.where((g) => _ownerOf('event_groups', g.key) != foreignRole).toList();
    if (keptGroups.isNotEmpty && keptGroups.length != groups.length) {
      EventGroupStore.applyRemote(keptGroups);
    }

    // NEU: Ein Kopiergerät (reader) hat Dienstplan, Fahrtenbuch, Notizen,
    // Ereignisse, Kollegen und Arbeitszeiten nur zum Ansehen erhalten —
    // diese Daten stammen komplett vom Original und dürfen nach dem
    // Trennen nicht lokal verbleiben.
    if (formerRole == 'reader') {
      final settingsBox = Hive.box('einstellungen');
      final keysToRemove = settingsBox.keys.where((k) {
        final s = k.toString();
        return s.startsWith('schedule_') ||
            s.startsWith('fahrten_') ||
            s.startsWith('events_') ||
            s.startsWith('colleagues_');
      }).toList();
      for (final k in keysToRemove) {
        await settingsBox.delete(k);
      }
      await Hive.box('arbeitszeiten').clear();

      // NEU: Der Lesemodus-Code schützt ausschließlich die mitgebrachten
      // Daten des verknüpften Original-Geräts. Ist die Verknüpfung
      // getrennt — egal ob durch dieses Gerät selbst oder durch das
      // Original —, gibt es nichts mehr zu schützen. Der Lesemodus wird
      // deshalb automatisch beendet, ohne dass der Code eingegeben
      // werden muss.
      await settingsBox.put('read_only_mode', false);
    }

    final box = Hive.box('einstellungen');
    await box.delete(_ownerMapKey);
    await box.delete(_pendingConflictsKey);
    await box.delete(_pendingOwnKey);
    for (final k in box.keys.where((k) => k.toString().startsWith(_shadowPrefix)).toList()) {
      await box.delete(k);
    }
    pendingConflictsCount.value = 0;
    scheduleDataChanged.value++;
  }

  // ── NEU: Konflikt-API für die Blob-Collections ────────────────────────────

  Map<String, dynamic> _loadPendingConflicts() {
    final raw = Hive.box('einstellungen').get(_pendingConflictsKey);
    if (raw is String && raw.isNotEmpty) {
      try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) {}
    }
    return {};
  }

  void _savePendingConflicts(Map<String, dynamic> data) {
    Hive.box('einstellungen').put(_pendingConflictsKey, jsonEncode(data));
    _refreshPendingConflictsCount(preloaded: data);
  }

  void _refreshPendingConflictsCount({Map<String, dynamic>? preloaded}) {
    final all = preloaded ?? _loadPendingConflicts();
    var count = 0;
    for (final v in all.values) {
      if (v is Map) count += v.length;
    }
    pendingConflictsCount.value = count;
  }

  Future<void> _queueConflict(
      String collection, String docId, dynamic payload, int? clientUpdatedAt, String? authorName) async {
    final all = _loadPendingConflicts();
    final col = Map<String, dynamic>.from(all[collection] as Map? ?? {});
    col[docId] = {'payload': payload, 'clientUpdatedAt': clientUpdatedAt, 'authorName': authorName};
    all[collection] = col;
    _savePendingConflicts(all);
  }

  /// Für die UI (Profil → Sync-Modus → Konflikte).
  List<SyncConflictItem> listPendingConflicts() {
    final all = _loadPendingConflicts();
    final result = <SyncConflictItem>[];
    for (final entry in all.entries) {
      final col = Map<String, dynamic>.from(entry.value as Map);
      for (final docEntry in col.entries) {
        final itemMap = Map<String, dynamic>.from(docEntry.value as Map);
        final payload = itemMap['payload'];
        final authorName = itemMap['authorName'] as String?;
        result.add(SyncConflictItem(
            collection: entry.key, docId: docEntry.key, payload: payload, authorName: authorName));
      }
    }
    return result;
  }

  /// Übernimmt den vom Kopiergerät mitgebrachten Stand für dieses Item.
  Future<void> acceptConflict(String collection, String docId) async {
    final all = _loadPendingConflicts();
    final col = Map<String, dynamic>.from(all[collection] as Map? ?? {});
    final entry = col.remove(docId);
    all[collection] = col;
    _savePendingConflicts(all);
    if (entry == null) return;
    final payload = (entry as Map)['payload'];
    await _writeLocal(collection, docId, payload);
    // NEU: Re-Push mit eigener (Original-)Autorenkennung — das Kopiergerät
    // erkennt dadurch, dass sein Vorschlag bestätigt wurde, und blendet
    // die bislang zurückgehaltene Änderung nun ein (siehe _applyRemoteDoc,
    // Reader-Zweig).
    await _push(collection, docId, payload);
  }

  /// Verwirft die eingehende Änderung und schreibt den eigenen (Original-)
  /// Stand zurück nach Firestore, damit das Kopiergerät den Konflikt nicht
  /// erneut anbietet.
  Future<void> rejectConflict(String collection, String docId) async {
    final all = _loadPendingConflicts();
    final col = Map<String, dynamic>.from(all[collection] as Map? ?? {});
    col.remove(docId);
    all[collection] = col;
    _savePendingConflicts(all);
    await _rePushLocal(collection, docId);
  }

  Future<void> acceptAllConflicts(String collection) async {
    final all = _loadPendingConflicts();
    final col = Map<String, dynamic>.from(all[collection] as Map? ?? {});
    for (final id in col.keys.toList()) {
      await acceptConflict(collection, id);
    }
  }

  Future<void> rejectAllConflicts(String collection) async {
    final all = _loadPendingConflicts();
    final col = Map<String, dynamic>.from(all[collection] as Map? ?? {});
    for (final id in col.keys.toList()) {
      await rejectConflict(collection, id);
    }
  }

  Future<void> _rePushLocal(String collection, String docId) async {
    final box = Hive.box('einstellungen');
    dynamic localValue;
    switch (collection) {
      case 'fahrten':
        localValue = box.get('fahrten_$docId');
        break;
      case 'schedule':
        localValue = box.get('schedule_$docId');
        break;
      case 'arbeitszeiten':
        localValue = Hive.box('arbeitszeiten').get(docId);
        break;
      case 'tasks':
        final all = TaskStore.loadAllRaw();
        final idx = all.indexWhere((t) => t.id == docId);
        localValue = idx != -1 ? all[idx].toJson() : null;
        break;
      case 'calendar_events':
        localValue = CalendarEventStore.byId(docId)?.toJson();
        break;
    }
    if (localValue != null) {
      // Original hatte bereits einen eigenen Stand — diesen zurücksenden,
      // damit das Kopiergerät den bestätigten Original-Stand erhält.
      await _push(collection, docId, localValue);
    } else {
      // NEU: Original hatte diesen Datensatz NIE lokal — der Vorschlag des
      // Kopiergeräts wird komplett verworfen. Ohne einen expliziten
      // Lösch-Vorgang würde das Kopiergerät nie erfahren, dass entschieden
      // wurde, und der Datensatz bliebe für immer "ausstehend" hängen.
      await _delete(collection, docId);
    }
  }

  // ── Owner-Markierung (welches Gerät hat dieses Item zuletzt geschrieben) ──

  void _markOwner(String collection, String docId, String? role) {
    if (role == null) return;
    final box = Hive.box('einstellungen');
    final map = Map<String, dynamic>.from(box.get(_ownerMapKey, defaultValue: {}) as Map);
    map['$collection/$docId'] = role;
    box.put(_ownerMapKey, map);
  }

  String? _ownerOf(String collection, String docId) {
    final box = Hive.box('einstellungen');
    final map = Map<String, dynamic>.from(box.get(_ownerMapKey, defaultValue: {}) as Map);
    return map['$collection/$docId'] as String?;
  }

/// Öffentlicher Zugriff für die UI — um zu erkennen, ob ein Termin vom
  /// jeweils ANDEREN Gerät stammt und dessen Sync-Gruppe deshalb gesperrt
  /// angezeigt werden muss.
  String? ownerOf(String collection, String docId) => _ownerOf(collection, docId);

  /// Prüft, ob eine Kalender-Gruppe Termine enthält, die nachweislich vom
  /// jeweils ANDEREN Gerät angelegt wurden. Genutzt, um einen Sync→Lokal-
  /// Wechsel zu verhindern, der diese Termine sonst beim nächsten Abgleich
  /// beim Partner-Gerät löschen würde (siehe pushCalendarEvent →
  /// _eventIsSyncScoped). Termine ohne Owner-Markierung (z.B. sehr alte
  /// Einträge) und eigene Termine zählen NICHT als fremd.
  bool groupHasForeignEvents(String groupKey) {
    final myRole = SyncTokenService.role;
    if (myRole == null) return false;
    final foreignRole = myRole == 'original' ? 'reader' : 'original';
    return CalendarEventStore.loadAllRaw()
        .where((e) => e.groupKeys.contains(groupKey))
        .any((e) => _ownerOf('calendar_events', e.id) == foreignRole);
  }

  void _clearOwner(String collection, String docId) {
    final box = Hive.box('einstellungen');
    final map = Map<String, dynamic>.from(box.get(_ownerMapKey, defaultValue: {}) as Map);
    map.remove('$collection/$docId');
    box.put(_ownerMapKey, map);
  }

  // ── Interner Start/Stop ────────────────────────────────────────────────────

  Future<void> _startSync(String token) async {
  _token = token;
  _initialized = true;
  // NEU: Ladezustand gilt ausdrücklich NUR für das Kopiergerät — das
  // Original hat während des initialen Push/Pull nichts "Falsches" zu
  // zeigen, seine eigenen Daten sind ja bereits korrekt lokal vorhanden.
  initialSyncInProgress.value = (SyncTokenService.role == 'reader');
  debugPrint('$_tag: Starte Sync mit Token ${token.substring(0, 6)}…');

    CalendarSyncHandshake.instance.onBecameActive = () async {
      await republishCalendarForHandshake();
      await _pullFilteredCalendarOnce();
      _restartListeners();
    };
    await CalendarSyncHandshake.instance.start(token);
    CalendarSyncHandshake.instance.state.removeListener(_onCalendarSyncStateChanged);
    CalendarSyncHandshake.instance.state.addListener(_onCalendarSyncStateChanged);

    // NEU: Präsenz-Überwachung starten, falls dieses Gerät Kopiergerät ist.
    SyncTokenService.instance.watchOriginalPresenceIfNeeded(token);

    // NEU: Ein Kopiergerät darf beim Verknüpfen NICHT einfach seine
    // lokalen Daten nach Firestore überschreiben (das würde die
    // Original-Daten dort löschen, bevor überhaupt gepullt wurde).
    // Stattdessen: erst pullen, dann eigene Abweichungen als Vorschlag
    // einreichen — siehe _initialSyncAsReader.
    if (SyncTokenService.role == 'reader') {
      await _initialSyncAsReader(token);
    } else {
      await _initialPush(token);
      await _initialPull(token);
    }
    _startListeners(token);
    _startCalendarResetListener(token); // NEU
    initialSyncInProgress.value = false; // NEU
    // NEU: Nach dem initialen Sync sollen offene Screens (Dienstplan,
    // Fahrtenbuch) sich sofort aktualisieren, ohne dass der Monat manuell
    // gewechselt werden muss.
    scheduleDataChanged.value++;
  }

  Future<void> _stopSync() async {
    await CalendarSyncHandshake.instance.stop();
    for (final sub in _listeners) {
      await sub.cancel();
    }
    _listeners.clear();
    _token = null;
    _initialized = false;
    initialSyncInProgress.value = false; // NEU — Absicherung bei Abbruch
    debugPrint('$_tag: Sync gestoppt.');
  }

  // ── NEU: Reconciliation beim Verknüpfen als Kopiergerät ──────────────────

  /// Wird beim Verknüpfen als Kopiergerät (role == 'reader') statt der
  /// normalen Push→Pull-Reihenfolge verwendet. Zuerst wird die Original-
  /// Wahrheit gepullt (Basis, sofort sichtbar), danach werden lokale
  /// Abweichungen bei geschützten Datensätzen NICHT einfach nach Firestore
  /// überschrieben, sondern als Vorschlag eingereicht und lokal als
  /// "ausstehend" markiert — sichtbar bleibt bis zur Entscheidung des
  /// Originals der gerade gepullte Original-Stand (Schatten).
  Future<void> _initialSyncAsReader(String token) async {
    debugPrint('$_tag: Initial Sync als Kopiergerät…');
    final settingsBox = Hive.box('einstellungen');
    final zeitBox = Hive.box('arbeitszeiten');

    // ── Schritt 1: lokale Vorab-Snapshots geschützter Blob-Collections ────
    // WICHTIG: 'schedule' bewusst NICHT mehr hier erfasst — der Dienstplan
    // kommt beim Verknüpfen IMMER vollständig vom Original (reiner Pull).
    // Ein Kopiergerät darf beim Verknüpfen nichts eigenes einbringen und
    // löst dafür auch NIE einen Konflikt aus.
    final Map<String, dynamic> localFahrten = {};
    final Map<String, dynamic> localArbeitszeiten = {};
    for (final key in settingsBox.keys) {
      final k = key.toString();
      if (k.startsWith('fahrten_')) {
        localFahrten[k.substring('fahrten_'.length)] = settingsBox.get(key);
      }
    }
    for (final key in zeitBox.keys) {
      final data = zeitBox.get(key);
      if (data != null) localArbeitszeiten[key.toString()] = data;
    }

    // ── Schritt 2: unkritische Collections normal pushen (kein Konflikt-
    // Schutz nötig: Notizen, Ereignisse, Kollegen, Fahrzeug-Gedächtnis,
    // Kalender/-Gruppen entscheiden selbst über Sync-Scope) ──────────────
    try {
      for (final key in settingsBox.keys) {
        final k = key.toString();
        if (k.startsWith('schedule_note_')) {
          await _push('notes', k.substring('schedule_note_'.length), settingsBox.get(key));
        } else if (k.startsWith('events_')) {
          await _push('events', k.substring('events_'.length), settingsBox.get(key));
        } else if (k.startsWith('colleagues_') && !k.startsWith('colleagues_debug_')) {
          await _push('colleagues', k.substring('colleagues_'.length), settingsBox.get(key));
        }
      }
      final kmAll = Map<String, dynamic>.from(settingsBox.get('fahrtenbuch_km_memory', defaultValue: {}) as Map);
      for (final entry in kmAll.entries) {
        await _push('vehicle_memory', entry.key, entry.value);
      }
      // WICHTIG: Kalender-Ereignisse NICHT mehr hier blind pushen — sie
      // sind jetzt konfliktgeschützt (_conflictProtected) und laufen
      // stattdessen weiter unten (Schritt 5), NACH dem Pull, über
      // denselben "Vorschlag zurückhalten"-Mechanismus wie Aufgaben.
      for (final g in EventGroupStore.loadAll()) {
        await pushEventGroup(g.key);
      }
    } catch (e) {
      debugPrint('$_tag: Initial Sync (unkritisch) Fehler: $e');
    }

    // ── Schritt 3: ALLES pullen — Original-Wahrheit wird jetzt Basis ──────
    await _initialPull(token);

    // NEU: Für 'fahrten' und 'arbeitszeiten' brauchen wir zusätzlich zum
    // reinen Wertevergleich die Information, ob das Original für einen
    // Schlüssel überhaupt schon ein Remote-Dokument hatte — sonst bleibt
    // afterPull==beforePull (der Pull hat ja nichts überschrieben) und der
    // alte Vergleich hätte fälschlich "keine Abweichung" gefolgert.
    Set<String> remoteFahrtenIds = {};
    Set<String> remoteArbeitszeitenIds = {};
    try {
      final fahrtenSnap = await _db.collection('syncData').doc(token).collection('fahrten')
          .get().timeout(const Duration(seconds: 8));
      remoteFahrtenIds = fahrtenSnap.docs.map((d) => d.id).toSet();
      final zeitSnap = await _db.collection('syncData').doc(token).collection('arbeitszeiten')
          .get().timeout(const Duration(seconds: 8));
      remoteArbeitszeitenIds = zeitSnap.docs.map((d) => d.id).toSet();
    } catch (e) {
      debugPrint('$_tag: Remote-IDs (fahrten/arbeitszeiten) Abruf Fehler: $e');
    }

    // ── Schritt 4: geschützte Collections abgleichen ──────────────────────
    for (final entry in localFahrten.entries) {
      await _reconcileProtectedDoc(
          'fahrten', entry.key, entry.value, () => settingsBox.get('fahrten_${entry.key}'),
          existedRemotely: remoteFahrtenIds.contains(entry.key));
    }
    for (final entry in localArbeitszeiten.entries) {
      await _reconcileProtectedDoc(
          'arbeitszeiten', entry.key, entry.value, () => zeitBox.get(entry.key),
          existedRemotely: remoteArbeitszeitenIds.contains(entry.key));
    }

    // ── Schritt 5: lokal-neue Aufgaben (noch nicht remote vorhanden) als
    // Vorschlag markieren — bereits remote vorhandene bleiben unberührt.
    if (!_isReadOnly) {
      Set<String> remoteTaskIds = {};
      try {
        final snap = await _db.collection('syncData').doc(token).collection('tasks')
            .get().timeout(const Duration(seconds: 8));
        remoteTaskIds = snap.docs.map((d) => d.id).toSet();
      } catch (e) {
        debugPrint('$_tag: Remote-Task-IDs Abruf Fehler: $e');
      }
      for (final task in TaskStore.loadAllRaw()) {
        if (!remoteTaskIds.contains(task.id)) {
          // NEU: Beim ERSTEN Verknüpfen mitgebrachte, dem Original noch
          // unbekannte Aufgabe -> als Vorschlag zurückhalten, bis das
          // Original sie im Konflikte-Screen bestätigt oder verwirft.
          _markPendingOwn('tasks', task.id);
          await _push('tasks', task.id, task.toJson(), isInitialLinkSync: true);
        }
      }

      // NEU: Exakt dasselbe Prinzip für Kalender-Ereignisse — lokal
      // bereits vorhandene Ereignisse, die das Original beim Verknüpfen
      // noch nicht kennt, werden NICHT automatisch gemergt, sondern als
      // Vorschlag zurückgehalten, bis das Original sie im
      // Konflikte-Screen bestätigt oder verwirft.
      Set<String> remoteEventIds = {};
      try {
        final snap = await _db.collection('syncData').doc(token).collection('calendar_events')
            .get().timeout(const Duration(seconds: 8));
        remoteEventIds = snap.docs.map((d) => d.id).toSet();
      } catch (e) {
        debugPrint('$_tag: Remote-Event-IDs Abruf Fehler: $e');
      }
      for (final e in CalendarEventStore.loadAllRaw()) {
        if (!remoteEventIds.contains(e.id)) {
          _markPendingOwn('calendar_events', e.id);
          await _push('calendar_events', e.id, e.toJson(), isInitialLinkSync: true);
        }
      }
    }

    debugPrint('$_tag: Initial Sync als Kopiergerät abgeschlossen.');
  }

  /// Vergleicht die VOR dem Pull vorhandene lokale Fassung eines
  /// geschützten Blob-Dokuments mit der nach dem Pull aktuell gültigen
  /// Fassung. Weichen sie ab, wird die eigene Fassung als Vorschlag an
  /// Firestore gesendet (löst beim Original einen Konflikt aus) und lokal
  /// als "ausstehend" markiert. Angezeigt wird bis zur Entscheidung
  /// weiterhin die gerade gepullte Fassung (Schatten) — die Box selbst
  /// wird NICHT mit der eigenen Fassung überschrieben.
  Future<void> _reconcileProtectedDoc(
    String collection,
    String docId,
    dynamic localValueBeforePull,
    dynamic Function() currentBoxValue, {
    required bool existedRemotely,
  }) async {
    if (localValueBeforePull == null) return;
    final afterPull = currentBoxValue();

    // BUGFIX: Existierte für diesen Schlüssel beim Original GAR KEIN
    // Remote-Dokument, bleibt afterPull zwangsläufig IDENTISCH zu
    // localValueBeforePull (der Pull hat hier ja nichts überschrieben).
    // Der alte Gleichheits-Check hat das fälschlich als "keine Abweichung"
    // gewertet und NIE gepusht — mitgebrachte Alt-Daten, die das Original
    // noch gar nicht kannte, blieben dadurch rein lokal auf dem
    // Kopiergerät hängen, ganz ohne Konflikt-Eintrag beim Original.
    if (existedRemotely && _deepEquals(localValueBeforePull, afterPull)) return;

    // WICHTIG: Das gilt IMMER beim (ersten) Verknüpfen eines Geräts, egal
    // ob später Lesemodus aktiv ist oder nicht — mitgebrachte Altdaten
    // werden als Vorschlag zurückgehalten, bis das Original sie im
    // Konflikte-Screen bestätigt oder verwirft. Laufende Änderungen NACH
    // dem Verknüpfen laufen NICHT mehr über diesen Pfad (siehe
    // pushFahrtenMonth/pushArbeitszeit/pushTask) und syncen direkt.
    //
    // BUGFIX: Ein Schatten darf NUR gesetzt werden, wenn beim Original
    // tatsächlich schon ein Remote-Dokument existierte (existedRemotely).
    // Sonst ist afterPull identisch mit dem eigenen, unbestätigten
    // localValueBeforePull (der Pull hat ja nichts überschrieben) — der
    // Schatten hätte dann exakt den eigenen Vorschlag angezeigt, obwohl
    // das Original ihn noch gar nicht bestätigt hat. In diesem Fall bleibt
    // der Schatten leer, sodass der Eintrag bis zur Entscheidung des
    // Originals komplett unsichtbar bleibt (wie bei komplett neuen
    // Aufgaben/Terminen).
    if (existedRemotely) {
      _updateShadow(collection, docId, afterPull);
    } else {
      await Hive.box('einstellungen').delete('$_shadowPrefix${collection}_$docId');
    }
    _markPendingOwn(collection, docId);
    await _push(collection, docId, localValueBeforePull, isInitialLinkSync: true);
  }
  bool _deepEquals(dynamic a, dynamic b) {
    try {
      return jsonEncode(_serialize(a)) == jsonEncode(_serialize(b));
    } catch (_) {
      return a == b;
    }
  }

  // ── Initial Pull: Firestore → Hive ────────────────────────────────────────

  Future<void> _initialPull(String token) async {
    debugPrint('$_tag: Initial Pull…');
    try {
      final base = _db.collection('syncData').doc(token);
      final collections = _activeCollections();
      
      // NEU: Collections, für die wir eine Reconciliation durchführen
      const reconciledCollections = {'calendar_events', 'tasks'};

      for (final col in collections) {
        final snap = await base.collection(col).get().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Pull timeout ($col)'),
        );
        _isSyncing = true;
        final remoteIds = <String>{};
        for (final doc in snap.docs) {
          remoteIds.add(doc.id);
          await _applyRemoteDoc(col, doc.id, doc.data());
        }
        if (reconciledCollections.contains(col)) {
          await _reconcileDeletions(col, remoteIds);
        }
        _isSyncing = false;
      }
      debugPrint('$_tag: Initial Pull abgeschlossen.');
    } catch (e) {
      _isSyncing = false;
      debugPrint('$_tag: Initial Pull Fehler: $e');
    }
  }

  // ── NEU: Reconciliation nach dem Pull ─────────────────────────────────────

  /// Räumt nach einem vollständigen Pull einer Collection lokale
  /// Datensätze weg, die remote nicht mehr existieren — Löschungen, die
  /// verpasst wurden, weil der Live-Listener zum Zeitpunkt der Löschung
  /// nicht lief (z.B. App war geschlossen). Bearbeitungen/Neuanlagen sind
  /// davon nicht betroffen, da deren Dokumente ja weiterhin remote existieren
  /// und über den normalen _applyRemoteDoc-Pfad laufen.
  ///
  /// WICHTIG: Eigene, noch unbestätigte Vorschläge des Kopiergeräts
  /// (isPendingOwn) dürfen NICHT gelöscht werden, nur weil sie remote noch
  /// nicht angekommen sind — sonst würde ein frisch eingereichter, aber noch
  /// nicht vom Original bestätigter Vorschlag sofort wieder verschwinden.
  Future<void> _reconcileDeletions(String collection, Set<String> remoteIds) async {
    switch (collection) {
      case 'calendar_events':
        final all = CalendarEventStore.loadAllRaw();
        final toKeep = <CalendarEvent>[];
        var changed = false;
        for (final e in all) {
          final isOwnPending =
              SyncTokenService.role == 'reader' && isPendingOwn('calendar_events', e.id);
          if (remoteIds.contains(e.id) || isOwnPending) {
            toKeep.add(e);
          } else {
            changed = true;
          }
        }
        if (changed) {
          await CalendarEventStore.saveAllExternal(toKeep);
        }
        break;

      case 'tasks':
        // Tasks sind im Lesemodus komplett isoliert (siehe _isolatedInReadOnly)
        // — 'tasks' taucht dann in _activeCollections() gar nicht auf, diese
        // Funktion wird für 'tasks' also nur aufgerufen, wenn Tasks aktiv
        // gesynct werden.
        final all = TaskStore.loadAllRaw();
        final toKeep = <Task>[];
        var changed = false;
        for (final t in all) {
          final isOwnPending =
              SyncTokenService.role == 'reader' && isPendingOwn('tasks', t.id);
          if (remoteIds.contains(t.id) || isOwnPending) {
            toKeep.add(t);
          } else {
            changed = true;
          }
        }
        if (changed) {
          TaskStore.saveAll(toKeep);
          TaskStore.changesSignal.value++;
        }
        break;
    }
  }

  // ── Initial Push: Hive → Firestore ────────────────────────────────────────

  Future<void> _initialPush(String token) async {
    debugPrint('$_tag: Initial Push…');
    try {
      final zeitBox = Hive.box('arbeitszeiten');
      final settingsBox = Hive.box('einstellungen');

      for (final key in zeitBox.keys) {
        final data = zeitBox.get(key);
        if (data != null) {
          await _push('arbeitszeiten', key.toString(), data);
        }
      }

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

      final kmAll = Map<String, dynamic>.from(settingsBox.get('fahrtenbuch_km_memory', defaultValue: {}) as Map);
      for (final entry in kmAll.entries) {
        await _push('vehicle_memory', entry.key, entry.value);
      }

      // Aufgaben bleiben im Lesemodus IMMER vollständig isoliert.
      if (!_isReadOnly) {
        for (final task in TaskStore.loadAll()) {
          await _push('tasks', task.id, task.toJson());
        }
      }

      // pushCalendarEvent/pushEventGroup entscheiden selbst anhand von
      // Sync-Scope + Lesemodus/Handshake — deshalb IMMER aufrufen, sonst
      // bleibt der Kalender-Handshake beim initialen Push wirkungslos.
      for (final e in CalendarEventStore.loadAll()) {
        await pushCalendarEvent(e.id);
      }
      for (final g in EventGroupStore.loadAll()) {
        await pushEventGroup(g.key);
      }

      debugPrint('$_tag: Initial Push abgeschlossen.');
    } catch (e) {
      debugPrint('$_tag: Initial Push Fehler: $e');
    }
  }

  // ── Realtime-Listener ─────────────────────────────────────────────────────

  void _startListeners(String token) {
    final base = _db.collection('syncData').doc(token);
    final collections = _activeCollections();

    for (final col in collections) {
      final sub = base.collection(col).snapshots().listen(
        (snap) {
          if (!_initialized) return;
          for (final change in snap.docChanges) {
            final pushKey = '$col/${change.doc.id}';
            // BUGFIX: Vorher wurde JEDE Änderung/Löschung am selben
            // Datensatz innerhalb von 8 Sekunden übersprungen, sobald
            // DIESES Gerät selbst kürzlich etwas zu genau diesem pushKey
            // gepusht hatte — auch wenn die eingehende Änderung in
            // Wahrheit vom ANDEREN Gerät kam (z.B. Original erstellt,
            // Kopiergerät löscht Sekunden später → Löschung ging beim
            // Original verloren). Jetzt wird nur noch übersprungen, wenn
            // es NACHWEISLICH das Echo des eigenen letzten Pushes ist
            // (exakt gleicher clientUpdatedAt-Stempel), und Löschungen
            // werden NIE übersprungen.
            final lastPush = _lastLocalPushAt[pushKey];
            final withinEchoWindow =
                lastPush != null && DateTime.now().difference(lastPush) < const Duration(seconds: 8);
            if (withinEchoWindow && change.type != DocumentChangeType.removed) {
              final incomingClientTs = (change.doc.data() ?? {})['clientUpdatedAt'] as int?;
              final ownLastPushTs = _lastLocalPushClientTs[pushKey];
              if (ownLastPushTs != null && incomingClientTs == ownLastPushTs) {
                continue;
              }
            }
            _pendingRemoteChanges[pushKey] = _PendingRemoteChange(
              collection: col,
              docId: change.doc.id,
              type: change.type,
              data: change.doc.data() ?? {},
            );
          }
          _scheduleRemoteBatchFlush();
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

  void _scheduleRemoteBatchFlush() {
    if (_remoteBatchTimer != null) return;
    _remoteBatchTimer = Timer(const Duration(milliseconds: 250), () async {
      _remoteBatchTimer = null;
      await _flushPendingRemoteChanges();
    });
  }

  Future<void> _flushPendingRemoteChanges() async {
    if (_pendingRemoteChanges.isEmpty) return;
    final pending = _pendingRemoteChanges.values.toList();
    _pendingRemoteChanges.clear();
    if (!_initialized) return;
    _isSyncing = true;
    try {
      for (final change in pending) {
        if (change.type == DocumentChangeType.added ||
            change.type == DocumentChangeType.modified) {
          await _applyRemoteDoc(change.collection, change.docId, change.data);
        } else if (change.type == DocumentChangeType.removed) {
          await _applyRemoteDeletion(change.collection, change.docId);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  void _onCalendarSyncStateChanged() => _restartListeners();

  void _restartListeners() {
    for (final sub in _listeners) {
      sub.cancel();
    }
    _listeners.clear();
    if (_token != null) _startListeners(_token!);
  }

  Future<void> _pullFilteredCalendarOnce() async {
    if (_token == null) return;
    final base = _db.collection('syncData').doc(_token);
    for (final col in ['event_groups', 'calendar_events']) {
      try {
        final snap = await base.collection(col).get().timeout(const Duration(seconds: 8));
        final remoteIds = <String>{};
        for (final doc in snap.docs) {
          remoteIds.add(doc.id);
          await _applyRemoteDoc(col, doc.id, doc.data());
        }
        if (col == 'calendar_events') {
          await _reconcileDeletions(col, remoteIds);
        }
      } catch (e) { debugPrint('$_tag: Pull-Fehler ($col): $e'); }
    }
  }

  // ── Remote → Hive anwenden ────────────────────────────────────────────────
  Future<void> _applyRemoteDoc(String collection, String docId, Map<String, dynamic> data) async {
    final payload = data['payload'];
    if (payload == null) return;

    final remoteClientTs = data['clientUpdatedAt'] as int?;
    final localTs = Hive.box('einstellungen').get('_syncver_$collection/$docId') as int?;
    if (remoteClientTs != null && localTs != null && localTs >= remoteClientTs) {
      final now = DateTime.now();
      final lastLogAt = _lastIgnoredRemoteLogAt['$collection/$docId'];
      if (lastLogAt == null || now.difference(lastLogAt) > const Duration(seconds: 20)) {
        debugPrint('$_tag: Remote-Update ignoriert ($collection/$docId) — lokal ist aktueller.');
        _lastIgnoredRemoteLogAt['$collection/$docId'] = now;
      }
      return;
    }

    // NEU: Firestore liefert beim ERSTEN Attach eines Listeners IMMER
    // ALLE bereits vorhandenen Dokumente nochmal als "added"-Änderung —
    // unabhängig davon, ob sie kurz zuvor schon per _initialPull()
    // explizit abgerufen und verarbeitet wurden. Bisher wurde die
    // Version eines EMPFANGENEN Dokuments nirgends vermerkt (nur bei
    // EIGENEN Pushes, siehe _push()), wodurch genau derselbe Stand
    // zweimal durch _writeLocal() lief. Bei calendar_events führte das
    // dazu, dass pushEvent() (async, nicht awaited) zweimal für dasselbe
    // Event startete, bevor der erste Aufruf sein Apple-Mapping
    // gespeichert hatte — Ergebnis: zwei Apple-Termine für ein Event.
    // Zusätzlich verdoppelte es beim initialen Verknüpfen schlicht die
    // Menge an sequenziell abzuarbeitender Arbeit (gefühltes Hängen).
    // Fix: Version JEDES verarbeiteten Remote-Dokuments merken, damit ein
    // exakt identischer zweiter Versand (gleicher clientUpdatedAt) durch
    // die obige Prüfung abgefangen wird. Eine ECHTE spätere Änderung hat
    // einen neuen, höheren Zeitstempel und wird weiterhin normal verarbeitet.
    if (remoteClientTs != null) {
      final metaBox = Hive.box('einstellungen');
      await metaBox.put('_syncver_$collection/$docId', remoteClientTs);
    }

    final authorRole = data['authorRole'] as String?;
    final isInitialLinkSync = data['initialLinkSync'] as bool? ?? false;

    // NEU: Nur Inhalte, die ein Kopiergerät beim ERSTEN Verknüpfen bereits
    // lokal hatte, lösen einen Konflikt aus, den das Original bestätigen
    // oder verwerfen muss (siehe _reconcileProtectedDoc). Laufende
    // Änderungen NACH dem Verknüpfen tragen dieses Flag nicht und werden
    // von beiden gleichberechtigten Geräten immer sofort übernommen.
    if (SyncTokenService.role == 'original' &&
        _conflictProtected.contains(collection) &&
        authorRole == 'reader' &&
        isInitialLinkSync) {
      final authorName = data['authorName'] as String?;
      await _queueConflict(collection, docId, payload, remoteClientTs, authorName);
      return;
    }
    if (collection == 'event_groups') {
      // NEU (Punkt 2): siehe _applyIncomingEventGroup weiter unten.
      await _applyIncomingEventGroup(docId, Map<String, dynamic>.from(payload as Map), authorRole);
      return;
    }

    _markOwner(collection, docId, authorRole);
    await _writeLocal(collection, docId, payload);

    // BUGFIX: Vorher wurde JEDE eintreffende Fassung als "Antwort des
    // Originals" gewertet — auch das eigene Echo des Kopiergeräts, falls
    // das 8-Sekunden-Echo-Fenster im Listener nicht rechtzeitig griff.
    // Ergebnis: der eigene, noch unbestätigte Vorschlag wurde sofort selbst
    // freigegeben, obwohl das Original ihn nie bestätigt hatte. Jetzt wird
    // nur noch als echte Antwort gewertet, was NICHT vom Kopiergerät selbst
    // stammt (authorRole != 'reader', also 'original').
    if (SyncTokenService.role == 'reader' &&
        _conflictProtected.contains(collection) &&
        authorRole != 'reader') {
      _updateShadow(collection, docId, payload);
      _clearPendingOwn(collection, docId);
    }
  }

  // ── NEU (Punkt 2): Kollisionssicherer Gruppen-Merge ──────────────────────
  //
  // Standard-Gruppen kollidieren geräteübergreifend im Schlüssel. Nur
  // Gruppen, die schon als gemeinsam bekannt sind (_ownerOf gesetzt),
  // werden aktualisiert. Bei Kollision mit einer rein lokalen, nie
  // geteilten Gruppe wird die eingehende Sync-Gruppe als NEUE eigenständige
  // Gruppe hinzugefügt — nie ersetzt.
  Future<void> _applyIncomingEventGroup(
      String docId, Map<String, dynamic> payload, String? authorRole) async {
    final incoming = EventGroupDef.fromJson(payload);

    if (_isReadOnly &&
        (incoming.scope != GroupScope.sync ||
            !CalendarSyncHandshake.instance.isActive)) {
      return;
    }

    final all = EventGroupStore.loadAll();
    final idx = all.indexWhere((g) => g.key == docId);
    final alreadyKnownAsShared = _ownerOf('event_groups', docId) != null;

    if (idx == -1) {
      all.add(incoming);
      EventGroupStore.applyRemote(all);
      _markOwner('event_groups', docId, authorRole);
      return;
    }

    // NEU (Punkt 6): Ist die LOKALE Gruppe unter diesem Schlüssel selbst
    // bereits sync-gescoped (z.B. beide Geräte haben nach einem
    // Lesemodus-Reset unabhängig voneinander dieselbe Standard-Gruppe
    // "Privat" als Sync markiert), ist das KEINE echte Kollision, sondern
    // exakt der Fall, den beide Seiten geteilt sehen wollen — beide
    // Fassungen unter demselben Schlüssel vereinheitlichen, statt eine
    // neue, separate Gruppe anzulegen.
    final localMatch = all[idx];
    final isMutualSyncMatch = localMatch.scope == GroupScope.sync;

    // NEU: Die drei Standard-Gruppen-Keys sind ein bewusst geteilter,
    // fester Namensraum — beide Geräte seeden sie unabhängig voneinander
    // beim allerersten App-Start mit demselben Key. Eine "Kollision" bei
    // GENAU diesen Keys ist also NIE ein echter Zufallstreffer zwischen
    // zwei unabhängigen Gruppen, sondern IMMER dieselbe konzeptionelle
    // Gruppe — unabhängig vom aktuell gesetzten scope. Nur bei den
    // Zeitstempel-basierten Custom-Keys (grp_...) ist eine Kollision
    // praktisch ausgeschlossen und wird deshalb weiterhin als echte
    // Kollision (Remap) behandelt.
    const reservedDefaultKeys = {'privat', 'dienstlich', 'sonstiges'};
    final isReservedDefaultKey = reservedDefaultKeys.contains(docId);

    if (alreadyKnownAsShared || isMutualSyncMatch || isReservedDefaultKey) {
      all[idx] = incoming;
      EventGroupStore.applyRemote(all);
      _markOwner('event_groups', docId, authorRole);
      return;
    }

    // NEU: Bevor wir eine "echte Kollision" annehmen, prüfen wir, ob unter
    // einem ANDEREN Key bereits eine Gruppe mit exakt demselben Namen
    // existiert (z.B. beide Geräte haben unabhängig voneinander eine
    // Gruppe "Familie" angelegt, bevor überhaupt gesynct wurde). Ohne
    // diesen Check würde jedes Mal eine zweite, gleichnamige Gruppe unter
    // einem neuen grp_-Key entstehen — das sichtbare "Duplikat".
    // Groß-/Kleinschreibung und Leerraum werden dabei ignoriert.
    final normalizedIncomingName = incoming.name.trim().toLowerCase();
    final nameMatchIdx = all.indexWhere((g) =>
        g.key != docId && g.name.trim().toLowerCase() == normalizedIncomingName);

    if (nameMatchIdx != -1) {
      // Gleicher Name, anderer Key -> als DIESELBE konzeptionelle Gruppe
      // behandeln: lokale Gruppe unter ihrem BESTEHENDEN Key beibehalten
      // (keine neue Gruppe anlegen), aber das eingehende Dokument diesem
      // bestehenden Key zuordnen, damit künftige Updates unter demselben
      // Namen sauber zusammengeführt werden statt erneut zu kollidieren.
      _markOwner('event_groups', all[nameMatchIdx].key, authorRole);
      debugPrint('$_tag: Gruppen-Kollision bei "$docId" über Namensgleichheit '
          'mit bestehender Gruppe "${all[nameMatchIdx].key}" aufgelöst — keine Duplikat-Gruppe angelegt.');
      return;
    }

    // Echte Kollision: rein lokale, NICHT sync-gescopte Gruppe mit
    // zufällig gleichem Schlüssel UND unterschiedlichem Namen — bleibt
    // unangetastet, die eingehende Gruppe wird als eigenständige neue
    // Gruppe hinzugefügt statt ersetzt.
    final remapped = EventGroupDef(
      key: EventGroupStore.newKey(),
      name: incoming.name,
      colorValue: incoming.colorValue,
      scope: incoming.scope,
    );
    all.add(remapped);
    EventGroupStore.applyRemote(all);
    _markOwner('event_groups', remapped.key, authorRole);
    debugPrint('$_tag: Gruppen-Kollision bei "$docId" aufgelöst — neue Gruppe "${remapped.key}".');

    if (SyncTokenService.role == 'original') {
      _addGroupCollisionHint(incoming.name, docId, remapped.key);
    }
  }

  // ── NEU: Persistenter Hinweis bei Gruppen-Kollision (Punkt 2, Folge) ─────
  static const _groupCollisionHintsKey = '_group_collision_hints';

  void _addGroupCollisionHint(String groupName, String originalKey, String remappedKey) {
    final list = loadGroupCollisionHints();
    list.add({
      'id': '${DateTime.now().millisecondsSinceEpoch}_$originalKey',
      'groupName': groupName,
      'originalKey': originalKey,
      'remappedKey': remappedKey,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    Hive.box('einstellungen').put(_groupCollisionHintsKey, jsonEncode(list));
  }

  /// Öffentlich für die UI (Notification-Center).
  List<Map<String, dynamic>> loadGroupCollisionHints() {
    final raw = Hive.box('einstellungen').get(_groupCollisionHintsKey);
    if (raw is String && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      } catch (_) {}
    }
    return [];
  }

  /// Quittiert (entfernt) einen einzelnen Hinweis.
  void dismissGroupCollisionHint(String id) {
    final list = loadGroupCollisionHints()..removeWhere((e) => e['id'] == id);
    Hive.box('einstellungen').put(_groupCollisionHintsKey, jsonEncode(list));
  }

  /// Ausgelagert, damit sowohl der normale Remote-Apply-Pfad als auch
  /// [acceptConflict] denselben Schreib-Code nutzen.
  Future<void> _writeLocal(String collection, String docId, dynamic payload) async {
    if (payload == null) return;
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

        case 'tasks':
          // Aufgaben sind im Lesemodus IMMER vollständig isoliert — keine
          // Ausnahme (anders als Kalender gibt es dafür kein Handshake-
          // Feature). Verhindert, dass ein noch nicht abgemeldeter
          // Alt-Listener zurückgesetzte Aufgaben wieder befüllt.
          if (_isReadOnly) break;
          if (payload is Map) {
            final task = Task.fromJson(Map<String, dynamic>.from(payload));
            final all = TaskStore.loadAllRaw();
            final idx = all.indexWhere((t) => t.id == docId);
            if (idx >= 0) {
              all[idx] = task;
            } else {
              all.add(task);
            }
            TaskStore.saveAll(all);
            TaskStore.changesSignal.value++;
          }
          break;

        case 'calendar_events':
          if (payload is Map) {
            final event = CalendarEvent.fromJson(Map<String, dynamic>.from(payload));
            // NEU: Ein Lesemodus-Gerät mit aktivem Kalender-Handshake darf
            // NUR Termine übernehmen, deren Gruppe(n) als "Sync" markiert
            // sind. Das Original pusht bewusst weiterhin ALLE eigenen
            // Termine ungefiltert (für normale Vollspiegel-Zweitgeräte) —
            // die Einschränkung passiert deshalb hier beim Empfangen.
            if (_isReadOnly &&
                (!CalendarSyncHandshake.instance.isActive ||
                    !_hasKnownLocalSyncGroup(event.groupKeys))) {
              break;
            }
            final all = CalendarEventStore.loadAllRaw();
            final idx = all.indexWhere((e) => e.id == docId);
            if (idx >= 0) {
              all[idx] = event;
            } else {
              all.add(event);
            }
            await CalendarEventStore.saveAllExternal(all);
          }
          break;

        case 'event_groups':
          // NEU (Punkt 2): wird nicht mehr hier behandelt — siehe
          // _applyIncomingEventGroup(), das in _applyRemoteDoc() bereits
          // vorher greift und returned.
          break;

        case 'vehicle_memory':
          if (payload is Map) {
            final box = Hive.box('einstellungen');
            final all = Map<String, dynamic>.from(box.get('fahrtenbuch_km_memory', defaultValue: {}) as Map);
            all[docId] = Map<String, dynamic>.from(payload);
            box.put('fahrtenbuch_km_memory', all);
          }
          break;
      }
      // NEU: Dienstplan/Fahrtenbuch/Notiz-Screens über Datenänderung
      // informieren, damit sie sich ohne Monatswechsel aktualisieren.
      const _screenRefreshCollections = {
        'schedule', 'fahrten', 'notes', 'events', 'colleagues', 'arbeitszeiten',
      };
      if (_screenRefreshCollections.contains(collection)) {
        scheduleDataChanged.value++;
      }
    } catch (e) {
      debugPrint('$_tag: _writeLocal Fehler ($collection/$docId): $e');
    }
  }

  Future<void> _applyRemoteDeletion(String collection, String docId) async {
    // NEU: Eine eingehende Löschung kann eine noch offene Konflikt-Anfrage
    // für genau diesen Datensatz überflüssig machen (z.B. Lesemodus-Gerät
    // hat die eigene, noch unbestätigte Änderung selbst wieder gelöscht).
    // Ohne Aufräumen würde "Übernehmen" auf dem Original später einen
    // bereits gelöschten Datensatz wiederbeleben.
    if (_conflictProtected.contains(collection)) {
      final pendingAll = _loadPendingConflicts();
      final pendingCol = pendingAll[collection];
      if (pendingCol is Map && pendingCol.containsKey(docId)) {
        final updatedCol = Map<String, dynamic>.from(pendingCol)..remove(docId);
        pendingAll[collection] = updatedCol;
        _savePendingConflicts(pendingAll);
      }
    }

    // NEU: Löst auf dem Kopiergerät einen noch ausstehenden eigenen
    // Vorschlag auf, wenn das Original ihn per Löschung ablehnt (siehe
    // _rePushLocal) — sonst bliebe der Datensatz dauerhaft "ausstehend"
    // und unsichtbar hängen.
    if (SyncTokenService.role == 'reader' &&
        _conflictProtected.contains(collection) &&
        isPendingOwn(collection, docId)) {
      _clearPendingOwn(collection, docId);
    }

    switch (collection) {
      case 'schedule':
        final settingsBox = Hive.box('einstellungen');
        if (settingsBox.get('schedule_$docId') != null) {
          await settingsBox.delete('schedule_$docId');
          scheduleDataChanged.value++;
        }
        break;

      case 'fahrten':
        final settingsBox = Hive.box('einstellungen');
        if (settingsBox.get('fahrten_$docId') != null) {
          await settingsBox.delete('fahrten_$docId');
          scheduleDataChanged.value++;
        }
        break;

      case 'arbeitszeiten':
        final zeitBox = Hive.box('arbeitszeiten');
        if (zeitBox.get(docId) != null) {
          await zeitBox.delete(docId);
          scheduleDataChanged.value++;
        }
        break;

      case 'tasks':
        final all = TaskStore.loadAllRaw();
        final before = all.length;
        all.removeWhere((t) => t.id == docId);
        if (all.length != before) {
          TaskStore.saveAll(all);
          TaskStore.changesSignal.value++;
        }
        _clearOwner('tasks', docId);
        break;

      case 'calendar_events':
        final all = CalendarEventStore.loadAllRaw();
        final before = all.length;
        all.removeWhere((e) => e.id == docId);
        if (all.length != before) {
          await CalendarEventStore.saveAllExternal(all);
        }
        _clearOwner('calendar_events', docId);
        break;

      case 'event_groups':
        final allGroups = EventGroupStore.loadAll();
        if (allGroups.length <= 1) return;
        final beforeGroups = allGroups.length;
        allGroups.removeWhere((g) => g.key == docId);
        if (allGroups.length != beforeGroups) {
          EventGroupStore.applyRemote(allGroups);

          // NEU: Termine, die noch die gelöschte Gruppe referenzieren, auf
          // die erste verbleibende Gruppe umstellen — analog zu
          // EventGroupStore.delete() lokal, aber OHNE Re-Push, da diese
          // Löschung bereits vom anderen Gerät kommt (kein Zurücksenden
          // nötig, sonst unnötige Schreibschleife).
          final fallbackKey = allGroups.first.key;
          final events = CalendarEventStore.loadAllRaw();
          var eventsChanged = false;
          for (final e in events) {
            if (e.groupKeys.contains(docId)) {
              final remaining = e.groupKeys.where((k) => k != docId).toList();
              e.groupKeys = remaining.isEmpty ? [fallbackKey] : remaining;
              eventsChanged = true;
            }
          }
          if (eventsChanged) {
            await CalendarEventStore.saveAllExternal(events);
          }
        }
        _clearOwner('event_groups', docId);
        break;

      case 'vehicle_memory':
        final box = Hive.box('einstellungen');
        final all = Map<String, dynamic>.from(box.get('fahrtenbuch_km_memory', defaultValue: {}) as Map);
        if (all.remove(docId) != null) {
          box.put('fahrtenbuch_km_memory', all);
        }
        break;
    }
  }

  // ── Hive → Firestore pushen ───────────────────────────────────────────────

  final Map<String, DateTime> _lastLocalPushAt = {};
  // NEU: zusätzlich zum reinen Zeitfenster merken wir uns den exakten
  // clientUpdatedAt-Stempel unseres letzten eigenen Pushes je Datensatz.
  // Nur wenn eine eingehende Änderung GENAU diesen Stempel trägt, ist es
  // wirklich das Echo des eigenen Pushes — nicht bloß irgendeine Änderung
  // am selben Datensatz von einem ANDEREN Gerät, die zufällig kurz danach
  // eintrifft.
  final Map<String, int> _lastLocalPushClientTs = {};

  Future<void> _push(String collection, String docId, dynamic data, {bool isInitialLinkSync = false}) async {
    if (_token == null || data == null) return;
    final pushKey = '$collection/$docId';
    _lastLocalPushAt[pushKey] = DateTime.now();
    _markOwner(collection, docId, SyncTokenService.role);

    final localTs = DateTime.now().millisecondsSinceEpoch;
    _lastLocalPushClientTs[pushKey] = localTs;
    final metaBox = Hive.box('einstellungen');
    await metaBox.put('_syncver_$pushKey', localTs);
    await metaBox.flush();

    try {
      final authorName = Hive.box('einstellungen').get('name', defaultValue: '') as String;
      await _db
          .collection('syncData')
          .doc(_token)
          .collection(collection)
          .doc(docId)
          .set({
        'payload': _serialize(data),
        'updatedAt': FieldValue.serverTimestamp(),
        'clientUpdatedAt': localTs,
        'authorRole': SyncTokenService.role,
        'authorName': authorName,
        // NEU: Nur beim ERSTEN Verknüpfen eines Geräts gesetzt (mitgebrachte
        // Altdaten). Nur DAFÜR löst das Original einen Konflikt aus (siehe
        // _applyRemoteDoc). Laufende Änderungen tragen dieses Flag nicht und
        // werden von gleichberechtigten Geräten immer direkt übernommen.
        'initialLinkSync': isInitialLinkSync,
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
    _clearOwner(collection, docId);
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

  dynamic _serialize(dynamic data) {
    if (data == null) return null;
    if (data is String || data is num || data is bool) return data;
    if (data is List) {
      return data.map((e) => _serialize(e)).toList();
    }
    if (data is Map) {
      return data.map((k, v) => MapEntry(k.toString(), _serialize(v)));
    }
    try {
      return jsonEncode(data);
    } catch (_) {
      return data.toString();
    }
  }
}