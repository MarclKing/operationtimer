import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // NEU — für MethodChannel
import 'package:flutter/foundation.dart' show kIsWeb; // NEU
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/sync_service.dart';
import '../services/apple_calendar_sync_service.dart';
import '../services/event_group_store.dart'; // NEU — für Gruppenfarbe
import '../services/notification_service.dart'; // NEU — für Benachrichtigungen
import '../services/reminder_manager.dart'; // NEU — für Erinnerungsoptionen

// ─────────────────────────────────────────────────────────────────────────
// GRUPPE / FARBE
// ─────────────────────────────────────────────────────────────────────────

// EventGroup ist kein festes enum mehr — siehe EventGroupStore
// (services/event_group_store.dart). CalendarEvent trägt nur noch
// den groupKey (String); Name/Farbe kommen dynamisch aus dem Store.

// ─────────────────────────────────────────────────────────────────────────
// WIEDERHOLUNG
// ─────────────────────────────────────────────────────────────────────────

enum RepeatRule { none, daily, weekly, monthly, yearly }

extension RepeatRuleX on RepeatRule {
  String get label => switch (this) {
        RepeatRule.none => 'Nie',
        RepeatRule.daily => 'Täglich',
        RepeatRule.weekly => 'Wöchentlich',
        RepeatRule.monthly => 'Monatlich',
        RepeatRule.yearly => 'Jährlich',
      };

  static RepeatRule fromKey(String? key) => switch (key) {
        'daily' => RepeatRule.daily,
        'weekly' => RepeatRule.weekly,
        'monthly' => RepeatRule.monthly,
        'yearly' => RepeatRule.yearly,
        _ => RepeatRule.none,
      };

  String get key => switch (this) {
        RepeatRule.none => 'none',
        RepeatRule.daily => 'daily',
        RepeatRule.weekly => 'weekly',
        RepeatRule.monthly => 'monthly',
        RepeatRule.yearly => 'yearly',
      };
}

// ─────────────────────────────────────────────────────────────────────────
// CALENDAR EVENT
// ─────────────────────────────────────────────────────────────────────────

class CalendarEvent {
  final String id;
  String title;
  String location;
  DateTime start;
  DateTime end;
  bool allDay;
  RepeatRule repeat;
  List<String> groupKeys; // NEU: bis zu 2 Gruppen statt einer
  List<String> reminderOptionIds;
  String notes;
  final DateTime createdAt;

  // NEU: Apple-Sync-Metadaten — direkt am Event, damit Dedup beim Pull
  // unabhängig vom (ggf. gelöschten) Hive-Mapping funktioniert.
  // Format: "<appleEventId>_<VorkommenStartMillis>" — identifiziert genau
  // EIN Vorkommen (auch bei wiederkehrenden Apple-Terminen, die
  // device_calendar bereits als einzelne Vorkommen mit gleicher appleId
  // liefert).
  String? appleSourceKey;
  bool appleReadOnly; // true = aus einem read-only Apple-Kalender (Feiertage/Geburtstage), nie zurückschreiben
  String? appleCalendarId; // NEU: physischer Ursprungs-Kalender (für Push-Back bei Sammel-Gruppen-Events wichtig)

  CalendarEvent({
    required this.id,
    required this.title,
    this.location = '',
    required this.start,
    required this.end,
    this.allDay = false,
    this.repeat = RepeatRule.none,
    List<String>? groupKeys,
    List<String>? reminderOptionIds,
    this.notes = '',
    required this.createdAt,
    this.appleSourceKey,
    this.appleReadOnly = false,
    this.appleCalendarId,
  })  : groupKeys = (groupKeys == null)
            ? ['dienstlich']
            : groupKeys.take(3).toList(),
        reminderOptionIds = reminderOptionIds ?? [];

  /// Für Stellen, die weiterhin nur EINE Farbe/Gruppe brauchen
  /// (z.B. Balken-Akzent in der Detailansicht). null = "Ohne".
  String? get primaryGroupKey => groupKeys.isEmpty ? null : groupKeys.first;

