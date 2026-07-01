import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';
import 'package:geolocator/geolocator.dart';

class WeatherData {
  final double tempC;
  final double feelsLikeC;
  final int weatherCode;
  final double precipitationMm;
  final double windKmh;
  final String city;       // 'GPS' wenn per Standort
  final DateTime fetchedAt;
  final DateTime? sunrise;   // Sonnenaufgang
  final DateTime? sunset;    // Sonnenuntergang
  final bool isDay;          // Tag/Nacht-Status
  final int? humidityPercent;   // Luftfeuchtigkeit in %
   final double? dailyMaxTempC;
  final int? dailyWeatherCode;
  final double? tomorrowMaxTempC;      // NEU
  final int? tomorrowWeatherCode;  

  const WeatherData({
    required this.tempC,
    required this.feelsLikeC,
    required this.weatherCode,
    required this.precipitationMm,
    required this.windKmh,
    required this.city,
    required this.fetchedAt,
    this.sunrise,
    this.sunset,
    required this.isDay,
    this.humidityPercent,
    this.dailyMaxTempC,
    this.dailyWeatherCode,
    this.tomorrowMaxTempC,             // NEU
    this.tomorrowWeatherCode,
  });

  String get icon {
    if (!isDay) {
      // Nacht-Icons
      if (weatherCode == 0) return '🌙';
      if (weatherCode <= 2) return '🌙';
      if (weatherCode == 3) return '☁️';
      if (weatherCode <= 49) return '🌫️';
      if (weatherCode <= 59) return '🌦️';
      if (weatherCode <= 69) return '🌧️';
      if (weatherCode <= 79) return '❄️';
      if (weatherCode <= 82) return '🌧️';
      if (weatherCode <= 86) return '🌨️';
      if (weatherCode <= 99) return '⛈️';
      return '🌙';
    }
    // Tag-Icons
    if (weatherCode == 0) return '☀️';
    if (weatherCode <= 2) return '⛅';
    if (weatherCode == 3) return '☁️';
    if (weatherCode <= 49) return '🌫️';
    if (weatherCode <= 59) return '🌦️';
    if (weatherCode <= 69) return '🌧️';
    if (weatherCode <= 79) return '❄️';
    if (weatherCode <= 82) return '🌧️';
    if (weatherCode <= 86) return '🌨️';
    if (weatherCode <= 99) return '⛈️';
    return '⛅';
  }

  String get tempStr => '${tempC.round()}°';
  String get feelsLikeStr => '${feelsLikeC.round()}°';
  String get windStr => '${windKmh.round()} km/h';
  String get precipStr => precipitationMm > 0
      ? '${precipitationMm.toStringAsFixed(1)} mm'
      : 'kein';
  String get humidityStr => humidityPercent != null ? '$humidityPercent%' : '—';

  double get forecastTempC => dailyMaxTempC ?? tempC;
  int get forecastWeatherCode => dailyWeatherCode ?? weatherCode;

  bool get isStale =>
      DateTime.now().difference(fetchedAt).inMinutes > 30;

  bool get isGps => city == 'GPS';

  /// Gibt die nächste relevante Sonnen-Zeit zurück (Aufgang oder Untergang)
  /// und ob es Aufgang (true) oder Untergang (false) ist.
  (DateTime time, bool isSunrise)? get nextSunEvent {
    if (sunrise == null || sunset == null) return null;
    final now = DateTime.now();
    if (now.isBefore(sunrise!)) return (sunrise!, true);
    if (now.isBefore(sunset!)) return (sunset!, false);
    // Beide vorbei → nächster Aufgang morgen
    return (sunrise!.add(const Duration(days: 1)), true);
  }

  Map<String, dynamic> toJson() => {
    'tempC': tempC,
    'feelsLikeC': feelsLikeC,
    'weatherCode': weatherCode,
    'precipitationMm': precipitationMm,
    'windKmh': windKmh,
    'city': city,
    'fetchedAt': fetchedAt.toIso8601String(),
    'sunrise': sunrise?.toIso8601String(),
    'sunset': sunset?.toIso8601String(),
    'isDay': isDay,
    'humidityPercent': humidityPercent,
    'dailyMaxTempC': dailyMaxTempC,
    'dailyWeatherCode': dailyWeatherCode,
    'tomorrowMaxTempC': tomorrowMaxTempC,      // NEU
    'tomorrowWeatherCode': tomorrowWeatherCode,
  };

