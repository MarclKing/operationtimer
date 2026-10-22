// lib/widgets/day_plan.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';
import 'glass_pickers.dart';
import 'glass_snackbar.dart';
import '../services/sync_service.dart';
import '../models/location_info.dart';
import '../services/location_resolver.dart';
import 'location_actions.dart';
import '../services/favorite_place_store.dart';
import '../services/user_position.dart';
import '../services/recent_places.dart';
import 'favorite_suggestions.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────

class DayPlanItem {
  final String id;
  String title;
  DateTime start;
    DateTime end;
  String location;

  /// Strukturierter Ort (optional). `location` bleibt Anzeige-/Fallback-Text.
  LocationInfo? loc;

  DayPlanItem({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
    this.location = '',
    this.loc,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'location': location,
        if (loc != null) 'loc': loc!.toJson(),
      };

  factory DayPlanItem.fromJson(Map<String, dynamic> j) {
    final start = DateTime.tryParse(j['start'] as String? ?? '') ?? DateTime.now();
    final end = DateTime.tryParse(j['end'] as String? ?? '') ?? start.add(const Duration(hours: 1));
    return DayPlanItem(
      id: j['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: j['title'] as String? ?? '',
      start: start,
      end: end,
      location: j['location'] as String? ?? '',
      loc: LocationInfo.tryFromJson(j['loc']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// STORE — Hive-Box 'einstellungen', Key: dayplan_yyyy-MM-dd
// ─────────────────────────────────────────────────────────────────────────────

class DayPlanStore {
  static String _hiveKey(String dateKey) => 'dayplan_$dateKey';

  /// Chronologisch sortiert (Beginn, dann Ende).
  static List<DayPlanItem> load(String dateKey) {
    final raw = Hive.box('einstellungen').get(_hiveKey(dateKey));
    if (raw is! String || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List)
          .map((e) => DayPlanItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      list.sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.end.compareTo(b.end);
      });
      return list;
    } catch (_) {
      return [];
    }
  }

  /// Billiger Check ohne JSON-Decode (für die Tageskarten).
  static bool hasItems(String dateKey) {
    final raw = Hive.box('einstellungen').get(_hiveKey(dateKey));
    return raw is String && raw.length > 2;
  }

  static Future<void> _save(String dateKey, List<DayPlanItem> items) async {
    final box = Hive.box('einstellungen');
    if (items.isEmpty) {
      await box.delete(_hiveKey(dateKey));
    } else {
            await box.put(_hiveKey(dateKey), jsonEncode(items.map((e) => e.toJson()).toList()));
    }
    await box.flush();
    unawaited(SyncService.instance.pushDayPlan(dateKey));
  }

  static Future<void> upsert(String dateKey, DayPlanItem item) async {
    final items = load(dateKey);
    final i = items.indexWhere((e) => e.id == item.id);
    if (i == -1) {
      items.add(item);
    } else {
      items[i] = item;
    }
    await _save(dateKey, items);
  }

  static Future<void> delete(String dateKey, String id) async {
    final items = load(dateKey)..removeWhere((e) => e.id == id);
    await _save(dateKey, items);
  }

  /// Sinnvoller Startwert für einen neuen Eintrag:
  /// 1. Gibt es schon Einträge → Ende des letzten (nahtlos weiterplanen)
  /// 2. Sonst heute → nächste volle Stunde
  /// 3. Sonst anderer Tag → 08:00
  static DateTime suggestedStart(String dateKey, DateTime day) {
    final items = load(dateKey);
    if (items.isNotEmpty) {
      final last = items.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);
      if (last.hour >= 23) return DateTime(day.year, day.month, day.day, 23, 0);
      return DateTime(day.year, day.month, day.day, last.hour, last.minute);
    }
    final now = DateTime.now();
    final isToday = now.year == day.year && now.month == day.month && now.day == day.day;
    if (isToday) {
      final h = now.minute == 0 ? now.hour : now.hour + 1;
      return DateTime(day.year, day.month, day.day, h >= 24 ? 23 : h, 0);
    }
    return DateTime(day.year, day.month, day.day, 8, 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHEET: Ereignis hinzufügen / bearbeiten
// Aufbau + Verhalten analog zu EntrySheet (_EventFields), aber ohne
// Ganztägig und ohne Datum (der Tag steht ja fest).
// ─────────────────────────────────────────────────────────────────────────────

class DayPlanItemSheet extends StatefulWidget {
  final AppSkin skin;
  final DateTime day;
  final DayPlanItem? existing;
    final DateTime? initialStart;
  final void Function(DayPlanItem item) onSave;
  final VoidCallback? onDelete;

  // Vorbelegung für NEUE Ereignisse (z. B. beim Teilen aus Maps)
  final String? initialTitle;
  final String? initialLocation;
  final LocationInfo? initialLoc;

  const DayPlanItemSheet({
    super.key,
    required this.skin,
    required this.day,
    required this.onSave,
    this.existing,
    this.initialStart,
    this.onDelete,
    this.initialTitle,
    this.initialLocation,
    this.initialLoc,
  });

  @override
  State<DayPlanItemSheet> createState() => _DayPlanItemSheetState();
}

class _DayPlanItemSheetState extends State<DayPlanItemSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locationCtrl;
    final _titleFocus = FocusNode();
  late DateTime _start;
  late DateTime _end;

  // ── Ort: Auto-Auswertung ──
  final _locFocus = FocusNode();
  LocationInfo? _loc;
  bool _resolving = false;
  bool _resolveFailed = false;
  bool _suppressLocListener = false;
  bool _saving = false;
  String _resolvedText = '';
  int _prevLocLength = 0;
  int _resolveSeq = 0;
  Timer? _debounce;
  Future<void>? _pending;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
        _titleCtrl = TextEditingController(text: e?.title ?? widget.initialTitle ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? widget.initialLocation ?? '');
    _loc = e?.loc ?? widget.initialLoc;
    _resolvedText = _locationCtrl.text.trim();  
    _prevLocLength = _locationCtrl.text.length;
    _locationCtrl.addListener(_onLocationChanged);
    _locFocus.addListener(_onLocFocusChanged);
    if (e != null) {
      _start = e.start;
      _end = e.end;
    } else {
      final d = widget.day;
      _start = widget.initialStart ?? DateTime(d.year, d.month, d.day, 8, 0);
      _end = _start;
      _correctEndIfBeforeStart(); // → Start + 1h (max. 23:59 am selben Tag)
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
       _debounce?.cancel();
    _locationCtrl.removeListener(_onLocationChanged);
    _locFocus.removeListener(_onLocFocusChanged);
    _suggDebounce?.cancel();
    _locationCtrl.dispose();
    _locFocus.dispose();
    _titleFocus.dispose();
    super.dispose();
  }

  // ── Ort: Auswertung ─────────────────────────────────────────────────────

  void _onLocationChanged() {
    if (_suppressLocListener) return;
    final text = _locationCtrl.text;
    final trimmed = text.trim();

    // Eingabe weicht vom ausgewerteten Stand ab → alte Auswertung verwerfen
    if (trimmed != _resolvedText && (_loc != null || _resolveFailed)) {
      setState(() {
        _loc = null;
        _resolveFailed = false;
      });
    }

    // Einfügen erkennen (großer Längensprung, Link, Zeilenumbruch) → Debounce
    final jump = text.length - _prevLocLength;
    _prevLocLength = text.length;
    final looksPasted = jump > 6 || text.contains('\n') || text.contains('http');
    if (looksPasted && _looksLikeLink(trimmed)) {
      _clearSuggestions();
    } else {
      _scheduleSuggestions(trimmed);
    }
    if (looksPasted && trimmed.isNotEmpty) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _pending = _resolveLocation();
      });
    }
  }

  void _onLocFocusChanged() {
    if (!_locFocus.hasFocus) {
      _clearSuggestions();
    } else {
      unawaited(UserPosition.get());
      _scheduleSuggestions(_locationCtrl.text.trim());
    }
    // Beim Verlassen des Feldes auswerten
    if (!_locFocus.hasFocus) {
      _debounce?.cancel();
      _pending = _resolveLocation();
    }
  }

  /// Nur eingefügte Maps-Links und Koordinaten werden automatisch ausgewertet.
  /// Getippter Text wird NICHT mehr auf einen Ort festgelegt (dafür gibt es die Vorschläge).
  bool _looksLikeLink(String t) {
    final l = t.toLowerCase();
    if (l.contains('http://') || l.contains('https://') || l.contains('goo.gl/maps') || l.contains('maps.apple.com')) {
      return true;
    }
    return RegExp(r'^-?\d{1,3}\.\d+\s*[,;]\s*-?\d{1,3}\.\d+$').hasMatch(t.trim());
  }

  Future<void> _resolveLocation() async {
    _debounce?.cancel();
    final text = _locationCtrl.text.trim();

    if (text.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loc = null;
        _resolving = false;
        _resolveFailed = false;
        _resolvedText = '';
      });
      return;
    }
    if (!_looksLikeLink(text)) {
      if (!mounted) return;
      setState(() {
        _resolving = false;
        _resolveFailed = false;
      });
      return;
    }
    if (text == _resolvedText && (_loc != null || _resolveFailed)) return;

    final seq = ++_resolveSeq;
    setState(() {
      _resolving = true;
      _resolveFailed = false;
    });

    final info = await LocationResolver.resolve(text);
    if (!mounted || seq != _resolveSeq) return;

    setState(() {
      _resolving = false;
      if (info == null) {
        // Nichts erkannt: Text bleibt unverändert, Speichern bleibt möglich
        _loc = null;
        _resolveFailed = true;
        _resolvedText = text;
      } else {
        _loc = info;
        _resolveFailed = false;
        // Feld auf die saubere, einzeilige Adresse umschreiben
        final clean = info.singleLine.isNotEmpty ? info.singleLine : (info.name ?? text);
        _suppressLocListener = true;
        _locationCtrl.value = TextEditingValue(
          text: clean,
          selection: TextSelection.collapsed(offset: clean.length),
        );
        _suppressLocListener = false;
        _prevLocLength = clean.length;
        _resolvedText = clean.trim();
      }
    });
  }

