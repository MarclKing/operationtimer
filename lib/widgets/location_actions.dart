import 'dart:async';
// lib/widgets/location_actions.dart
// Navigieren (Google Maps / Apple Maps) + Kartenvorschau (flutter_map, OSM).

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/user_position.dart';
import '../services/recent_places.dart';
import '../models/location_info.dart';
import '../services/location_resolver.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';
import 'glass_snackbar.dart';
import '../services/favorite_place_store.dart';
import 'favorite_name_sheet.dart';
import '../tutorial/tutorial_controller.dart';
import '../tutorial/tutorial_demos.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NAVIGIEREN
// ─────────────────────────────────────────────────────────────────────────────

enum MapApp { google, apple }

class MapsNavigator {
  MapsNavigator._();

  /// Navigieren geht mit Koordinaten, Adresse, Name oder (Fallback) Rohtext.
  static bool canNavigate(LocationInfo? loc, String fallbackText) {
    if (loc != null) {
      if (loc.hasCoords || loc.hasAddress) return true;
      if ((loc.name ?? '').trim().isNotEmpty) return true;
    }
    return fallbackText.trim().isNotEmpty;
  }

  /// Text für die Zielsuche, wenn keine Koordinaten vorliegen.
  static String _destinationText(LocationInfo? loc, String fallbackText) {
    if (loc != null) {
      if (loc.singleLine.isNotEmpty) return loc.singleLine;
      final n = (loc.name ?? '').trim();
      if (n.isNotEmpty) return n;
    }
    return fallbackText.trim();
  }

  /// Koordinaten bevorzugt, sonst die Adresse als Text.
  static String _destination(LocationInfo? loc, String fallbackText) {
    if (loc != null && loc.hasCoords) return '${loc.lat},${loc.lng}';
    return _destinationText(loc, fallbackText);
  }

