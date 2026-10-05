// lib/models/location_info.dart
// Strukturierter Ort eines Ereignisses: Adresse + optionale Koordinaten.

class LocationInfo {
  /// Originaleingabe des Nutzers (Adresse, Link oder geteilter Text).
  final String rawInput;

  /// Optionaler Ortsname, z. B. "Rathaus".
  final String? name;

  /// Straße + Hausnummer.
  final String? street;
  final String? postalCode;
  final String? city;
  final double? lat;
  final double? lng;

  /// Ursprünglicher Maps-Link (falls vorhanden).
  final String? sourceUrl;

  const LocationInfo({
    required this.rawInput,
    this.name,
    this.street,
    this.postalCode,
    this.city,
    this.lat,
    this.lng,
    this.sourceUrl,
  });

  bool get hasCoords => lat != null && lng != null;

  /// Zeile 1: Straße + Hausnummer.
  String get line1 => (street ?? '').trim();

  /// Zeile 2: PLZ + Stadt.
  String get line2 => [postalCode, city]
      .where((e) => e != null && e.trim().isNotEmpty)
      .map((e) => e!.trim())
      .join(' ');

  bool get hasAddress => line1.isNotEmpty || line2.isNotEmpty;

  /// Einzeilige, saubere Adresse (wird ins Textfeld geschrieben).
  String get singleLine => [line1, line2].where((e) => e.isNotEmpty).join(', ');

  Map<String, dynamic> toJson() => {
        'rawInput': rawInput,
        if (name != null) 'name': name,
        if (street != null) 'street': street,
        if (postalCode != null) 'postalCode': postalCode,
        if (city != null) 'city': city,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (sourceUrl != null) 'sourceUrl': sourceUrl,
      };

  /// Fehlertolerant: null bei fehlenden oder kaputten Daten.
  static LocationInfo? tryFromJson(dynamic j) {
    if (j is! Map) return null;
    try {
      String? s(String k) {
        final v = j[k];
        if (v is! String) return null;
        final t = v.trim();
        return t.isEmpty ? null : t;
      }

      return LocationInfo(
        rawInput: (j['rawInput'] as String?) ?? '',
        name: s('name'),
        street: s('street'),
        postalCode: s('postalCode'),
        city: s('city'),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        sourceUrl: s('sourceUrl'),
      );
    } catch (_) {
      return null;
    }
  }
}