  factory WeatherData.fromJson(Map<String, dynamic> j) => WeatherData(
    tempC: (j['tempC'] as num).toDouble(),
    feelsLikeC: (j['feelsLikeC'] as num? ?? j['tempC'] as num).toDouble(),
    weatherCode: j['weatherCode'] as int,
    precipitationMm: (j['precipitationMm'] as num? ?? 0).toDouble(),
    windKmh: (j['windKmh'] as num? ?? 0).toDouble(),
    city: j['city'] as String,
    fetchedAt: DateTime.parse(j['fetchedAt'] as String),
    sunrise: j['sunrise'] != null ? DateTime.parse(j['sunrise'] as String) : null,
    sunset: j['sunset'] != null ? DateTime.parse(j['sunset'] as String) : null,
    isDay: (j['isDay'] as bool? ?? true),
    humidityPercent: j['humidityPercent'] as int?,
    dailyMaxTempC: (j['dailyMaxTempC'] as num?)?.toDouble(),
    dailyWeatherCode: j['dailyWeatherCode'] as int?,
    tomorrowMaxTempC: (j['tomorrowMaxTempC'] as num?)?.toDouble(),    // NEU
    tomorrowWeatherCode: j['tomorrowWeatherCode'] as int?,  
  );
}

class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  static const _cacheKey = 'weather_cache';

  WeatherData? _cached;
  bool _fetching = false;
  DateTime? _lastFailedAttempt;

  /// Wird bei jeder Cache-Invalidierung hochgezählt. Listener (z.B. HomeScreen)
  /// können darauf reagieren, um automatisch neu zu laden.
  final ValueNotifier<int> refreshSignal = ValueNotifier(0);   // ← NEU

  WeatherData? get cached {
    if (_cached != null) return _cached;
    try {
      final box = Hive.box('einstellungen');
      final raw = box.get(_cacheKey) as String?;
      if (raw != null) {
        _cached = WeatherData.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {}
    return _cached;
  }

  /// Löscht den In-Memory Cache, damit beim nächsten fetchIfNeeded
  /// frisch geladen wird.
  void invalidateCache() {
  _cached = null;
  try {
    Hive.box('einstellungen').delete(_cacheKey);
  } catch (_) {}
  refreshSignal.value++;   // ← NEU: benachrichtigt alle Listener
}

  /// Versucht zuerst GPS, fällt auf cityName zurück.
  /// cityName kann leer sein — dann nur GPS.
  Future<WeatherData?> fetchIfNeeded(String cityName, {bool useGps = true}) async {
    final c = cached;
    if (c != null && !c.isStale) {
      final modeChanged = useGps != c.isGps;
      final cityChanged = !useGps && cityName.isNotEmpty &&
          c.city.toLowerCase() != cityName.toLowerCase();
      if (modeChanged || cityChanged) {
        invalidateCache();
        // Cache war ungültig → Fetch erzwingen, nicht zurückgeben
      } else {
        return c;
      }
    }
    if (_fetching) return cached; // cached ist nach invalidateCache() null

    // Nach einem gescheiterten Versuch nicht öfter als alle 20 Sekunden
    // erneut versuchen, aber NICHT für immer blockieren wie bisher.
    if (_lastFailedAttempt != null &&
        DateTime.now().difference(_lastFailedAttempt!) < const Duration(seconds: 20)) {
      return c;
    }

    _fetching = true;
    try {
      if (useGps) {
        final gpsData = await _fetchByGps();
        if (gpsData != null) {
          _lastFailedAttempt = null;
          _save(gpsData);
          return gpsData;
        }
        _lastFailedAttempt = DateTime.now();
        return c;
      } else {
        if (cityName.trim().isNotEmpty) {
          final cityData = await _fetchByCity(cityName.trim());
          if (cityData != null) {
            _lastFailedAttempt = null;
            _save(cityData);
            return cityData;
          }
        }
        _lastFailedAttempt = DateTime.now();
        return c;
      }
    } catch (e) {
      debugPrint('[WeatherService] Fehler: $e');
      _lastFailedAttempt = DateTime.now();
      return c;
    } finally {
      _fetching = false;
    }
  }

  Future<WeatherData?> _fetchByGps() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return await _fetchFromCoords(pos.latitude, pos.longitude, 'GPS');
    } catch (_) {
      return null;
    }
  }

  Future<WeatherData?> _fetchByCity(String cityName) async {
    try {
      final geoUri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(cityName)}&format=json&limit=1',
      );
      final geoResp = await http
          .get(geoUri, headers: {'User-Agent': 'OpTimes/1.0'})
          .timeout(const Duration(seconds: 8));

      if (geoResp.statusCode != 200) return null;
      final geoList = jsonDecode(geoResp.body) as List;
      if (geoList.isEmpty) return null;

      final lat = double.parse(geoList[0]['lat'] as String);
      final lon = double.parse(geoList[0]['lon'] as String);
      return await _fetchFromCoords(lat, lon, cityName);
    } catch (_) {
      return null;
    }
  }

  /// Prüft per Geocoding, ob ein Ortsname gefunden wird, und liefert einen
