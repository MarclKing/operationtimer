// lib/services/favorite_place_store.dart
// Favorisierte Orte. Lokal in Hive ('einstellungen'), Sortierung nach letzter Benutzung.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/location_info.dart';

class FavoritePlace {
  final String id;
  final String name;
  final LocationInfo loc; // ohne favoriteId gespeichert
  final int createdAt;
  final int lastUsed;
  final int updatedAt;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.loc,
    required this.createdAt,
    required this.lastUsed,
    required this.updatedAt,
  });

  FavoritePlace copyWith({String? name, LocationInfo? loc, int? lastUsed, int? updatedAt}) => FavoritePlace(
        id: id,
        name: name ?? this.name,
        loc: loc ?? this.loc,
        createdAt: createdAt,
        lastUsed: lastUsed ?? this.lastUsed,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// Ort, wie er in Ereignissen verwendet wird: Name statt Adresse, mit Favoriten-Bezug.
  LocationInfo toLocationInfo() => loc.withFavorite(id, name);

  String get addressLine {
    if (loc.singleLine.isNotEmpty) return loc.singleLine;
    if (loc.hasCoords) return '${loc.lat!.toStringAsFixed(5)}, ${loc.lng!.toStringAsFixed(5)}';
    return '';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'loc': loc.toJson(),
        'createdAt': createdAt,
        'lastUsed': lastUsed,
        'updatedAt': updatedAt,
      };

  static FavoritePlace? tryFromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      final loc = LocationInfo.tryFromJson(j['loc']);
      final id = j['id'] as String?;
      final name = (j['name'] as String?)?.trim();
      if (loc == null || !loc.hasCoords || id == null || name == null || name.isEmpty) return null;
      final created = (j['createdAt'] as num?)?.toInt() ?? 0;
      return FavoritePlace(
        id: id,
        name: name,
        loc: loc.withoutFavorite(),
        createdAt: created,
        lastUsed: (j['lastUsed'] as num?)?.toInt() ?? created,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? created,
      );
    } catch (_) {
      return null;
    }
  }
}

class FavoritePlaceStore {
  FavoritePlaceStore._();

  static const hiveKey = 'favorite_places';

  /// Wird nach jeder Änderung aufgerufen (Anschluss für den Sync).
  static VoidCallback? onChanged;

  /// Alle Favoriten, zuletzt benutzte zuerst.
  static List<FavoritePlace> all() {
    final raw = Hive.box('einstellungen').get(hiveKey);
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map(FavoritePlace.tryFromJson)
          .whereType<FavoritePlace>()
          .toList();
      list.sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return list;
    } catch (_) {
      return [];
    }
  }

  static FavoritePlace? byId(String id) {
    for (final f in all()) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Favoriten für Vorschläge: leere Suche = zuletzt benutzte, sonst Treffer in Name/Adresse.
  static List<FavoritePlace> search(String query, {int limit = 8}) {
    final q = query.trim().toLowerCase();
    final list = all();
    if (q.isEmpty) return list.take(limit).toList();
    return list
        .where((f) => f.name.toLowerCase().contains(q) || f.loc.singleLine.toLowerCase().contains(q))
        .take(limit)
        .toList();
  }

  static Future<void> _save(List<FavoritePlace> list) async {
    final box = Hive.box('einstellungen');
    await box.put(hiveKey, jsonEncode(list.map((e) => e.toJson()).toList()));
    await box.flush();
    onChanged?.call();
  }

  static Future<FavoritePlace> add(String name, LocationInfo loc) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final plain = loc.withoutFavorite();
    final trimmed = name.trim();
    final fav = FavoritePlace(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: trimmed.isNotEmpty ? trimmed : (plain.line1.isNotEmpty ? plain.line1 : 'Favorit'),
      loc: plain,
      createdAt: now,
      lastUsed: now,
      updatedAt: now,
    );
    final list = all()..add(fav);
    await _save(list);
    return fav;
  }

  static Future<void> update(FavoritePlace f) async {
    final list = all();
    final i = list.indexWhere((e) => e.id == f.id);
    if (i < 0) return;
    list[i] = f.copyWith(loc: f.loc.withoutFavorite(), updatedAt: DateTime.now().millisecondsSinceEpoch);
    await _save(list);
  }

  static Future<void> delete(String id) async {
    final list = all()..removeWhere((e) => e.id == id);
    await _save(list);
  }

  /// Merkt sich die Benutzung (Sortierung "zuletzt benutzt").
  static Future<void> touch(String id) async {
    final list = all();
    final i = list.indexWhere((e) => e.id == id);
    if (i < 0) return;
    list[i] = list[i].copyWith(lastUsed: DateTime.now().millisecondsSinceEpoch);
    await _save(list);
  }
}
