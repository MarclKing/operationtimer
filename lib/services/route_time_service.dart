// lib/services/route_time_service.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/location_info.dart';
import '../widgets/day_plan.dart';

/// TomTom-Key: hier als Defaultwert eintragen ODER per
/// `--dart-define=TOMTOM_KEY=...` mitgeben.
const String kTomTomKey = String.fromEnvironment('TOMTOM_KEY', defaultValue: 'nA6lAr5YPNncTAoBV70w51qVeQEmzf0A');

/// Woher kam der angezeigte Wert?
///  none     = Live-Verkehr aus -> kein Icon
///  live     = Live-Verkehr an UND Wert von TomTom -> gruenes Blitz-Icon
///  fallback = Live-Verkehr an, Wert aber vom Fallback (OSRM) -> rotes Blitz-Icon
enum RouteBadge { none, live, fallback }

enum LiveTrafficStatus { off, unknown, ok, failing }

class RouteInfo {
  final String text; // "ca. 25 Minuten"
  final String short; // "25 Min"
  final RouteBadge badge;
  const RouteInfo(this.text, this.short, this.badge);
}

class RouteBadgeIcon extends StatelessWidget {
  final RouteBadge badge;
  final double size;
  const RouteBadgeIcon({super.key, required this.badge, this.size = 12});

  @override
  Widget build(BuildContext context) {
    if (badge == RouteBadge.none) return const SizedBox.shrink();
    final live = badge == RouteBadge.live;
    return Icon(
      Icons.bolt_rounded,
      size: size,
      color: live ? const Color(0xFF3DD68C) : const Color(0xFFEF5B5B).withValues(alpha: 0.85),
    );
  }
}

/// Fahrzeit (Auto) zwischen zwei aufeinanderfolgenden Ereignissen im Tagesplan.
///  - Fahrzeiten werden IMMER berechnet/angezeigt
///  - Live-Verkehr an  -> TomTom (Fallback OSRM, wenn TomTom nicht klappt)
///  - Live-Verkehr aus -> nur OSRM (ohne Verkehr)
///  - Live-Verkehr nur heute und nur für noch anstehende Ereignisse, alle 30 Min
///  - kuenftige Tage ohne Live-Verkehr taeglich, vergangene: nie
class RouteTimeService {
  RouteTimeService._();

  static const _liveKeyHive = 'route_live_traffic';
  static const _boxName = 'route_time_cache';
  static const _lastPrunedAtKey = '__route_cache_last_pruned__';
  static const Duration _liveMaxAge = Duration(minutes: 30);
  static const Duration _offlineTodayMaxAge = Duration(minutes: 30);
  static const Duration _futureMaxAge = Duration(days: 1);
  static const Duration _retryAfterFail = Duration(minutes: 5);
  static const Duration _pruneAfter = Duration(days: 30);
  static const int _maxCacheEntries = 1000;
  static const int _maxTrackedFailures = 500;