  bool get hasNotes => notes.trim().isNotEmpty;
  bool get hasReminder => reminderOptionIds.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'location': location,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'allDay': allDay,
        'repeat': repeat.key,
        'groups': groupKeys,
        'reminderOptionIds': reminderOptionIds,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'appleSourceKey': appleSourceKey,
        'appleReadOnly': appleReadOnly,
        'appleCalendarId': appleCalendarId,
      };

  factory CalendarEvent.fromJson(Map<String, dynamic> j) {
    List<String> keys;
    final groupsRaw = j['groups'];
    if (groupsRaw is List) {
      // NEU: 'groups' vorhanden (auch leer = "Ohne") ist immer
      // maßgeblich — kein Zurückfallen auf 'dienstlich' mehr.
      keys = groupsRaw.map((e) => e.toString()).take(3).toList();
    } else {
      // Alt-Format (vor Multi-Gruppen): einzelner String unter 'group'.
      final legacy = j['group'] as String?;
      keys = (legacy != null && legacy.isNotEmpty) ? [legacy] : ['dienstlich'];
    }
    return CalendarEvent(
      id: j['id'] as String,
      title: j['title'] as String,
      location: j['location'] as String? ?? '',
      start: DateTime.parse(j['start'] as String),
      end: DateTime.parse(j['end'] as String),
      allDay: j['allDay'] as bool? ?? false,
      repeat: RepeatRuleX.fromKey(j['repeat'] as String?),
      groupKeys: keys,
      reminderOptionIds:
          (j['reminderOptionIds'] as List?)?.map((e) => e.toString()).toList() ?? [],
      notes: j['notes'] as String? ?? '',
      createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
      appleSourceKey: j['appleSourceKey'] as String?,
      appleReadOnly: j['appleReadOnly'] as bool? ?? false,
      appleCalendarId: j['appleCalendarId'] as String?,
    );
  }

  CalendarEvent occurrenceOn(DateTime occStart, DateTime occEnd) => CalendarEvent(
        id: id,
        title: title,
        location: location,
        start: occStart,
        end: occEnd,
        allDay: allDay,
        repeat: repeat,
        groupKeys: groupKeys,
        reminderOptionIds: reminderOptionIds,
        notes: notes,
        createdAt: createdAt,
        appleSourceKey: appleSourceKey,
        appleReadOnly: appleReadOnly,
        appleCalendarId: appleCalendarId,
      );
}

// ─────────────────────────────────────────────────────────────────────────
// STORE
// ─────────────────────────────────────────────────────────────────────────

class CalendarEventStore {
  static const _key = 'calendar_events';

  static final ValueNotifier<int> changesSignal = ValueNotifier(0);
  static String? _lastWidgetPayload;
  static bool? _lastWidgetReadOnly;

  static void _notifyChanged() => changesSignal.value++;

  static void _normalizeAllDay(CalendarEvent e) {
    if (e.allDay && !e.end.isAfter(e.start)) {
      e.end = DateTime(e.start.year, e.start.month, e.start.day + 1);
    }
  }

  /// Zentrale Methode zum Planen von Benachrichtigungen für einen Termin
  static void _scheduleNotifications(CalendarEvent e) {
    // Erst alle alten Benachrichtigungen für diesen Termin löschen
    NotificationService.instance.cancelEventReminders(e.id);

    // Ganztägige Termine bekommen keine Erinnerungs-Benachrichtigungen
    // (laufen separat über den Banner, wie im Notification-Center)
    if (e.allDay) return;

    // Haupt-Erinnerung (garantierte Benachrichtigung)
    NotificationService.instance.scheduleGuaranteedEventReminder(
      eventId: e.id,
      eventTitle: e.title,
      eventStart: e.start,
    );

    // Benutzerdefinierte Erinnerungen basierend auf den reminderOptionIds
    final options = ReminderManager.optionsFor(ReminderMode.beforeDeadline);
    for (var i = 0; i < e.reminderOptionIds.length; i++) {
      final opt = options.firstWhere(
        (o) => o.id == e.reminderOptionIds[i],
        orElse: () => options.first,
      );
      NotificationService.instance.scheduleEventReminder(
        eventId: e.id,
        reminderIndex: i,
        eventTitle: e.title,
        eventStart: e.start,
        reminderAt: e.start.subtract(opt.duration),
      );
    }
  }

