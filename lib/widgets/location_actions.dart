import 'dart:async';
// lib/widgets/location_actions.dart
// Navigieren (Google Maps / Apple Maps) + Kartenvorschau (flutter_map, OSM).

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/location_info.dart';
import '../services/location_resolver.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';
import 'glass_snackbar.dart';

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
  const _OsmMap({
    required this.loc,
    required this.zoom,
    required this.interactive,
    this.controller,
    this.showMarker = true,
    this.onCenterChanged,
    this.onPointerDown,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(loc.lat!, loc.lng!);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => onPointerDown?.call(),
      child: FlutterMap(
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
  const LocationMapCard({
    super.key,
    required this.skin,
    required this.loc,
    required this.onNavigate,
    this.onLocationChanged,
  });

  Future<void> _openFullscreen(BuildContext context) async {
    final result = await showLocationFullscreen(context, skin: skin, loc: loc);
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
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: skin.bgCard.withValues(alpha: 0.85), shape: BoxShape.circle),
              child: Icon(Icons.open_in_full_rounded, size: 14, color: skin.textPrimary),
            ),
          ),
        ),
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
}) {
  if (!loc.hasCoords) return Future.value(null);
  return _showMapSheet(context, skin, loc);
}

/// Öffnet die Karte zur Neuauswahl eines Ortes (mit Suchfeld).
Future<LocationInfo?> showLocationPicker(
  BuildContext context, {
  required AppSkin skin,
}) =>
    _showMapSheet(context, skin, null);

Future<LocationInfo?> _showMapSheet(BuildContext context, AppSkin skin, LocationInfo? loc) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet<LocationInfo>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    // Karte soll ungestört verschiebbar sein: geschlossen wird über Handle/X
    enableDrag: false,
    builder: (_) => LocationFullscreenSheet(skin: skin, loc: loc),
  );
}

class LocationFullscreenSheet extends StatefulWidget {
  final AppSkin skin;

  /// null = Auswahlmodus (neuer Ort, mit Suchfeld)
  final LocationInfo? loc;
  const LocationFullscreenSheet({super.key, required this.skin, this.loc});

  @override
  State<LocationFullscreenSheet> createState() => _LocationFullscreenSheetState();
}

class _LocationFullscreenSheetState extends State<LocationFullscreenSheet> {
  final MapController _mapCtrl = MapController();
  late final LocationInfo _start;
  bool _adjusting = false;
  bool _moved = false;
  bool _resolving = false;
  LatLng? _center;
  late LocationInfo _picked;
  Timer? _debounce;
  int _seq = 0;

  // Suche (nur Auswahlmodus)
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchDebounce;
  int _searchSeq = 0;
  bool _searching = false;
  List<PlaceSuggestion> _results = [];

  AppSkin get skin => widget.skin;
  bool get _pickMode => widget.loc == null;

  @override
  void initState() {
    super.initState();
    // Ohne Startort: Deutschland-Übersicht, dann per Suche oder Verschieben
    _start = widget.loc ?? const LocationInfo(rawInput: '', lat: 51.1657, lng: 10.4515);
    _picked = _start;
    _center = LatLng(_start.lat!, _start.lng!);
    _adjusting = _pickMode;
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
    final last = _center;
    if (last != null &&
        (last.latitude - c.latitude).abs() < 1e-7 &&
        (last.longitude - c.longitude).abs() < 1e-7) {
      return;
    }
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

  void _apply() => Navigator.of(context).pop(_moved ? _picked : null);

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
    _searchDebounce = Timer(const Duration(milliseconds: 600), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    final r = await LocationResolver.searchPlaces(q);
    if (!mounted || seq != _searchSeq) return;
    setState(() {
      _results = r;
      _searching = false;
    });
  }

  void _selectSuggestion(PlaceSuggestion s) {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    _searchSeq++;
    setState(() {
      _results = [];
      _searching = false;
    });
    _searchCtrl.text = s.title;
    _mapCtrl.move(LatLng(s.lat, s.lng), s.zoom);
  }

  void _clearSearch() {
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
              onSubmitted: (v) {
                final q = v.trim();
                if (q.length >= 2) {
                  _searchDebounce?.cancel();
                  _runSearch(q);
                }
              },
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
    return GlassSurface(
      borderRadius: 14,
      padding: EdgeInsets.zero,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < _results.length; i++)
          GlassListItem(
            title: _results[i].title,
            subtitle: _results[i].subtitle,
            isLast: i == _results.length - 1,
            leading: Icon(Icons.place_outlined, size: 22, color: skin.primary),
            onTap: () => _selectSuggestion(_results[i]),
          ),
      ]),
    );
  }

  Widget _addressColumn(LocationInfo info) {
    final name = (info.name ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty)
          Text(name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: skin.textPrimary)),
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
    void close() => Navigator.of(context).pop();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height - topInset - 16,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: Stack(children: [
          // Karte füllt das gesamte Sheet
          Positioned.fill(
            child: _OsmMap(
              loc: _start,
              zoom: _pickMode ? 6 : 16,
              interactive: true,
              controller: _mapCtrl,
              showMarker: !_adjusting,
              onCenterChanged: _onCenter,
              onPointerDown: _dismissSuggestions,
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
              left: 14,
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

          // Suchfeld oben + Vorschläge (nur Auswahlmodus)
          if (_pickMode)
            Positioned(
              top: 22,
              left: 14,
              right: 62,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _searchField(),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _suggestionList(),
                ],
              ]),
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
                      ? Text('Karte verschieben oder oben nach einem Ort suchen',
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
                  _circleButton(
                    icon: Icons.navigation_outlined,
                    color: skin.primary,
                    onTap: () => MapsNavigator.navigate(context, skin: skin, loc: _start),
                  ),
                  const SizedBox(width: 8),
                  _circleButton(
                    icon: Icons.location_on_outlined,
                    color: skin.deleteColor,
                    onTap: _startAdjust,
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
