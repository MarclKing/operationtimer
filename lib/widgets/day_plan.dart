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
    if (looksPasted && trimmed.isNotEmpty) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 500), () {
        _pending = _resolveLocation();
      });
    }
  }

  void _onLocFocusChanged() {
    // Beim Verlassen des Feldes auswerten
    if (!_locFocus.hasFocus) {
      _debounce?.cancel();
      _pending = _resolveLocation();
    }
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
    final clean = info.singleLine.isNotEmpty
        ? info.singleLine
        : ((info.name ?? '').trim().isNotEmpty
            ? info.name!.trim()
            : '${info.lat!.toStringAsFixed(6)}, ${info.lng!.toStringAsFixed(6)}');
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
                                            child: _buildLocationStatus(skin),
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
