// lib/services/user_position.dart
// Echter Standort (geolocator) mit Zwischenspeicher + Distanz-Helfer.

import 'dart:async';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

typedef GeoPoint = ({double lat, double lng});

class UserPosition {
  UserPosition._();

  static const _key = 'last_user_pos';
  static GeoPoint? _mem;
  static DateTime? _memAt;
  static Future<GeoPoint?>? _inflight;

  /// Sofort verfügbar: letzter bekannter Standort (Speicher oder Hive), sonst null.
  static GeoPoint? get cached {
    if (_mem != null) return _mem;
    try {
      final raw = Hive.box('einstellungen').get(_key);
      if (raw is List && raw.length == 2) {
        return (lat: (raw[0] as num).toDouble(), lng: (raw[1] as num).toDouble());
      }
    } catch (_) {}
    return null;
  }

  /// Schnell: letzter bekannter Standort sofort, Aktualisierung im Hintergrund.
  /// Nur ohne gespeicherten Standort wird gewartet.
  static Future<GeoPoint?> quick() async {
    final c = cached;
    if (c != null) {
      unawaited(get());
      return c;
    }
    return get();
  }

  /// Aktueller Standort. Fragt bei Bedarf die Berechtigung an, fällt bei Fehlern auf [cached] zurück.
  static Future<GeoPoint?> get() => _inflight ??= _load().whenComplete(() => _inflight = null);

  static Future<GeoPoint?> _load() async {
    final fresh = _mem != null &&
        _memAt != null &&
        DateTime.now().difference(_memAt!) < const Duration(minutes: 3);
    if (fresh) return _mem;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return cached;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return cached;
      Position? p;
      try {
        p = await Geolocator.getLastKnownPosition();
      } catch (_) {}
      p ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 4),
        ),
      );
      _mem = (lat: p.latitude, lng: p.longitude);
      _memAt = DateTime.now();
      try {
        await Hive.box('einstellungen').put(_key, [p.latitude, p.longitude]);
      } catch (_) {}
      return _mem;
    } catch (_) {
      return cached;
    }
  }

  static double distanceM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
  }

  static String formatDistance(double m) {
    if (m < 1000) return '${math.max(10, (m / 10).round() * 10)} m';
    final km = m / 1000;
    if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${km.round()} km';
  }
}