  static Uri googleUri(LocationInfo? loc, String fallbackText) => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {'api': '1', 'destination': _destination(loc, fallbackText)},
      );

  static Uri appleUri(LocationInfo? loc, String fallbackText) => Uri.https(
        'maps.apple.com',
        '/',
        {'daddr': _destination(loc, fallbackText), 'dirflg': 'd'},
      );

  static Future<bool> _launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Android: direkt Google Maps. iOS: erst Auswahl-Sheet Google / Apple.
  static Future<void> navigate(
    BuildContext context, {
    required AppSkin skin,
    LocationInfo? loc,
    String fallbackText = '',
  }) async {
    if (!canNavigate(loc, fallbackText)) return;

    var app = MapApp.google;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final label = _destinationText(loc, fallbackText);
      final choice = await _chooseApp(context, skin, label.isEmpty ? 'Ausgewählter Ort' : label);
      if (choice == null) return;
      app = choice;
    }

    final ok = await _launch(
      app == MapApp.apple ? appleUri(loc, fallbackText) : googleUri(loc, fallbackText),
    );
    if (!ok && context.mounted) {
      showGlassSnackBar(context, 'Karten-App konnte nicht geöffnet werden.',
          type: GlassSnackBarType.error);
    }
  }

  static Future<MapApp?> _chooseApp(BuildContext context, AppSkin skin, String destination) {
    FocusManager.instance.primaryFocus?.unfocus();
    return showModalBottomSheet<MapApp>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => GlassSheet(
        skin: skin,
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: SheetHandle(skin: skin)),
              const SizedBox(height: 14),
              Row(children: [
                Icon(Icons.navigation_outlined, color: skin.primary, size: 20),
                const SizedBox(width: 10),
                Text('Navigieren mit',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              ]),
              const SizedBox(height: 6),
              Text(destination,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: skin.textMuted)),
              const SizedBox(height: 16),
              GlassSurface(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  GlassListItem(
                    title: 'Google Maps',
                    leading: Icon(Icons.map_outlined, color: skin.primary, size: 24),
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                    onTap: () => Navigator.pop(ctx, MapApp.google),
                  ),
                  GlassListItem(
                    title: 'Apple Maps',
                    isLast: true,
                    leading: Icon(Icons.explore_outlined, color: skin.primary, size: 24),
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                    onTap: () => Navigator.pop(ctx, MapApp.apple),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VORSCHAU
// ─────────────────────────────────────────────────────────────────────────────

/// Kleines Glass-Sheet mit Karte (nicht verschiebbar) + Adresse.
/// Tipp auf die Karte öffnet das Vollbild. Nur mit Koordinaten.
Future<void> showLocationPreview(
  BuildContext context, {
  required AppSkin skin,
  required LocationInfo loc,
}) async {
  if (!loc.hasCoords) return;
  FocusManager.instance.primaryFocus?.unfocus();
  await showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => LocationPreviewSheet(skin: skin, loc: loc),
  );
}

class LocationPreviewSheet extends StatelessWidget {
  final AppSkin skin;
  final LocationInfo loc;
  const LocationPreviewSheet({super.key, required this.skin, required this.loc});

  void _openFullscreen(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LocationFullscreenMap(skin: skin, loc: loc),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final name = (loc.name ?? '').trim();
    return GlassSheet(
      skin: skin,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.paddingOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: SheetHandle(skin: skin)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 220,
                child: Stack(children: [
                  // Karte ist nicht bedienbar; ein Tipp geht an die Fläche darüber
                  IgnorePointer(child: _OsmMap(loc: loc, zoom: 16, interactive: false)),
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _openFullscreen(context),
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: skin.bgCard.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.open_in_full_rounded, size: 15, color: skin.textPrimary),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 14),
            if (name.isNotEmpty)
              Text(name, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
            if (loc.line1.isNotEmpty)
              Text(loc.line1, style: TextStyle(fontSize: 14, color: skin.textPrimary)),
            if (loc.line2.isNotEmpty)
              Text(loc.line2, style: TextStyle(fontSize: 14, color: skin.surface(0.6))),
            if (name.isEmpty && !loc.hasAddress)
              Text('${loc.lat!.toStringAsFixed(5)}, ${loc.lng!.toStringAsFixed(5)}',
                  style: TextStyle(fontSize: 14, color: skin.surface(0.6))),
            const SizedBox(height: 8),
            Text('Zum Vergrößern auf die Karte tippen',
                style: TextStyle(fontSize: 11.5, color: skin.surface(0.38))),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOLLBILD
// ─────────────────────────────────────────────────────────────────────────────

class LocationFullscreenMap extends StatelessWidget {
  final AppSkin skin;
  final LocationInfo loc;
  const LocationFullscreenMap({super.key, required this.skin, required this.loc});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Stack(children: [
        Positioned.fill(
          child: SafeArea(
            top: false,
            child: _OsmMap(loc: loc, zoom: 16, interactive: true),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 10,
          right: 14,
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: skin.bgCard.withValues(alpha: 0.92),
                shape: BoxShape.circle,
                border: Border.all(color: skin.glassBorder),
                boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
              ),
              child: Icon(Icons.close_rounded, size: 20, color: skin.textPrimary),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KARTE (gemeinsam für Vorschau und Vollbild)
// ─────────────────────────────────────────────────────────────────────────────

class _OsmMap extends StatelessWidget {
  final LocationInfo loc;
  final double zoom;
  final bool interactive;
  final MapController? controller;
  final bool showMarker;
  final void Function(LatLng center)? onCenterChanged;
  final VoidCallback? onPointerDown;
  final List<Marker> extraMarkers;
  final LatLng? userPoint;
  const _OsmMap({
    required this.loc,
    required this.zoom,
    required this.interactive,
    this.controller,
    this.showMarker = true,
    this.onCenterChanged,
    this.onPointerDown,
    this.extraMarkers = const [],
    this.userPoint,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(loc.lat!, loc.lng!);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onPointerDown?.call(),
      child: FlutterMap(
      // Neue Koordinaten -> Karte neu aufbauen, sonst bleibt die Kamera am alten Ort
      key: ValueKey('${loc.lat},${loc.lng}'),
      mapController: controller,
      options: MapOptions(
        initialCenter: point,
        initialZoom: zoom,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: InteractionOptions(
          flags: interactive ? (InteractiveFlag.all & ~InteractiveFlag.rotate) : InteractiveFlag.none,
        ),
        onMapEvent: onCenterChanged == null ? null : (e) => onCenterChanged!(e.camera.center),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'de.marcel.optimes',
        ),
        if (userPoint != null)
          MarkerLayer(markers: [
            Marker(
              point: userPoint!,
              width: 24,
              height: 24,
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4285F4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)],
                ),
              ),
            ),
          ]),
        if (extraMarkers.isNotEmpty) MarkerLayer(markers: extraMarkers),
        if (showMarker)
          MarkerLayer(markers: [
            Marker(
              point: point,
              width: 44,
              height: 44,
              // Pin-Spitze sitzt auf dem Punkt
              alignment: Alignment.topCenter,
              child: const Icon(Icons.location_on, size: 44, color: Color(0xFFEF5B5B)),
            ),
          ]),
        const SimpleAttributionWidget(
          source: Text('© OpenStreetMap', style: TextStyle(fontSize: 11, color: Colors.black87)),
          backgroundColor: Color(0xCCFFFFFF),
        ),
      ],
    ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INLINE-KARTENKACHEL (im Ereignis-Sheet) + VOLLBILD ALS SHEET
// ─────────────────────────────────────────────────────────────────────────────

/// Navigieren-Button im App-Glass-Stil. Der blickdichte Untergrund sorgt
/// dafür, dass er auch über einer Karte gut lesbar bleibt.
class _MapNavButton extends StatelessWidget {
  final AppSkin skin;
  final VoidCallback onTap;
  final double width;
  const _MapNavButton({required this.skin, required this.onTap, this.width = 150});

  @override
  Widget build(BuildContext context) {
    final bg = skin.isLight ? skin.primary.withValues(alpha: 0.13) : skin.primary.withValues(alpha: 0.22);
    final border = skin.isLight ? skin.primary.withValues(alpha: 0.28) : skin.primary.withValues(alpha: 0.45);
    final fg = skin.isLight ? skin.primary.withValues(alpha: 0.90) : skin.primary.withValues(alpha: 0.85);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 34,
        decoration: BoxDecoration(
          // blickdichter Untergrund, damit der Button auf der Karte lesbar bleibt
          color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgCard.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border, width: 1.5),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.navigation_outlined, size: 15, color: fg),
            const SizedBox(width: 6),
            Text('Navigieren',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg, letterSpacing: 0.2)),
          ]),
        ),
      ),
    );
  }
}

class LocationMapCard extends StatelessWidget {
  final AppSkin skin;
  final LocationInfo loc;
  final VoidCallback onNavigate;

  /// Wird aufgerufen, wenn im Vollbild eine neue Position übernommen wurde.
  final ValueChanged<LocationInfo>? onLocationChanged;

  /// false = kein Favoriten-Stern im Vollbild (z. B. beim Bearbeiten eines Favoriten).
  final bool allowFavorite;

  /// false = kein Navigieren-Button in der Vorschau und im Vollbild.
  final bool allowNavigate;

  /// Tutorial: Key + Puls-Animation für das Vollbild-Symbol
  final GlobalKey? expandIconKey;
  final bool pulseExpandIcon;
  const LocationMapCard({
    super.key,
    required this.skin,
    required this.loc,
    required this.onNavigate,
    this.onLocationChanged,
    this.allowFavorite = true,
    this.allowNavigate = true,
    this.expandIconKey,
    this.pulseExpandIcon = false,
  });

  Future<void> _openFullscreen(BuildContext context) async {
    final result = await showLocationFullscreen(context, skin: skin, loc: loc, allowFavorite: allowFavorite, allowNavigate: allowNavigate);
    if (result != null) onLocationChanged?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 230,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: skin.glassBorder),
      ),
      child: Stack(children: [
        IgnorePointer(child: _OsmMap(loc: loc, zoom: 16, interactive: false)),
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openFullscreen(context),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: IgnorePointer(
            child: TutorialPulse(
                active: pulseExpandIcon,
                maxScale: 1.5,
                child: Container(
                  key: expandIconKey,
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: skin.bgCard.withValues(alpha: 0.85), shape: BoxShape.circle),
                  child: Icon(Icons.open_in_full_rounded, size: 14, color: skin.textPrimary),
                ),
              ),
          ),
        ),
        if (allowNavigate)
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(child: _MapNavButton(skin: skin, onTap: onNavigate)),
          ),
      ]),
    );
  }
}

