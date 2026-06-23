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
  final DateTime? sunrise;   // NEU: Sonnenaufgang
  final DateTime? sunset;    // NEU: Sonnenuntergang

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
  });

  String get icon {
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
  );
}

class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  static const _cacheKey = 'weather_cache';

  WeatherData? _cached;
  bool _fetching = false;

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
  }

  /// Versucht zuerst GPS, fällt auf cityName zurück.
  /// cityName kann leer sein — dann nur GPS.
  Future<WeatherData?> fetchIfNeeded(String cityName, {bool useGps = true}) async {
    final c = cached;
    if (c != null && !c.isStale) {
      final modeChanged = useGps != c.isGps;
      final cityChanged = !useGps && cityName.isNotEmpty &&
          c.city.toLowerCase() != cityName.toLowerCase();
      if (!modeChanged && !cityChanged) return c;
    }
    if (_fetching) return c;

    _fetching = true;
    try {
      if (useGps) {
        final gpsData = await _fetchByGps();
        if (gpsData != null) { _save(gpsData); return gpsData; }
        return c;
      } else {
        if (cityName.trim().isNotEmpty) {
          final cityData = await _fetchByCity(cityName.trim());
          if (cityData != null) { _save(cityData); return cityData; }
        }
        return c;
      }
    } catch (e) {
      debugPrint('[WeatherService] Fehler: $e');
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
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 6),
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

  Future<WeatherData?> _fetchFromCoords(
      double lat, double lon, String label) async {
    final weatherUri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&current=temperature_2m,apparent_temperature,weather_code,'
      'precipitation,wind_speed_10m'
      '&daily=sunrise,sunset'    // NEU: Sonnenzeiten abrufen
      '&timezone=auto',
    );
    final wResp = await http
        .get(weatherUri)
        .timeout(const Duration(seconds: 8));

    if (wResp.statusCode != 200) return null;
    final wJson = jsonDecode(wResp.body) as Map<String, dynamic>;
    final cur = wJson['current'] as Map<String, dynamic>;

    // ── Sunrise/Sunset parsen ──────────────────────────────────────────────
    DateTime? sunrise, sunset;
    try {
      final daily = wJson['daily'] as Map<String, dynamic>;
      final srList = daily['sunrise'] as List;
      final ssList = daily['sunset'] as List;
      if (srList.isNotEmpty) sunrise = DateTime.parse(srList.first as String);
      if (ssList.isNotEmpty) sunset = DateTime.parse(ssList.first as String);
    } catch (_) {
      // Sunrise/Sunset nicht verfügbar → ignoriert
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
    );
  }

  void _save(WeatherData data) {
    _cached = data;
    Hive.box('einstellungen')
        .put(_cacheKey, jsonEncode(data.toJson()));
  }
}