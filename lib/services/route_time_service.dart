// lib/services/route_time_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_info.dart';
import '../widgets/day_plan.dart';

/// TomTom-Key: hier als Defaultwert eintragen ODER per
/// `--dart-define=TOMTOM_KEY=...` mitgeben. Ohne Key läuft OSRM (ohne Verkehr).
const String kTomTomKey = String.fromEnvironment('TOMTOM_KEY', defaultValue: 'nA6lAr5YPNncTAoBV70w51qVeQEmzf0A');

/// Fahrzeit (Auto) zwischen zwei aufeinanderfolgenden Ereignissen im Tagesplan.
///
/// Regeln (Kapazität schonen):
///  • heute: Wert wird höchstens alle 30 Min neu geholt, nur für Ereignisse,
///    die noch nicht vorbei sind
///  • künftige Tage: genau einmal (beim Anlegen/Ändern, bzw. beim ersten Ansehen)
///  • vergangene Tage: nie
///  • neu gerechnet wird nur bei geänderter Start-/Zielposition (Cache-Schlüssel = Koordinaten)
class RouteTimeService {
  RouteTimeService._();

  static const _settingKey = 'route_time_enabled';
  static const _boxName = 'route_time_cache';
  static const Duration _liveMaxAge = Duration(minutes: 30);
  static const Duration _retryAfterFail = Duration(minutes: 5);
  static const Duration _pruneAfter = Duration(days: 30);

  /// Wird hochgezählt, sobald sich Werte oder die Einstellung ändern.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static Box? _box;
  static final Set<String> _inFlight = {};
  static final Map<String, DateTime> _failedAt = {};

  static bool get enabled =>
      Hive.box('einstellungen').get(_settingKey, defaultValue: true) as bool;

  static set enabled(bool v) {
    Hive.box('einstellungen').put(_settingKey, v);
    changed.value++;
  }

  static bool get _hasKey => kTomTomKey.isNotEmpty && kTomTomKey != 'DEIN_TOMTOM_KEY';

