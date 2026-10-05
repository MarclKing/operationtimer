// lib/services/location_resolver.dart
// Wandelt Adresse, Ortsname, Maps-Link oder geteilten Maps-Text in ein
// LocationInfo um. Wirft nie, alles mit Timeout, Ergebnis wird gecacht.

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';
import 'package:geocoding/geocoding.dart' as geo;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/location_info.dart';

/// Ein Treffer der Ortssuche (Freitext → Vorschlagsliste).
class PlaceSuggestion {
  final String title;
  final String? subtitle;
  final double lat;
  final double lng;
  final double zoom;
  const PlaceSuggestion({
    required this.title,
    this.subtitle,
    required this.lat,
    required this.lng,
    required this.zoom,
  });
}

typedef _Addr = ({String? street, String? plz, String? city, double? lat, double? lng});

class LocationResolver {
  LocationResolver._();

  static final geo.Geocoding _geocoder = geo.Geocoding();

  static const _browserUa =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
      '(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';
  static const _nominatimUa = 'OpTimes/1.0 (de.marcel.optimes)';
  static const _countries = {
    'deutschland', 'germany', 'österreich', 'austria', 'schweiz', 'switzerland',
  };

  static final Map<String, LocationInfo> _cache = {};
  static DateTime _lastNominatim = DateTime.fromMillisecondsSinceEpoch(0);

  static final _urlRe = RegExp(r'https?://[^\s]+');
  static final _coordRe =
      RegExp(r'^\s*(-?\d{1,3}(?:\.\d+)?)\s*[,;]\s*(-?\d{1,3}(?:\.\d+)?)\s*$');

  // ───────────────────────────────────────────────────────────────────────────
  // Öffentliche API
  // ───────────────────────────────────────────────────────────────────────────

  /// Enthält der Text einen Maps-Link? (z. B. für die Share-Erkennung)
  static bool containsMapsLink(String text) => _firstMapsUrl(text) != null;