/// Öffnet das Vollbild für einen bestehenden Ort.
/// Ergebnis: neue Position (nur wenn übernommen), sonst null.
Future<LocationInfo?> showLocationFullscreen(
  BuildContext context, {
  required AppSkin skin,
  required LocationInfo loc,
  bool allowFavorite = true,
  bool allowNavigate = true,
}) {
  if (!loc.hasCoords) return Future.value(null);
  return _showMapSheet(context, skin, loc, allowFavorite: allowFavorite, allowNavigate: allowNavigate);
}

/// Öffnet die Karte zur Neuauswahl eines Ortes (mit Suchfeld).
Future<LocationInfo?> showLocationPicker(
  BuildContext context, {
  required AppSkin skin,
}) =>
    _showMapSheet(context, skin, null);

Future<LocationInfo?> _showMapSheet(BuildContext context, AppSkin skin, LocationInfo? loc,
    {bool allowFavorite = true, bool allowNavigate = true}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<LocationInfo>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    // Karte soll ungestört verschiebbar sein: geschlossen wird über Handle/X
    enableDrag: false,
    builder: (_) => LocationFullscreenSheet(
        skin: skin, loc: loc, allowFavorite: allowFavorite, allowNavigate: allowNavigate),
  );
}

class LocationFullscreenSheet extends StatefulWidget {
  final AppSkin skin;

  /// null = Auswahlmodus (neuer Ort, mit Suchfeld)
  final LocationInfo? loc;
  final bool allowFavorite;
  final bool allowNavigate;
  final bool tutorialDemo;
  const LocationFullscreenSheet(
      {super.key, required this.skin, this.loc, this.allowFavorite = true, this.allowNavigate = true, this.tutorialDemo = false});

  @override
  State<LocationFullscreenSheet> createState() => _LocationFullscreenSheetState();
}

