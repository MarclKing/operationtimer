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

class TravelModeService {
  TravelModeService._();
  static final _box = Hive.box('einstellungen');

  static const _kEnabled   = 'reisemodus_enabled';
  static const _kActiveTz  = 'reisemodus_active_tz';
  static const _kHomeTz    = 'reisemodus_home_tz';
  static const _kPendingTz = 'reisemodus_pending_tz';
  static const _kIgnoredTz = 'reisemodus_ignored_tz';
  static const _kArmed     = 'reisemodus_switch_armed';
  static const _kLastPhys  = 'reisemodus_last_device_tz';
  static const _kDebugTz   = 'reisemodus_debug_override_tz'; // ← NEU

  /// Liest die Geräte-Zeitzone sicher aus. Nutzt einen Debug-Override,
  /// falls gesetzt (zum manuellen Testen). Fängt Plattformen ohne
  /// flutter_timezone-Support ab (z.B. Flutter Web) statt zu crashen.
  static Future<String> _detectDeviceTz() async {
    final override = _box.get(_kDebugTz) as String?;
    if (override != null) return override;
    try {
      return await FlutterTimezone.getLocalTimezone();
    } catch (_) {
      // Web/nicht unterstützte Plattform → grober Fallback per UTC-Offset
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
        'Pending': pendingTzId ?? '—',
        'Ignoriert': (_box.get(_kIgnoredTz) as String?) ?? '—',
        'Scharf (armed)': (_box.get(_kArmed, defaultValue: false) as bool).toString(),
        'Debug-Override': debugOverrideTz ?? 'aus (echtes Gerät)',
        'Letzte erkannte Geräte-Zone': lastKnownDeviceTz ?? '—',
      };

  static bool get isEnabled => _box.get(_kEnabled, defaultValue: false) as bool;

  static String get _fallbackTz => 'Europe/Berlin';

  static String get activeTzId =>
      _box.get(_kActiveTz, defaultValue: _fallbackTz) as String;

  static String? get pendingTzId => _box.get(_kPendingTz) as String?;

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
  /// Wird beim Umschalten des Toggles in den Settings aufgerufen.
  /// Setzt die aktuelle Geräte-Zone als Start-/Home-Zone.
  static Future<void> enableAndSeed() async {
    final deviceTz = await _detectDeviceTz(); // ← wirft jetzt nie mehr
    await _box.put(_kEnabled, true);
    await _box.put(_kActiveTz, deviceTz);
    await _box.put(_kHomeTz, deviceTz);
    await _box.put(_kPendingTz, null);
    await _box.put(_kIgnoredTz, null);
    await _box.put(_kArmed, false);
  }

  static Future<void> disable() async => _box.put(_kEnabled, false);

  // ── Erkennung + Dedupe ───────────────────────────────────────────────
  /// Zentrale Prüf-Methode. Von allen Triggern (App-Resume, Screen-Open,
  /// Zeitpicker-Open) aufgerufen. Gibt die erkannte Zone zurück, NUR wenn
  /// ein Bestätigungs-Dialog gezeigt werden soll.
  static Future<String?> checkForTimeZoneChange() async {
    if (!isEnabled) return null;

    final deviceTz = await _detectDeviceTz();
    await _box.put(_kLastPhys, deviceTz);

    if (deviceTz == activeTzId) return null;   // schon korrekt
    if (deviceTz == pendingTzId) return null;  // schon bestätigt, wartet
    if (deviceTz == (_box.get(_kIgnoredTz) as String?)) return null; // schon abgelehnt

    return deviceTz;
  }

  static void confirmDetectedTz(String tzId) {
    _box.put(_kPendingTz, tzId);
    _box.put(_kIgnoredTz, null);
  }

  static void ignoreDetectedTz(String tzId) {
    _box.put(_kIgnoredTz, tzId);
  }

  /// Manuelle Auswahl überschreibt direkt die pending-Zone (gleicher
  /// Mechanismus wie eine bestätigte Auto-Erkennung).
  static void setPendingTzManually(String tzId) {
    _box.put(_kPendingTz, tzId);
    _box.put(_kIgnoredTz, null);
  }

  // ── Arm/Resolve-Mechanik (siehe Beispiel-Regel) ─────────────────────
  /// Wird aufgerufen, wenn ein Eintrag mit echtem Dienstende ('gehen'
  /// nicht leer) gespeichert wird.
  static void armSwitchIfNeeded() {
    if (isEnabled && pendingTzId != null) {
      _box.put(_kArmed, true);
    }
  }

  /// Wird aufgerufen, BEVOR ein neuer Dienst (neues 'kommen') gespeichert
  /// wird. Wendet ggf. den gemerkten Wechsel an und gibt die für DIESEN
  /// Eintrag zu verwendende Zone zurück.
  static TzInfo resolveTzForNewEntry() {
    final armed = _box.get(_kArmed, defaultValue: false) as bool;
    final pending = pendingTzId;
    if (isEnabled && armed && pending != null) {
      _box.put(_kActiveTz, pending);
      _box.put(_kPendingTz, null);
      _box.put(_kArmed, false);
      return TzInfo(pending, offsetLabelFor(pending));
    }
    return activeTz;
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

  // ── Manuelle Zonen-Suche (Freitext, wie WeatherService.verifyCityName) ─
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