import 'package:hive_flutter/hive_flutter.dart';

/// Zentrale, rein lokale (nicht gesynct) Freischaltung optionaler
/// App-Funktionen — steuerbar über Einstellungen → Profil →
/// Funktionsfreischaltung. Jedes Gerät entscheidet für sich selbst.
class FeatureFlags {
  FeatureFlags._();

  static const _kBva = 'feature_bva_enabled';
  static const _kCalendarSync = 'feature_calendar_sync_enabled';
  static const _kAppleCalendar = 'feature_apple_calendar_enabled';

  static Box get _box => Hive.box('einstellungen');

  static bool get bvaEnabled => _box.get(_kBva, defaultValue: true) as bool;
static set bvaEnabled(bool v) => _box.put(_kBva, v);

static bool get calendarSyncEnabled =>
    _box.get(_kCalendarSync, defaultValue: false) as bool; // GEÄNDERT: Standard aus
static set calendarSyncEnabled(bool v) => _box.put(_kCalendarSync, v);

static bool get appleCalendarEnabled =>
    _box.get(_kAppleCalendar, defaultValue: false) as bool; // GEÄNDERT: Standard aus
static set appleCalendarEnabled(bool v) => _box.put(_kAppleCalendar, v);
}