class _LocationFullscreenSheetState extends State<LocationFullscreenSheet> {
  final MapController _mapCtrl = MapController();
  late LocationInfo _start;
  bool _adjusting = false;
  bool _moved = false;
  bool _resolving = false;
  LatLng? _center;
  late LocationInfo _picked;
  Timer? _debounce;
  int _seq = 0;
  bool _userStart = false;
  bool _favChanged = false;
  DateTime _ignoreUntil = DateTime.fromMillisecondsSinceEpoch(0);
  LatLng? _userLatLng;
  List<PlaceSuggestion> _pins = [];
  String _pinQuery = '';
  bool _pinsStale = false;

  // Suche (nur Auswahlmodus)
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  bool _searching = false;
  List<PlaceSuggestion> _results = [];

  // Favoriten: gerade gewählter bzw. eben gespeicherter Favorit (Name + Adresse bleiben erhalten)
  FavoritePlace? _selectedFav;

  AppSkin get skin => widget.skin;
  bool get _pickMode => widget.loc == null;

  @override
  void initState() {
    super.initState();
    // Ohne Startort: Deutschland-Übersicht, dann per Suche oder Verschieben
    final upc = UserPosition.cached;
    if (widget.loc == null && upc != null) _userStart = true;
    _userLatLng = upc == null ? null : LatLng(upc.lat, upc.lng);
    _start = widget.loc ?? LocationInfo(rawInput: '', lat: upc?.lat ?? 51.1657, lng: upc?.lng ?? 10.4515);
    _picked = _start;
    _center = LatLng(_start.lat!, _start.lng!);
    _adjusting = _pickMode;
    _searchFocus.addListener(() {
      if (!mounted) return;
      if (_searchFocus.hasFocus && _pickMode && _searchCtrl.text.trim().isEmpty) {
        final rec = RecentPlaces.all();
        setState(() => _results = rec);
      } else {
        setState(() {
          // Zuletzt benutzte schließen, sobald das Feld den Fokus verliert
          if (!_searchFocus.hasFocus && _searchCtrl.text.trim().isEmpty) _results = [];
        });
      }
    });
    if (!widget.tutorialDemo) {
      _centerOnUser();
      TutorialTriggers.maybeStart(TutorialKind.map,
          delay: const Duration(milliseconds: 1100));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ── Position verschieben ────────────────────────────────────────────────

  /// Standort holen: blauen Punkt zeigen und – solange nichts gewählt wurde – die Karte darauf zentrieren.
  Future<void> _centerOnUser() async {
    final pos = await UserPosition.get();
    if (pos == null || !mounted) return;
    final ll = LatLng(pos.lat, pos.lng);
    final untouched = _pickMode && !_moved && !_userStart && _pins.isEmpty && _searchCtrl.text.isEmpty;
    setState(() {
      _userLatLng = ll;
      if (untouched) {
        _userStart = true;
        _start = LocationInfo(rawInput: '', lat: pos.lat, lng: pos.lng);
        _picked = _start;
        _center = ll;
      }
    });
  }

  void _programmatic(VoidCallback f) {
    _ignoreUntil = DateTime.now().add(const Duration(milliseconds: 600));
    f();
  }

  /// "Mein Standort": Karte dorthin, Position wird wie beim Verschieben übernommen.
  Future<void> _goToMe() async {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    final p = await UserPosition.get();
    if (!mounted) return;
    if (p == null) {
      showGlassSnackBar(context, 'Standort nicht verfügbar. Bitte in den iOS-Einstellungen erlauben.',
          type: GlassSnackBarType.info);
      return;
    }
    final ll = LatLng(p.lat, p.lng);
    setState(() => _userLatLng = ll);
    try {
      _mapCtrl.move(ll, 16);
    } catch (_) {}
  }

  /// Suchmitte wie bei Google: sichtbarer Kartenausschnitt (wenn hineingezoomt), sonst echter Standort.
  Future<(double?, double?)> _searchBias() async {
    try {
      final cam = _mapCtrl.camera;
      if (cam.zoom >= 10) return (cam.center.latitude, cam.center.longitude);
    } catch (_) {}
    final p = await UserPosition.quick();
    return (p?.lat, p?.lng);
  }

  /// Ort aus Treffer/Markierung/Leiste wählen: Nadel dorthin, "Position übernehmen" sofort aktiv.
  void _applyPlace(PlaceSuggestion s, {bool setText = false}) {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    final c = LatLng(s.lat, s.lng);
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _searchSeq++;
    _seq++;
    _selectedFav = null;
    setState(() {
      _results = [];
      _searching = false;
      _resolving = false;
      _moved = true;
      _center = c;
      _picked = s.toLocationInfo();
    });
    if (setText) _searchCtrl.text = s.title;
    _programmatic(() => _mapCtrl.move(c, s.zoom));
  }

  /// Suchtaste: alle Treffer in der Nähe als Markierungen zeigen (wie Google Maps).
  Future<void> _submitSearch(String q) async {
    if (q.length < 2) return;
    _searchDebounce?.cancel();
    FocusManager.instance.primaryFocus?.unfocus();
    final seq = ++_searchSeq;
    setState(() {
      _results = [];
      _searching = true;
    });
    final bias = await _searchBias();
    if (!mounted || seq != _searchSeq) return;
    final r = await LocationResolver.searchPlaces(q,
        biasLat: bias.$1, biasLng: bias.$2, max: 12, nearOnly: true);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _searching = false;
      _pins = r;
      _pinQuery = q;
      _pinsStale = false;
    });
    if (r.isEmpty) {
      showGlassSnackBar(context, 'Keine Treffer für „$q“', type: GlassSnackBarType.info);
      return;
    }
    _fitPins(r);
  }

