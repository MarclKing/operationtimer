import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import '../models/calendar_event.dart';
import 'event_group_store.dart';
import '../services/travel_mode_service.dart';
import 'sync_service.dart'; // NEU

// Für vollständigen Import: Standardfarbe, falls ein Apple-Kalender keine
// eigene Farbe mitliefert.
// NEU: gedämpftes Off-White statt Blau — Apple-Importe sollen sich optisch
// klar von normalen (leuchtenden) Gruppenfarben absetzen, ohne zu schimmern.
const int _appleImportFallbackColor = 0xFFB8B8BC;

// ─────────────────────────────────────────────────────────────────────────
// APPLE CALENDAR SYNC — rein GERÄTELOKAL. Diese Zuordnungen (welche Gruppe
// gehört zu welchem Apple-Kalender, welches lokale Event zu welchem
// EKEvent) werden NIEMALS über SyncService/Firestore an ein zweites Gerät
// verteilt. Jedes Gerät hat seine eigene Apple-ID / sein eigenes EventKit.
// ─────────────────────────────────────────────────────────────────────────

class AppleCalendarSyncService {
  AppleCalendarSyncService._();
  static final AppleCalendarSyncService instance = AppleCalendarSyncService._();

  static const _tag = '🍎 AppleSync';

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  bool _tzInitialized = false;
  DateTime? _lastPullAllAt;
  final Map<String, DateTime> _lastPullByCalendar = {};

  // NEU: verhindert, dass pushEvent() für DASSELBE lokale Event zweimal
  // gleichzeitig läuft (z.B. weil derselbe Remote-Stand kurz hintereinander
  // zweimal ankam, siehe SyncService._applyRemoteDoc-Fix) — sonst können
  // zwei parallele Aufrufe je einen eigenen Apple-Termin anlegen, bevor
  // der erste sein Mapping gespeichert hat.
final Set<String> _pushInFlight = {};

  final Map<String, Future<void>> _calendarLocks = {};