  // ── Ort: Vorschläge (Favoriten, zuletzt benutzt, Freitext – nach Standort gewichtet) ──
  List<PlaceSuggestion> _placeSuggestions = [];
  List<PlaceSuggestion> _recentSugg = [];
  List<FavoritePlace> _favSugg = [];
  bool _searchingPlaces = false;
  Timer? _suggDebounce;
  int _suggSeq = 0;
  final GlobalKey _suggKey = GlobalKey();

  void _clearSuggestions() {
    _suggDebounce?.cancel();
    _suggSeq++;
    if (!mounted) return;
    if (_placeSuggestions.isNotEmpty || _favSugg.isNotEmpty || _recentSugg.isNotEmpty || _searchingPlaces) {
      setState(() {
        _placeSuggestions = [];
        _favSugg = [];
        _recentSugg = [];
        _searchingPlaces = false;
      });
    }
  }

  /// Liste über die Tastatur scrollen.
  void _revealSuggestions() {
    Future.delayed(const Duration(milliseconds: 120), () {
      final ctx = _suggKey.currentContext;
      if (!mounted || ctx == null || Scrollable.maybeOf(ctx) == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  void _scheduleSuggestions(String q) {
    _suggDebounce?.cancel();
    if (!mounted) return;
    if (!_locFocus.hasFocus || (q.isNotEmpty && q == _resolvedText)) {
      _clearSuggestions();
      return;
    }
    // Sofort: Favoriten (solange sie zum Eingegebenen passen) + bei leerem Feld zuletzt benutzte
    final favs = FavoritePlaceStore.search(q, limit: q.isEmpty ? 5 : 4);
    final recents = q.isEmpty ? RecentPlaces.all().take(5).toList() : <PlaceSuggestion>[];
    setState(() {
      _favSugg = favs;
      _recentSugg = recents;
      if (q.length < 3) {
        _placeSuggestions = [];
        _searchingPlaces = false;
      }
    });
    _revealSuggestions();
    if (q.length < 3) {
      _suggSeq++;
      return;
    }
    final seq = ++_suggSeq;
    _suggDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || seq != _suggSeq) return;
      setState(() => _searchingPlaces = true);
      final pos = await UserPosition.quick();
      if (!mounted || seq != _suggSeq) return;
      final r = await LocationResolver.searchPlaces(
        q,
        biasLat: pos?.lat ?? _loc?.lat,
        biasLng: pos?.lng ?? _loc?.lng,
      );
      if (!mounted || seq != _suggSeq || !_locFocus.hasFocus) return;
      setState(() {
        _placeSuggestions = r;
        _searchingPlaces = false;
      });
      _revealSuggestions();
    });
  }

  String? _distText(double lat, double lng) {
    final p = UserPosition.cached;
    if (p == null) return null;
    return UserPosition.formatDistance(UserPosition.distanceM(p.lat, p.lng, lat, lng));
  }

  void _resetSuggestionState() {
    _debounce?.cancel();
    _suggDebounce?.cancel();
    _suggSeq++;
    _resolveSeq++;
  }

  /// Favorit übernehmen: Name im Feld, Titel (falls leer) befüllen, Tastatur zu.
  void _pickFavorite(FavoritePlace f) {
    HapticFeedback.selectionClick();
    _resetSuggestionState();
    _suppressLocListener = true;
    _locationCtrl.value = TextEditingValue(
      text: f.name,
      selection: TextSelection.collapsed(offset: f.name.length),
    );
    _suppressLocListener = false;
    if (_titleCtrl.text.trim().isEmpty) _titleCtrl.text = f.name;
    setState(() {
      _favSugg = [];
      _recentSugg = [];
      _placeSuggestions = [];
      _searchingPlaces = false;
      _loc = f.toLocationInfo();
      _resolving = false;
      _resolveFailed = false;
      _resolvedText = f.name.trim();
      _prevLocLength = f.name.length;
    });
    FocusManager.instance.primaryFocus?.unfocus();
    FavoritePlaceStore.touch(f.id);
  }

  Future<void> _pickSuggestion(PlaceSuggestion s) async {
    HapticFeedback.selectionClick();
    _resetSuggestionState();
    final seq = _resolveSeq;
    RecentPlaces.add(s);
    final sub = (s.subtitle ?? '').trim();
    final text = sub.isEmpty ? s.title : '${s.title}, $sub';
    _suppressLocListener = true;
    _locationCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _suppressLocListener = false;
    // Titel füllen, wenn leer und der Treffer ein benannter Ort ist (z. B. "Rossmann")
    if (_titleCtrl.text.trim().isEmpty && s.named) _titleCtrl.text = s.title;
    setState(() {
      _favSugg = [];
      _recentSugg = [];
      _placeSuggestions = [];
      _searchingPlaces = false;
      _loc = s.toLocationInfo();
      _resolving = false;
      _resolveFailed = false;
      _resolvedText = text.trim();
      _prevLocLength = text.length;
    });
    FocusManager.instance.primaryFocus?.unfocus();

    // Adresse nur nachladen, wenn der Treffer keine mitgebracht hat
    if (s.street != null || s.city != null) return;
    final info = await LocationResolver.resolve(
        '${s.lat.toStringAsFixed(6)}, ${s.lng.toStringAsFixed(6)}');
    if (!mounted || seq != _resolveSeq || info == null) return;
    setState(() {
      _loc = LocationInfo(
        rawInput: text,
        name: s.named ? s.title : null,
        street: info.street,
        postalCode: info.postalCode,
        city: info.city,
        lat: s.lat,
        lng: s.lng,
      );
    });
  }

  Future<void> _removeRecent(PlaceSuggestion p) async {
    HapticFeedback.selectionClick();
    await RecentPlaces.remove(p);
    if (!mounted) return;
    setState(() {
      _recentSugg = _recentSugg
          .where((e) => !((e.lat - p.lat).abs() < 1e-4 && (e.lng - p.lng).abs() < 1e-4))
          .toList();
    });
  }

  Widget _suggTile(
    AppSkin skin, {
    required IconData icon,
    Color? iconColor,
    required String title,
    String? subtitle,
    Widget? trailing,
    required VoidCallback onTap,
    required bool last,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: last ? Colors.transparent : skin.glassBorder, width: 0.5),
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: iconColor ?? skin.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                if ((subtitle ?? '').isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ]),
      ),
    );
  }

  Widget _buildPlaceSuggestions(AppSkin skin) {
    final favs = _favSugg;
    final recents = _recentSugg;
    bool isFav(PlaceSuggestion p) => favs.any((f) =>
        f.loc.hasCoords && (f.loc.lat! - p.lat).abs() < 1e-4 && (f.loc.lng! - p.lng).abs() < 1e-4);
    final places = _placeSuggestions.where((p) => !isFav(p)).toList();
    final total = favs.length + recents.length + places.length;
    final tail = _searchingPlaces && places.isEmpty;
    if (total == 0 && !tail) return const SizedBox(width: double.infinity);

    var i = 0;
    bool last() => (i++) == total - 1 && !tail;
    Widget dist(double lat, double lng) {
      final d = _distText(lat, lng);
      return d == null
          ? const SizedBox.shrink()
          : Text(d, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: skin.surface(0.45)));
    }

    final rows = <Widget>[
      for (final f in favs)
        _suggTile(skin,
            icon: Icons.place_outlined,
            title: f.name,
            subtitle: f.addressLine,
            trailing: const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFB347)),
            onTap: () => _pickFavorite(f),
            last: last()),
      for (final p in recents)
        _suggTile(skin,
            icon: Icons.history_rounded,
            iconColor: skin.surface(0.45),
            title: p.title,
            subtitle: p.subtitle,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              dist(p.lat, p.lng),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _removeRecent(p),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 0, 4),
                  child: Icon(Icons.close_rounded, size: 18, color: skin.surface(0.4)),
                ),
              ),
            ]),
            onTap: () => _pickSuggestion(p),
            last: last()),
      for (final p in places)
        _suggTile(skin,
            icon: Icons.place_outlined,
            title: p.title,
            subtitle: p.subtitle,
            trailing: dist(p.lat, p.lng),
            onTap: () => _pickSuggestion(p),
            last: last()),
      if (tail)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          child: Row(children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: skin.surface(0.5)),
            ),
            const SizedBox(width: 10),
            Text('Suche …', style: TextStyle(fontSize: 13, color: skin.surface(0.5))),
          ]),
        ),
    ];

    return Padding(
      key: _suggKey,
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 260),
        decoration: BoxDecoration(
          color: skin.surface(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: NotificationListener<ScrollNotification>(
          onNotification: (_) => true,
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const BouncingScrollPhysics(),
            children: rows,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationStatus(AppSkin skin) {
    if (_resolving) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: skin.surface(0.5)),
          ),
          const SizedBox(width: 10),
          Text('Adresse wird gesucht …', style: TextStyle(fontSize: 13, color: skin.surface(0.5))),
        ]),
      );
    }

    final loc = _loc;
    if (loc != null) {
      final name = (loc.name ?? '').trim();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10, left: 4),
              child: Row(children: [
                Icon(Icons.apartment_rounded, size: 14, color: skin.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                ),
              ]),
            ),
          if (loc.hasCoords)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: LocationMapCard(
                skin: skin,
                loc: loc,
                onNavigate: _navigate,
                onLocationChanged: _applyPickedLocation,
              ),
            ),
        ],
      );
    }

    if (_resolveFailed) {
      return Padding(
        padding: const EdgeInsets.only(top: 10, left: 4),
        child: Text('Adresse nicht erkannt, Text wird so gespeichert',
            style: TextStyle(fontSize: 13, color: skin.surface(0.45))),
      );
    }
    return const SizedBox(width: double.infinity);
  }

  // ── Ort: Navigieren / Löschen ───────────────────────────────────────────

  /// Wertet den Ort aus, falls der Text noch nicht ausgewertet wurde.
  Future<void> _ensureResolved() async {
    _debounce?.cancel();
    final t = _locationCtrl.text.trim();
    if (t.isNotEmpty && t != _resolvedText) {
      await _resolveLocation();
    } else if (_resolving && _pending != null) {
      await _pending;
    }
  }

  Future<void> _navigate() async {
    await _ensureResolved();
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    await MapsNavigator.navigate(
      context,
      skin: widget.skin,
      loc: _loc,
      fallbackText: _locationCtrl.text,
    );
  }

  /// Ort direkt auf der Karte auswählen (mit Suchfeld).
  Future<void> _pickOnMap() async {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    final res = await showLocationPicker(context, skin: widget.skin);
    if (res != null && mounted) _applyPickedLocation(res);
  }

  /// Neue Position aus dem Karten-Vollbild übernehmen (Adresse oder Koordinaten).
  void _applyPickedLocation(LocationInfo info) {
    if (!mounted) return;
    final nm = (info.name ?? '').trim();
    if (nm.isNotEmpty && _titleCtrl.text.trim().isEmpty) _titleCtrl.text = nm;
    final favName = (info.favoriteId != null && (info.name ?? '').trim().isNotEmpty)
        ? info.name!.trim()
        : null;
    final cleanAuto = info.singleLine.isNotEmpty
        ? info.singleLine
        : ((info.name ?? '').trim().isNotEmpty
            ? info.name!.trim()
            : '${info.lat!.toStringAsFixed(6)}, ${info.lng!.toStringAsFixed(6)}');
    final clean = favName ?? cleanAuto;
    _debounce?.cancel();
    _resolveSeq++;
    _suppressLocListener = true;
    _locationCtrl.value = TextEditingValue(
      text: clean,
      selection: TextSelection.collapsed(offset: clean.length),
    );
    _suppressLocListener = false;
    setState(() {
      _loc = info;
      _resolving = false;
      _resolveFailed = false;
      _prevLocLength = clean.length;
      _resolvedText = clean.trim();
    });
  }

  void _clearLocation() {
    _clearSuggestions();
    HapticFeedback.selectionClick();
    _debounce?.cancel();
    _resolveSeq++; // laufende Auswertung verwerfen
    _suppressLocListener = true;
    _locationCtrl.clear();
    _suppressLocListener = false;
    setState(() {
      _loc = null;
      _resolving = false;
      _resolveFailed = false;
      _resolvedText = '';
      _prevLocLength = 0;
    });
  }

  /// 1:1 die Logik aus _EventFields: Ende ≤ Beginn → Ende = Beginn + 1h,
  /// gedeckelt auf 23:59 desselben Tages.
  void _correctEndIfBeforeStart() {
    if (!_end.isAfter(_start)) {
      final sameDayCap = DateTime(_start.year, _start.month, _start.day, 23, 59);
      final proposedEnd = _start.add(const Duration(hours: 1));
      _end = proposedEnd.isAfter(sameDayCap) ? sameDayCap : proposedEnd;
    }
  }

  void _set(VoidCallback fn) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(fn);
  }

  Future<void> _pickStartTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: _start.hour, minute: _start.minute),
        skin: widget.skin,
        minuteInterval: 5,
        onTimeSelected: (t) => _set(() {
          _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute);
          _correctEndIfBeforeStart();
        }),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _pickEndTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: TimeOfDay(hour: _end.hour, minute: _end.minute),
        skin: widget.skin,
        minuteInterval: 5,
        onTimeSelected: (t) =>
            _set(() => _end = DateTime(_end.year, _end.month, _end.day, t.hour, t.minute)),
      ),
    );
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _close() {
    FocusScope.of(context).unfocus();
    Navigator.pop(context);
  }

    Future<void> _save() async {
    if (_saving) return;
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    if (_end.isBefore(_start)) {
      HapticFeedback.heavyImpact();
      showGlassSnackBar(context, 'Das Ende liegt vor dem Beginn.', type: GlassSnackBarType.warning);
      return;
    }

    _saving = true;
    _debounce?.cancel();

    // Laufende bzw. noch ausstehende Ortsauswertung abwarten (hat Timeouts)
    if (_resolving && _pending != null) await _pending;
    if (!mounted) return;
    final pendingText = _locationCtrl.text.trim();
    if (pendingText.isNotEmpty && pendingText != _resolvedText) {
      await _resolveLocation();
      if (!mounted) return;
    }

    final locText = _locationCtrl.text.trim();
    widget.onSave(DayPlanItem(
      id: widget.existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      start: _start,
      end: _end,
      location: locText,
      loc: locText.isEmpty ? null : _loc,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
        top: MediaQuery.paddingOf(context).top + 12,
      ),
      child: GlassSheet(
        skin: skin,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is ScrollUpdateNotification && n.scrollDelta != null && n.scrollDelta! < -5) {
              FocusScope.of(context).unfocus();
            }
            return false;
          },
          child: GestureDetector(
            onVerticalDragUpdate: (d) {
              if (d.delta.dy > 12) FocusScope.of(context).unfocus();
            },
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.paddingOf(context).bottom),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) > 100) _close();
                      },
                      child: Container(
                        width: double.infinity,
                        color: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: SheetHandle(skin: skin),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ── Titel ──
                    TextField(
                      controller: _titleCtrl,
                      focusNode: _titleFocus,
                      autofocus: !_isEditing && (widget.initialTitle ?? '').isEmpty,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 0),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _titleCtrl,
                          builder: (_, v, __) => v.text.isEmpty
                              ? const SizedBox.shrink()
                              : GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    _titleCtrl.clear();
                                    _titleFocus.requestFocus();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Icon(Icons.close_rounded, size: 19, color: skin.surface(0.45)),
                                  ),
                                ),
                        ),
                        hintText: 'Titel',
                        hintStyle: TextStyle(color: skin.surface(0.22), fontSize: 17),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(height: 0.6, color: skin.surface(0.10)),
                    const SizedBox(height: 16),

                    // ── Dauer: Beginn / Ende in einer Zeile ──
                    Row(children: [
                      Expanded(
                        child: _TimeField(
                          skin: skin,
                          label: 'Beginn',
                          time: TimeOfDay(hour: _start.hour, minute: _start.minute).format(context),
                          onTap: _pickStartTime,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _TimeField(
                          skin: skin,
                          label: 'Ende',
                          time: TimeOfDay(hour: _end.hour, minute: _end.minute).format(context),
                          onTap: _pickEndTime,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // ── Ort ──
                    TextField(
                      controller: _locationCtrl,
                      focusNode: _locFocus,
                      keyboardType: TextInputType.streetAddress,
                      textInputAction: TextInputAction.done,
                      // mehrzeilig, damit eingefügter Maps-Text (Name/Adresse/Link) seine Zeilenumbrüche behält
                      minLines: 1,
                      maxLines: 3,
                      style: TextStyle(color: skin.textPrimary, fontSize: 14.5, fontWeight: FontWeight.w500),
                      decoration: InputDecoration(
                        hintText: 'Ort (Adresse oder Maps-Link)',
                        hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14.5),
                        filled: true,
                        fillColor: skin.surface(0.04),
                        prefixIcon: Icon(Icons.place_outlined, size: 18, color: skin.surface(0.4)),
                        suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        suffixIcon: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _locationCtrl,
                          builder: (_, v, __) => v.text.isEmpty
                              ? GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _pickOnMap,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    child: Icon(Icons.map_outlined, size: 20, color: skin.primary),
                                  ),
                                )
                              : GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: _clearLocation,
                                  child: Icon(Icons.close_rounded, size: 18, color: skin.surface(0.4)),
                                ),
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                                               contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOut,
                      alignment: Alignment.topCenter,
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildPlaceSuggestions(skin),
                        _buildLocationStatus(skin),
                      ]),
                    ),

                    const SizedBox(height: 14),
                    GlassPrimaryButton(
                      skin: skin,
                      label: _isEditing ? 'Speichern' : 'Hinzufügen',
                      icon: Icons.check_circle_outline,
                      large: true,
                      onTap: _save,
                    ),
                    if (_isEditing && widget.onDelete != null) ...[
                      const SizedBox(height: 10),
                      GlassDangerButton(
                        skin: skin,
                        label: 'Löschen',
                        icon: Icons.delete_outline,
                        onTap: () {
                          widget.onDelete!();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback? onTap;
  const _PlanPill({required this.skin, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(color: skin.surface(0.08), borderRadius: BorderRadius.circular(10)),
        child: Text(label,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500, color: skin.textPrimary)),
      ),
    );
  }
}
class _TimeField extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final String time;
  final VoidCallback onTap;
  const _TimeField({required this.skin, required this.label, required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: skin.surface(0.04), borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: skin.surface(0.6))),
          const Spacer(),
          _PlanPill(skin: skin, label: time, onTap: onTap),
        ]),
      ),
    );
  }
}