/// lesbaren Anzeigenamen (z.B. "Berlin, Deutschland") zur Bestätigung zurück.
/// Gibt null zurück, wenn nichts gefunden wurde oder die Anfrage fehlschlägt.
Future<String?> verifyCityName(String cityName) async {
  try {
    final geoUri = Uri.parse(
      'https://nominatim.openstreetmap.org/search'
      '?q=${Uri.encodeComponent(cityName)}&format=json&limit=1&addressdetails=1',
    );
    final geoResp = await http
        .get(geoUri, headers: {'User-Agent': 'OpTimes/1.0'})
        .timeout(const Duration(seconds: 8));

    if (geoResp.statusCode != 200) return null;
    final geoList = jsonDecode(geoResp.body) as List;
    if (geoList.isEmpty) return null;

    final result = geoList[0] as Map<String, dynamic>;
    final address = result['address'] as Map<String, dynamic>?;
    final place = address?['city'] ?? address?['town'] ??
        address?['village'] ?? address?['municipality'];
    final country = address?['country'];

    if (place != null && country != null) {
      return '$place, $country';
    }
    // Fallback: gekürzter display_name
    final display = result['display_name'] as String?;
    if (display == null) return null;
    return display.split(',').take(2).map((s) => s.trim()).join(', ');
  } catch (_) {
    return null;
  }
}

  Future<WeatherData?> _fetchFromCoords(
      double lat, double lon, String label) async {
    final weatherUri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,apparent_temperature,weather_code,'
      'precipitation,wind_speed_10m,is_day,relative_humidity_2m'
      '&daily=sunrise,sunset,temperature_2m_max,weather_code'
      '&timezone=auto',
    );
    final wResp = await http
        .get(weatherUri)
        .timeout(const Duration(seconds: 8));

    if (wResp.statusCode != 200) return null;
    final wJson = jsonDecode(wResp.body) as Map<String, dynamic>;
    final cur = wJson['current'] as Map<String, dynamic>;

    // ── is_day parsen ──────────────────────────────────────────────────────
    final isDay = (cur['is_day'] as int? ?? 1) == 1;
    final humidity = cur['relative_humidity_2m'] as int?;

    // ── Sunrise/Sunset parsen ──────────────────────────────────────────────
    DateTime? sunrise, sunset;
    double? dailyMaxTemp;
    int? dailyWeatherCodeValue;
    double? tomorrowMaxTemp;       // NEU
    int? tomorrowWeatherCodeValue;

    try {
      final daily = wJson['daily'] as Map<String, dynamic>;
      final srList = daily['sunrise'] as List;
      final ssList = daily['sunset'] as List;
      if (srList.isNotEmpty) sunrise = DateTime.parse(srList.first as String);
      if (ssList.isNotEmpty) sunset = DateTime.parse(ssList.first as String);

      final maxList = daily['temperature_2m_max'] as List?;
      final codeList = daily['weather_code'] as List?;
      if (maxList != null && maxList.isNotEmpty) {
        dailyMaxTemp = (maxList.first as num).toDouble();
        if (maxList.length > 1) tomorrowMaxTemp = (maxList[1] as num).toDouble();  // NEU
      }
      if (codeList != null && codeList.isNotEmpty) {
        dailyWeatherCodeValue = (codeList.first as num).toInt();
        if (codeList.length > 1) tomorrowWeatherCodeValue = (codeList[1] as num).toInt(); // NEU
      }
    } catch (_) {
      // Sunrise/Sunset oder daily-Daten nicht verfügbar → ignoriert
    }

    return WeatherData(
      tempC: (cur['temperature_2m'] as num).toDouble(),
      feelsLikeC: (cur['apparent_temperature'] as num).toDouble(),
      weatherCode: (cur['weather_code'] as num).toInt(),
      precipitationMm: (cur['precipitation'] as num).toDouble(),
      windKmh: (cur['wind_speed_10m'] as num).toDouble(),
      city: label,
      fetchedAt: DateTime.now(),
      sunrise: sunrise,
      sunset: sunset,
      isDay: isDay,
      humidityPercent: humidity,
      dailyMaxTempC: dailyMaxTemp,
      dailyWeatherCode: dailyWeatherCodeValue,
      tomorrowMaxTempC: tomorrowMaxTemp,           // NEU
      tomorrowWeatherCode: tomorrowWeatherCodeValue,
    );
  }

  /// Für Notifications: holt immer frische Daten (ignoriert Cache),
  /// liest GPS/City-Einstellung direkt aus Hive.
  Future<WeatherData?> fetchForecastForNotification() async {
    final box = Hive.box('einstellungen');
    final useGps = box.get('weather_use_gps', defaultValue: true) as bool;
    final city = box.get('weather_city', defaultValue: '') as String;

    // Cache leeren → fetchIfNeeded erzwingt einen echten API-Call
    invalidateCache();
    return fetchIfNeeded(city, useGps: useGps);
  }

  void _save(WeatherData data) {
    _cached = data;
    Hive.box('einstellungen')
        .put(_cacheKey, jsonEncode(data.toJson()));
  }
}