  Future<T> _withCalendarLock<T>(
    String calendarId,
    Future<T> Function() action,
  ) async {
    final previous = _calendarLocks[calendarId] ?? Future.value();
    final completer = Completer<void>();
    _calendarLocks[calendarId] = previous.then((_) => completer.future);
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  // Guard gegen Endlosschleifen: während wir GERADE einen Pull von Apple
  // in den lokalen Store schreiben, darf das keinen Push zurück auslösen.
  bool _isApplyingRemote = false;
  bool get isApplyingRemote => _isApplyingRemote;

  // ── Hive-Keys (alle rein lokal, keine Sync-Weitergabe) ─────────────────
  static const _boxName = 'einstellungen';
  static const _calendarMapKey = 'apple_calendar_map';     // groupKey -> appleCalendarId
  static const _eventMapKey = 'apple_event_map';           // localId  -> appleEventId
  static const _lastSyncedKey = 'apple_event_last_synced'; // localId  -> ISO-Timestamp (letzter Abgleich)
  static const _readOnlyCalendarsKey = 'apple_readonly_calendars'; // Set von calendarId
  static const _pulledCalendarIdsKey = 'apple_pulled_calendar_ids'; // NEU: Liste ALLER global importierten Apple-Kalender-IDs
  static const _autoPushGroupsKey = 'apple_auto_push_groups'; // NEU: Set von groupKey, deren Apple-Kalender automatisch (nicht manuell) angelegt wurde

  /// NEU: feste Sammel-Gruppe für ALLES, was über den globalen Schalter
  /// aus Apple importiert wird — egal aus wie vielen Apple-Kalendern.
  /// Ersetzt die alte "ein App-Gruppe pro Apple-Kalender"-Logik.
  static const appleImportGroupKey = 'apple_import';

  Box get _box => Hive.box(_boxName);

  // ── read-only Kalender (Feiertage/Geburtstage) ───────────────────────────
  Set<String> _loadReadOnlyCalendarSet() {
    final raw = _box.get(_readOnlyCalendarsKey);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  void _addReadOnlyCalendar(String calendarId) {
    final s = _loadReadOnlyCalendarSet()..add(calendarId);
    _box.put(_readOnlyCalendarsKey, s.toList());
  }

  void _removeReadOnlyCalendar(String calendarId) {
    final s = _loadReadOnlyCalendarSet()..remove(calendarId);
    _box.put(_readOnlyCalendarsKey, s.toList());
  }

  // ── NEU: global gepullte Apple-Kalender (fließen alle in DIESELBE
  // Sammel-Gruppe "Apple") ──────────────────────────────────────────────────
  List<String> _loadPulledCalendarIds() {
    final raw = _box.get(_pulledCalendarIdsKey);
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return [];
  }

  void _addPulledCalendarId(String calendarId) {
    final ids = _loadPulledCalendarIds();
    if (!ids.contains(calendarId)) {
      ids.add(calendarId);
      _box.put(_pulledCalendarIdsKey, ids);
    }
  }

  void _ensureAppleImportGroupExists() {
    if (EventGroupStore.loadAll().any((g) => g.key == appleImportGroupKey)) return;
    EventGroupStore.add(EventGroupDef(
      key: appleImportGroupKey,
      name: 'Apple',
      colorValue: _appleImportFallbackColor,
      scope: GroupScope.local, // NIE über Firestore an andere Geräte weitergeben
    ));
  }

  // ── NEU: automatisch (nicht manuell im Gruppen-Editor) angelegte
  // Push-Kalender — pausieren mit dem globalen Schalter; manuell
  // verknüpfte Gruppen laufen davon unberührt immer weiter.
  Set<String> _loadAutoPushGroups() {
    final raw = _box.get(_autoPushGroupsKey);
    if (raw is List) return raw.map((e) => e.toString()).toSet();
    return {};
  }

  void _addAutoPushGroup(String groupKey) {
    final s = _loadAutoPushGroups()..add(groupKey);
    _box.put(_autoPushGroupsKey, s.toList());
  }

  bool _isAutoPushGroup(String groupKey) => _loadAutoPushGroups().contains(groupKey);

  /// NEU: Legt bei Bedarf automatisch einen passend benannten Apple-
  /// Kalender für eine App-Gruppe an (Push-Richtung) — genutzt, sobald der
  /// globale Schalter an ist und ein Event in einer noch nicht
  /// verknüpften Gruppe angelegt/geändert wird.
  Future<String?> _ensurePushCalendarFor(String groupKey) async {
    if (!await requestPermission()) return null;
    await _ensureTz();
    final group = EventGroupStore.byKey(groupKey);
    final createResult = await _plugin.createCalendar(
      'OpTimes – ${group.name}',
      calendarColor: group.color,
    );
    if (!createResult.isSuccess || createResult.data == null) return null;
    final calendarId = createResult.data!;
    _setAppleCalendarId(groupKey, calendarId);
    _addAutoPushGroup(groupKey);
    return calendarId;
  }

  /// NEU: Liefert die Apple-EventId für ein Event — entweder aus dem
  /// normalen Mapping (Push-Fall) oder, falls das Event ursprünglich aus
  /// Apple importiert wurde, aus dessen appleSourceKey abgeleitet (Pull-
  /// importierte Events aus der Sammel-Gruppe werden nie über
  /// _setEventMapping registriert).
  String? _appleEventIdOf(CalendarEvent e) {
    final mapped = _appleEventIdFor(e.id);
    if (mapped != null) return mapped;
    final key = e.appleSourceKey;
    if (key == null) return null;
    final idx = key.lastIndexOf('_');
    return idx > 0 ? key.substring(0, idx) : null;
  }

  Future<void> _ensureTz() async {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    // NEU (Bugfix): ohne setLocalLocation() bleibt tz.local auf UTC —
    // jeder tz.TZDateTime.from(e.start, tz.local)-Push in
    // _pushEventInternal hat dadurch besonders ganztägige Termine auf den
    // falschen Kalendertag geschrieben.
    try {
      tz.setLocalLocation(tz.getLocation(TravelModeService.activeTzId));
    } catch (e) {
      debugPrint('$_tag: Lokale Zeitzone konnte nicht gesetzt werden ($e) — Fallback UTC.');
    }
    _tzInitialized = true;
  }

  // ── Mapping-Helfer ──────────────────────────────────────────────────────

  Map<String, String> _loadMap(String key) {
    final raw = _box.get(key);
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, String>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return {};
  }

  void _saveMap(String key, Map<String, String> map) {
    _box.put(key, jsonEncode(map));
  }

  String? appleCalendarIdFor(String groupKey) => _loadMap(_calendarMapKey)[groupKey];

  void _setAppleCalendarId(String groupKey, String calendarId) {
    final map = _loadMap(_calendarMapKey);
    map[groupKey] = calendarId;
    _saveMap(_calendarMapKey, map);
  }

  void _removeAppleCalendarId(String groupKey) {
    final map = _loadMap(_calendarMapKey)..remove(groupKey);
    _saveMap(_calendarMapKey, map);
  }

  bool isGroupAppleLinked(String groupKey) => appleCalendarIdFor(groupKey) != null;

  String? _appleEventIdFor(String localId) => _loadMap(_eventMapKey)[localId];

  void _setEventMapping(String localId, String appleEventId) {
    final map = _loadMap(_eventMapKey);
    map[localId] = appleEventId;
    _saveMap(_eventMapKey, map);
    _touchSyncedTimestamp(localId);
  }

  void _removeEventMapping(String localId) {
    final map = _loadMap(_eventMapKey)..remove(localId);
    _saveMap(_eventMapKey, map);
    final ts = _loadMap(_lastSyncedKey)..remove(localId);
    _saveMap(_lastSyncedKey, ts);
  }

  void _touchSyncedTimestamp(String localId) {
    final ts = _loadMap(_lastSyncedKey);
    ts[localId] = DateTime.now().toIso8601String();
    _saveMap(_lastSyncedKey, ts);
  }

  // ── Berechtigungen ──────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    var result = await _plugin.hasPermissions();
    if (result.isSuccess && result.data == true) return true;
    result = await _plugin.requestPermissions();
    return result.isSuccess && result.data == true;
  }

  // ── Gruppe verknüpfen / trennen ─────────────────────────────────────────

  /// Legt automatisch einen neuen Apple-Kalender für diese Gruppe an
  /// (Frage 1: kein Auswahl-Dialog, einfach anlegen — vermeidet, dass
  /// bestehende fremde Apple-Termine reingemischt werden) und importiert
  /// anschließend + exportiert bestehende Events dieser Gruppe.
  ///
  /// Gibt true zurück bei Erfolg.
  Future<bool> linkGroup(EventGroupDef group) async {
    if (!await requestPermission()) return false;
    await _ensureTz();

    final createResult = await _plugin.createCalendar(
      'OpTimes – ${group.name}',
      calendarColor: group.color,
    );
    if (!createResult.isSuccess || createResult.data == null) return false;

    final calendarId = createResult.data!;
    _setAppleCalendarId(group.key, calendarId);

    await _fullResync(group.key, calendarId);
    return true;
  }

  /// Trennt die Verknüpfung. Löscht NICHT den Apple-Kalender selbst
  /// (der Nutzer soll seine Apple-Daten behalten können) — nur die
  /// Zuordnung + das ID-Mapping der betroffenen Events.
  Future<void> unlinkGroup(String groupKey) async {
    _removeAppleCalendarId(groupKey);
    final eventMap = _loadMap(_eventMapKey);
    final toRemove = <String>[];
    for (final e in CalendarEventStore.loadAllRaw()) {
      if (e.groupKeys.contains(groupKey) && eventMap.containsKey(e.id)) {
        toRemove.add(e.id);
      }
    }
    for (final id in toRemove) {
      _removeEventMapping(id);
    }
  }

  // ── GLOBALER SCHALTER — "Mit Apple-Kalender teilen" in den Einstellungen ──
  //
  // Anders als linkGroup() (einzelne, selbst angelegte App-Gruppe → NEUER
  // Apple-Kalender) importiert dies ALLE bestehenden Apple-Kalender als
  // eigene App-Gruppen und verknüpft sie sofort. Kalender, die schon
  // verknüpft sind (z.B. weil der Nutzer sie vorher einzeln über
  // linkGroup() angelegt hat, oder von einem früheren Lauf dieses
  // Schalters), werden übersprungen statt doppelt importiert.

  static const _globalEnabledKey = 'apple_sync_globally_enabled';

  bool get isGloballyEnabled =>
      _box.get(_globalEnabledKey, defaultValue: false) as bool;

  /// NEU: importiert ALLE fremden Apple-Kalender in EINE Sammel-Gruppe
  /// "Apple" (statt eine App-Gruppe pro Apple-Kalender anzulegen).
  /// Von der App selbst angelegte Push-Kalender ("OpTimes – ...") werden
  /// dabei übersprungen — sonst würde sich das eigene Zurückschreiben mit
  /// dem Import selbst überschneiden.
  /// NEU: Kernlogik ausgelagert, damit sie sowohl beim erstmaligen
  /// Einschalten (enableGlobalSync) als auch als SELBSTHEILUNG in
  /// pullAllLinkedGroups() genutzt werden kann — relevant für Nutzer,
  /// bei denen der Schalter schon vor diesem Update an war: für die
  /// wurde _pulledCalendarIdsKey (neuer Key) nie befüllt, weil
  /// enableGlobalSync() ja nur beim Umschalten läuft, nicht bei jedem
  /// Start. Ohne diese Selbstheilung bliebe der Import für Bestandsnutzer
  /// dauerhaft leer, bis sie den Schalter manuell aus- und wieder
  /// einschalten.
  Future<bool> _discoverAndPullForeignCalendars() async {
    final hasPermission = await requestPermission();
    if (!hasPermission) return false;
    await _ensureTz();

    final calResult = await _plugin.retrieveCalendars();
    debugPrint('$_tag: retrieveCalendars isSuccess=${calResult.isSuccess}, '
        'Anzahl=${calResult.data?.length}, Fehler=${calResult.errors}');
    if (!calResult.isSuccess || calResult.data == null) return false;

    for (final cal in calResult.data!) {
      debugPrint('$_tag:   Kalender gefunden: id=${cal.id}, name=${cal.name}, '
          'readOnly=${cal.isReadOnly}');
    }

    _ensureAppleImportGroupExists();
    final alreadyPulled = _loadPulledCalendarIds().toSet();

    for (final cal in calResult.data!) {
      final calId = cal.id;
      if (calId == null) continue;
      if (alreadyPulled.contains(calId)) {
        debugPrint('$_tag: ${cal.name} übersprungen (schon in pulledIds)');
        continue;
      }
      if ((cal.name ?? '').startsWith('OpTimes – ')) {
        debugPrint('$_tag: ${cal.name} übersprungen (eigener Push-Kalender)');
        continue;
      }

      if (cal.isReadOnly == true) _addReadOnlyCalendar(calId);
      _addPulledCalendarId(calId);

      await pullCalendar(appleImportGroupKey, calId);
    }
    return true;
  }

  Future<bool> enableGlobalSync() async {
    final ok = await _discoverAndPullForeignCalendars();
    if (!ok) return false;
    _box.put(_globalEnabledKey, true);
    return true;
  }

  /// Deaktivieren PAUSIERT nur — alle Mappings bleiben bestehen, damit
  /// erneutes Aktivieren nicht dupliziert.
  Future<void> disableGlobalSync() async {
    _box.put(_globalEnabledKey, false);
  }

  /// Echtes Löschen aller in die Sammel-Gruppe "Apple" importierten
  /// Termine + Mappings. Push-Kalender (App → Apple) bleiben unangetastet
  /// — das sind eigene, keine "Importe".
  Future<void> deleteAllGlobalImports() async {
    for (final e in CalendarEventStore.loadAllRaw()) {
      if (e.appleSourceKey != null && e.groupKeys.contains(appleImportGroupKey)) {
        // WICHTIG: deleteExternal() statt delete() — entfernt das Event
        // NUR aus dem lokalen OpTimes-Store, ohne AppleCalendarSyncService
        // zu benachrichtigen. So bleibt der echte Apple-Termin unangetastet,
        // egal in welchem Kalender er liegt.
        CalendarEventStore.deleteExternal(e.id);
      }
    }
    for (final calId in _loadPulledCalendarIds()) {
      _removeReadOnlyCalendar(calId);
    }
    _box.put(_pulledCalendarIdsKey, <String>[]);
    _box.put(_globalEnabledKey, false);
  }

/// NEU: Sicherer Reset-Baustein für "gefährliche" Zustandswechsel
  /// (Token-Verknüpfung, Lesemodus-Aktivierung) — trennt ALLE Apple-
  /// Verknüpfungen (global + einzeln pro Gruppe) und löscht die lokal
  /// importierten Termine der Sammel-Gruppe. Die echten Apple-Kalender
  /// und deren Termine bleiben dabei UNANGETASTET — nur die OpTimes-
  /// seitige Zuordnung/Kopie wird entfernt. Verhindert den Bug, bei dem
  /// _pulledCalendarIdsKey über einen lokalen Reset hinweg bestehen
  /// blieb und der Import danach dauerhaft leer blieb.
  Future<void> disconnectAllForSafeReset() async {
    await deleteAllGlobalImports();
    for (final groupKey in _loadMap(_calendarMapKey).keys.toList()) {
      await unlinkGroup(groupKey);
    }
  }

  /// NEU: Für UI-Entscheidungen, ob ein Warn-Dialog vor einem Reset
  /// nötig ist (nichts zu tun, wenn ohnehin nichts verknüpft ist).
  bool get hasAnyAppleLink =>
      isGloballyEnabled || _loadMap(_calendarMapKey).isNotEmpty;

  /// NEU: Für den Admin-"Alles löschen"-Button — trennt WIRKLICH alle
  /// Apple-Verknüpfungen (global importierte UND individuell verknüpfte)
  /// und löscht die von der App selbst angelegten Apple-Kalender
  /// ("OpTimes – ..."). Fremde Apple-Kalender (aus dem globalen Import)
  /// werden NICHT gelöscht — nur die App-seitige Zuordnung verschwindet.
  Future<void> wipeEverything() async {
    final calendarMap = _loadMap(_calendarMapKey);
    List<Calendar>? deviceCalendars;
    try {
      final calResult = await _plugin.retrieveCalendars();
      if (calResult.isSuccess) deviceCalendars = calResult.data;
    } catch (_) {}

    for (final calendarId in calendarMap.values.toSet()) {
      Calendar? match;
      if (deviceCalendars != null) {
        for (final c in deviceCalendars) {
          if (c.id == calendarId) { match = c; break; }
        }
      }
      if (match != null && (match.name ?? '').startsWith('OpTimes – ')) {
        try {
          await _plugin.deleteCalendar(calendarId);
        } catch (_) {}
      }
    }

    _saveMap(_calendarMapKey, {});
    _saveMap(_eventMapKey, {});
    _saveMap(_lastSyncedKey, {});
    _box.put(_readOnlyCalendarsKey, <String>[]);
    _box.put(_pulledCalendarIdsKey, <String>[]);
    _box.put(_autoPushGroupsKey, <String>[]);
    _box.put(_globalEnabledKey, false);
  }

  // ── Voller Abgleich (beim Verknüpfen einer EINZELNEN Gruppe) ────────────

  Future<void> _fullResync(String groupKey, String calendarId) async {
    // 1) Export: alle lokalen Events dieser Gruppe (primäre Gruppe!) nach
    //    Apple schreiben, die noch keine Zuordnung haben.
    final localEvents = CalendarEventStore.loadAllRaw()
        .where((e) => e.primaryGroupKey == groupKey);
    for (final e in localEvents) {
      await pushEvent(e);
    }

    // 2) Import: bestehende Apple-Events aus diesem (frisch angelegten,
    //    also i.d.R. leeren) Kalender übernehmen — relevant, falls der
    //    Kalender schon vorher existierte oder zwischenzeitlich befüllt
    //    wurde.
    await pullCalendar(groupKey, calendarId);
  }

  // ── PUSH: App → Apple ────────────────────────────────────────────────────

  /// Wird von CalendarEventStore.add/update aufgerufen. No-op, wenn die
  /// primäre Gruppe des Events nicht Apple-verknüpft ist, oder wenn wir
  /// gerade selbst einen Pull anwenden (Loop-Schutz).
  /// Wird von CalendarEventStore.add/update aufgerufen. Push läuft jetzt
  /// automatisch für JEDE Gruppe, sobald der globale Schalter an ist —
  /// dafür wird bei Bedarf ein passend benannter Apple-Kalender live
  /// angelegt (_ensurePushCalendarFor). Manuell im Gruppen-Editor
  /// verknüpfte Gruppen pushen unabhängig vom globalen Schalter immer.
  Future<void> pushEvent(CalendarEvent e) async {
    if (_isApplyingRemote) return;
    if (_pushInFlight.contains(e.id)) return; // NEU: bereits ein Push für dieses Event unterwegs
    _pushInFlight.add(e.id);
    try {
      await _pushEventInternal(e);
    } finally {
      _pushInFlight.remove(e.id);
    }
  }

  Future<void> _pushEventInternal(CalendarEvent e) async {
    // WICHTIG: Termine aus der globalen Sammel-Gruppe sind reiner Import
    // (nur Pull, nie Push zurück nach Apple) — dieser Check muss VOR der
    // appleCalendarId-Ermittlung stehen, denn importierte Events haben
    // appleCalendarId immer gesetzt, wodurch die alte Prüfung weiter
    // unten (calendarId == null) nie greift.
    if (e.groupKeys.contains(appleImportGroupKey)) return;

    final previousCalendarId = e.appleCalendarId;
    String? calendarId = previousCalendarId;
    final groupKey = e.primaryGroupKey;

    // NEU (Punkt 1 Härtung): Wurde die primäre Gruppe des Events auf eine
    // ANDERE, ebenfalls Apple-verknüpfte Gruppe geändert, soll der Termin
    // dem neuen Gruppen-Kalender folgen statt weiter am alten Kalender zu
    // kleben — sonst entstünde im neuen Kalender ein zusätzlicher Termin,
    // während die alte Kopie im ursprünglichen Apple-Kalender als
    // Karteileiche liegen bleibt.
    if (groupKey != null && groupKey != appleImportGroupKey) {
      final groupCalendarId = appleCalendarIdFor(groupKey);
      if (groupCalendarId != null && groupCalendarId != previousCalendarId) {
        calendarId = groupCalendarId;
      }
    }

    if (calendarId == null) {
      if (groupKey == null || groupKey == appleImportGroupKey) return;

      calendarId = appleCalendarIdFor(groupKey);
      if (calendarId == null) {
        if (!isGloballyEnabled) return; // kein Auto-Push ohne aktivierten Schalter
        calendarId = await _ensurePushCalendarFor(groupKey);
        if (calendarId == null) return;
      } else if (_isAutoPushGroup(groupKey) && !isGloballyEnabled) {
        return; // automatisch angelegte Verknüpfung pausiert
      }
    }

    if (_loadReadOnlyCalendarSet().contains(calendarId)) return;

    await _withCalendarLock(calendarId, () async {
      await _ensureTz();
      final loc = tz.local;

      final calendarChanged = previousCalendarId != null && previousCalendarId != calendarId;
      if (calendarChanged) {
        final oldAppleId = _appleEventIdFor(e.id);
        if (oldAppleId != null && !_loadReadOnlyCalendarSet().contains(previousCalendarId)) {
          try {
            await _plugin.deleteEvent(previousCalendarId, oldAppleId);
          } catch (_) {}
        }
        _removeEventMapping(e.id);
      }

      final existingAppleId = calendarChanged ? null : _appleEventIdOf(e);

      final appleAllDayEnd = e.end.isAfter(e.start)
          ? DateTime(e.end.year, e.end.month, e.end.day).subtract(const Duration(days: 1))
          : DateTime(e.start.year, e.start.month, e.start.day);

      final tzStart = e.allDay
          ? tz.TZDateTime.utc(e.start.year, e.start.month, e.start.day)
          : tz.TZDateTime.from(e.start, loc);
      final tzEnd = e.allDay
          ? tz.TZDateTime.utc(appleAllDayEnd.year, appleAllDayEnd.month, appleAllDayEnd.day)
          : tz.TZDateTime.from(e.end, loc);

      final event = Event(
        calendarId,
        eventId: existingAppleId,
        title: e.title,
        description: e.notes.isEmpty ? null : e.notes,
        location: e.location.isEmpty ? null : e.location,
        start: tzStart,
        end: tzEnd,
        allDay: e.allDay,
      );

      final result = await _plugin.createOrUpdateEvent(event);
      if (result == null || !result.isSuccess || result.data == null) {
        debugPrint('$_tag: createOrUpdateEvent FEHLGESCHLAGEN für "${e.title}" '
            '(calendarId=$calendarId): ${result?.errors}');
        return;
      }

      final appleEventId = result.data!;
      _setEventMapping(e.id, appleEventId);

      final safeAppleId = appleEventId.replaceAll(RegExp(r'[/#\[\]]'), '-');
      final normalizedStart = e.allDay
          ? DateTime(e.start.year, e.start.month, e.start.day)
          : e.start;
      final sourceKey = '${safeAppleId}_${normalizedStart.millisecondsSinceEpoch}';

      if (e.appleCalendarId != calendarId || e.appleSourceKey != sourceKey) {
        e.appleCalendarId = calendarId;
        e.appleSourceKey = sourceKey;
        CalendarEventStore.updateExternal(e);
      }
    });
  }

  /// Wird von CalendarEventStore.delete aufgerufen, BEVOR das lokale Event
  /// tatsächlich weg ist (wir brauchen noch die groupKeys für die
  /// Kalender-Zuordnung).
  Future<void> deleteEvent(CalendarEvent e) async {
    if (_isApplyingRemote) return;

    // WICHTIG: Einzelnes Löschen eines Events (egal ob eigen angelegt
    // oder aus Apple importiert) soll den echten Apple-Termin ebenfalls
    // löschen — nur der GLOBALE "Alles löschen"-Button (siehe
    // deleteAllGlobalImports) soll rein lokal bleiben und nutzt dafür
    // deleteExternal() statt delete(), sodass diese Methode hier gar
    // nicht erst aufgerufen wird.
    String? calendarId = e.appleCalendarId;
    if (calendarId == null) {
      final groupKey = e.primaryGroupKey;
      if (groupKey == null || groupKey == appleImportGroupKey) return;
      calendarId = appleCalendarIdFor(groupKey);
      if (calendarId == null) return;
      if (_isAutoPushGroup(groupKey) && !isGloballyEnabled) return;
    }
    if (_loadReadOnlyCalendarSet().contains(calendarId)) return;

    final appleId = _appleEventIdOf(e);
    if (appleId == null) return;

    await _plugin.deleteEvent(calendarId, appleId);
    _removeEventMapping(e.id);
  }

  // ── PULL: Apple → App ────────────────────────────────────────────────────
// NEU — einmalige Bereinigung, z.B. in AppleCalendarSyncService, vor dem ersten pullAllLinkedGroups()-Aufruf
static void purgeInvalidLocalIds() {
  final all = CalendarEventStore.loadAllRaw();
  final bad = all.where((e) => e.id.contains('/')).toList();
  for (final e in bad) {
    CalendarEventStore.deleteExternal(e.id);
  }
}
  /// Beim App-Start / Foreground für alle verknüpften Gruppen aufrufen.
  Future<void> pullAllLinkedGroups({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastPullAllAt != null && now.difference(_lastPullAllAt!) < const Duration(minutes: 5)) {
      debugPrint('$_tag: pullAllLinkedGroups übersprungen (Cooldown).');
      return;
    }
    _lastPullAllAt = now;

    // Sammel-Gruppe "Apple" — pausiert komplett mit dem globalen Schalter.
    if (isGloballyEnabled) {
      // NEU: Discovery läuft jetzt bei JEDEM Aufruf, nicht mehr nur einmalig
      // beim ersten Mal — so werden neu hinzugekommene Apple-Kalender
      // automatisch erkannt, und ein unvollständiger erster Lauf (z.B. durch
      // ein Timing-Problem direkt nach Berechtigungserteilung) repariert
      // sich von selbst beim nächsten App-Start. _discoverAndPullForeignCalendars()
      // überspringt intern bereits bekannte IDs, pullt also nicht doppelt —
      // zusätzlich wird für alle bereits bekannten Kalender hier trotzdem
      // aktualisiert (pullCalendar), damit auch bestehende Kalender ihre
      // neuesten Termine bekommen.
      await _discoverAndPullForeignCalendars();
      for (final calId in _loadPulledCalendarIds()) {
        await pullCalendar(appleImportGroupKey, calId);
      }
    }
    // Push-verknüpfte Gruppen (manuell ODER automatisch) — bleiben
    // bidirektional synchron. Automatisch angelegte pausieren mit dem
    // globalen Schalter, manuell verknüpfte laufen immer weiter.
    final map = _loadMap(_calendarMapKey);
    for (final entry in map.entries) {
      if (_isAutoPushGroup(entry.key) && !isGloballyEnabled) continue;
      await pullCalendar(entry.key, entry.value);
    }
  }

  Future<void> pullCalendar(String groupKey, String calendarId, {bool force = false}) async {
    final key = '$groupKey/$calendarId';
    final now = DateTime.now();
    if (!force && _lastPullByCalendar[key] != null && now.difference(_lastPullByCalendar[key]!) < const Duration(minutes: 5)) {
      return;
    }
    _lastPullByCalendar[key] = now;
    await _withCalendarLock(calendarId, () => _pullCalendarInternal(groupKey, calendarId));
  }

  Future<void> _pullCalendarInternal(String groupKey, String calendarId) async {
    await _ensureTz();
    final now = DateTime.now();
    final rangeStart = now.subtract(const Duration(days: 365));
    final rangeEnd = now.add(const Duration(days: 730));
    final result = await _plugin.retrieveEvents(
      calendarId,
      RetrieveEventsParams(startDate: rangeStart, endDate: rangeEnd),
    );
    debugPrint('$_tag: retrieveEvents($calendarId) isSuccess=${result.isSuccess}, '
        'Anzahl=${result.data?.length}, Fehler=${result.errors}');
    if (!result.isSuccess || result.data == null) return;

    final isReadOnlyCal = _loadReadOnlyCalendarSet().contains(calendarId);

    // NEU (Punkt 3+4+5+6): device_calendar liefert bei wiederkehrenden
    // Apple-Terminen MEHRERE Vorkommen mit DERSELBEN appleId — vorher
    // wurde jedes weitere Vorkommen fälschlich als "Änderung" desselben
    // lokalen Termins gewertet und hat ihn immer wieder überschrieben
    // (→ Ghost-Einträge, fehlende Termine, Duplikate). Jetzt bekommt
    // JEDES Vorkommen einen eigenen, stabilen Schlüssel aus appleId +
    // Vorkommen-Start und wird als eigenständiges lokales Ereignis
    // geführt — auf Wunsch bewusst ohne eigenes RepeatRule-Mapping,
    // einfach als einzelne Termine im 2-Jahres-Fenster.
    final existingBySourceKey = <String, CalendarEvent>{};
    for (final e in CalendarEventStore.loadAllRaw()) {
      if (e.appleSourceKey != null) existingBySourceKey[e.appleSourceKey!] = e;
    }
    final seenSourceKeys = <String>{};

    _isApplyingRemote = true;
    try {
      for (final ev in result.data!) {
        final appleId = ev.eventId;
        if (appleId == null) continue;
        final isAllDay = ev.allDay ?? false;

        // NEU: Bei ganztägigen Terminen NIE .toLocal() anwenden — EventKit
        // liefert hier reine Kalenderdaten ohne echte Uhrzeit. Eine
        // Zeitzonen-Konvertierung kann das Datum um einen Tag verschieben
        // (z.B. Feiertag am 13. erscheint als Punkt am 12.). Datum daher
        // unverändert aus Jahr/Monat/Tag übernehmen.
        // WICHTIG: ev.start/ev.end sind TZDateTime (aus dem timezone-Paket),
        // nicht simples DateTime. Deren .year/.month/.toLocal() hängen von
        // der intern mitgeführten Location ab, die je nach Plugin-Version
        // nicht zuverlässig UTC oder lokal ist — das führte zum Tages-
        // Versatz bei ganztägigen und zur 2h-Verschiebung bei Zeit-
        // Terminen. Fix: über millisecondsSinceEpoch gehen (eindeutiger,
        // location-unabhängiger UTC-Zeitstempel) und daraus explizit neu
        // aufbauen.
        DateTime? occStart;
        DateTime? occEnd;
        if (ev.start != null) {
          final startMs = ev.start!.millisecondsSinceEpoch;
          if (isAllDay) {
            // NEU (Punkt 2 Fix): device_calendar liefert ganztägige Termine
            // als Mitternacht in der GERÄTE-lokalen Zeitzone, nicht als
            // UTC-Mitternacht. Die bisherige UTC-Normalisierung hat den
            // Kalendertag bei positivem UTC-Offset (z.B. Deutschland)
            // fälschlich einen Tag zu früh berechnet.
            final local = DateTime.fromMillisecondsSinceEpoch(startMs);
            occStart = DateTime(local.year, local.month, local.day);
          } else {
            occStart = DateTime.fromMillisecondsSinceEpoch(startMs);
          }
        }
        if (ev.end != null) {
          final endMs = ev.end!.millisecondsSinceEpoch;
          if (isAllDay) {
            final local = DateTime.fromMillisecondsSinceEpoch(endMs);
            occEnd = DateTime(local.year, local.month, local.day).add(const Duration(days: 1));
          } else {
            occEnd = DateTime.fromMillisecondsSinceEpoch(endMs);
          }
        }
        if (occStart == null) continue;

         // NEU: iOS-Kontakt-Geburtstage liefern EventKit-IDs, die selbst
        // ein "/" enthalten (z.B. "..._NativeStorePersistentID_...:gregorian/
        // <uuid>:ABPerson_..."). Ein "/" in der lokalen Event-ID wird später
        // 1:1 als Firestore-Dokumentpfad verwendet — Firestore wirft dann
        // eine NSException ("must have an even number of segments"), die
        // auf iOS NICHT als Dart-Fehler abgefangen wird, sondern die App
        // nativ crasht. Daher hier alle Pfad-kritischen Zeichen ersetzen.
        final safeAppleId = appleId.replaceAll(RegExp(r'[/#\[\]]'), '-');
        final sourceKey = '${safeAppleId}_${occStart.millisecondsSinceEpoch}';
        seenSourceKeys.add(sourceKey);

        final existing = existingBySourceKey[sourceKey];
        if (existing == null) {
          final newEvent = CalendarEvent(
            id: 'apple_${sourceKey}_${DateTime.now().microsecondsSinceEpoch}',
            title: ev.title ?? '(Ohne Titel)',
            location: ev.location ?? '',
            start: occStart,
            end: occEnd ?? occStart.add(const Duration(hours: 1)),
            allDay: isAllDay,
            groupKeys: [groupKey],
            notes: ev.description ?? '',
            createdAt: DateTime.now(),
            appleSourceKey: sourceKey,
            appleReadOnly: isReadOnlyCal,
            appleCalendarId: calendarId,
          );
          CalendarEventStore.addExternal(newEvent);
          // NEU: Direkt in Apple Kalender neu angelegte Termine müssen auch
          // bei anderen synchronisierten Geräten ankommen — addExternal()
          // selbst löst bewusst KEINEN Push aus (Loop-Schutz Richtung
          // Apple), das darf aber nicht auch den Firestore-Sync blockieren.
          SyncService.instance.pushCalendarEvent(newEvent.id);
        } else {
          final changed = existing.title != (ev.title ?? existing.title) ||
              existing.location != (ev.location ?? existing.location) ||
              existing.end != (occEnd ?? existing.end) ||
              existing.notes != (ev.description ?? existing.notes);
          if (changed) {
            existing.title = ev.title ?? existing.title;
            existing.location = ev.location ?? existing.location;
            existing.end = occEnd ?? existing.end;
            existing.allDay = isAllDay;
            existing.notes = ev.description ?? existing.notes;
            CalendarEventStore.updateExternal(existing);
            SyncService.instance.pushCalendarEvent(existing.id); // NEU
          }
        }
      }

      // Auf Apple-Seite gelöschte/verschobene Vorkommen lokal entfernen —
      // NUR für Vorkommen, deren Start im aktuell abgefragten Fenster
      // liegt. Sonst würden ältere, außerhalb des rollierenden 365-Tage-
      // Fensters liegende (aber weiterhin gültige) Vorkommen fälschlich
      // als "auf Apple-Seite gelöscht" gewertet und entfernt.
      // NEU
      for (final entry in existingBySourceKey.entries) {
        final e = entry.value;
        if (e.appleCalendarId != calendarId) continue;
        if (!e.groupKeys.contains(groupKey)) continue;
        if (e.start.isBefore(rangeStart) || e.start.isAfter(rangeEnd)) continue;
        if (!seenSourceKeys.contains(entry.key)) {
          CalendarEventStore.deleteExternal(e.id);
          SyncService.instance.pushCalendarEvent(e.id); // NEU — propagiert die Löschung nach Firestore
        }
      }

      // NEU (Punkt 1 Fix): In der App angelegte und nach Apple GEPUSHTE
      // Termine tragen kein appleSourceKey (das wird nur beim PULL gesetzt)
      // — sie waren in existingBySourceKey unsichtbar, eine Löschung auf
      // Apple-Seite wurde daher nie erkannt. Sie sind aber über das
      // Event-Mapping (lokale ID -> Apple-EventId) verknüpft; darüber jetzt
      // zusätzlich auf Löschung prüfen.
      final seenAppleEventIds = <String>{
        for (final ev in result.data!)
          if (ev.eventId != null) ev.eventId!,
      };
      for (final e in CalendarEventStore.loadAllRaw()) {
        if (e.appleSourceKey != null) continue;
        if (e.primaryGroupKey != groupKey) continue;
        final mappedAppleId = _appleEventIdFor(e.id);
        if (mappedAppleId == null) continue;
        if (!seenAppleEventIds.contains(mappedAppleId)) {
          CalendarEventStore.deleteExternal(e.id);
          _removeEventMapping(e.id);
          SyncService.instance.pushCalendarEvent(e.id); // NEU
        }
      }

      debugPrint('$_tag: pullCalendar($groupKey, $calendarId) fertig — '
          '${seenSourceKeys.length} Vorkommen verarbeitet, '
          '${CalendarEventStore.loadAllRaw().where((e) => e.groupKeys.contains(groupKey)).length} '
          'Events jetzt insgesamt in Gruppe "$groupKey".');
      CalendarEventStore.pushUpcomingEventsToWidget(); // NEU
    } finally {
      _isApplyingRemote = false;
    }
  }
}