  /// Eingabe → LocationInfo. null, wenn nichts erkannt wurde.
  static Future<LocationInfo?> resolve(String input) async {
    final text = input.trim();
    if (text.isEmpty) return null;
    final cached = _cache[text];
    if (cached != null) return cached;
    try {
      final sw = Stopwatch()..start();
      debugPrint('[RESOLVER] start: $text');
      final info = await _resolveInner(text).timeout(const Duration(seconds: 15));
      debugPrint('[RESOLVER] fertig nach ${sw.elapsedMilliseconds} ms: ${info == null ? "NULL" : "${info.name} / ${info.street} / ${info.city} / ${info.lat},${info.lng}"}');
      if (info != null) _cache[text] = info;
      return info;
    } catch (e) {
      debugPrint('[RESOLVER] resolve Fehler/Timeout: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ablauf
  // ───────────────────────────────────────────────────────────────────────────

  static Future<LocationInfo?> _resolveInner(String text) async {
    final url = _firstMapsUrl(text);
    if (url != null) return _fromMapsLink(text, url);

    // Reine Koordinaten ("48.1371, 11.5754")
    final m = _coordRe.firstMatch(text);
    if (m != null) {
      final lat = double.tryParse(m.group(1)!);
      final lng = double.tryParse(m.group(2)!);
      if (lat != null && lng != null && _validCoords(lat, lng)) {
        return _complete(raw: text, lat: lat, lng: lng);
      }
    }

    // Fremder Link → nicht auswertbar
    if (_urlRe.hasMatch(text)) return null;

    // Adresse oder Ortsname → Vorwärts-Geocoding
    return _complete(raw: text, query: text);
  }

  static Future<LocationInfo?> _fromMapsLink(String text, String url) async {
    // Geteilter Google-Text: Zeilen vor dem Link = Name + Adresse (ohne Netzwerk)
    final lines = _linesBefore(text, url);
    String? name;
    String? addr;
    if (lines.length >= 2) {
      name = lines.first;
      addr = lines.sublist(1).join(', ');
    } else if (lines.length == 1) {
      if (_looksLikeAddress(lines.first)) {
        addr = lines.first;
      } else {
        name = lines.first;
      }
    }

    var finalUrl = url;
    if (_isShort(url)) finalUrl = await _followRedirects(url);

    final p = _parseMapsUrl(finalUrl);
    debugPrint('[RESOLVER] finalUrl: $finalUrl -> lat=${p.lat} lng=${p.lng} name=${p.name} addr=${p.address}');
    name ??= p.name;
    addr ??= p.address;

    // Google-Place-URL: "Name, Straße Nr, PLZ Stadt" -> Name abtrennen,
    // wenn vor dem PLZ-Teil mehr als ein Segment steht und das erste keine Hausnummer hat.
    if (name == null && addr != null) {
      final parts = addr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final plzIdx = parts.indexWhere((e) => RegExp(r'^\d{4,5}\s+').hasMatch(e));
      if (plzIdx >= 2 && !RegExp(r'\d').hasMatch(parts.first)) {
        name = parts.first;
        addr = parts.sublist(1).join(', ');
      }
    }

    return _complete(
      raw: text,
      name: name,
      addressLine: addr,
      lat: p.lat,
      lng: p.lng,
      sourceUrl: url,
    );
  }

  /// Ergänzt fehlende Teile per Geocoding (vorwärts bzw. rückwärts).
  static Future<LocationInfo?> _complete({
    required String raw,
    String? name,
    String? addressLine,
    String? query,
    double? lat,
    double? lng,
    String? sourceUrl,
  }) async {
    String? street, plz, city;
    if (addressLine != null) {
      final a = _parseAddressLine(addressLine);
      street = a.street;
      plz = a.plz;
      city = a.city;
    }

    final q = query ?? addressLine ?? name;
    if ((lat == null || lng == null) && q != null) {
      final g = await _forward(q);
      if (g != null) {
        lat = g.lat;
        lng = g.lng;
        street ??= g.street;
        plz ??= g.plz;
        city ??= g.city;
      }
    }

    if (lat != null && lng != null && street == null && city == null) {
      final g = await _reverse(lat, lng);
      if (g != null) {
        street = g.street;
        plz = g.plz;
        city = g.city;
      }
    }

    // Offiziellen Ortsnamen ergänzen (Botschaft, Rathaus, Bahnhof …), falls noch keiner da ist
    if (name == null) {
      name = await _lookupPlaceName(street: street, plz: plz, city: city, lat: lat, lng: lng);
    }

    if (name != null && (name == street || name == addressLine)) name = null;
    if (lat == null && street == null && city == null && name == null) return null;

    return LocationInfo(
      rawInput: raw,
      name: name,
      street: street,
      postalCode: plz,
      city: city,
      lat: lat,
      lng: lng,
      sourceUrl: sourceUrl,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Links
  // ───────────────────────────────────────────────────────────────────────────

  static String? _firstMapsUrl(String text) {
    for (final m in _urlRe.allMatches(text)) {
      final u = m.group(0)!.replaceAll(RegExp(r'[.,;:)\]>"]+$'), '');
      if (_isMapsUrl(u)) return u;
    }
    return null;
  }

  static bool _isMapsUrl(String u) {
    final uri = Uri.tryParse(u);
    if (uri == null) return false;
    final h = uri.host.toLowerCase();
    final p = uri.path.toLowerCase();
    if (h == 'maps.app.goo.gl' || h == 'maps.apple.com') return true;
    if (h == 'goo.gl' && p.startsWith('/maps')) return true;
    if (h.startsWith('maps.google.')) return true;
    if (RegExp(r'(^|\.)google\.[a-z.]+$').hasMatch(h) && p.startsWith('/maps')) return true;
    return false;
  }

  static bool _isShort(String u) {
    final h = Uri.tryParse(u)?.host.toLowerCase() ?? '';
    return h == 'maps.app.goo.gl' || h == 'goo.gl';
  }

  static List<String> _linesBefore(String text, String url) {
    final idx = text.indexOf(url);
    final before = idx >= 0 ? text.substring(0, idx) : text;
    return before
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && !e.contains('://'))
        .toList();
  }

  /// Kurzlinks per HTTP-Redirect auflösen (manuell, damit die EU-Zustimmungsseite
  /// abgefangen werden kann). Gibt bei Fehlern die zuletzt erreichte URL zurück.
  static Future<String> _followRedirects(String url) async {
    final client = http.Client();
    var uri = Uri.parse(url);
    try {
      for (var i = 0; i < 8; i++) {
        // Zustimmungsseite: das eigentliche Ziel steht im continue-Parameter
        if (uri.host.contains('consent.google.')) {
          final cont = uri.queryParameters['continue'];
          if (cont != null && cont.isNotEmpty) {
            uri = Uri.parse(cont);
          }
          break;
        }
        final req = http.Request('GET', uri)
          ..followRedirects = false
          ..headers['User-Agent'] = _browserUa
          ..headers['Accept-Language'] = 'de-DE,de;q=0.9';
        final resp = await client.send(req).timeout(const Duration(seconds: 6));
        final loc = resp.headers['location'];
        if (resp.statusCode >= 300 && resp.statusCode < 400 && loc != null) {
          await resp.stream.drain<void>().timeout(const Duration(seconds: 3));
          uri = uri.resolve(loc);
          continue;
        }
        break; // Endziel erreicht (Body wird nicht geladen)
      }
    } catch (_) {
      // zuletzt erreichte URL zurückgeben
    } finally {
      client.close();
    }
    return uri.toString();
  }

  /// Koordinaten + Name/Adresse aus einer (aufgelösten) Maps-URL.
  /// Reihenfolge: !3d/!4d (Pin) → @lat,lng → Query-Parameter.
  static ({double? lat, double? lng, String? name, String? address}) _parseMapsUrl(String url) {
    double? lat, lng;
    String? name, address;

    var decoded = url;
    try {
      decoded = Uri.decodeFull(url);
    } catch (e) { debugPrint('[RESOLVER] Catch: $e'); }

    final pin = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)').firstMatch(decoded);
    if (pin != null) {
      lat = double.tryParse(pin.group(1)!);
      lng = double.tryParse(pin.group(2)!);
    }
    if (lat == null || lng == null) {
      final at = RegExp(r'@(-?\d+(?:\.\d+)?),(-?\d+(?:\.\d+)?)').firstMatch(decoded);
      if (at != null) {
        lat = double.tryParse(at.group(1)!);
        lng = double.tryParse(at.group(2)!);
      }
    }

    final uri = Uri.tryParse(url);
    if (uri != null) {
      final qp = uri.queryParameters;
      final isApple = uri.host.toLowerCase().contains('apple');

      // Koordinaten aus Parametern
      if (lat == null || lng == null) {
        for (final k in const ['ll', 'coordinate', 'q', 'query', 'daddr', 'destination']) {
          final v = qp[k];
          if (v == null) continue;
          final m = _coordRe.firstMatch(v);
          if (m != null) {
            lat = double.tryParse(m.group(1)!);
            lng = double.tryParse(m.group(2)!);
            break;
          }
        }
      }

      // Texte aus Parametern
      if (isApple) {
        name = _nz(qp['name']);
        address = _nz(qp['address']);
      }
      final t = _nz(qp['q'] ?? qp['query'] ?? qp['daddr'] ?? qp['destination']);
      if (t != null && !_coordRe.hasMatch(t)) {
        if (_looksLikeAddress(t)) {
          address ??= t;
        } else {
          name ??= t;
        }
      }

      // /maps/place/<Name>/
      final segs = uri.pathSegments;
      final i = segs.indexOf('place');
      if (i >= 0 && i + 1 < segs.length) {
        final s = _nz(_decodeSeg(segs[i + 1]).replaceAll('+', ' '));
        if (s != null && !s.startsWith('@') && !_coordRe.hasMatch(s)) {
          if (_looksLikeAddress(s)) {
            address ??= s;
          } else {
            name ??= s;
          }
        }
      }
    }

    if (lat != null && lng != null && !_validCoords(lat, lng)) {
      lat = null;
      lng = null;
    }
    return (lat: lat, lng: lng, name: name, address: address);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Adress-Parsing
  // ───────────────────────────────────────────────────────────────────────────

  /// "Marienplatz 8, 80331 München, Deutschland" → Straße / PLZ / Stadt.
  static _Addr _parseAddressLine(String line) {
    final parts = line.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.isNotEmpty && _countries.contains(parts.last.toLowerCase())) parts.removeLast();
    if (parts.isEmpty) return _mk();

    final plzRe = RegExp(r'^(?:[A-Z]{1,2}-)?(\d{4,5})\s+(.+)$');
    for (var i = 0; i < parts.length; i++) {
      final m = plzRe.firstMatch(parts[i]);
      if (m != null) {
        return _mk(
          street: i > 0 ? parts[i - 1] : null,
          plz: m.group(1),
          city: m.group(2)!.trim(),
        );
      }
    }
    return _mk(street: parts.first, city: parts.length > 1 ? parts[1] : null);
  }

  static bool _looksLikeAddress(String s) =>
      RegExp(r'\d{5}').hasMatch(s) || (s.contains(',') && RegExp(r'\d').hasMatch(s));

  // ───────────────────────────────────────────────────────────────────────────
  // Geocoding: nativ (geocoding-Paket), Fallback Nominatim
  // ───────────────────────────────────────────────────────────────────────────

  static Future<_Addr?> _forward(String query) async {
    try {
      final locs = await _geocoder.locationFromAddress(query).timeout(const Duration(seconds: 6));
      if (locs.isNotEmpty) {
        final l = locs.first;
        final a = await _reverse(l.latitude, l.longitude);
        return _mk(
          street: a?.street,
          plz: a?.plz,
          city: a?.city,
          lat: l.latitude,
          lng: l.longitude,
        );
      }
    } catch (e) { debugPrint('[RESOLVER] Catch: $e'); }

    try {
      final j = await _nominatim(Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '1',
        'accept-language': 'de',
      }));
      if (j != null) {
        final lat = double.tryParse('${j['lat']}');
        final lng = double.tryParse('${j['lon']}');
        if (lat != null && lng != null) {
          final a = _fromNominatimAddress(j['address']);
          return _mk(street: a.street, plz: a.plz, city: a.city, lat: lat, lng: lng);
        }
      }
    } catch (e) { debugPrint('[RESOLVER] Catch: $e'); }
    return null;
  }

  static Future<_Addr?> _reverse(double lat, double lng) async {
    try {
      final pms = await _geocoder.placemarkFromCoordinates(lat, lng).timeout(const Duration(seconds: 6));
      if (pms.isNotEmpty) {
        final p = pms.first;
        final t = (p.thoroughfare ?? '').trim();
        final n = (p.subThoroughfare ?? '').trim();
        String? street;
        if (t.isNotEmpty) {
          street = n.isNotEmpty ? '$t $n' : t;
        } else {
          street = _nz(p.street);
        }
        final city = _nz(p.locality) ?? _nz(p.subAdministrativeArea);
        if (street != null || city != null) {
          return _mk(street: street, plz: _nz(p.postalCode), city: city, lat: lat, lng: lng);
        }
      }
    } catch (e) { debugPrint('[RESOLVER] Catch: $e'); }

    try {
      final j = await _nominatim(Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '$lat',
        'lon': '$lng',
        'format': 'jsonv2',
        'addressdetails': '1',
        'accept-language': 'de',
      }));
      if (j != null) {
        final a = _fromNominatimAddress(j['address']);
        if (a.street != null || a.city != null) {
          return _mk(street: a.street, plz: a.plz, city: a.city, lat: lat, lng: lng);
        }
      }
    } catch (e) { debugPrint('[RESOLVER] Catch: $e'); }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Ortsname (Botschaft, Reichstag, Bahnhof …) per Nominatim
  // ───────────────────────────────────────────────────────────────────────────