  /// Rohdaten — ALLE lokal gespeicherten Ereignisse, unabhängig davon, ob
  /// ein noch unbestätigter eigener Vorschlag (Kopiergerät, beim Erst-
  /// Verknüpfen mitgebracht) dabei ist. Nur intern für Lese-Änderungs-
  /// Schreib-Zyklen und den Sync verwenden — NIE direkt für die Anzeige,
  /// sonst würden zurückgehaltene Vorschläge sichtbar.
  static List<CalendarEvent> loadAllRaw() {
    final box = Hive.box('einstellungen');
    final raw = box.get(_key);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List;
        return decoded
            .map((e) => CalendarEvent.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  /// Für die Anzeige: blendet eigene, auf dem Kopiergerät beim Erst-
  /// Verknüpfen mitgebrachte Ereignisse aus, solange das Original sie noch
  /// nicht im Konflikte-Screen bestätigt oder verworfen hat.
  static List<CalendarEvent> loadAll() =>
      SyncService.instance.filterPendingCalendarEvents(loadAllRaw());

  static void _saveAll(List<CalendarEvent> events) {
    final box = Hive.box('einstellungen');
    box.put(_key, jsonEncode(events.map((e) => e.toJson()).toList()));
  }

  /// Öffentlicher Zugriff für EventGroupStore (Gruppen-Löschung) und
  /// SyncService (Remote-Übernahme).
  static Future<void> saveAllExternal(List<CalendarEvent> events, {bool notify = true}) async {
    final previous = {for (final e in loadAllRaw()) e.id: e};
    _saveAll(events);
    if (notify) _notifyChanged();

    final newIds = <String>{};
    for (final e in events) {
      newIds.add(e.id);
      final old = previous[e.id];
      final isNewOrChanged = old == null ||
          old.title != e.title ||
          old.location != e.location ||
          old.start != e.start ||
          old.end != e.end ||
          old.allDay != e.allDay ||
          old.notes != e.notes ||
          old.groupKeys.join(',') != e.groupKeys.join(',');
      if (isNewOrChanged) {
        // NEU: awaiten statt fire-and-forget — verhindert, dass bei einem
        // Batch mit vielen Events (initialer Sync, Restore) mehrere
        // Apple-Pushes parallel laufen, bevor jeweils appleSourceKey
        // gesetzt ist.
        await AppleCalendarSyncService.instance.pushEvent(e);
      }
    }
    for (final old in previous.values) {
      if (!newIds.contains(old.id)) {
        await AppleCalendarSyncService.instance.deleteEvent(old);
      }
    }
    pushUpcomingEventsToWidget(); // NEU
  }

  /// Setzt Kalender-Termine dieses Geräts lokal auf leer zurück — genutzt
  /// beim Aktivieren des Lesemodus, um dieses Gerät bewusst vom Sync zu
  /// trennen, statt mit den bisher gepullten Original-Daten weiterzuarbeiten.
  static void resetLocal() {
    // Benachrichtigungen für alle gelöschten Termine stornieren
    final all = loadAllRaw();
    for (final e in all) {
      NotificationService.instance.cancelEventReminders(e.id);
    }
    _saveAll([]);
    _notifyChanged();
    pushUpcomingEventsToWidget();
  }

  // ── EXTERNE ÜBERNAHME (Apple-Pull) — löst KEINEN erneuten Push aus ─────

  static void addExternal(CalendarEvent e) {
    final all = loadAllRaw()..add(e);
    _saveAll(all);
    _notifyChanged();
    _scheduleNotifications(e); // NEU — bisher gefehlt!
    pushUpcomingEventsToWidget();
  }

  static void updateExternal(CalendarEvent e) {
    final all = loadAllRaw();
    final idx = all.indexWhere((x) => x.id == e.id);
    if (idx != -1) {
      all[idx] = e;
      _saveAll(all);
      _notifyChanged();
      _scheduleNotifications(e); // NEU — bisher gefehlt!
      pushUpcomingEventsToWidget();
    }
  }

  static void deleteExternal(String id) {
    // Benachrichtigungen für gelöschten Termin stornieren
    final existing = byId(id);
    if (existing != null) {
      NotificationService.instance.cancelEventReminders(id);
    }
    final all = loadAllRaw()..removeWhere((e) => e.id == id);
    _saveAll(all);
    _notifyChanged();
    pushUpcomingEventsToWidget();
  }

  // ── LOKALE ÄNDERUNGEN (mit Push zum Apple-Kalender) ────────────────────

  static void add(CalendarEvent e) {
    _normalizeAllDay(e);
    final all = loadAllRaw()..add(e);
    _saveAll(all);
    _notifyChanged();
    SyncService.instance.pushCalendarEvent(e.id);
    AppleCalendarSyncService.instance.pushEvent(e);
    _scheduleNotifications(e); // NEU — zentral geplant
    pushUpcomingEventsToWidget();
  }

  static void update(CalendarEvent e) {
    _normalizeAllDay(e);
    final all = loadAllRaw();
    final idx = all.indexWhere((x) => x.id == e.id);
    if (idx != -1) {
      all[idx] = e;
      _saveAll(all);
      _notifyChanged();
      SyncService.instance.pushCalendarEvent(e.id);
      AppleCalendarSyncService.instance.pushEvent(e);
      _scheduleNotifications(e); // NEU — zentral geplant (überschreibt alte)
      pushUpcomingEventsToWidget();
    }
  }

  /// Löscht IMMER die ganze Serie (wie vereinbart — keine
  /// "nur dieses Vorkommen"-Abfrage).
  static void delete(String id) {
    final existing = byId(id);
    if (existing != null) {
      NotificationService.instance.cancelEventReminders(id); // NEU — Benachrichtigungen stornieren
      AppleCalendarSyncService.instance.deleteEvent(existing);
    }
    final all = loadAllRaw()..removeWhere((e) => e.id == id);
    _saveAll(all);
    _notifyChanged();
    SyncService.instance.pushCalendarEvent(id); // fehlt lokal -> Sync löscht remote
    pushUpcomingEventsToWidget();
  }

  static CalendarEvent? byId(String id) {
    try {
      return loadAllRaw().firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  // ── OCCURRENCE-BERECHNUNG ─────────────────────────────────────────────
  //
  // Virtuell, nur für den angefragten Zeitraum — wird von der Monatsansicht
  // mit [rangeStart, rangeEnd] = sichtbarer Monat ±1 Monat aufgerufen.
  // Für RepeatRule.none liefert das genau 0 oder 1 Eintrag.

  static List<CalendarEvent> occurrencesInRange(
    List<CalendarEvent> events,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final result = <CalendarEvent>[];
    for (final e in events) {
      result.addAll(_occurrencesFor(e, rangeStart, rangeEnd));
    }
    return result;
  }

  // ── NEU: Push der nächsten Kalender-Termine an die Widget-Extension ──────
  static const _widgetChannel = MethodChannel('de.marcel.optimes/widget');

  static Future<void> pushUpcomingEventsToWidget({bool force = false}) async {
    if (kIsWeb) return;
    try {
      // NEU: Flag mitschicken, damit das Fahrtenbuch-Quick-Start-Widget
      // im Lesemodus ausgeblendet werden kann (dort nicht nutzbar).
      final readOnly = Hive.box('einstellungen').get('read_only_mode', defaultValue: false) as bool;
      final now = DateTime.now();
      final rangeStart = DateTime(now.year, now.month, now.day);
      final rangeEnd = rangeStart.add(const Duration(days: 14));
      final all = loadAll();
      final occ = occurrencesInRange(all, rangeStart, rangeEnd)
        ..sort((a, b) => a.start.compareTo(b.start));

      final entries = occ.map((e) {
        String? colorHex;
        if (e.primaryGroupKey != null) {
          final c = EventGroupStore.byKey(e.primaryGroupKey!).colorValue;
          colorHex = '#${c.toRadixString(16).padLeft(8, '0').substring(2)}';
        }
        return {
          'title': e.title,
          'start': e.start.toIso8601String(),
          'end': e.end.toIso8601String(),
          'allDay': e.allDay,
          if (colorHex != null) 'colorHex': colorHex,
        };
      }).toList();

      final payload = jsonEncode(entries);
      if (!force && _lastWidgetPayload == payload && _lastWidgetReadOnly == readOnly) {
        return;
      }

      _lastWidgetPayload = payload;
      _lastWidgetReadOnly = readOnly;

      await _widgetChannel.invokeMethod('updateCalendarEvents', {
        'json': payload,
        'readOnly': readOnly, // NEU
      });
    } catch (e) {
      debugPrint('❌ Kalender-Widget-Push Fehler: $e');
    }
  }

  static List<CalendarEvent> _occurrencesFor(
    CalendarEvent e,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final duration = e.end.difference(e.start);

    if (e.repeat == RepeatRule.none) {
      if (e.start.isBefore(rangeEnd) && e.end.isAfter(rangeStart)) {
        return [e];
      }
      return [];
    }

    final out = <CalendarEvent>[];
    // Sicherheitslimit gegen Endlosschleifen bei kaputten Daten.
    const maxIterations = 400;
    var occStart = e.start;
    var i = 0;

    while (occStart.isBefore(rangeEnd) && i < maxIterations) {
      final occEnd = occStart.add(duration);
      if (occEnd.isAfter(rangeStart)) {
        out.add(e.occurrenceOn(occStart, occEnd));
      }
      occStart = _nextOccurrence(occStart, e.repeat);
      i++;
    }
    return out;
  }

  static DateTime _nextOccurrence(DateTime from, RepeatRule rule) {
    switch (rule) {
      case RepeatRule.daily:
        return from.add(const Duration(days: 1));
      case RepeatRule.weekly:
        return from.add(const Duration(days: 7));
      case RepeatRule.monthly:
        return _addMonths(from, 1);
      case RepeatRule.yearly:
        return _addYearsSameDate(from, 1);
      case RepeatRule.none:
        return from; // wird nie erreicht
    }
  }

  /// Addiert Monate unter Beibehaltung von Uhrzeit; kappt auf den letzten
  /// Tag des Zielmonats, falls der Ursprungstag dort nicht existiert
  /// (z. B. 31. Jan → 28./29. Feb).
  static DateTime _addMonths(DateTime d, int months) {
    var year = d.year;
    var month = d.month + months;
    while (month > 12) {
      month -= 12;
      year++;
    }
    final lastDayOfTargetMonth = DateTime(year, month + 1, 0).day;
    final day = d.day > lastDayOfTargetMonth ? lastDayOfTargetMonth : d.day;
    return DateTime(year, month, day, d.hour, d.minute);
  }

  /// "Jährlich = selbes Datum", nicht 365 Tage später. Fängt den
  /// 29. Februar ab (fällt in Nicht-Schaltjahren auf den 28.).
  static DateTime _addYearsSameDate(DateTime d, int years) {
    final targetYear = d.year + years;
    final isFeb29 = d.month == 2 && d.day == 29;
    if (isFeb29 && !_isLeapYear(targetYear)) {
      return DateTime(targetYear, 2, 28, d.hour, d.minute);
    }
    return DateTime(targetYear, d.month, d.day, d.hour, d.minute);
  }

  static bool _isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
}