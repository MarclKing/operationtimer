import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/calendar_event.dart';
import 'sync_service.dart';

enum GroupScope { local, sync }

extension GroupScopeX on GroupScope {
  String get key => this == GroupScope.sync ? 'sync' : 'local';
  String get label => this == GroupScope.sync ? 'Sync' : 'Lokal';

  static GroupScope fromKey(String? k) => k == 'sync' ? GroupScope.sync : GroupScope.local;
}

class EventGroupDef {
  final String key;
  String name;
  int colorValue;
  GroupScope scope;

  EventGroupDef({
    required this.key,
    required this.name,
    required this.colorValue,
    this.scope = GroupScope.local,
  });

  Color get color => Color(colorValue);
  bool get isSync => scope == GroupScope.sync;

  Map<String, dynamic> toJson() =>
      {'key': key, 'name': name, 'colorValue': colorValue, 'scope': scope.key};

  factory EventGroupDef.fromJson(Map<String, dynamic> j) {
    final key = j['key'] as String;
    final rawScope = j['scope'] as String?;
    // Migration: Alt-Daten ohne scope-Feld — 'privat' war implizit die
    // Teilen-Gruppe, alles andere blieb lokal.
    final scope = rawScope != null
        ? GroupScopeX.fromKey(rawScope)
        : (key == 'privat' ? GroupScope.sync : GroupScope.local);
    return EventGroupDef(
      key: key,
      name: j['name'] as String,
      colorValue: j['colorValue'] as int,
      scope: scope,
    );
  }
}

class EventGroupStore {
  static const _key = 'event_groups';
  static final ValueNotifier<int> changesSignal = ValueNotifier(0);

  static const appleImportGroupKey = 'apple_import';

  static List<EventGroupDef> _seedDefaults() => [
        EventGroupDef(key: 'privat', name: 'Privat', colorValue: 0xFF34C759, scope: GroupScope.sync),
        EventGroupDef(key: 'dienstlich', name: 'Dienstlich', colorValue: 0xFF2D6CFF, scope: GroupScope.local),
        EventGroupDef(key: 'sonstiges', name: 'Sonstiges', colorValue: 0xFF2FD3C7, scope: GroupScope.local),
      ];

  static List<EventGroupDef> loadAll() {
    final box = Hive.box('einstellungen');
    final raw = box.get(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        final list = decoded
            .map((e) => EventGroupDef.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        if (list.isNotEmpty) return list;
      } catch (_) {}
    }
    final seeded = _seedDefaults();
    _saveAll(seeded, notify: false);
    return seeded;
  }

  static List<EventGroupDef> loadSelectable() =>
      loadAll().where((g) => g.key != appleImportGroupKey).toList();

  static void _saveAll(List<EventGroupDef> groups, {bool notify = true}) {
    final box = Hive.box('einstellungen');
    box.put(_key, jsonEncode(groups.map((g) => g.toJson()).toList()));
    if (notify) changesSignal.value++;
  }

  static void add(EventGroupDef g) {
    final all = loadAll()..add(g);
    _saveAll(all);
    SyncService.instance.pushEventGroup(g.key);
  }

  static void update(EventGroupDef g) {
    final all = loadAll();
    final idx = all.indexWhere((x) => x.key == g.key);
    if (idx != -1) {
      final oldScope = all[idx].scope;
      all[idx] = g;
      _saveAll(all);
      SyncService.instance.pushEventGroup(g.key);

      // NEU: Ein Scope-Wechsel (Lokal↔Sync) betrifft auch bereits
      // bestehende Termine dieser Gruppe. Ohne Re-Push blieben bei
      // Sync→Lokal geteilte Termine für immer in Firestore hängen, und
      // bei Lokal→Sync würden bestehende Termine nie initial geteilt —
      // nur neu angelegte/bearbeitete Termine hätten es zufällig
      // mitbekommen.
      if (oldScope != g.scope) {
        for (final e in CalendarEventStore.loadAllRaw()) {
          if (e.groupKeys.contains(g.key)) {
            SyncService.instance.pushCalendarEvent(e.id);
          }
        }
      }
    }
  }

  /// Löscht eine Gruppe. Es muss immer mindestens eine übrig bleiben.
  /// Termine, die diese Gruppe (evtl. neben einer zweiten) hatten, werden
  /// auf die erste verbleibende Gruppe umgestellt — ist die zweite Gruppe
  /// des Termins noch gültig, bleibt sie bestehen.
  static Future<void> delete(String key) async {
    if (key == appleImportGroupKey) return;
    final all = loadAll();
    if (all.length <= 1) return;
    all.removeWhere((g) => g.key == key);
    _saveAll(all);
    SyncService.instance.pushEventGroup(key); // erkennt "fehlt lokal" -> löscht remote

    final fallbackKey = all.first.key;
    final events = CalendarEventStore.loadAllRaw();
    var changed = false;
    for (final e in events) {
      if (e.groupKeys.contains(key)) {
        final remaining = e.groupKeys.where((k) => k != key).toList();
        e.groupKeys = remaining.isEmpty ? [fallbackKey] : remaining;
        changed = true;
      }
    }
    if (changed) {
      await CalendarEventStore.saveAllExternal(events);
      for (final e in events) {
        SyncService.instance.pushCalendarEvent(e.id);
      }
    }
  }

  static EventGroupDef byKey(String? key) {
    final all = loadAll();
    return all.firstWhere((g) => g.key == key, orElse: () => all.first);
  }

  /// Direkt für Remote-Sync-Anwendung genutzt (überschreibt komplett).
  static void applyRemote(List<EventGroupDef> groups) {
    if (groups.isEmpty) return;
    _saveAll(groups, notify: false);
    changesSignal.value++;
  }

  /// Setzt die Gruppen dieses Geräts lokal auf die Standard-Gruppen zurück,
  /// OHNE das an andere Geräte zu pushen — genutzt beim Aktivieren des
  /// Lesemodus (dieses Gerät wird bewusst vom Sync isoliert).
  static void resetToDefaultsLocal() {
    final seeded = _seedDefaults();
    Hive.box('einstellungen').put(_key, jsonEncode(seeded.map((g) => g.toJson()).toList()));
    changesSignal.value++;
  }

  static String newKey() => 'grp_${DateTime.now().millisecondsSinceEpoch}';

  // ── Standard-Gruppe für neue Ereignisse ─────────────────────────────────
  static const _defaultGroupKey = 'default_event_group_key';

  static String? getDefaultGroupKey() =>
      Hive.box('einstellungen').get(_defaultGroupKey) as String?;

  static void setDefaultGroupKey(String key) {
    Hive.box('einstellungen').put(_defaultGroupKey, key);
  }

  /// Gruppe, die bei neuen Ereignissen vorausgewählt sein soll. Fällt auf
  /// die erste vorhandene Gruppe zurück, falls keine gültige Standard-
  /// Gruppe gesetzt ist (z.B. nie gewählt oder zwischenzeitlich gelöscht).
  static EventGroupDef defaultGroup() {
    final all = loadAll();
    final key = getDefaultGroupKey();
    if (key != null) {
      final match = all.where((g) => g.key == key);
      if (match.isNotEmpty) return match.first;
    }
    return all.first;
  }
}