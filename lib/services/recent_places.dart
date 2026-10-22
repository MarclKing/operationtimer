// lib/services/recent_places.dart
// Zuletzt gewählte Orte (lokal, max. 8).

import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'location_resolver.dart';

class RecentPlaces {
  RecentPlaces._();
  static const _key = 'recent_places';

  static List<PlaceSuggestion> all() {
    try {
      final raw = Hive.box('einstellungen').get(_key);
      if (raw is! String || raw.isEmpty) return [];
      final out = <PlaceSuggestion>[];
      for (final e in (jsonDecode(raw) as List)) {
        if (e is! Map) continue;
        final lat = (e['lat'] as num?)?.toDouble();
        final lng = (e['lng'] as num?)?.toDouble();
        final title = e['title'] as String?;
        if (lat == null || lng == null || title == null) continue;
        out.add(PlaceSuggestion(
          title: title,
          subtitle: e['subtitle'] as String?,
          lat: lat,
          lng: lng,
          zoom: (e['zoom'] as num?)?.toDouble() ?? 17,
          street: e['street'] as String?,
          postalCode: e['postalCode'] as String?,
          city: e['city'] as String?,
          named: e['named'] == true,
        ));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(List<PlaceSuggestion> list) async {
    await Hive.box('einstellungen').put(
      _key,
      jsonEncode(list
          .map((e) => {
                'title': e.title,
                'subtitle': e.subtitle,
                'lat': e.lat,
                'lng': e.lng,
                'zoom': e.zoom,
                'street': e.street,
                'postalCode': e.postalCode,
                'city': e.city,
                'named': e.named,
              })
          .toList()),
    );
  }

  static bool _same(PlaceSuggestion a, PlaceSuggestion b) =>
      (a.lat - b.lat).abs() < 1e-4 && (a.lng - b.lng).abs() < 1e-4;

  static Future<void> add(PlaceSuggestion s) async {
    try {
      final list = all()..removeWhere((e) => _same(e, s));
      list.insert(0, s);
      if (list.length > 8) list.removeRange(8, list.length);
      await _write(list);
    } catch (_) {}
  }

  /// Entfernt einen Ort dauerhaft aus den "zuletzt benutzt"-Vorschlägen.
  static Future<void> remove(PlaceSuggestion s) async {
    try {
      await _write(all()..removeWhere((e) => _same(e, s)));
    } catch (_) {}
  }
}
