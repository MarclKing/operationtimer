import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;

class TzInfo {
  final String id;
  final String offsetLabel; // z.B. 'UTC+2'
  const TzInfo(this.id, this.offsetLabel);
}

/// Reisemodus — EINFACHES Modell:
/// Es gibt genau EINE "aktive Zone" (activeTzId). Sie ändert sich sofort,
/// sobald irgendwo eine Zone ausgewählt wird (Kommen-Chip, Gehen-Chip,
/// Settings). Kein Pending/Armed/Ignored mehr — jeder Eintrag bekommt
/// seine Kommen-Zone direkt aus der aktiven Zone (oder einem expliziten
/// Override), und nur bei Kommen-Zone ≠ Gehen-Zone wird umgerechnet.
class TravelModeService {
  TravelModeService._();
  static final _box = Hive.box('einstellungen');

  static const _kEnabled  = 'reisemodus_enabled';
  static const _kActiveTz = 'reisemodus_active_tz';
  static const _kHomeTz   = 'reisemodus_home_tz';
  static const _kLastPhys = 'reisemodus_last_device_tz';
  static const _kDebugTz  = 'reisemodus_debug_override_tz';
  static const _kRecentZones = 'reisemodus_recent_zones';

  /// Liest die Geräte-Zeitzone sicher aus. Nutzt einen Debug-Override,
  /// falls gesetzt. Fängt Plattformen ohne flutter_timezone-Support ab.
  static Future<String> _detectDeviceTz() async {
    final override = _box.get(_kDebugTz) as String?;
    if (override != null) return override;
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      final offsetH = DateTime.now().timeZoneOffset.inHours;
      const map = {
        -8: 'America/Los_Angeles', -7: 'America/Denver', -6: 'America/Chicago',
        -5: 'America/New_York', 0: 'Europe/London', 1: 'Europe/Berlin',
        2: 'Europe/Helsinki', 9: 'Asia/Tokyo',
      };
      return map[offsetH] ?? 'Europe/Berlin';
    }
  }

  // ── Debug: manuelle Zeitzonen-Simulation zum Testen ─────────────────
  static String? get debugOverrideTz => _box.get(_kDebugTz) as String?;

  static void setDebugOverrideTz(String? tzId) => _box.put(_kDebugTz, tzId);

  static Map<String, String> get debugSnapshot => {
        'Aktiviert': isEnabled.toString(),
        'Aktive Zone': activeTzId,
        'Home-Zone': (_box.get(_kHomeTz) as String?) ?? '—',
        'Debug-Override': debugOverrideTz ?? 'aus (echtes Gerät)',
        'Letzte erkannte Geräte-Zone': lastKnownDeviceTz ?? '—',
      };

  static bool get isEnabled => _box.get(_kEnabled, defaultValue: false) as bool;

  static String get _fallbackTz => 'Europe/Berlin';

  /// Die aktuell gültige Zone. Wird für neue Einträge als Kommen-Zone
  /// verwendet, sofern kein expliziter Override übergeben wird.
  static String get activeTzId =>
      _box.get(_kActiveTz, defaultValue: _fallbackTz) as String;

  static String? get lastKnownDeviceTz => _box.get(_kLastPhys) as String?;

  /// Formatierter UTC-Offset-Label für eine IANA-Zone, z.B. 'UTC+2'.
  static String offsetLabelFor(String tzId) {
    try {
      final loc = tz.getLocation(tzId);
      final now = tz.TZDateTime.now(loc);
      final offset = now.timeZoneOffset;
      final h = offset.inHours;
      final m = offset.inMinutes.remainder(60).abs();
      final sign = h >= 0 ? '+' : '-';
      return m == 0 ? 'UTC$sign${h.abs()}' : 'UTC$sign${h.abs()}:${m.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  static TzInfo get activeTz => TzInfo(activeTzId, offsetLabelFor(activeTzId));

  // ── Aktivierung ──────────────────────────────────────────────────────
  /// Setzt die aktuelle Geräte-Zone als Start-/Home-Zone.
  static Future<void> enableAndSeed() async {
    final deviceTz = await _detectDeviceTz();
    await _box.put(_kEnabled, true);
    await _box.put(_kActiveTz, deviceTz);
    await _box.put(_kHomeTz, deviceTz);
  }

  static Future<void> disable() async => _box.put(_kEnabled, false);

  // ── Erkennung ────────────────────────────────────────────────────────
  /// Vergleicht die Geräte-Zone mit der aktiven Zone. Gibt die erkannte
  /// Zone zurück, NUR wenn sie von der aktiven Zone abweicht — dient
  /// ausschließlich dazu, sie im Zonen-Picker oben vorzuschlagen
  /// (kein Dialog, keine Bestätigung nötig).
  static Future<String?> checkForTimeZoneChange() async {
    if (!isEnabled) return null;
    final deviceTz = await _detectDeviceTz();
    await _box.put(_kLastPhys, deviceTz);
    if (deviceTz == activeTzId) return null;
    return deviceTz;
  }

  /// Setzt die aktive Zone direkt — wird immer aufgerufen, wenn der
  /// Nutzer irgendwo (Kommen-Chip, Gehen-Chip, Settings) eine Zone
  /// auswählt. Das ist die einzige Stelle, an der sich die aktive Zone
  /// ändert.
  static Future<void> setActiveTz(String tzId) async {
    await _box.put(_kActiveTz, tzId);
    await registerZoneUsage(tzId);
  }

  // ── Zonen-Historie für Picker-Vorschläge ────────────────────────────
  static List<String> get recentZoneIds {
    final raw = _box.get(_kRecentZones);
    if (raw is List) return raw.cast<String>();
    return [];
  }

  static Future<void> registerZoneUsage(String tzId) async {
    final list = List<String>.from(recentZoneIds);
    list.remove(tzId);
    list.insert(0, tzId);
    if (list.length > 8) list.removeRange(8, list.length);
    await _box.put(_kRecentZones, list);
  }

  /// Vorgeschlagene Zonen für Kommen-/Gehen-Picker: erkannte Geräte-Zone
  /// zuerst (falls abweichend), dann aktive Zone, Home-Zone, Historie.
  static List<String> suggestedZoneIds() {
    final result = <String>[];
    void add(String? id) {
      if (id != null && id.isNotEmpty && !result.contains(id)) result.add(id);
    }
    final detected = lastKnownDeviceTz;
    if (detected != null && detected != activeTzId) add(detected);
    add(activeTzId);
    add(_box.get(_kHomeTz) as String?);
    for (final id in recentZoneIds) {
      add(id);
    }
    return result;
  }

  // ── UTC-Umrechnung für korrekte Dauer-Berechnung ────────────────────
  static String? toUtcIso(DateTime datum, String hhmm, String tzId) {
    if (hhmm.isEmpty || hhmm == '--:--') return null;
    try {
      final parts = hhmm.split(':');
      final loc = tz.getLocation(tzId);
      final local = tz.TZDateTime(loc, datum.year, datum.month, datum.day,
          int.parse(parts[0]), int.parse(parts[1]));
      return local.toUtc().toIso8601String();
    } catch (_) {
      return null;
    }
  }

  // ── Zonen-Umrechnung für Reisemodus (Kommen-Zone ≠ Gehen-Zone) ──────

  static ({String time, int dayShift})? convertTimeAcrossZones({
    required DateTime datum,
    required String hhmm,
    required String fromTzId,
    required String toTzId,
  }) {
    if (hhmm.isEmpty || hhmm == '--:--') return null;
    try {
      final parts = hhmm.split(':');
      final fromLoc = tz.getLocation(fromTzId);
      final fromDt = tz.TZDateTime(fromLoc, datum.year, datum.month, datum.day,
          int.parse(parts[0]), int.parse(parts[1]));

      final toLoc = tz.getLocation(toTzId);
      final toDt = tz.TZDateTime.from(fromDt, toLoc);

      final fromDateOnly = DateTime(datum.year, datum.month, datum.day);
      final toDateOnly = DateTime(toDt.year, toDt.month, toDt.day);
      final dayShift = toDateOnly.difference(fromDateOnly).inDays;

      final time =
          '${toDt.hour.toString().padLeft(2, '0')}:${toDt.minute.toString().padLeft(2, '0')}';
      return (time: time, dayShift: dayShift);
    } catch (_) {
      return null;
    }
  }

  /// Tatsächliche Dienstdauer bei Kommen/Gehen in unterschiedlichen Zonen.
  static Duration? actualDuration({
    required DateTime datum,
    required String kommenHhmm,
    required String kommenTzId,
    required String gehenHhmm,
    required String gehenTzId,
  }) {
    if (kommenHhmm.isEmpty || gehenHhmm.isEmpty) return null;
    try {
      final kParts = kommenHhmm.split(':');
      final kLoc = tz.getLocation(kommenTzId);
      final kDt = tz.TZDateTime(kLoc, datum.year, datum.month, datum.day,
          int.parse(kParts[0]), int.parse(kParts[1]));

      final gParts = gehenHhmm.split(':');
      final gLoc = tz.getLocation(gehenTzId);
      var gDt = tz.TZDateTime(gLoc, datum.year, datum.month, datum.day,
          int.parse(gParts[0]), int.parse(gParts[1]));

      if (gDt.toUtc().isBefore(kDt.toUtc())) {
        gDt = tz.TZDateTime(gLoc, datum.year, datum.month, datum.day + 1,
            int.parse(gParts[0]), int.parse(gParts[1]));
      }

      return gDt.toUtc().difference(kDt.toUtc());
    } catch (_) {
      return null;
    }
  }

  /// Rechnet die roh eingetragene Gehen-Zeit (in gehenTzId) auf die
  /// Kommen-Zone (kommenTzId) um.
  static String? convertGehenToKommenTz({
    required DateTime datum,
    required String kommenHhmm,
    required String kommenTzId,
    required String gehenHhmm,
    required String gehenTzId,
  }) {
    if (kommenHhmm.isEmpty || gehenHhmm.isEmpty) return null;
    try {
      final kParts = kommenHhmm.split(':');
      final kLoc = tz.getLocation(kommenTzId);
      final kDt = tz.TZDateTime(kLoc, datum.year, datum.month, datum.day,
          int.parse(kParts[0]), int.parse(kParts[1]));

      final gParts = gehenHhmm.split(':');
      final gLoc = tz.getLocation(gehenTzId);
      var gDt = tz.TZDateTime(gLoc, datum.year, datum.month, datum.day,
          int.parse(gParts[0]), int.parse(gParts[1]));

      if (gDt.toUtc().isBefore(kDt.toUtc())) {
        gDt = tz.TZDateTime(gLoc, datum.year, datum.month, datum.day + 1,
            int.parse(gParts[0]), int.parse(gParts[1]));
      }

      final converted = tz.TZDateTime.from(gDt, kLoc);
      return '${converted.hour.toString().padLeft(2, '0')}:${converted.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return null;
    }
  }

  // ── Manuelle Zonen-Suche (Freitext) ─────────────────────────────────
  static Future<({String tzId, String displayLabel})?> verifyLocationTimeZone(
      String query) async {
    try {
      final geoUri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}&format=json&limit=1&addressdetails=1',
      );
      final geoResp = await http
          .get(geoUri, headers: {'User-Agent': 'OpTimes/1.0'})
          .timeout(const Duration(seconds: 8));
      if (geoResp.statusCode != 200) return null;
      final geoList = jsonDecode(geoResp.body) as List;
      if (geoList.isEmpty) return null;

      final result = geoList[0] as Map<String, dynamic>;
      final lat = double.parse(result['lat'] as String);
      final lon = double.parse(result['lon'] as String);

      final address = result['address'] as Map<String, dynamic>?;
      final place = address?['city'] ?? address?['town'] ?? address?['village'];
      final country = address?['country'];
      final displayLabel = (place != null && country != null)
          ? '$place, $country'
          : (result['display_name'] as String).split(',').take(2).map((s) => s.trim()).join(', ');

      final tzUri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon&current=temperature_2m&timezone=auto',
      );
      final tzResp = await http.get(tzUri).timeout(const Duration(seconds: 8));
      if (tzResp.statusCode != 200) return null;
      final tzJson = jsonDecode(tzResp.body) as Map<String, dynamic>;
      final tzId = tzJson['timezone'] as String?;
      if (tzId == null) return null;

      return (tzId: tzId, displayLabel: displayLabel);
    } catch (_) {
      return null;
    }
  }
}