  void _fitPins(List<PlaceSuggestion> r) {
    try {
      _programmatic(() {
        if (r.length == 1) {
          _mapCtrl.move(LatLng(r.first.lat, r.first.lng), 16);
        } else {
          _mapCtrl.fitCamera(CameraFit.coordinates(
            coordinates: r.map((e) => LatLng(e.lat, e.lng)).toList(),
            padding: const EdgeInsets.fromLTRB(48, 160, 48, 220),
            maxZoom: 16,
          ));
        }
      });
    } catch (_) {}
  }

  bool _isPicked(PlaceSuggestion p) =>
      _moved && _picked.hasCoords && (_picked.lat! - p.lat).abs() < 1e-5 && (_picked.lng! - p.lng).abs() < 1e-5;

  List<Marker> _pinMarkers() => [
        for (final p in _pins)
          if (!_isPicked(p))
            Marker(
              point: LatLng(p.lat, p.lng),
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _applyPlace(p),
                child: Icon(Icons.location_on, size: 40, color: skin.primary),
              ),
            ),
      ];

  Widget _pinStrip() {
    return Positioned(
      top: 70,
      left: 0,
      right: 0,
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 0, 62, 0),
        itemCount: _pins.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final p = _pins[i];
          final sel = _isPicked(p);
          return GestureDetector(
            onTap: () => _applyPlace(p),
            child: Container(
              width: 190,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: skin.bgCard.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: sel ? skin.primary : skin.glassBorder, width: sel ? 1.6 : 1.0),
                boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 10, offset: const Offset(0, 3))],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                  if ((_withDistance(p) ?? '').isNotEmpty)
                    Text(_withDistance(p)!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _searchAreaPill() {
    return Positioned(
      top: 142,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: () => _submitSearch(_pinQuery),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: skin.bgCard.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: skin.primary.withValues(alpha: 0.5)),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.refresh_rounded, size: 16, color: skin.primary),
              const SizedBox(width: 6),
              Text('In diesem Gebiet suchen',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: skin.primary)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _locateButton() {
    return Positioned(
      top: 70,
      right: 14,
      child: GestureDetector(
        onTap: _goToMe,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: skin.bgCard.withValues(alpha: 0.92),
            shape: BoxShape.circle,
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: const Icon(Icons.my_location_rounded, size: 19, color: Color(0xFF4285F4)),
        ),
      ),
    );
  }

  String? _withDistance(PlaceSuggestion s) {
    final base = (s.subtitle ?? '').trim();
    final p = UserPosition.cached;
    if (p == null) return base.isEmpty ? null : base;
    final d = UserPosition.formatDistance(UserPosition.distanceM(p.lat, p.lng, s.lat, s.lng));
    return base.isEmpty ? d : '$d · $base';
  }

  void _startAdjust() {
    setState(() {
      _adjusting = true;
      _moved = false;
      _resolving = false;
      _picked = _start;
      _center = LatLng(_start.lat!, _start.lng!);
    });
  }

  String _coordText(LatLng c) => '${c.latitude.toStringAsFixed(6)}, ${c.longitude.toStringAsFixed(6)}';

  void _onCenter(LatLng c) {
    if (!_adjusting || !mounted) return;
    // Kamerabewegungen, die wir selbst ausgelöst haben (Treffer wählen, auf Treffer zoomen), nicht als Verschieben werten
    if (DateTime.now().isBefore(_ignoreUntil)) {
      _center = c;
      return;
    }
    if (_pins.isNotEmpty) _pinsStale = true;
    final last = _center;
    if (last != null &&
        (last.latitude - c.latitude).abs() < 1e-7 &&
        (last.longitude - c.longitude).abs() < 1e-7) {
      return;
    }
    final sf = _selectedFav;
    if (sf != null &&
        (sf.loc.lat! - c.latitude).abs() < 1e-6 &&
        (sf.loc.lng! - c.longitude).abs() < 1e-6) {
      return; // Kamera steht nur auf dem Favoriten
    }
    _selectedFav = null;
    _center = c;
    _moved = true;
    _debounce?.cancel();
    final seq = ++_seq;
    final text = _coordText(c);
    setState(() {
      _resolving = true;
      _picked = LocationInfo(rawInput: text, lat: c.latitude, lng: c.longitude);
    });
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      final info = await LocationResolver.resolve(text);
      if (!mounted || seq != _seq) return;
      setState(() {
        _resolving = false;
        if (info != null) {
          // exakt die Kartenmitte behalten, Adresse/Name aus der Auswertung
          _picked = LocationInfo(
            rawInput: text,
            name: info.name,
            street: info.street,
            postalCode: info.postalCode,
            city: info.city,
            lat: c.latitude,
            lng: c.longitude,
          );
        }
      });
    });
  }

  void _apply() {
    final f = _selectedFav;
    if (f != null) FavoritePlaceStore.touch(f.id);
    Navigator.of(context).pop((_moved || _favChanged) ? _currentInfo : null);
  }

  // ── Suche ───────────────────────────────────────────────────────────────

  void _onSearchChanged(String v) {
    _searchDebounce?.cancel();
    final q = v.trim();
    if (q.length < 3) {
      _searchSeq++;
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() {});
    _searchDebounce = Timer(const Duration(milliseconds: 400), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final bias = await _searchBias();
    if (!mounted || seq != _searchSeq) return;
    final r = await LocationResolver.searchPlaces(q, biasLat: bias.$1, biasLng: bias.$2);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = r;
      _searching = false;
    });
  }

  void _selectSuggestion(PlaceSuggestion s) {
    RecentPlaces.add(s);
    if (_pins.isNotEmpty) setState(() => _pins = []);
    _applyPlace(s, setText: true);
  }

  Future<void> _removeRecent(PlaceSuggestion p) async {
    HapticFeedback.selectionClick();
    await RecentPlaces.remove(p);
    if (!mounted) return;
    setState(() {
      _results = _results
          .where((e) => !((e.lat - p.lat).abs() < 1e-4 && (e.lng - p.lng).abs() < 1e-4))
          .toList();
    });
  }

  void _clearSearch() {
    if (_pins.isNotEmpty) setState(() => _pins = []);
    _searchDebounce?.cancel();
    _searchSeq++;
    _searchCtrl.clear();
    setState(() {
      _results = [];
      _searching = false;
    });
  }

  /// Vorschlagsliste schließen (Tipp oder Verschieben auf der Karte).
  void _dismissSuggestions() {
    FocusManager.instance.primaryFocus?.unfocus();
    if (_results.isEmpty && !_searching) return;
    _searchDebounce?.cancel();
    _searchSeq++;
    setState(() {
      _results = [];
      _searching = false;
    });
  }

  // ── Bausteine ───────────────────────────────────────────────────────────

  // ── Favoriten ───────────────────────────────────────────────────────────

  LocationInfo get _currentInfo => _adjusting ? _picked : _start;

  bool get _currentIsFavorite {
    final id = _currentInfo.favoriteId;
    return id != null && FavoritePlaceStore.byId(id) != null;
  }

  bool get _canSaveFavorite {
    if (!widget.allowFavorite) return false;
    if (!_currentInfo.hasCoords || _resolving) return false;
    if (_pickMode && !_moved) return false;
    return true;
  }

  Future<void> _saveFavorite() async {
    if (_currentIsFavorite) {
      showGlassSnackBar(context, 'Dieser Ort ist bereits ein Favorit', type: GlassSnackBarType.info);
      return;
    }
    if (!_canSaveFavorite) {
      showGlassSnackBar(
        context,
        _resolving ? 'Adresse wird noch gesucht …' : 'Wähle zuerst einen Ort auf der Karte',
        type: GlassSnackBarType.info,
      );
      return;
    }
    final info = _currentInfo;
    final nm = (info.name ?? '').trim();
    final name = await showFavoriteNameSheet(context, skin: skin, initial: nm.isNotEmpty ? nm : info.line1);
    if (name == null || !mounted) return;
    final saved = await FavoritePlaceStore.add(name, info);
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    final li = saved.toLocationInfo();
    setState(() {
      _selectedFav = saved;
      _favChanged = true;
      if (_adjusting) {
        _picked = li;
      } else {
        _start = li;
      }
    });
    showGlassSnackBar(context, 'Als Favorit gespeichert', type: GlassSnackBarType.success);
  }

  /// Favoriten als Vorschläge: leeres Feld = zuletzt benutzte, sonst passende Treffer.
  List<FavoritePlace> get _favSuggestions {
    if (!_pickMode || !_searchFocus.hasFocus) return const [];
    final q = _searchCtrl.text.trim();
    return FavoritePlaceStore.search(q, limit: q.isEmpty ? 8 : 4);
  }

  bool get _hasSuggestions => _results.isNotEmpty || _favSuggestions.isNotEmpty;

  void _selectFavorite(FavoritePlace f) {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchSeq++;
    _seq++; // laufende Adress-Auswertung verwerfen
    _debounce?.cancel();
    final c = LatLng(f.loc.lat!, f.loc.lng!);
    setState(() {
      _results = [];
      _searching = false;
      _resolving = false;
      _moved = true;
      _selectedFav = f;
      _center = c;
      _picked = f.toLocationInfo();
    });
    _searchCtrl.text = f.name;
    _mapCtrl.move(c, 17);
  }

  Widget _searchField() {
    return GlassSurface(
      borderRadius: 14,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 40,
        child: Row(children: [
          Icon(Icons.search_rounded, size: 19, color: skin.surface(0.5)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              onChanged: _onSearchChanged,
              onSubmitted: (v) => _submitSearch(v.trim()),
              style: TextStyle(color: skin.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Ort suchen, z. B. Berlin',
                hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 14.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searching)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: skin.surface(0.5)),
            )
          else if (_searchCtrl.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _clearSearch,
              child: Icon(Icons.close_rounded, size: 18, color: skin.surface(0.45)),
            ),
        ]),
      ),
    );
  }

  Widget _suggestionList() {
    final favs = _favSuggestions;
    final total = favs.length + _results.length;
    final recentMode = _searchCtrl.text.trim().isEmpty;
    final maxH = MediaQuery.sizeOf(context).height * 0.38;
    return GlassSurface(
      borderRadius: 14,
      padding: EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (_searchCtrl.text.trim().length >= 3)
              GlassListItem(
                title: 'Alle Treffer für „${_searchCtrl.text.trim()}“ auf der Karte',
                leading: Icon(Icons.search_rounded, size: 22, color: skin.primary),
                onTap: () => _submitSearch(_searchCtrl.text.trim()),
              ),
            for (int i = 0; i < favs.length; i++)
              GlassListItem(
                title: favs[i].name,
                subtitle: favs[i].addressLine.isEmpty ? null : favs[i].addressLine,
                isLast: i == total - 1,
                leading: Icon(Icons.place_outlined, size: 22, color: skin.primary),
                trailing: const Icon(Icons.star_rounded, size: 20, color: Color(0xFFFFB347)),
                onTap: () => _selectFavorite(favs[i]),
              ),
            for (int i = 0; i < _results.length; i++)
              GlassListItem(
                title: _results[i].title,
                subtitle: _withDistance(_results[i]),
                isLast: favs.length + i == total - 1,
                leading: Icon(recentMode ? Icons.history_rounded : Icons.place_outlined,
                    size: 22, color: recentMode ? skin.surface(0.45) : skin.primary),
                trailing: recentMode
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _removeRecent(_results[i]),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.close_rounded, size: 18, color: skin.surface(0.4)),
                        ),
                      )
                    : null,
                onTap: () => _selectSuggestion(_results[i]),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _addressColumn(LocationInfo info) {
    final name = (info.name ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: skin.textPrimary)),
            ),
            if (info.favoriteId != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.star_rounded, size: 16, color: Color(0xFFFFB347)),
            ],
          ]),
        if (info.line1.isNotEmpty) Text(info.line1, style: TextStyle(fontSize: 13.5, color: skin.textPrimary)),
        if (info.line2.isNotEmpty) Text(info.line2, style: TextStyle(fontSize: 13.5, color: skin.surface(0.6))),
        if (name.isEmpty && !info.hasAddress)
          Text('${info.lat!.toStringAsFixed(5)}, ${info.lng!.toStringAsFixed(5)}',
              style: TextStyle(fontSize: 13.5, color: skin.surface(0.6))),
      ],
    );
  }

  Widget _circleButton({required IconData icon, required Color color, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: skin.isLight ? 0.13 : 0.22),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: skin.isLight ? 0.28 : 0.45), width: 1.5),
        ),
        child: Icon(icon, size: 20, color: color),
      ),
    );
  }

  /// Kräftig gefüllt mit weißer Schrift; grau und transparent, solange
  /// gesucht wird oder noch nichts verschoben wurde.
  Widget _applyButton() {
    final enabled = !_resolving && (_moved || !_pickMode);
    final fg = enabled ? Colors.white : Colors.white.withValues(alpha: 0.6);
    return GestureDetector(
      onTap: enabled ? _apply : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: enabled ? skin.primary : Colors.grey.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(14),
          boxShadow: enabled
              ? [BoxShadow(color: skin.primary.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_rounded, size: 18, color: fg),
          const SizedBox(width: 6),
          Text('Position\nübernehmen',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.15, color: fg)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    // Modal-Sheets entfernen intern den oberen Safe-Area-Wert → direkt vom Fenster lesen
    final topInset = MediaQueryData.fromView(View.of(context)).padding.top;
    void close() => Navigator.of(context).pop(_favChanged ? _currentInfo : null);

    return SizedBox(
      height: MediaQuery.sizeOf(context).height - topInset - 16,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(children: [
          // Karte füllt das gesamte Sheet
          Positioned.fill(
            child: _OsmMap(
              loc: _start,
              zoom: _pickMode ? (_userStart ? 14 : 6) : 16,
              interactive: true,
              controller: _mapCtrl,
              showMarker: !_adjusting,
              onCenterChanged: _onCenter,
              onPointerDown: _dismissSuggestions,
              extraMarkers: _pinMarkers(),
              userPoint: _userLatLng,
            ),
          ),

          // Feste Nadel in der Kartenmitte (beim Verschieben/Auswählen)
          if (_adjusting)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -22),
                      child: const Icon(Icons.location_on, size: 44, color: Color(0xFFEF5B5B)),
                    ),
                  ]),
                ),
              ),
            ),

          // Handle (Tippen oder nach unten wischen schließt)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: close,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 150) close();
              },
              child: Container(
                padding: const EdgeInsets.only(bottom: 18),
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 10),
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                    color: skin.bgCard.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: skin.glassBorder),
                  ),
                ),
              ),
            ),
          ),

          // Hinweis beim Verschieben (nur bestehender Ort)
          if (_adjusting && !_pickMode)
            Positioned(
              top: 24,
              left: widget.allowFavorite ? 60 : 14,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: skin.bgCard.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: skin.glassBorder),
                  ),
                  child: Text('Karte verschieben',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                ),
              ),
            ),

          if (_pickMode && _pins.isNotEmpty) _pinStrip(),
          if (_pickMode && _pins.isNotEmpty && _pinsStale && !_searching) _searchAreaPill(),
          _locateButton(),

          // Suchfeld oben + Vorschläge (nur Auswahlmodus)
          if (_pickMode)
            Positioned(
              top: 22,
              left: widget.allowFavorite ? 60 : 14,
              right: 62,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _searchField(),
                if (_hasSuggestions) ...[
                  const SizedBox(height: 6),
                  _suggestionList(),
                ],
              ]),
            ),

          // Favoriten-Stern oben links (speichert die aktuelle Position)
          if (widget.allowFavorite)
            Positioned(
              top: 22,
              left: 14,
              child: GestureDetector(
                key: widget.tutorialDemo ? TutorialKeys.mapFavorite : null,
                onTap: _saveFavorite,
                child: Opacity(
                  opacity: (_canSaveFavorite || _currentIsFavorite) ? 1.0 : 0.5,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: skin.bgCard.withValues(alpha: 0.92),
                      shape: BoxShape.circle,
                      border: Border.all(color: skin.glassBorder),
                      boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
                    ),
                    child: Icon(
                      _currentIsFavorite ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 21,
                      color: const Color(0xFFFFB347),
                    ),
                  ),
                ),
              ),
            ),

          // X rechts oben (schließt und verwirft)
          Positioned(
            top: 22,
            right: 14,
            child: GestureDetector(
              onTap: close,
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: skin.bgCard.withValues(alpha: 0.92),
                  shape: BoxShape.circle,
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
                ),
                child: Icon(Icons.close_rounded, size: 19, color: skin.textPrimary),
              ),
            ),
          ),

          // Overlay unten
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + bottomSafe,
            child: GlassSurface(
              borderRadius: 18,
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(children: [
                Expanded(
                  child: (_pickMode && !_moved)
                      ? Text(_pins.isNotEmpty ? 'Markierung antippen, um den Ort zu wählen' : 'Karte verschieben oder oben nach einem Ort suchen',
                          style: TextStyle(fontSize: 13.5, color: skin.surface(0.6)))
                      : Opacity(
                          opacity: _adjusting && _resolving ? 0.55 : 1.0,
                          child: _addressColumn(_adjusting ? _picked : _start),
                        ),
                ),
                const SizedBox(width: 10),
                if (_adjusting)
                  _applyButton()
                else ...[
                  if (widget.allowNavigate) ...[
                    _circleButton(
                      icon: Icons.navigation_outlined,
                      color: skin.primary,
                      onTap: () => MapsNavigator.navigate(context, skin: skin, loc: _start),
                    ),
                    const SizedBox(width: 8),
                  ],
                  KeyedSubtree(
                    key: widget.tutorialDemo ? TutorialKeys.mapAdjust : null,
                    child: _circleButton(
                      icon: Icons.location_on_outlined,
                      color: skin.deleteColor,
                      onTap: _startAdjust,
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}


/// Tutorial: Vollbild-Karte mit Platzhalter-Ort (Bundestag), nichts wird gespeichert.
Future<void> showTutorialMapDemo(BuildContext context, {required AppSkin skin}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    enableDrag: false,
    isDismissible: false,
    builder: (_) => LocationFullscreenSheet(
      skin: skin,
      loc: TutorialDemo.bundestag(),
      tutorialDemo: true,
    ),
  );
}