  /// OSM-Kategorie → erlaubte Typen ('*' = jeder Typ). Nur diese gelten als
  /// "wichtiger Ort". Zum Erweitern einfach Einträge ergänzen.
  static const Map<String, Set<String>> _notablePlaces = {
    'amenity': {
      'embassy', 'townhall', 'courthouse', 'police', 'fire_station', 'hospital',
      'school', 'university', 'college', 'library', 'theatre', 'cinema',
      'arts_centre', 'community_centre', 'post_office', 'prison', 'place_of_worship',
    },
    'office': {'government', 'diplomatic', 'administrative'},
    'tourism': {'museum', 'attraction', 'hotel', 'gallery', 'zoo'},
    'historic': {'*'},
    'railway': {'station'},
    'public_transport': {'station'},
    'aeroway': {'terminal', 'aerodrome'},
    'leisure': {'stadium'},
    'man_made': {'tower'},
  };

  /// Gewöhnliche Wohn-/Nebengebäude zählen nicht, benannte sonstige Gebäude schon.
  static const Set<String> _plainBuildings = {
    'house', 'apartments', 'residential', 'detached', 'semidetached_house',
    'terrace', 'garage', 'garages', 'shed', 'roof', 'hut', 'cabin',
  };

  /// Ausgabe nur im Debug-Modus (erscheint im Terminal bei `flutter run`).
  static void _log(String message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }

  static bool _isNotable(String? category, String? type) {
    if (category == null) return false;
    if (category == 'building') return type == null || !_plainBuildings.contains(type);
    final allowed = _notablePlaces[category];
    if (allowed == null) return false;
    return allowed.contains('*') || (type != null && allowed.contains(type));
  }

  static double _distanceM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(lat2 - lat1);
    final dLng = rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(a));
  }

  /// "Platz der Republik 1" → (road: "platzderrepublik", nr: "1")
  static ({String road, String nr})? _splitStreet(String street) {
    final m = RegExp(r'^(.*?)[\s,]+(\d+\s*[a-zA-Z]?)$').firstMatch(street.trim());
    if (m == null) return null;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), '');
    return (road: norm(m.group(1)!), nr: norm(m.group(2)!));
  }

  /// Treffer der Adresssuche: Name nur, wenn Straße UND Hausnummer passen.
  static String? _acceptByAddress(Map<String, dynamic> j, String street) {
    final name = _nz(j['name']?.toString());
    final cat = j['category']?.toString();
    final type = j['type']?.toString();
    _log('📍 Namenssuche (Adresse): ${name ?? "-"} [$cat/$type]');
    if (name == null || !_isNotable(cat, type)) return null;

    final want = _splitStreet(street);
    final a = j['address'];
    if (want == null || a is! Map) return null;
    String norm(String? s) => (s ?? '').toLowerCase().replaceAll(RegExp(r'\s+'), '');
    final gotRoad = norm(a['road']?.toString());
    final gotNr = norm(a['house_number']?.toString());
    if (gotNr != want.nr) return null;
    if (gotRoad.isEmpty || !(gotRoad.contains(want.road) || want.road.contains(gotRoad))) return null;
    if (name.toLowerCase() == street.toLowerCase()) return null;
    return name;
  }

  /// Treffer der Koordinatensuche: Punkt liegt im Gebäudeumriss oder ist max. 60 m entfernt.
  static String? _acceptByPoint(Map<String, dynamic>? j, double lat, double lng, String? street) {
    if (j == null) return null;
    final name = _nz(j['name']?.toString());
    final cat = j['category']?.toString();
    final type = j['type']?.toString();
    _log('📍 Namenssuche (Punkt): ${name ?? "-"} [$cat/$type]');
    if (name == null || !_isNotable(cat, type)) return null;

    var inside = false;
    final bb = j['boundingbox'];
    if (bb is List && bb.length == 4) {
      final s = double.tryParse('${bb[0]}');
      final n = double.tryParse('${bb[1]}');
      final w = double.tryParse('${bb[2]}');
      final e = double.tryParse('${bb[3]}');
      if (s != null && n != null && w != null && e != null) {
        const pad = 0.0003;
        inside = lat >= s - pad && lat <= n + pad && lng >= w - pad && lng <= e + pad;
      }
    }
    if (!inside) {
      final rLat = double.tryParse('${j['lat']}');
      final rLng = double.tryParse('${j['lon']}');
      if (rLat == null || rLng == null) return null;
      if (_distanceM(lat, lng, rLat, rLng) > 60) return null;
      final a = j['address'];
      if (a is Map && street != null) {
        final road = _nz(a['road']?.toString());
        if (road != null && !street.toLowerCase().contains(road.toLowerCase())) return null;
      }
    }
    if (street != null && name.toLowerCase() == street.toLowerCase()) return null;
    return name;
  }

  static Future<List<Map<String, dynamic>>> _nominatimList(Uri uri) async {
    await _throttle();
    final resp = await http
        .get(uri, headers: {'User-Agent': _nominatimUa, 'Accept-Language': 'de'})
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) return const [];
    final data = jsonDecode(resp.body);
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) return [Map<String, dynamic>.from(data)];
    return const [];
  }

  static Future<String?> _lookupPlaceName({
    String? street,
    String? plz,
    String? city,
    double? lat,
    double? lng,
  }) async {
    // 1. Über die Adresse suchen: liefert bei benannten Gebäuden direkt den Namen
    if (street != null && RegExp(r'\d').hasMatch(street)) {
      try {
        final cityPart = [plz, city].where((e) => e != null && e.trim().isNotEmpty).join(' ');
        final q = [street, cityPart].where((e) => e.isNotEmpty).join(', ');
        final results = await _nominatimList(Uri.https('nominatim.openstreetmap.org', '/search', {
          'q': q,
          'format': 'jsonv2',
          'addressdetails': '1',
          'limit': '5',
          'accept-language': 'de',
        }));
        for (final j in results) {
          final n = _acceptByAddress(j, street);
          if (n != null) return n;
        }
      } catch (e) {
        _log('📍 Namenssuche (Adresse) Fehler: $e');
      }
    }

    // 2. Über die Koordinaten: Objekt an dieser Stelle
    if (lat != null && lng != null) {
      try {
        final j = await _nominatim(Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'lat': '$lat',
          'lon': '$lng',
          'format': 'jsonv2',
          'zoom': '18',
          'addressdetails': '1',
          'accept-language': 'de',
        }));
        final n = _acceptByPoint(j, lat, lng, street);
        if (n != null) return n;
      } catch (e) {
        _log('📍 Namenssuche (Punkt) Fehler: $e');
      }
    }
    return null;
  }

  /// Freitextsuche für die Kartenauswahl ("Berlin", "Hauptbahnhof Potsdam" …).
  static Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 2) return const [];
    try {
      final results = await _nominatimList(Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': q,
        'format': 'jsonv2',
        'addressdetails': '1',
        'limit': '6',
        'accept-language': 'de',
      }));
      final out = <PlaceSuggestion>[];
      for (final j in results) {
        final lat = double.tryParse('${j['lat']}');
        final lng = double.tryParse('${j['lon']}');
        if (lat == null || lng == null) continue;
        final parts = (j['display_name']?.toString() ?? '')
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final name = _nz(j['name']?.toString()) ?? (parts.isNotEmpty ? parts.first : q);
        final rest = (parts.isNotEmpty && parts.first == name) ? parts.skip(1) : parts;
        final sub = rest.take(3).join(', ');
        final cat = j['category']?.toString();
        final type = j['type']?.toString();
        // Städte/Regionen weit herauszoomen, konkrete Orte nah
        final isArea = cat == 'boundary' ||
            (cat == 'place' && !const {'house', 'building', 'square', 'address'}.contains(type));
        out.add(PlaceSuggestion(
          title: name,
          subtitle: sub.isEmpty ? null : sub,
          lat: lat,
          lng: lng,
          zoom: isArea ? 12 : 17,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Nominatim-Nutzungsrichtlinie: max. 1 Anfrage/s, eigener User-Agent.
  static Future<void> _throttle() async {
    final next = _lastNominatim.add(const Duration(seconds: 1));
    final now = DateTime.now();
    if (next.isAfter(now)) {
      _lastNominatim = next;
      await Future.delayed(next.difference(now));
    } else {
      _lastNominatim = now;
    }
  }

  static Future<Map<String, dynamic>?> _nominatim(Uri uri) async {
    await _throttle();
    final resp = await http
        .get(uri, headers: {'User-Agent': _nominatimUa, 'Accept-Language': 'de'})
        .timeout(const Duration(seconds: 6));
    debugPrint('[RESOLVER] nominatim ${uri.path} -> ${resp.statusCode}');
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    if (data is List) {
      return data.isEmpty ? null : Map<String, dynamic>.from(data.first as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }

  static _Addr _fromNominatimAddress(dynamic a) {
    if (a is! Map) return _mk();
    String? g(String k) => _nz(a[k]?.toString());
    final road = g('road') ?? g('pedestrian') ?? g('footway') ?? g('path');
    final nr = g('house_number');
    final street = road == null ? null : (nr != null ? '$road $nr' : road);
    final city = g('city') ?? g('town') ?? g('village') ?? g('municipality') ?? g('hamlet');
    return _mk(street: street, plz: g('postcode'), city: city);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Helfer
  // ───────────────────────────────────────────────────────────────────────────

  static _Addr _mk({String? street, String? plz, String? city, double? lat, double? lng}) =>
      (street: street, plz: plz, city: city, lat: lat, lng: lng);

  static String _decodeSeg(String seg) {
    try {
      return seg.contains('%') ? Uri.decodeComponent(seg) : seg;
    } catch (_) {
      return seg;
    }
  }

  static String? _nz(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  static bool _validCoords(double lat, double lng) =>
      lat.abs() <= 90 && lng.abs() <= 180 && !(lat == 0 && lng == 0);
}