  /// Cache-Box lazy öffnen (eigene Box, damit sie nicht im Backup/Sync landet).
  static Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    try {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box(_boxName);
        return;
      }
      _box = await Hive.openBox(_boxName);
      changed.value++;
    } catch (e) {
      debugPrint('RouteTimeService.init: $e');
    }
  }

  // ── Schlüssel / Cache ───────────────────────────────────────────────────
  static String _pt(LocationInfo l) => '${l.lat!.toStringAsFixed(4)},${l.lng!.toStringAsFixed(4)}';
  static String _key(LocationInfo a, LocationInfo b) => '${_pt(a)}>${_pt(b)}';

  static int? _cachedSec(String key) {
    final raw = _box?.get(key);
    if (raw is Map) {
      final s = raw['sec'];
      if (s is num) return s.toInt();
    }
    return null;
  }

  static DateTime? _cachedAt(String key) {
    final raw = _box?.get(key);
    if (raw is Map) {
      final t = raw['at'];
      if (t is num) return DateTime.fromMillisecondsSinceEpoch(t.toInt());
    }
    return null;
  }

  static Future<void> _store(String key, int sec, String src) async {
    final box = _box;
    if (box == null) return;
    await box.put(key, {'sec': sec, 'at': DateTime.now().millisecondsSinceEpoch, 'src': src});
    final cut = DateTime.now().subtract(_pruneAfter).millisecondsSinceEpoch;
    final old = <dynamic>[];
    for (final k in box.keys) {
      final v = box.get(k);
      final at = v is Map ? v['at'] : null;
      if (at is num && at < cut) old.add(k);
    }
    if (old.isNotEmpty) await box.deleteAll(old);
  }

  // ── Anzeige ─────────────────────────────────────────────────────────────
  /// Text für die Karte von [cur]: Fahrzeit von [prev] nach [cur], sonst null.
  static String? labelFor(DayPlanItem prev, DayPlanItem cur) {
    final a = prev.loc, b = cur.loc;
    if (a == null || b == null || !a.hasCoords || !b.hasCoords) return null;
    if (_pt(a) == _pt(b)) return null;
    final s = _cachedSec(_key(a, b));
    return s == null ? null : _format(s);
  }

  static String _format(int sec) {
    var min = (sec / 60).round();
    if (min < 1) min = 1;
    if (min >= 10) min = ((min / 5).round()) * 5;
    if (min < 60) return 'ca. $min Min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? 'ca. $h Std' : 'ca. $h Std $m Min';
  }

  // ── Berechnung ──────────────────────────────────────────────────────────
  static Future<void> ensureForDay(DateTime day, List<DayPlanItem> items) async {
    if (_box == null || !enabled || items.length < 2) return;
    final n0 = DateTime.now();
    final today = DateTime(n0.year, n0.month, n0.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(today)) return;
    final isToday = d.isAtSameMomentAs(today);

    for (int i = 1; i < items.length; i++) {
      final now = DateTime.now();
      final prev = items[i - 1];
      final cur = items[i];
      final a = prev.loc, b = cur.loc;
      if (a == null || b == null || !a.hasCoords || !b.hasCoords) continue;
      if (_pt(a) == _pt(b)) continue;

      final key = _key(a, b);
      if (_inFlight.contains(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && now.difference(failed) < _retryAfterFail) continue;

      final at = _cachedAt(key);
      if (isToday) {
        if (!cur.end.isAfter(now)) continue;
        if (at != null && now.difference(at) < _liveMaxAge) continue;
      } else if (at != null) {
        continue;
      }

      _inFlight.add(key);
      try {
        final depart = prev.end.isAfter(now.add(const Duration(minutes: 10))) ? prev.end : null;
        final r = await _fetch(a, b, depart);
        if (r == null) {
          _failedAt[key] = DateTime.now();
        } else {
          _failedAt.remove(key);
          await _store(key, r.$1, r.$2);
          changed.value++;
        }
      } finally {
        _inFlight.remove(key);
      }
    }
  }

  static Future<(int, String)?> _fetch(LocationInfo a, LocationInfo b, DateTime? departAt) async {
    if (_hasKey) {
      final s = (departAt != null ? await _tomtom(a, b, departAt) : null) ?? await _tomtom(a, b, null);
      if (s != null) return (s, 'tomtom');
    }
    final o = await _osrm(a, b);
    return o == null ? null : (o, 'osrm');
  }

  static String _iso(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final o = dt.timeZoneOffset;
    final sign = o.isNegative ? '-' : '+';
    final hh = two(o.inHours.abs());
    final mm = two(o.inMinutes.abs() % 60);
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}T${two(dt.hour)}:${two(dt.minute)}:00$sign$hh:$mm';
  }

  static Future<int?> _tomtom(LocationInfo a, LocationInfo b, DateTime? departAt) async {
    try {
      final uri = Uri.https(
        'api.tomtom.com',
        '/routing/1/calculateRoute/${a.lat},${a.lng}:${b.lat},${b.lng}/json',
        {
          'key': kTomTomKey,
          'traffic': 'true',
          'travelMode': 'car',
          'routeType': 'fastest',
          if (departAt != null) 'departAt': _iso(departAt),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final routes = (jsonDecode(res.body) as Map)['routes'];
      if (routes is List && routes.isNotEmpty) {
        final sum = (routes.first as Map)['summary'];
        final t = sum is Map ? sum['travelTimeInSeconds'] : null;
        if (t is num && t > 0) return t.round();
      }
    } catch (_) {}
    return null;
  }

  /// Fallback ohne Live-Verkehr (OSRM-Demoserver).
  static Future<int?> _osrm(LocationInfo a, LocationInfo b) async {
    try {
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/${a.lng},${a.lat};${b.lng},${b.lat}',
        {'overview': 'false'},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final routes = (jsonDecode(res.body) as Map)['routes'];
      if (routes is List && routes.isNotEmpty) {
        final t = (routes.first as Map)['duration'];
        if (t is num && t > 0) return t.round();
      }
    } catch (_) {}
    return null;
  }
}