  /// Wird hochgezaehlt, sobald sich Werte oder Einstellungen aendern.
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);

  static Box? _box;
  static final Set<String> _inFlight = {};
  static final Map<String, DateTime> _failedAt = {};

  /// Fahrzeit ist immer an (Getter bleibt, damit bestehende Aufrufe weiterlaufen).
  static bool get enabled => true;

  // ── Live-Verkehr ────────────────────────────────────────────────────────
  static bool get liveTraffic =>
      Hive.box('einstellungen').get(_liveKeyHive, defaultValue: true) as bool;

  static set liveTraffic(bool v) {
    Hive.box('einstellungen').put(_liveKeyHive, v);
    if (v) tomtomOk = null;
    changed.value++;
    if (v) unawaited(checkLive());
  }

  /// null = unbekannt, true = letzte TomTom-Anfrage ok, false = fehlgeschlagen.
  static bool? tomtomOk;

  static LiveTrafficStatus get liveStatus {
    if (!liveTraffic) return LiveTrafficStatus.off;
    if (tomtomOk == null) return LiveTrafficStatus.unknown;
    return tomtomOk! ? LiveTrafficStatus.ok : LiveTrafficStatus.failing;
  }

  /// Kurzer Test mit dem aktiven Key -> aktualisiert [tomtomOk].
  static Future<void> checkLive() => testKey(_activeKey);

  // ── Eigener Key ─────────────────────────────────────────────────────────
  static const _userKeyHive = 'tomtom_api_key';

  static String get userKey =>
      ((Hive.box('einstellungen').get(_userKeyHive, defaultValue: '') as String?) ?? '').trim();

  static set userKey(String v) {
    Hive.box('einstellungen').put(_userKeyHive, v.trim());
    tomtomOk = null;
    changed.value++;
  }

  static String get _activeKey => userKey.isNotEmpty ? userKey : kTomTomKey;

  static bool get _hasKey => _activeKey.isNotEmpty && _activeKey != 'DEIN_TOMTOM_KEY';

  /// Cache-Box lazy oeffnen.
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

  // ── Schluessel / Cache ──────────────────────────────────────────────────
  static String _pt(LocationInfo l) => '${l.lat!.toStringAsFixed(4)},${l.lng!.toStringAsFixed(4)}';

  static String _key(
    LocationInfo a,
    LocationInfo b, {
    required DateTime departure,
  }) {
    final halfHour = (departure.minute ~/ 30) * 30;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${_pt(a)}>${_pt(b)}@${departure.year}-'
        '${two(departure.month)}-${two(departure.day)}T'
        '${two(departure.hour)}:${two(halfHour)}';
  }

  static int? _cachedSec(String key) {
    final raw = _box?.get(key);
    if (raw is Map) {
      final s = raw['sec'];
      if (s is num) return s.toInt();
    }
    return null;
  }

  static String? _cachedSrc(String key) {
    final raw = _box?.get(key);
    if (raw is Map) {
      final s = raw['src'];
      if (s is String) return s;
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
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    await box.put(key, {'sec': sec, 'at': nowMs, 'src': src});

    final lastPruned = box.get(_lastPrunedAtKey);
    final hasPruneMarker = box.containsKey(_lastPrunedAtKey);
    final cacheEntryCount = box.length - (hasPruneMarker ? 1 : 0);
    final pruneDue = lastPruned is! num ||
        nowMs < lastPruned.toInt() ||
        nowMs - lastPruned.toInt() >= const Duration(hours: 24).inMilliseconds;
    if (!pruneDue && cacheEntryCount <= _maxCacheEntries) {
      return;
    }

    final cut = now.subtract(_pruneAfter).millisecondsSinceEpoch;
    final old = <dynamic>[];
    final current = <({dynamic key, int at})>[];
    for (final k in box.keys) {
      if (k == _lastPrunedAtKey) continue;
      final v = box.get(k);
      final at = v is Map ? v['at'] : null;
      if (at is! num) {
        old.add(k);
      } else if (at < cut) {
        old.add(k);
      } else {
        current.add((key: k, at: at.toInt()));
      }
    }
    current.sort((a, b) => a.at.compareTo(b.at));
    if (current.length > _maxCacheEntries) {
      old.addAll(current.take(current.length - _maxCacheEntries).map((e) => e.key));
    }
    if (old.isNotEmpty) await box.deleteAll(old);
    await box.put(_lastPrunedAtKey, nowMs);
  }

  static void _recordFailure(String key) {
    _failedAt[key] = DateTime.now();
    if (_failedAt.length > _maxTrackedFailures) {
      final oldest = _failedAt.entries.reduce(
        (a, b) => a.value.isBefore(b.value) ? a : b,
      );
      _failedAt.remove(oldest.key);
    }
  }

  // ── Anzeige ─────────────────────────────────────────────────────────────
  /// Fahrzeit von [prev] nach [cur] samt Herkunfts-Badge, sonst null.
  static RouteInfo? infoFor(DayPlanItem prev, DayPlanItem cur) {
    final a = prev.loc, b = cur.loc;
    if (a == null || b == null || !a.hasCoords || !b.hasCoords) return null;
    if (_pt(a) == _pt(b)) return null;
    final k = _key(a, b, departure: prev.end);
    final s = _cachedSec(k);
    if (s == null) return null;
    final RouteBadge badge;
    if (!liveTraffic) {
      badge = RouteBadge.none;
    } else {
      badge = _cachedSrc(k) == 'tomtom' ? RouteBadge.live : RouteBadge.fallback;
    }
    return RouteInfo(_format(s), _formatShort(s), badge);
  }

  static String? labelFor(DayPlanItem prev, DayPlanItem cur) => infoFor(prev, cur)?.text;

  static int _minutes(int sec) {
    var min = (sec / 60).round();
    if (min < 1) min = 1;
    if (min >= 10) min = ((min / 5).round()) * 5;
    return min;
  }

  static String _format(int sec) {
    final min = _minutes(sec);
    if (min < 60) return 'ca. $min Minuten';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? 'ca. $h Std' : 'ca. $h Std $m Min';
  }

  static String _formatShort(int sec) {
    final min = _minutes(sec);
    if (min < 60) return '$min Min';
    final h = min ~/ 60;
    final m = min % 60;
    return m == 0 ? '$h Std' : '$h Std $m';
  }

  // ── Berechnung ──────────────────────────────────────────────────────────
  static Future<void> ensureForDay(DateTime day, List<DayPlanItem> items) async {
    if (_box == null || items.length < 2) return;
    final n0 = DateTime.now();
    final today = DateTime(n0.year, n0.month, n0.day);
    final d = DateTime(day.year, day.month, day.day);
    if (d.isBefore(today)) return;
    final isToday = d.isAtSameMomentAs(today);
    final wantLive = liveTraffic && _hasKey;

    for (int i = 1; i < items.length; i++) {
      final now = DateTime.now();
      final prev = items[i - 1];
      final cur = items[i];
      final a = prev.loc, b = cur.loc;
      if (a == null || b == null || !a.hasCoords || !b.hasCoords) continue;
      if (_pt(a) == _pt(b)) continue;

      if (isToday && !cur.start.isAfter(now)) continue;

      final depart = prev.end.isAfter(now.add(const Duration(minutes: 10))) ? prev.end : null;
      final key = _key(a, b, departure: prev.end);
      if (_inFlight.contains(key)) continue;
      final failed = _failedAt[key];
      if (failed != null && now.difference(failed) < _retryAfterFail) continue;

      final at = _cachedAt(key);
      final src = _cachedSrc(key);
      final maxAge = wantLive
          ? _liveMaxAge
          : (isToday ? _offlineTodayMaxAge : _futureMaxAge);
      // Future routes never use live traffic; replace a prior TomTom cache once.
      final needsSwitch =
          (wantLive &&
              src != 'tomtom' &&
              (at == null || now.difference(at) >= _liveMaxAge)) ||
              (!wantLive && src == 'tomtom');

      if (isToday && !cur.end.isAfter(now)) continue;
      if (at != null && now.difference(at) < maxAge && !needsSwitch) {
        continue;
      }

      _inFlight.add(key);
      try {
        final r = await _fetch(a, b, depart, useLiveTraffic: wantLive);
        if (r == null) {
          _recordFailure(key);
        } else {
          _failedAt.remove(key);
          await _store(key, r.$1, r.$2);
        }
        changed.value++;
      } finally {
        _inFlight.remove(key);
      }
    }
  }

  static Future<(int, String)?> _fetch(
    LocationInfo a,
    LocationInfo b,
    DateTime? departAt, {
    required bool useLiveTraffic,
  }) async {
    if (useLiveTraffic && _hasKey) {
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

  static void _setOk(bool ok) {
    if (tomtomOk == ok) return;
    tomtomOk = ok;
    changed.value++;
  }

  static Future<int?> _tomtom(LocationInfo a, LocationInfo b, DateTime? departAt) async {
    try {
      final uri = Uri.https(
        'api.tomtom.com',
        '/routing/1/calculateRoute/${a.lat},${a.lng}:${b.lat},${b.lng}/json',
        {
          'key': _activeKey,
          'traffic': 'true',
          'travelMode': 'car',
          'routeType': 'fastest',
          if (departAt != null) 'departAt': _iso(departAt),
        },
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        _setOk(false);
        return null;
      }
      final routes = (jsonDecode(res.body) as Map)['routes'];
      if (routes is List && routes.isNotEmpty) {
        final sum = (routes.first as Map)['summary'];
        final t = sum is Map ? sum['travelTimeInSeconds'] : null;
        if (t is num && t > 0) {
          _setOk(true);
          return t.round();
        }
      }
    } catch (_) {}
    _setOk(false);
    return null;
  }

  /// true = Key gueltig, false = abgelehnt, null = keine Verbindung.
  /// Ist [key] der aktive Key, wird dabei auch [tomtomOk] aktualisiert.
  static Future<bool?> testKey(String key) async {
    final isActive = key.trim() == _activeKey;
    try {
      final uri = Uri.https(
        'api.tomtom.com',
        '/routing/1/calculateRoute/52.5200,13.4050:52.5163,13.3777/json',
        {'key': key.trim(), 'traffic': 'true'},
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      final ok = res.statusCode == 200;
      if (isActive) _setOk(ok);
      return ok;
    } catch (_) {
      if (isActive) _setOk(false);
      return null;
    }
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
