import 'dart:ui';
import 'dart:io' as dartio;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_pickers.dart';
import '../widgets/glass_dialogs.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/swipe_animation_mixin.dart';
import 'km_scanner_screen.dart';
import 'fuel_scanner_screen.dart';
import '../services/fahrt_export_service.dart';
import '../services/sync_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT MODEL
// ─────────────────────────────────────────────────────────────────────────────

class Fahrt {
  final String id;
  final DateTime datum;
  final int kmStart;
  final int kmEnd;
  final String kennzeichen;
  final double? getanktLiter;
  final String? fotoStartPath;
  final String? fotoEndPath;
  final bool uebertragen;
  final DateTime? abfahrtZeit;
  final DateTime? ankunftDatum;
  final DateTime? ankunftZeit;
  final String fahrtTyp;
  final bool sonderWegerecht;
  final bool autoGewaschen;
  final double? stromKwh;
  final double? adblueKwh;
  final String fahrtZiel;

  Fahrt({
    required this.id,
    required this.datum,
    required this.kmStart,
    required this.kmEnd,
    required this.kennzeichen,
    this.getanktLiter,
    this.fotoStartPath,
    this.fotoEndPath,
    this.uebertragen = false,
    this.abfahrtZeit,
    this.ankunftDatum,
    this.ankunftZeit,
    this.fahrtTyp = '',
    this.sonderWegerecht = false,
    this.autoGewaschen = false,
    this.stromKwh,
    this.adblueKwh,
    this.fahrtZiel = '',
  });

  int get kmGefahren => kmEnd - kmStart;

  Map<String, dynamic> toMap() => {
        'id': id,
        'datum': datum.toIso8601String(),
        'kmStart': kmStart,
        'kmEnd': kmEnd,
        'kennzeichen': kennzeichen,
        'getanktLiter': getanktLiter,
        'fotoStartPath': fotoStartPath,
        'fotoEndPath': fotoEndPath,
        'uebertragen': uebertragen,
        'abfahrtZeit': abfahrtZeit?.toIso8601String(),
        'ankunftDatum': ankunftDatum?.toIso8601String(),
        'ankunftZeit': ankunftZeit?.toIso8601String(),
        'fahrtTyp': fahrtTyp,
        'sonderWegerecht': sonderWegerecht,
        'autoGewaschen': autoGewaschen,
        'stromKwh': stromKwh,
        'adblueKwh': adblueKwh,
        'fahrtZiel': fahrtZiel,
      };

  factory Fahrt.fromMap(Map<String, dynamic> map) => Fahrt(
        id: map['id'] as String,
        datum: DateTime.parse(map['datum'] as String),
        kmStart: map['kmStart'] as int,
        kmEnd: map['kmEnd'] as int,
        kennzeichen: map['kennzeichen'] as String? ?? '',
        getanktLiter: (map['getanktLiter'] as num?)?.toDouble(),
        fotoStartPath: map['fotoStartPath'] as String?,
        fotoEndPath: map['fotoEndPath'] as String?,
        uebertragen: map['uebertragen'] as bool? ?? false,
        abfahrtZeit: map['abfahrtZeit'] != null ? DateTime.tryParse(map['abfahrtZeit'] as String) : null,
        ankunftDatum: map['ankunftDatum'] != null ? DateTime.tryParse(map['ankunftDatum'] as String) : null,
        ankunftZeit: map['ankunftZeit'] != null ? DateTime.tryParse(map['ankunftZeit'] as String) : null,
        fahrtTyp: map['fahrtTyp'] as String? ?? '',
        sonderWegerecht: map['sonderWegerecht'] as bool? ?? false,
        autoGewaschen: map['autoGewaschen'] as bool? ?? false,
        stromKwh: (map['stromKwh'] as num?)?.toDouble(),
        adblueKwh: (map['adblueKwh'] as num?)?.toDouble(),
        fahrtZiel: map['fahrtZiel'] as String? ?? '',
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTTYP MANAGER — Offizielle Codes + MRU-Sortierung
// ─────────────────────────────────────────────────────────────────────────────

class FahrtTyp {
  final String code;
  final String label;

  const FahrtTyp(this.code, this.label);

  String get displayShort => label.length > 22 ? '${label.substring(0, 20)}…' : label;
  String get fullLabel => '$code – $label';
}

class FahrtTypManager {
  static const _mruKey = 'fahrttyp_mru';

  static const List<FahrtTyp> allTypes = [
    FahrtTyp('190',  'Ermittlung/Einsatz (Sonst.)'),
    FahrtTyp('1111', 'Besprechung/Tagung/Workshop'),
    FahrtTyp('1112', 'Aus- und Fortbildung'),
    FahrtTyp('1113', 'Dienstsport, Schießen'),
    FahrtTyp('1114', 'Materialtransport (ohne Kf)'),
    FahrtTyp('1115', 'Personentransport (ohne Kf)'),
    FahrtTyp('1119', 'Fahrt ohne ZV-Kraftf. (Sonst.)'),
    FahrtTyp('1121', 'Materialtransport (mit Kf)'),
    FahrtTyp('1122', 'Personentransport (mit Kf)'),
    FahrtTyp('1123', 'LSch-Wechsel (Stadtfahrer)'),
    FahrtTyp('1124', 'Fahrt mit ZV-Kraftf. (Sonst.)'),
    FahrtTyp('1210', 'Liegenschaftsmanagement'),
    FahrtTyp('1221', 'Werkstattfahrt/-aufenthalt'),
    FahrtTyp('1222', 'Tankung/Wäsche/Wagenpflege'),
    FahrtTyp('1223', 'Rufbereitschaft'),
    FahrtTyp('1229', 'Fuhrparkmanagement (Sonst.)'),
    FahrtTyp('1290', 'Spezialaufgaben n-pol (Sonst.)'),
    FahrtTyp('1300', 'VB-Privatfahrt (KM erfassen!)'),
    FahrtTyp('2110', 'BAO/EG/EL'),
    FahrtTyp('2120', 'Ermittlung/Fahndung'),
    FahrtTyp('2130', 'Observation/Aufklärung'),
    FahrtTyp('2140', 'Transport/Begleitung SchPers.'),
    FahrtTyp('2150', 'Operativ/Technik'),
    FahrtTyp('2210', 'Sprengstoff / Entschärfung'),
    FahrtTyp('2220', 'Tatortarbeit'),
    FahrtTyp('2230', 'Forschung (AIT)'),
    FahrtTyp('2240', 'Asservatentransport'),
    FahrtTyp('2290', 'Kriminaltechn. Aufg. (Sonst.)'),
    FahrtTyp('3000', 'Fahrtraining gem. Konzept'),
    FahrtTyp('4000', 'Pseudobuchung'),
  ];

  static List<String> _loadMru() {
    final box = Hive.box('einstellungen');
    final raw = box.get(_mruKey);
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).toList();
  }

  static void recordUsage(String code) {
    final box = Hive.box('einstellungen');
    final mru = _loadMru();
    mru.remove(code);
    mru.insert(0, code);
    box.put(_mruKey, mru.take(10).toList());
  }

  static List<FahrtTyp> getSorted() {
    final mru = _loadMru();
    final sorted = List<FahrtTyp>.from(allTypes);
    sorted.sort((a, b) {
      final ai = mru.indexOf(a.code);
      final bi = mru.indexOf(b.code);
      if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
      if (ai >= 0) return -1;
      if (bi >= 0) return 1;
      return a.code.compareTo(b.code);
    });
    return sorted;
  }

  static FahrtTyp? byCode(String code) {
    try {
      return allTypes.firstWhere((t) => t.code == code);
    } catch (_) {
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INTELLIGENTES KM-GEDÄCHTNIS
// ─────────────────────────────────────────────────────────────────────────────

class KmMemory {
  static const _hiveKey = 'fahrtenbuch_km_memory';
  static const _maxKmDiff = 5000;
  static const _maxDaysDiff = 30;

  static Map<String, Map<String, dynamic>> _loadAll() {
    final box = Hive.box('einstellungen');
    final raw = box.get(_hiveKey);
    if (raw is! Map) return {};
    final result = <String, Map<String, dynamic>>{};
    for (final entry in raw.entries) {
      try {
        result[entry.key.toString()] = Map<String, dynamic>.from(entry.value as Map);
      } catch (_) {}
    }
    return result;
  }

  static void delete(String kennzeichen) {
    final box = Hive.box('einstellungen');
    final all = _loadAll();
    all.remove(kennzeichen.toUpperCase());
    box.put(_hiveKey, all);
  }

  static void save(String kennzeichen, int kmEnd) {
    if (kennzeichen.trim().isEmpty || kmEnd <= 0) return;
    final box = Hive.box('einstellungen');
    final all = _loadAll();
    all[kennzeichen.toUpperCase()] = {
      'kmEnd': kmEnd,
      'datum': DateTime.now().toIso8601String(),
      'kennzeichen': kennzeichen.toUpperCase(),
    };
    // Einträge auf 30 begrenzen — älteste zuerst entfernen
    if (all.length > 30) {
      final sorted = all.entries.toList()
        ..sort((a, b) {
          final da = DateTime.tryParse(a.value['datum'] as String? ?? '') ?? DateTime(2000);
          final db = DateTime.tryParse(b.value['datum'] as String? ?? '') ?? DateTime(2000);
          return da.compareTo(db); // älteste zuerst
        });
      final toRemove = sorted.take(all.length - 30);
      for (final entry in toRemove) {
        all.remove(entry.key);
      }
    }
    box.put(_hiveKey, all);
  }

  static List<Map<String, dynamic>> getAll() {
    return _loadAll().values.toList();
  }

  static int? getLastKmForKennzeichen(String kennzeichen) {
    if (kennzeichen.trim().isEmpty) return null;
    final all = _loadAll();
    final entry = all[kennzeichen.trim().toUpperCase()];
    return entry?['kmEnd'] as int?;
  }

  static List<Map<String, dynamic>> findCandidates(int kmStart) {
    final all = _loadAll();
    final candidates = <Map<String, dynamic>>[];
    final now = DateTime.now();
    for (final entry in all.values) {
      final lastKm = entry['kmEnd'] as int? ?? 0;
      final datumStr = entry['datum'] as String?;
      if (datumStr == null) continue;
      final datum = DateTime.tryParse(datumStr);
      if (datum == null) continue;
      final daysDiff = now.difference(datum).inDays;
      final kmDiff = kmStart - lastKm;
      if (kmDiff >= 0 && kmDiff <= _maxKmDiff && daysDiff <= _maxDaysDiff) {
        candidates.add({...entry, 'kmDiff': kmDiff, 'daysDiff': daysDiff});
      }
    }
    candidates.sort((a, b) => (a['kmDiff'] as int).compareTo(b['kmDiff'] as int));
    return candidates;
  }

  static int? getLastKmForAny() {
    final all = _loadAll();
    if (all.isEmpty) return null;
    Map<String, dynamic>? newest;
    DateTime? newestDate;
    for (final entry in all.values) {
      final datumStr = entry['datum'] as String?;
      if (datumStr == null) continue;
      final d = DateTime.tryParse(datumStr);
      if (d == null) continue;
      if (newestDate == null || d.isAfter(newestDate)) {
        newestDate = d;
        newest = entry;
      }
    }
    return newest?['kmEnd'] as int?;
  }

  static List<String> getHintTexts() {
    final all = _loadAll();
    if (all.isEmpty) return [];
    final sorted = all.values.toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['datum'] as String? ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['datum'] as String? ?? '') ?? DateTime(2000);
        return db.compareTo(da);
      });
    return sorted.map((e) {
      final km = e['kmEnd'] as int? ?? 0;
      final kz = e['kennzeichen'] as String? ?? '';
      return '$kz: ${_formatKm(km)} km';
    }).take(3).toList();
  }

  static String _formatKm(int km) {
    if (km >= 1000) {
      return '${km ~/ 1000}.${(km % 1000).toString().padLeft(3, '0')}';
    }
    return km.toString();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KENNZEICHEN-HELPER
// ─────────────────────────────────────────────────────────────────────────────

class KennzeichenHelper {
  static List<String> loadKnownKennzeichen() {
    final box = Hive.box('einstellungen');
    final result = <String>{};
    for (final key in box.keys) {
      final k = key.toString();
      if (!k.startsWith('fahrten_')) continue;
      final raw = box.get(k);
      if (raw is! List) continue;
      for (final e in raw) {
        try {
          final kz = (Map<String, dynamic>.from(e as Map)['kennzeichen'] as String?)?.trim();
          if (kz != null && kz.isNotEmpty) result.add(kz.toUpperCase());
        } catch (_) {}
      }
    }
    return result.toList()..sort();
  }

  static String normalize(String input, List<String> known) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return input;
    final rawInput = trimmed.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    for (final k in known) {
      if (k.replaceAll(RegExp(r'[\s\-]'), '') == rawInput) return k;
    }
    final m = RegExp(
      r'^([A-ZÄÖÜ]{1,3})'
      r'([A-ZÄÖÜ]{1,2})'
      r'(\d{1,4})'
      r'([EH]?)$'
    ).firstMatch(rawInput);
    if (m != null) {
      final ort = m.group(1)!;
      final buch = m.group(2)!;
      final num = m.group(3)!;
      final suffix = m.group(4)!;
      return '$ort-$buch $num$suffix';
    }
    return trimmed.toUpperCase();
  }

  static List<String> suggestions(String input, List<String> known) {
    if (input.trim().isEmpty) return known;
    final raw = input.trim().toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    return known.where((k) => k.replaceAll(RegExp(r'[\s\-]'), '').contains(raw)).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTZIEL-HELPER
// ─────────────────────────────────────────────────────────────────────────────

class FahrtZielHelper {
  static List<String> loadKnownZiele() {
    final box = Hive.box('einstellungen');
    final result = <String>{};
    for (final key in box.keys) {
      final k = key.toString();
      if (!k.startsWith('fahrten_')) continue;
      final raw = box.get(k);
      if (raw is! List) continue;
      for (final e in raw) {
        try {
          final ziel = (Map<String, dynamic>.from(e as Map)['fahrtZiel'] as String?)?.trim();
          if (ziel != null && ziel.isNotEmpty) result.add(ziel);
        } catch (_) {}
      }
    }
    return result.toList();
  }

  static List<String> suggestions(String input, List<String> known) {
    if (input.trim().isEmpty) return known.take(5).toList();
    final lower = input.trim().toLowerCase();
    return known
        .where((z) => z.toLowerCase().contains(lower))
        .take(5)
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DRAFT
// ─────────────────────────────────────────────────────────────────────────────

class FahrtDraft {
  String kennzeichen = '';
  DateTime abfahrtDatum = DateTime.now();
  TimeOfDay? abfahrtZeit;
  DateTime? ankunftDatum;
  TimeOfDay? ankunftZeit;
  String kmStart = '';
  String kmEnd = '';
  String? fotoStartPath;
  String? fotoEndPath;
  String fahrtTypCode = '';
  bool sonderWegerecht = false;
  bool autoGewaschen = false;
  String kraftstoff = '';
  String strom = '';
  String adblue = '';
  String fahrtZiel = '';

  FahrtDraft();

  void reset() {
    final now = DateTime.now();
    kennzeichen = '';
    abfahrtDatum = now;
    abfahrtZeit = null;
    ankunftDatum = null;
    ankunftZeit = null;
    kmStart = '';
    kmEnd = '';
    fotoStartPath = null;
    fotoEndPath = null;
    fahrtTypCode = '';
    sonderWegerecht = false;
    autoGewaschen = false;
    kraftstoff = '';
    strom = '';
    adblue = '';
    fahrtZiel = '';
  }

  bool get hasAnyData =>
      kennzeichen.isNotEmpty ||
      abfahrtZeit != null ||
      ankunftDatum != null ||
      ankunftZeit != null ||
      kmStart.isNotEmpty ||
      kmEnd.isNotEmpty ||
      fahrtTypCode.isNotEmpty ||
      sonderWegerecht ||
      autoGewaschen ||
      kraftstoff.isNotEmpty ||
      strom.isNotEmpty ||
      adblue.isNotEmpty ||
      fahrtZiel.isNotEmpty;
}

// ─────────────────────────────────────────────────────────────────────────────
// LISTEN-ITEM: entweder Monats-Header oder Fahrt
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtListItem {
  final String? sectionLabel;
  final Fahrt? fahrt;
  _FahrtListItem.header(this.sectionLabel) : fahrt = null;
  _FahrtListItem.fahrt(this.fahrt) : sectionLabel = null;
}

// ─────────────────────────────────────────────────────────────────────────────
// MONATS-TRENNER — dünne Linie + kurze Beschriftung
// ─────────────────────────────────────────────────────────────────────────────

class _MonthSectionHeader extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _MonthSectionHeader({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(children: [
        Expanded(child: Container(height: 0.6, color: skin.surface(0.10))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: skin.surface(0.4),
              letterSpacing: 1.0,
            ),
          ),
        ),
        Expanded(child: Container(height: 0.6, color: skin.surface(0.10))),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTENBUCH SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class FahrtenbuchScreen extends StatefulWidget {
  final VoidCallback? onDraftChanged;
  const FahrtenbuchScreen({super.key, this.onDraftChanged});

  @override
  State<FahrtenbuchScreen> createState() => FahrtenbuchScreenState();
}

class FahrtenbuchScreenState extends State<FahrtenbuchScreen> with TickerProviderStateMixin {
  final FahrtDraft _draft = FahrtDraft();

  bool _draftVisible = false;
  bool _sheetOpen = false;
  String? _openSwipedFahrtId;

  // ── Mehrfachauswahl ───────────────────────────────────────────────────────
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  late AnimationController _draftBannerCtrl;
  late Animation<double> _draftBannerAnim;

  final Map<String, GlobalKey<_FahrtCardState>> _fahrtCardKeys = {};
  final ScrollController _fahrtScrollController = ScrollController();

  @override
  void initState() {
    super.initState();

    _draftBannerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _draftBannerAnim = CurvedAnimation(
      parent: _draftBannerCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _selectionBarCtrl = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 320),
);
_selectionBarAnim = CurvedAnimation(
  parent: _selectionBarCtrl,
  curve: Curves.easeOutCubic,
  reverseCurve: Curves.easeInCubic,
);
  }

  late AnimationController _selectionBarCtrl;
  late Animation<double> _selectionBarAnim;

  @override
  void dispose() {
    _draftBannerCtrl.dispose();
    _selectionBarCtrl.dispose();
    _fahrtScrollController.dispose();
    super.dispose();
  }

  void scrollToTop() {
    if (_fahrtScrollController.hasClients) {
      _fahrtScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  bool get hasDraft => _draftVisible;

  // ── Mehrfachauswahl-Logik ─────────────────────────────────────────────────

  void _enterSelectionMode(String id) {
  HapticFeedback.mediumImpact();
  setState(() {
    _selectionMode = true;
    _selectedIds.add(id);
    _openSwipedFahrtId = null;
  });
  _selectionBarCtrl.forward();
}

  void _toggleSelection(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
    // Auto-Exit wenn keine mehr ausgewählt
    if (_selectedIds.isEmpty && _selectionMode) {
      _exitSelectionMode();
    }
  }
  void _exitSelectionMode() {
  _selectionBarCtrl.reverse().then((_) {
    if (mounted) {
      setState(() {
        _selectionMode = false;
        _selectedIds.clear();
      });
    }
  });
}

  Future<void> _exportSelected() async {
  final fahrten = _getAllFahrten().where((f) => _selectedIds.contains(f.id)).toList();
  if (fahrten.isEmpty) return;
  _exitSelectionMode();
  final success = await FahrtExportService.exportFahrten(fahrten);
  if (success == true) {
    for (final f in fahrten) {
      _saveFahrt(Fahrt(
        id: f.id, datum: f.datum, kmStart: f.kmStart, kmEnd: f.kmEnd,
        kennzeichen: f.kennzeichen, getanktLiter: f.getanktLiter,
        fotoStartPath: f.fotoStartPath, fotoEndPath: f.fotoEndPath,
        uebertragen: true,  // ← automatisch eingetragen
        abfahrtZeit: f.abfahrtZeit, ankunftDatum: f.ankunftDatum,
        ankunftZeit: f.ankunftZeit, fahrtTyp: f.fahrtTyp,
        sonderWegerecht: f.sonderWegerecht, autoGewaschen: f.autoGewaschen,
        stromKwh: f.stromKwh, adblueKwh: f.adblueKwh, fahrtZiel: f.fahrtZiel,
      ));
    }
  }
}

  Future<void> _exportAll() async {
  final fahrten = _getAllFahrten();
  if (fahrten.isEmpty) return;
  final success = await FahrtExportService.exportFahrten(fahrten);
  if (success == true) {
    for (final f in fahrten) {
      _saveFahrt(Fahrt(
        id: f.id, datum: f.datum, kmStart: f.kmStart, kmEnd: f.kmEnd,
        kennzeichen: f.kennzeichen, getanktLiter: f.getanktLiter,
        fotoStartPath: f.fotoStartPath, fotoEndPath: f.fotoEndPath,
        uebertragen: true,
        abfahrtZeit: f.abfahrtZeit, ankunftDatum: f.ankunftDatum,
        ankunftZeit: f.ankunftZeit, fahrtTyp: f.fahrtTyp,
        sonderWegerecht: f.sonderWegerecht, autoGewaschen: f.autoGewaschen,
        stromKwh: f.stromKwh, adblueKwh: f.adblueKwh, fahrtZiel: f.fahrtZiel,
      ));
    }
  }
}

  void closeOverlays() {
  if (_openSwipedFahrtId != null) {
    setState(() => _openSwipedFahrtId = null);
  }
  if (_selectionMode) _exitSelectionMode();
}

  void reopenDraft() {
    if (_sheetOpen) return;
    final skin = AppTheme.of(context);
    setState(() { _sheetOpen = true; _draftVisible = false; });
    widget.onDraftChanged?.call();
    _draftBannerCtrl.reverse();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
        child: _FahrtEintragenSheet(
          skin: skin, draft: _draft, isEdit: false,
          onSave: (fahrt, {editingId}) {
            _saveFahrt(fahrt);
            _draft.reset();
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onDiscard: () {
            _draft.reset();
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onMinimize: () {
            Navigator.pop(context);
            if (_draft.hasAnyData) {
              setState(() { _sheetOpen = false; _draftVisible = true; });
              _draftBannerCtrl.forward();
              widget.onDraftChanged?.call();
            } else {
              setState(() { _sheetOpen = false; _draftVisible = false; });
              widget.onDraftChanged?.call();
            }
          },
        ),
      ),
    ).then((_) {
      if (_sheetOpen) {
        if (_draft.hasAnyData) {
          setState(() { _sheetOpen = false; _draftVisible = true; });
          _draftBannerCtrl.forward();
          widget.onDraftChanged?.call();
        } else {
          setState(() { _sheetOpen = false; _draftVisible = false; });
          widget.onDraftChanged?.call();
        }
      }
    });
  }

  void showAddFahrtOverlay({bool autoScanKmStart = false}) {
    if (_sheetOpen) return;
    final skin = AppTheme.of(context);
    setState(() { _sheetOpen = true; _draftVisible = false; });
    widget.onDraftChanged?.call();
    _draftBannerCtrl.reverse();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
        child: _FahrtEintragenSheet(
          skin: skin,
          draft: _draft,
          isEdit: false,
          autoScanKmStart: autoScanKmStart,
          onSave: (fahrt, {editingId}) {
            _saveFahrt(fahrt);
            _draft.reset();
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onDiscard: () {
            _draft.reset();
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onMinimize: () {
            Navigator.pop(context);
            if (_draft.hasAnyData) {
              setState(() { _sheetOpen = false; _draftVisible = true; });
              _draftBannerCtrl.forward();
              widget.onDraftChanged?.call();
            } else {
              setState(() { _sheetOpen = false; _draftVisible = false; });
              widget.onDraftChanged?.call();
            }
          },
        ),
      ),
    ).then((_) {
      _pendingKmStartScan = false;
      if (_sheetOpen) {
        if (_draft.hasAnyData) {
          setState(() { _sheetOpen = false; _draftVisible = true; });
          _draftBannerCtrl.forward();
          widget.onDraftChanged?.call();
        } else {
          setState(() { _sheetOpen = false; _draftVisible = false; });
          widget.onDraftChanged?.call();
        }
      }
    });
  }

  void triggerKmStartScan() {
    _pendingKmStartScan = false;
    showAddFahrtOverlay(autoScanKmStart: true);
  }

  bool _pendingKmStartScan = false;

  void _editFahrt(Fahrt fahrt) {
    if (_sheetOpen) return;

    final editDraft = FahrtDraft();
    editDraft.kennzeichen = fahrt.kennzeichen;
    editDraft.abfahrtDatum = fahrt.datum;
    editDraft.abfahrtZeit = fahrt.abfahrtZeit != null ? TimeOfDay.fromDateTime(fahrt.abfahrtZeit!) : null;
    editDraft.ankunftDatum = fahrt.ankunftDatum;
    editDraft.ankunftZeit = fahrt.ankunftZeit != null ? TimeOfDay.fromDateTime(fahrt.ankunftZeit!) : null;
    editDraft.kmStart = fahrt.kmStart.toString();
    editDraft.kmEnd = fahrt.kmEnd.toString();
    editDraft.fotoStartPath = fahrt.fotoStartPath;
    editDraft.fotoEndPath = fahrt.fotoEndPath;
    editDraft.fahrtTypCode = fahrt.fahrtTyp;
    editDraft.sonderWegerecht = fahrt.sonderWegerecht;
    editDraft.autoGewaschen = fahrt.autoGewaschen;
    editDraft.kraftstoff = fahrt.getanktLiter?.toString() ?? '';
    editDraft.strom = fahrt.stromKwh?.toString() ?? '';
    editDraft.adblue = fahrt.adblueKwh?.toString() ?? '';
    editDraft.fahrtZiel = fahrt.fahrtZiel;

    final skin = AppTheme.of(context);
    setState(() { _sheetOpen = true; _draftVisible = false; });
    _draftBannerCtrl.reverse();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.08),
        child: _FahrtEintragenSheet(
          skin: skin, draft: editDraft, isEdit: true, editingId: fahrt.id,
          onSave: (updatedFahrt, {editingId}) {
            _saveFahrt(updatedFahrt);
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onDiscard: () {
            setState(() { _sheetOpen = false; _draftVisible = false; });
            _draftBannerCtrl.reverse();
          },
          onMinimize: () {
            Navigator.pop(context);
            setState(() { _sheetOpen = false; _draftVisible = false; });
          },
          onDelete: () => _deleteFahrtWithAnimation(fahrt.id),
        ),
      ),
    ).then((_) {
      setState(() { _sheetOpen = false; _draftVisible = false; });
      widget.onDraftChanged?.call();
    });
  }

  void _deleteFahrtWithAnimation(String id) {
    final cardKey = _fahrtCardKeys[id];
    if (cardKey?.currentState != null) {
      cardKey!.currentState!.animateOutAndDelete(() {
        _deleteFahrt(id);
        _fahrtCardKeys.remove(id);
      });
    } else {
      _deleteFahrt(id);
    }
  }

  /// Lädt ALLE Fahrten über alle Monate hinweg (neueste zuerst)
  List<Fahrt> _getAllFahrten() {
    final box = Hive.box('einstellungen');
    final result = <Fahrt>[];
    for (final key in box.keys) {
      final k = key.toString();
      if (!k.startsWith('fahrten_')) continue;
      final raw = box.get(k);
      if (raw is! List) continue;
      for (final e in raw) {
        try {
          result.add(Fahrt.fromMap(Map<String, dynamic>.from(e as Map)));
        } catch (_) {}
      }
    }
    result.sort((a, b) => b.datum.compareTo(a.datum)); // neueste zuerst
    return result;
  }

  /// Baut eine flache Liste aus Monats-Headern + Fahrten für die ListView
  List<_FahrtListItem> _buildGroupedItems(List<Fahrt> fahrten) {
    final items = <_FahrtListItem>[];
    String? lastMonthKey;
    for (final f in fahrten) {
      final monthKey = DateFormat('yyyy-MM').format(f.datum);
      if (monthKey != lastMonthKey) {
        items.add(_FahrtListItem.header(DateFormat('MMMM yyyy', 'de').format(f.datum)));
        lastMonthKey = monthKey;
      }
      items.add(_FahrtListItem.fahrt(f));
    }
    return items;
  }

  void _saveFahrt(Fahrt fahrt) {
    final box = Hive.box('einstellungen');
    final monthKey = DateFormat('yyyy-MM').format(fahrt.datum);
    final raw = box.get('fahrten_$monthKey');
    final existing = (raw is List)
        ? raw.map((e) => Fahrt.fromMap(Map<String, dynamic>.from(e as Map))).toList()
        : <Fahrt>[];
    final idx = existing.indexWhere((f) => f.id == fahrt.id);
    if (idx >= 0) {
      existing[idx] = fahrt;
    } else {
      existing.add(fahrt);
    }
    box.put('fahrten_$monthKey', existing.map((f) => f.toMap()).toList());
    if (fahrt.kennzeichen.isNotEmpty && fahrt.kmEnd > 0) {
      KmMemory.save(fahrt.kennzeichen, fahrt.kmEnd);
      SyncService.instance.pushFahrtenMonth(monthKey);
    }
    setState(() {});
  }

  void _deleteFahrt(String id) {
    final box = Hive.box('einstellungen');
    final fahrt = _getAllFahrten().where((f) => f.id == id).firstOrNull;
    if (fahrt == null) return;
    final monthKey = DateFormat('yyyy-MM').format(fahrt.datum);
    final raw = box.get('fahrten_$monthKey');
    if (raw is! List) return;
    final existing = raw.map((e) => Fahrt.fromMap(Map<String, dynamic>.from(e as Map))).toList();

    // Foto-Dateien löschen bevor Eintrag entfernt wird
    final toDelete = existing.where((f) => f.id == id).firstOrNull;
    if (toDelete != null) {
      if (toDelete.fotoStartPath != null) {
        try { dartio.File(toDelete.fotoStartPath!).deleteSync(); } catch (_) {}
      }
      if (toDelete.fotoEndPath != null) {
        try { dartio.File(toDelete.fotoEndPath!).deleteSync(); } catch (_) {}
      }
    }
    existing.removeWhere((f) => f.id == id);
    box.put('fahrten_$monthKey', existing.map((f) => f.toMap()).toList());
    setState(() {});
  }

  Future<bool?> _discardDraft() async {
    final skin = AppTheme.of(context);
    // ── confirmDeleteDialog aus glass_dialogs.dart ──
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Entwurf verwerfen',
      message: 'Alle eingegebenen Daten werden unwiderruflich gelöscht.',
      cancelLabel: 'Zurück',
      confirmLabel: 'Verwerfen',
    );
    if (confirmed == true && mounted) {
      _draft.reset();
      setState(() { _draftVisible = false; _sheetOpen = false; });
      _draftBannerCtrl.reverse();
      widget.onDraftChanged?.call();
    }
    return confirmed;
  }

  @override
Widget build(BuildContext context) {
  final skin = AppTheme.of(context);
  final fahrten = _getAllFahrten();
  final groupedItems = _buildGroupedItems(fahrten);
  final bottomNavHeight = 70.0 + MediaQuery.of(context).padding.bottom;
  final draftBannerHeight = 56.0;
  final extraBottomOffset = _draftVisible ? draftBannerHeight + 8 : 48.0;

  final totalFahrten = fahrten.length;
  final uebertragenCount = fahrten.where((f) => f.uebertragen).length;

  return Scaffold(
    backgroundColor: skin.bgBase,
    body: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_selectionMode) _exitSelectionMode();
        if (_openSwipedFahrtId != null) setState(() => _openSwipedFahrtId = null);
      },
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 50),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Fahrtenbuch', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                        const SizedBox(width: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB347).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFFFB347).withValues(alpha: 0.4)),
                              ),
                              child: const Text('BETA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFFFB347), letterSpacing: 0.8)),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        GlassStatCard(label: 'Fahrten', value: '$totalFahrten', color: skin.primary),
                        const SizedBox(width: 10),
                        GlassStatCard(label: 'Eingetragen', value: '$uebertragenCount', color: skin.statComplete),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        'Wischen · Gedrückt Halten · Doppeltippen',
                        style: TextStyle(fontSize: 11, color: skin.surface(0.3)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: (fahrten.isEmpty)
                      ? Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Text('🚗', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Keine Fahrten eingetragen', style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                            const SizedBox(height: 6),
                            Text(
                              'Tippe auf + um eine Fahrt einzutragen',
                              style: TextStyle(color: skin.surface(0.2), fontSize: 12),
                              textAlign: TextAlign.center,
                            ),
                          ]),
                        )
                      : FadingListView(
                          fadeFromBottom: bottomNavHeight + extraBottomOffset + 20,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => setState(() => _openSwipedFahrtId = null),
                            child: ListView.builder(
                              controller: _fahrtScrollController,
                              padding: const EdgeInsets.fromLTRB(24, 4, 24, 0),
                              itemCount: groupedItems.length + 1,
                              itemBuilder: (context, index) {
                                if (index == groupedItems.length) {
  return Padding(
    padding: EdgeInsets.fromLTRB(0, 8, 0, bottomNavHeight + extraBottomOffset + 32),
    child: _ExportButtonAnimated(
      skin: skin,
      animation: _selectionBarAnim,
      selectedCount: _selectedIds.length,
      onExportAll: _exportAll,
      onExportSelected: _exportSelected,
      onExitSelection: _exitSelectionMode,
    ),
  );
}
                                final item = groupedItems[index];
                                if (item.sectionLabel != null) {
                                  return _MonthSectionHeader(label: item.sectionLabel!, skin: skin);
                                }
                                final fahrt = item.fahrt!;
                                _fahrtCardKeys.putIfAbsent(fahrt.id, () => GlobalKey<_FahrtCardState>());
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _FahrtCard(
                                    key: _fahrtCardKeys[fahrt.id],
                                    fahrt: fahrt, skin: skin,
                                    selectionMode: _selectionMode,
                                    isSelected: _selectedIds.contains(fahrt.id),
                                    onLongPress: () => _enterSelectionMode(fahrt.id),
                                    onSelectTap: () => _toggleSelection(fahrt.id),
                                    onDelete: () => _deleteFahrtWithAnimation(fahrt.id),
                                    onToggleUebertragen: () {
                                      _saveFahrt(Fahrt(
                                        id: fahrt.id, datum: fahrt.datum,
                                        kmStart: fahrt.kmStart, kmEnd: fahrt.kmEnd,
                                        kennzeichen: fahrt.kennzeichen, getanktLiter: fahrt.getanktLiter,
                                        fotoStartPath: fahrt.fotoStartPath, fotoEndPath: fahrt.fotoEndPath,
                                        uebertragen: !fahrt.uebertragen,
                                        abfahrtZeit: fahrt.abfahrtZeit, ankunftDatum: fahrt.ankunftDatum,
                                        ankunftZeit: fahrt.ankunftZeit, fahrtTyp: fahrt.fahrtTyp,
                                        sonderWegerecht: fahrt.sonderWegerecht, autoGewaschen: fahrt.autoGewaschen,
                                        stromKwh: fahrt.stromKwh, adblueKwh: fahrt.adblueKwh, fahrtZiel: fahrt.fahrtZiel,
                                      ));
                                    },
                                    onEdit: () => _editFahrt(fahrt),
                                    externallyOpenKey: _openSwipedFahrtId,
                                    onCardSwiped: (id) => setState(() => _openSwipedFahrtId = id),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),

          // ── Draft Banner ────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _draftBannerAnim,
            builder: (context, child) {
              if (!_draftVisible && _draftBannerAnim.value == 0) return const SizedBox.shrink();
              final bottomOffset = bottomNavHeight + 12;
              return Positioned(
                bottom: bottomOffset, left: 16, right: 16,
                child: Transform.translate(
                  offset: Offset(0, 8 * (1 - _draftBannerAnim.value)),
                  child: Opacity(opacity: _draftBannerAnim.value.clamp(0.0, 1.0), child: child),
                ),
              );
            },
            child: _DraftBanner(skin: skin, onReopen: reopenDraft, onDiscard: _discardDraft),
          ),

          // ── Glass FAB ───────────────────────────────────────────────────────
          AnimatedBuilder(
            animation: _selectionBarAnim,
            builder: (context, child) {
              final bottomOffset = _draftVisible
                  ? bottomNavHeight + draftBannerHeight + 20
                  : bottomNavHeight + 16;
              // FAB blendet aus wenn Selection aktiv
              return Positioned(
                bottom: bottomOffset,
                right: 20,
                child: Opacity(
                  opacity: (1 - _selectionBarAnim.value).clamp(0.0, 1.0),
                  child: child,
                ),
              );
            },
            child: GestureDetector(
              onTap: () {
                if (_sheetOpen) return;
                if (_draftVisible) {
                  reopenDraft();
                } else {
                  showAddFahrtOverlay();
                }
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: skin.isLight
                          ? Colors.white.withValues(alpha: 0.72)
                          : Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: skin.isLight
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      _draftVisible ? Icons.edit_note_rounded : Icons.add,
                      color: skin.primary,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
}

// ─────────────────────────────────────────────────────────────────────────────
// ENTWURFS-BANNER
// ─────────────────────────────────────────────────────────────────────────────

class _DraftBanner extends StatefulWidget {
  final AppSkin skin;
  final VoidCallback onReopen;
  final Future<bool?> Function() onDiscard;
  const _DraftBanner({required this.skin, required this.onReopen, required this.onDiscard});

  @override
  State<_DraftBanner> createState() => _DraftBannerState();
}

class _DraftBannerState extends State<_DraftBanner> {
  double _drag = 0;
  bool _hapticFired = false;
  static const double _threshold = 90.0;
  static const double _maxDrag = 160.0;

  void _reset() => setState(() { _drag = 0; _hapticFired = false; });

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final progress = (-_drag / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: _drag == 0 ? widget.onReopen : null,
      onHorizontalDragUpdate: (d) {
        final next = (_drag + d.delta.dx).clamp(-_maxDrag, 0.0);
        setState(() => _drag = next);
        if (!_hapticFired && -_drag >= _threshold) { _hapticFired = true; HapticFeedback.mediumImpact(); }
        else if (_hapticFired && -_drag < _threshold) { _hapticFired = false; }
      },
      onHorizontalDragEnd: (d) async {
        if (-_drag >= _threshold) {
          HapticFeedback.heavyImpact();
          final confirmed = await widget.onDiscard();
          if (confirmed != true && mounted) _reset();
        } else {
          _reset();
        }
      },
      child: Stack(children: [
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: skin.deleteColor.withValues(alpha: 0.15 + progress * 0.15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25 + progress * 0.35), width: 0.8),
                ),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 22),
                    child: Opacity(
                      opacity: progress,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.delete_outline, color: skin.deleteColor, size: 18),
                        const SizedBox(width: 6),
                        Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 13,
                            fontWeight: progress >= 1.0 ? FontWeight.w800 : FontWeight.w600)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(_drag, 0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12),
                    width: 0.8,
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35), blurRadius: 24, offset: const Offset(0, 6))],
                ),
                child: Stack(children: [
                  Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.edit_note_rounded, size: 18, color: skin.primary),
                    const SizedBox(width: 8),
                    Text('Neue Fahrt – Entwurf', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                  ])),
                  Positioned(top: 6, left: 0, right: 0,
                    child: Center(child: Container(width: 40, height: 4,
                        decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2))))),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXPORT BUTTON MIT SELECTION-ANIMATION
// ─────────────────────────────────────────────────────────────────────────────

class _ExportButtonAnimated extends StatelessWidget {
  final AppSkin skin;
  final Animation<double> animation;
  final int selectedCount;
  final VoidCallback onExportAll;
  final VoidCallback onExportSelected;
  final VoidCallback onExitSelection;

  const _ExportButtonAnimated({
    required this.skin,
    required this.animation,
    required this.selectedCount,
    required this.onExportAll,
    required this.onExportSelected,
    required this.onExitSelection,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final p = animation.value; // 0 = normal, 1 = selection

        // Breite: normal = nur Label-Breite (min), selection = volle Breite
        // Wir verwenden einen AnimatedContainer-ähnlichen Ansatz über SizedBox
        // height bleibt konstant bei 50
        const double buttonHeight = 50.0;

        // Chips-Scale: erscheinen von 0 → 1 gestaffelt
        final closeScale = Curves.easeOutBack.transform(
          ((p - 0.1) / 0.6).clamp(0.0, 1.0),
        );
        final countScale = Curves.easeOutBack.transform(
          ((p - 0.2) / 0.6).clamp(0.0, 1.0),
        );
        final exportChipScale = Curves.easeOutBack.transform(
          ((p - 0.3) / 0.6).clamp(0.0, 1.0),
        );
        final normalOpacity = (1 - p * 2.5).clamp(0.0, 1.0);
        final selectionOpacity = ((p - 0.4) / 0.6).clamp(0.0, 1.0);

        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Der Button selbst wächst von "auto" auf "full row minus margins"
            // indem wir den Clip/Container animieren
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: double.infinity,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: AnimatedContainer(
                    duration: Duration.zero, // wird durch AnimatedBuilder gesteuert
                    height: buttonHeight,
                    // Padding schmilzt beim Übergang
                    padding: EdgeInsets.symmetric(
                      horizontal: 20 + p * 4,
                      vertical: 0,
                    ),
                    decoration: BoxDecoration(
                      // Im Selection-Mode: glassmorphism weiß/schwarz
                      // Im Normal-Mode: primary-tint
                      color: Color.lerp(
                        skin.primary.withValues(alpha: 0.07),
                        skin.isLight
                            ? Colors.white.withValues(alpha: 0.88)
                            : Colors.black.withValues(alpha: 0.70),
                        p,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Color.lerp(
                          skin.primary.withValues(alpha: 0.22),
                          skin.glassBorder,
                          p,
                        )!,
                        width: 1.0 + p * 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08 + p * 0.10),
                          blurRadius: 12 + p * 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // ── Normal Label ──
                        Opacity(
                          opacity: normalOpacity,
                          child: GestureDetector(
                            onTap: p < 0.1 ? onExportAll : null,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.upload_outlined,
                                    color: skin.primary, size: 16),
                                const SizedBox(width: 7),
                                Text(
                                  'Alle Fahrten exportieren',
                                  style: TextStyle(
                                    color: skin.primary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // ── Selection Chips ──
                        Opacity(
                          opacity: selectionOpacity,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // X Button
                              Transform.scale(
                                scale: closeScale,
                                child: GestureDetector(
                                  onTap: onExitSelection,
                                  child: Container(
                                    padding: const EdgeInsets.all(7),
                                    decoration: BoxDecoration(
                                      color: skin.surface(0.08),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: Icon(Icons.close_rounded,
                                        size: 16, color: skin.textMuted),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Count
                              Transform.scale(
                                scale: countScale,
                                child: Text(
                                  '$selectedCount ausgewählt',
                                  style: TextStyle(
                                    color: skin.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Export Chip
                              Transform.scale(
                                scale: exportChipScale,
                                child: GestureDetector(
                                  onTap: onExportSelected,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(
                                      gradient: skin.gradient,
                                      borderRadius: BorderRadius.circular(11),
                                      boxShadow: [
                                        BoxShadow(
                                          color: skin.primaryWithAlpha(0.30),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        )
                                      ],
                                    ),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.upload_outlined,
                                              size: 14,
                                              color: skin.onGradient),
                                          const SizedBox(width: 5),
                                          Text('Exportieren',
                                              style: TextStyle(
                                                color: skin.onGradient,
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                              )),
                                        ]),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT CARD — SwipeAnimationMixin statt Future.doWhile
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtCard extends StatefulWidget {
  final Fahrt fahrt;
  final AppSkin skin;
  final VoidCallback onDelete, onToggleUebertragen, onEdit;
  final String? externallyOpenKey;
  final void Function(String?) onCardSwiped;

  // Mehrfachauswahl
  final bool selectionMode;
  final bool isSelected;
  final VoidCallback? onLongPress;
  final VoidCallback? onSelectTap;

  const _FahrtCard({
    super.key, required this.fahrt, required this.skin,
    required this.onDelete, required this.onToggleUebertragen, required this.onEdit,
    this.externallyOpenKey, required this.onCardSwiped,
    this.selectionMode = false,
    this.isSelected = false,
    this.onLongPress,
    this.onSelectTap,
  });

  @override
  State<_FahrtCard> createState() => _FahrtCardState();
}

// ── SwipeAnimationMixin ersetzt die private _animateTo(Future.doWhile)-Methode ──
class _FahrtCardState extends State<_FahrtCard>
    with TickerProviderStateMixin, SwipeAnimationMixin {
  static const double _rightRevealWidth = 90.0;
  static const double _leftRevealWidth = 190.0;
  static const double _snapThreshold = 50.0;
  bool _isOpenRight = false, _isOpenLeft = false, _dragging = false;
  double _dragStartX = 0, _dragStartY = 0;

  late AnimationController _deleteAnimController;
  late Animation<double> _slideOutAnim, _fadeOutAnim, _heightCollapseAnim;

  @override
  void initState() {
    super.initState();
    // SwipeAnimationMixin initialisieren (ersetzt altes Future.doWhile)
    initSwipeAnimation(vsync: this);

    _deleteAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideOutAnim = Tween<double>(begin: 0, end: -420).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.0, 0.6, curve: Curves.easeInBack)));
    _fadeOutAnim = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.25, 0.7, curve: Curves.easeOut)));
    _heightCollapseAnim = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteAnimController, curve: const Interval(0.6, 1.0, curve: Curves.easeInOut)));
    _deleteAnimController.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    disposeSwipeAnimation(); // Mixin aufräumen
    _deleteAnimController.dispose();
    super.dispose();
  }

  void animateOutAndDelete(VoidCallback onDone) {
    _deleteAnimController.forward().then((_) => onDone());
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = false;
    _dragStartX = d.globalPosition.dx;
    _dragStartY = d.globalPosition.dy;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final totalDx = d.globalPosition.dx - _dragStartX;
    final totalDy = (d.globalPosition.dy - _dragStartY).abs();
    if (!_dragging) {
      if (totalDy > totalDx.abs()) return;
      if (totalDx.abs() < 8) return;
      _dragging = true;
    }
    final newOffset = (swipeOffset + d.delta.dx).clamp(-_rightRevealWidth, _leftRevealWidth);
    setSwipeOffsetImmediate(newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;
    if (swipeOffset < -_snapThreshold || v < -400) {
      animateSwipeTo(-_rightRevealWidth);
      setState(() { _isOpenRight = true; _isOpenLeft = false; });
      widget.onCardSwiped(widget.fahrt.id);
    } else if (swipeOffset > _snapThreshold || v > 400) {
      animateSwipeTo(_leftRevealWidth);
      setState(() { _isOpenLeft = true; _isOpenRight = false; });
      widget.onCardSwiped(widget.fahrt.id);
    } else {
      animateSwipeTo(0);
      setState(() { _isOpenRight = false; _isOpenLeft = false; });
      widget.onCardSwiped(null);
    }
  }

  void _close() {
    animateSwipeTo(0);
    if (mounted) setState(() { _isOpenRight = false; _isOpenLeft = false; });
    widget.onCardSwiped(null);
  }

  void _showShareAlert(BuildContext context, AppSkin skin, Fahrt fahrt) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.50),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
        return ScaleTransition(scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
            child: FadeTransition(opacity: anim, child: child));
      },
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 36),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: skin.isLight ? Colors.white.withValues(alpha: 0.94) : skin.bgCard.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 28, offset: const Offset(0, 8))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: skin.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.ios_share_outlined, color: skin.primary, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Fahrt teilen', style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(DateFormat('dd.MM.yyyy', 'de').format(fahrt.datum), style: TextStyle(color: skin.textMuted, fontSize: 12)),
                    ])),
                  ]),
                  const SizedBox(height: 18),
                  Row(children: [
                    Expanded(child: GestureDetector(
                      onTap: () { Navigator.pop(ctx); HapticFeedback.selectionClick(); widget.onToggleUebertragen(); },
                      child: AspectRatio(aspectRatio: 1, child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: skin.statComplete.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: skin.statComplete.withValues(alpha: 0.30)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(fahrt.uebertragen ? Icons.check_circle_rounded : Icons.check_circle_outline, color: skin.statComplete, size: 30),
                          const SizedBox(height: 10),
                          Text(fahrt.uebertragen ? 'Eingetragen' : 'Eintragen', textAlign: TextAlign.center,
                              style: TextStyle(color: skin.statComplete, fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      )),
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        HapticFeedback.selectionClick();
                        showGlassSnackBar(
  context,
  'Export kommt bald…',
  type: GlassSnackBarType.info,
  duration: const Duration(seconds: 2),
);
                      },
                      child: AspectRatio(aspectRatio: 1, child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: skin.primary.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: skin.primary.withValues(alpha: 0.20)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.upload_file_outlined, color: skin.primary, size: 30),
                          const SizedBox(height: 10),
                          Text('Exportieren', textAlign: TextAlign.center,
                              style: TextStyle(color: skin.primary, fontSize: 14, fontWeight: FontWeight.w600)),
                        ]),
                      )),
                    )),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(_FahrtCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.externallyOpenKey != widget.fahrt.id && (_isOpenRight || _isOpenLeft)) {
      animateSwipeTo(0);
      setState(() { _isOpenRight = false; _isOpenLeft = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final fahrt = widget.fahrt;
    final dayName = DateFormat('EEE', 'de').format(fahrt.datum);
    final dayNum = DateFormat('dd', 'de').format(fahrt.datum);
    final monthAbbr = DateFormat('MMM', 'de').format(fahrt.datum);
    final hatGetankt = fahrt.getanktLiter != null && fahrt.getanktLiter! > 0;

    final rightProgress = (swipeOffset.abs() / _rightRevealWidth).clamp(0.0, 1.0);
    final leftProgress = (swipeOffset / _leftRevealWidth).clamp(0.0, 1.0);

    final fahrtTypObj = FahrtTypManager.byCode(fahrt.fahrtTyp);

    return AnimatedBuilder(
      animation: _deleteAnimController,
      builder: (context, child) => SizeTransition(
        sizeFactor: _heightCollapseAnim, axisAlignment: -1,
        child: Opacity(opacity: _fadeOutAnim.value,
            child: Transform.translate(offset: Offset(_slideOutAnim.value, 0), child: child!)),
      ),
      child: GestureDetector(
        onHorizontalDragStart: widget.selectionMode ? null : _onPanStart,
        onHorizontalDragUpdate: widget.selectionMode ? null : _onPanUpdate,
        onHorizontalDragEnd: widget.selectionMode ? null : _onPanEnd,
        onTap: widget.selectionMode
            ? widget.onSelectTap
            : ((_isOpenRight || _isOpenLeft) ? _close : null),
        onDoubleTap: widget.selectionMode ? null : () { if (!_isOpenRight && !_isOpenLeft) widget.onEdit(); },
        onLongPress: widget.selectionMode ? null : widget.onLongPress,
        child: SizedBox(
          height: 90,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                if (swipeOffset <= 0)
                  Positioned(
                    right: 0, top: 4, bottom: 4, width: _rightRevealWidth,
                    child: Opacity(opacity: rightProgress, child: Transform.scale(
                      scale: rightProgress, alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () { _close(); widget.onDelete(); },
                        child: ClipRRect(borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              margin: const EdgeInsets.only(left: 5),
                              decoration: BoxDecoration(
                                color: skin.deleteColor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
                              ),
                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.delete_outline, color: skin.deleteColor, size: 22),
                                const SizedBox(height: 4),
                                Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 11, fontWeight: FontWeight.w600)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                    )),
                  ),

                if (swipeOffset >= 0)
                  Positioned(
                    left: 0, top: 4, bottom: 4, width: _leftRevealWidth,
                    child: Row(children: [
                      Expanded(child: Opacity(opacity: leftProgress, child: Transform.scale(
                        scale: leftProgress, alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () { _close(); widget.onEdit(); },
                          child: ClipRRect(borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                margin: const EdgeInsets.only(left: 5, right: 5),
                                decoration: BoxDecoration(
                                  color: skin.primary.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: skin.primary.withValues(alpha: 0.22)),
                                ),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.edit_outlined, color: skin.primary, size: 22),
                                  const SizedBox(height: 4),
                                  Text('Bearb.', style: TextStyle(color: skin.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ))),
                      Expanded(child: Opacity(opacity: leftProgress, child: Transform.scale(
                        scale: leftProgress, alignment: Alignment.centerRight,
                        child: GestureDetector(
                          onTap: () { _close(); _showShareAlert(context, skin, fahrt); },
                          child: ClipRRect(borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                margin: const EdgeInsets.only(right: 5),
                                decoration: BoxDecoration(
                                  color: skin.statComplete.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: skin.statComplete.withValues(alpha: 0.22)),
                                ),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.ios_share_outlined, color: skin.statComplete, size: 22),
                                  const SizedBox(height: 4),
                                  Text('Teilen', style: TextStyle(color: skin.statComplete, fontSize: 11, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ),
                        ),
                      ))),
                    ]),
                  ),

                Transform.translate(
                  offset: Offset(widget.selectionMode ? 0 : swipeOffset, 0),
                  child: Stack(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                            child: Container(
                              decoration: BoxDecoration(
                                color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: fahrt.uebertragen ? skin.statComplete.withValues(alpha: 0.35) : skin.glassBorder,
                                  width: fahrt.uebertragen ? 1.5 : 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
                                  BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 52,
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                      Text(dayName.toUpperCase(),
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: skin.surface(0.38))),
                                      const SizedBox(height: 2),
                                      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                                        Text(dayNum, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: skin.textPrimary, height: 1)),
                                        const SizedBox(width: 3),
                                        Text(monthAbbr, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: skin.surface(0.3))),
                                      ]),
                                    ]),
                                  ),
                                  Container(width: 1, height: 44, margin: const EdgeInsets.symmetric(horizontal: 12), color: skin.surface(0.07)),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            return _AdaptiveKmRow(
                                              kmStart: fahrt.kmStart,
                                              kmEnd: fahrt.kmEnd,
                                              skin: skin,
                                              maxWidth: constraints.maxWidth,
                                            );
                                          },
                                        ),
                                        if (fahrt.kennzeichen.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Row(children: [
                                            Icon(Icons.directions_car_outlined, size: 13, color: skin.surface(0.35)),
                                            const SizedBox(width: 4),
                                            Flexible(child: Text(fahrt.kennzeichen,
                                                style: TextStyle(fontSize: 12, color: skin.surface(0.42), fontWeight: FontWeight.w500),
                                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                                            if (hatGetankt) ...[
                                              const SizedBox(width: 8),
                                              Icon(Icons.local_gas_station_outlined, size: 13, color: skin.primary.withValues(alpha: 0.55)),
                                            ],
                                            if (fahrt.sonderWegerecht) ...[
                                              const SizedBox(width: 6),
                                              Icon(Icons.emergency_outlined, size: 13, color: const Color(0xFF2962FF).withValues(alpha: 0.75)),
                                            ],
                                          ]),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        fahrt.kmStart == 0 || fahrt.kmEnd == 0 ? '—' : '${fahrt.kmGefahren} km',
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: skin.textPrimary),
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 100,
                                        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                          Icon(
                                            fahrt.uebertragen ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                                            size: 12,
                                            color: fahrt.uebertragen ? skin.statComplete : skin.statOpen,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(child: Text(
                                            fahrt.fahrtTyp.isNotEmpty
                                                ? (fahrtTypObj != null ? fahrtTypObj.label : fahrt.fahrtTyp)
                                                : (fahrt.fahrtZiel.isNotEmpty ? fahrt.fahrtZiel : (fahrt.uebertragen ? 'Eingetr.' : 'Offen')),
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: skin.textMuted),
                                            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.right,
                                          )),
                                        ]),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Auswahl-Overlay
                      if (widget.selectionMode)
                        Positioned.fill(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            decoration: BoxDecoration(
                              color: widget.isSelected
                                  ? widget.skin.primary.withValues(alpha: 0.18)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: widget.isSelected
                                    ? widget.skin.primary.withValues(alpha: 0.6)
                                    : widget.skin.glassBorder,
                                width: widget.isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: widget.isSelected
                                ? Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: widget.skin.primary,
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                      ),
                                    ),
                                  )
                                : Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          border: Border.all(color: widget.skin.surface(0.3), width: 1.5),
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADAPTIVE KM ROW
// ─────────────────────────────────────────────────────────────────────────────

class _AdaptiveKmRow extends StatelessWidget {
  final int kmStart, kmEnd;
  final AppSkin skin;
  final double maxWidth;

  const _AdaptiveKmRow({
    required this.kmStart, required this.kmEnd,
    required this.skin, required this.maxWidth,
  });

  String _fmt(int km) {
    final h = (km % 1000).toString().padLeft(3, '0');
    final t = km ~/ 1000;
    return t > 0 ? '$t.$h' : h;
  }

  Widget _kmText(String formatted) {
    if (formatted == '—') {
      return Text(
        '—',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: skin.textPrimary.withValues(alpha: 0.3),
          letterSpacing: -1,
        ),
      );
    }

    final dotIdx = formatted.indexOf('.');
    if (dotIdx < 0) {
      return Text(
        formatted,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: skin.textPrimary,
          letterSpacing: -1,
        ),
      );
    }
    final thousands = formatted.substring(0, dotIdx);
    final rest = formatted.substring(dotIdx);
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: thousands,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: skin.textPrimary.withValues(alpha: 0.5),
              letterSpacing: -0.3,
            ),
          ),
          TextSpan(
            text: rest,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: skin.textPrimary,
              letterSpacing: -1,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startStr = kmStart == 0 ? '—' : _fmt(kmStart);
    final endStr = kmEnd == 0 ? '—' : _fmt(kmEnd);

    final estimatedWidth = (startStr.length + endStr.length) * 13.0 + 30;

    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        _kmText(startStr),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: Icon(Icons.arrow_forward, size: 13, color: skin.surface(0.2)),
        ),
        _kmText(endStr),
      ],
    );

    if (estimatedWidth > maxWidth) {
      return SizedBox(
        width: maxWidth,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: row,
        ),
      );
    }
    return row;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TOGGLE KACHEL (Sirenen-Effekt)
// ─────────────────────────────────────────────────────────────────────────────

class _ToggleKachel extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final AppSkin skin;
  final VoidCallback onTap;
  final bool policeLights;

  const _ToggleKachel({
    required this.label, required this.icon, required this.active,
    required this.activeColor, required this.skin, required this.onTap, this.policeLights = false,
  });

  @override
  State<_ToggleKachel> createState() => _ToggleKachelState();
}

class _ToggleKachelState extends State<_ToggleKachel> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Color?> _sirenColor;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _sirenColor = ColorTween(begin: const Color(0xFF2962FF), end: const Color(0xFFD32F2F))
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final active = widget.active;
    final activeColor = widget.activeColor;

    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); widget.onTap(); },
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final Color currentColor = (active && widget.policeLights)
              ? (_sirenColor.value ?? const Color(0xFF2962FF)) : activeColor;
          final Border border;
          if (active && widget.policeLights) border = Border.all(color: currentColor.withValues(alpha: 0.55), width: 1.5);
          else if (active) border = Border.all(color: activeColor.withValues(alpha: 0.45), width: 1.5);
          else border = Border.all(color: skin.glassBorder, width: 1.0);

          final Color fillColor;
          if (active && widget.policeLights) fillColor = currentColor.withValues(alpha: skin.isLight ? 0.10 : 0.18);
          else if (active) fillColor = activeColor.withValues(alpha: skin.isLight ? 0.13 : 0.18);
          else fillColor = skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity);

          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: fillColor, borderRadius: BorderRadius.circular(16), border: border,
                  boxShadow: [
                    BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
                    if (active && widget.policeLights)
                      BoxShadow(color: currentColor.withValues(alpha: 0.20), blurRadius: 12, spreadRadius: 1),
                  ],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(active ? Icons.check_circle_rounded : widget.icon, size: 18,
                      color: active ? currentColor : skin.surface(0.35)),
                  const SizedBox(width: 8),
                  Flexible(child: Text(widget.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: active ? currentColor : skin.surface(0.45)),
                      maxLines: 2, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRT EINTRAGEN SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtEintragenSheet extends StatefulWidget {
  final AppSkin skin;
  final FahrtDraft draft;
  final bool isEdit;
  final String? editingId;
  final void Function(Fahrt, {String? editingId}) onSave;
  final VoidCallback onDiscard, onMinimize;
  final VoidCallback? onDelete;
  final bool autoScanKmStart;

  const _FahrtEintragenSheet({
    required this.skin,
    required this.draft,
    required this.isEdit,
    required this.onSave,
    required this.onDiscard,
    required this.onMinimize,
    this.editingId,
    this.onDelete,
    this.autoScanKmStart = false,
  });

  @override
  State<_FahrtEintragenSheet> createState() => _FahrtEintragenSheetState();
}

class _FahrtEintragenSheetState extends State<_FahrtEintragenSheet> {
  final _kennzeichenCtrl = TextEditingController();
  late DateTime _abfahrtDatum;
  TimeOfDay? _abfahrtZeit, _ankunftZeit;
  DateTime? _ankunftDatum;

  final _kmStartCtrl = TextEditingController();
  final _kmEndCtrl = TextEditingController();
  String? _fotoStartPath, _fotoEndPath;

  String _fahrtTypCode = '';
  List<FahrtTyp> _sortedTypes = [];

  bool _sonderWegerecht = false, _autoGewaschen = false;

  final _kraftstoffCtrl = TextEditingController();
  final _stromCtrl = TextEditingController();
  final _adblueCtrl = TextEditingController();
  final _fahrtZielCtrl = TextEditingController();

  List<Map<String, dynamic>> _kmCandidates = [];
  bool _kmCandidateShown = false;
  int? _lastKmHint;
  bool _finalized = false;

  List<String> _knownZiele = [];

  final Map<String, DateTime> _lastAlertTime = {};
  static const Duration _alertCooldown = Duration(seconds: 3);

  bool _canShowAlert(String key) {
    final last = _lastAlertTime[key];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _alertCooldown) return false;
    _lastAlertTime[key] = now;
    return true;
  }

  final _scrollCtrl = ScrollController();
  AppSkin get skin => widget.skin;
  FahrtDraft get _d => widget.draft;

  @override
  void initState() {
    super.initState();
    _kennzeichenCtrl.text = _d.kennzeichen;
    _abfahrtDatum = _d.abfahrtDatum;
    _abfahrtZeit = _d.abfahrtZeit;
    _ankunftDatum = _d.ankunftDatum;
    _ankunftZeit = _d.ankunftZeit;
    _kmStartCtrl.text = _d.kmStart;
    _kmEndCtrl.text = _d.kmEnd;
    _fotoStartPath = _d.fotoStartPath;
    _fotoEndPath = _d.fotoEndPath;
    _fahrtTypCode = _d.fahrtTypCode;
    _sonderWegerecht = _d.sonderWegerecht;
    _autoGewaschen = _d.autoGewaschen;
    _kraftstoffCtrl.text = _d.kraftstoff;
    _stromCtrl.text = _d.strom;
    _adblueCtrl.text = _d.adblue;
    _fahrtZielCtrl.text = _d.fahrtZiel;

    _sortedTypes = FahrtTypManager.getSorted();
    _updateKmHint();
    _knownZiele = FahrtZielHelper.loadKnownZiele();

    _kennzeichenCtrl.addListener(_updateKmHint);
    _kmStartCtrl.addListener(_syncDraft);
    _kmEndCtrl.addListener(_syncDraft);
    _kraftstoffCtrl.addListener(_syncDraft);
    _stromCtrl.addListener(_syncDraft);
    _adblueCtrl.addListener(_syncDraft);
    _fahrtZielCtrl.addListener(_syncDraft);
    _kennzeichenCtrl.addListener(_syncDraft);

    if (widget.autoScanKmStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted) _pickPhoto(true);
        });
      });
    }
  }

  void _updateKmHint() {
    final kz = _kennzeichenCtrl.text.trim();
    final hint = kz.isEmpty ? null : KmMemory.getLastKmForKennzeichen(kz);
    if (hint != _lastKmHint) setState(() => _lastKmHint = hint);
  }

  void _syncDraft() {
    _d.kennzeichen = _kennzeichenCtrl.text;
    _d.abfahrtDatum = _abfahrtDatum;
    _d.abfahrtZeit = _abfahrtZeit;
    _d.ankunftDatum = _ankunftDatum;
    _d.ankunftZeit = _ankunftZeit;
    _d.kmStart = _kmStartCtrl.text;
    _d.kmEnd = _kmEndCtrl.text;
    _d.fotoStartPath = _fotoStartPath;
    _d.fotoEndPath = _fotoEndPath;
    _d.fahrtTypCode = _fahrtTypCode;
    _d.sonderWegerecht = _sonderWegerecht;
    _d.autoGewaschen = _autoGewaschen;
    _d.kraftstoff = _kraftstoffCtrl.text;
    _d.strom = _stromCtrl.text;
    _d.adblue = _adblueCtrl.text;
    _d.fahrtZiel = _fahrtZielCtrl.text;
  }

  void _set(VoidCallback fn) { setState(fn); _syncDraft(); }

  @override
  void dispose() {
    if (!_finalized) _syncDraft();
    _kennzeichenCtrl.dispose();
    _kmStartCtrl.dispose();
    _kmEndCtrl.dispose();
    _kraftstoffCtrl.dispose();
    _stromCtrl.dispose();
    _adblueCtrl.dispose();
    _fahrtZielCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(bool isStart) async {
    final color = isStart ? skin.kommenColor : skin.gehenColor;
    final label = isStart ? 'ABFAHRT KM' : 'ANKUNFT KM';

    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => KmScannerScreen(label: label, color: color)),
    );

    if (result == null || !mounted) return;

    final km = result['km'] as String?;
    final imagePath = result['imagePath'] as String?;

    _set(() {
      if (isStart) {
        _fotoStartPath = imagePath;
        _d.fotoStartPath = imagePath;
        if (km != null) _kmStartCtrl.text = km;
      } else {
        _fotoEndPath = imagePath;
        _d.fotoEndPath = imagePath;
        if (km != null) _kmEndCtrl.text = km;
      }
    });

    if (km != null) {
      final kmInt = int.tryParse(km);
      if (kmInt != null && kmInt > 0 && _kennzeichenCtrl.text.trim().isEmpty) {
        final candidates = KmMemory.findCandidates(kmInt);
        if (candidates.isNotEmpty && mounted && !_kmCandidateShown) {
          _kmCandidateShown = true;
          await Future.delayed(const Duration(milliseconds: 400));
          if (mounted) _showKmCandidateDialog(candidates);
        }
      }

      if (mounted) {
  showGlassSnackBar(
    context,
    'KM-Stand übernommen: $km km',
    type: GlassSnackBarType.success,
    duration: const Duration(seconds: 2),
  );
}
    }
  }

  Future<void> _pickFuelPhoto() async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FuelScannerScreen(
          label: 'KRAFTSTOFF LITER',
          color: const Color(0xFFFFB347),
        ),
      ),
    );

    if (result == null || !mounted) return;

    final liter = result['liter'] as String?;
    if (liter != null) {
      _set(() => _kraftstoffCtrl.text = liter);
      showGlassSnackBar(
  context,
  'Liter übernommen: $liter L',
  type: GlassSnackBarType.warning,
  duration: const Duration(seconds: 2),
);
    }
  }

  void _checkKmCandidates(int kmStart) {
    if (_kmCandidateShown) return;
    if (kmStart <= 0) return;
    if (_kennzeichenCtrl.text.trim().isNotEmpty) return;
    final candidates = KmMemory.findCandidates(kmStart);
    if (candidates.isEmpty) return;
    _kmCandidates = candidates;
    _kmCandidateShown = true;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _showKmCandidateDialog(candidates);
    });
  }

  void _showKmCandidateDialog(List<Map<String, dynamic>> candidates) {
    if (candidates.isEmpty) return;
    final skin = AppTheme.of(context);

    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
        return ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1.0).animate(curved),
            child: FadeTransition(opacity: anim, child: child));
      },
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: skin.isLight ? Colors.white.withValues(alpha: 0.94) : skin.bgCard.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 28, offset: const Offset(0, 8))],
                ),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(width: 38, height: 38,
                        decoration: BoxDecoration(color: skin.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.directions_car_outlined, color: skin.primary, size: 20)),
                    const SizedBox(width: 12),
                    Expanded(child: Text('Fahrzeug erkannt?',
                        style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700))),
                  ]),
                  const SizedBox(height: 10),
                  Text('Basierend auf dem KM-Stand könnte es sich um folgendes Fahrzeug handeln:',
                      style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.4)),
                  const SizedBox(height: 14),
                  ...candidates.take(3).map((c) {
                    final kz = c['kennzeichen'] as String;
                    final lastKm = c['kmEnd'] as int;
                    final diff = c['kmDiff'] as int;
                    return GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        setState(() => _kennzeichenCtrl.text = kz);
                        _syncDraft();
                        _updateKmHint();
                        HapticFeedback.selectionClick();
                      },
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          color: skin.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.primary.withValues(alpha: 0.22)),
                        ),
                        child: Row(children: [
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(kz, style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                            Text('Letzter KM: ${_formatKm(lastKm)}  •  +$diff km',
                                style: TextStyle(color: skin.textMuted, fontSize: 11)),
                          ])),
                          Icon(Icons.chevron_right, color: skin.primary, size: 20),
                        ]),
                      ),
                    );
                  }),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: skin.surface(0.06), borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.glassBorder),
                      ),
                      child: Center(child: Text('Keines davon',
                          style: TextStyle(color: skin.textMuted, fontSize: 14, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatKm(int km) {
    if (km >= 1000) return '${km ~/ 1000}.${(km % 1000).toString().padLeft(3, '0')}';
    return km.toString();
  }

  void _openKmInput(TextEditingController ctrl, String label, {bool isStart = false}) {
    FocusScope.of(context).unfocus();
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        // ── GlassSheet aus glass_kit.dart ──
        child: GlassSheet(
          skin: skin,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Center(child: SheetHandle(skin: skin)),
              ),
              const SizedBox(height: 16),
              Text(label, style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      color: skin.isLight ? Colors.white.withValues(alpha: 0.65) : Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.glassBorder),
                    ),
                    child: TextField(
                      controller: ctrl, autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      enableInteractiveSelection: false,
                      style: TextStyle(color: skin.textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
                      decoration: InputDecoration(
                        hintText: '0', hintStyle: TextStyle(color: skin.surface(0.2), fontSize: 28),
                        border: InputBorder.none, isDense: true,
                        suffix: Text(' km', style: TextStyle(color: skin.surface(0.4), fontSize: 16, fontWeight: FontWeight.w500)),
                      ),
                      onSubmitted: (_) => Navigator.pop(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // ── GlassPrimaryButton aus glass_kit.dart ──
              GlassPrimaryButton(skin: skin, label: 'Übernehmen', onTap: () {
                _syncDraft(); setState(() {}); Navigator.pop(context);
              }),
            ]),
          ),
        ),
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusManager.instance.primaryFocus?.unfocus();
      });
      _syncDraft(); setState(() {});
      if (isStart) {
        final km = int.tryParse(_kmStartCtrl.text);
        if (km != null && km > 0) _checkKmCandidates(km);
      }
    });
  }

  Future<void> _pickDate(bool isAbfahrt) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final savedOffset = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0.0;
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final skin = AppTheme.of(context);

    // ── showSingleDatePicker aus glass_pickers.dart ──
    final result = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: isAbfahrt ? _abfahrtDatum : (_ankunftDatum ?? _abfahrtDatum),
      minimumDate: DateTime(2020),
      maximumDate: DateTime(2030),
    );

    if (result != null) {
      _set(() {
        if (isAbfahrt) {
          _abfahrtDatum = result;
          if (_ankunftDatum != null && _ankunftDatum!.isBefore(result)) {
            _ankunftDatum = result;
          }
        } else {
          _ankunftDatum = result;
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      FocusManager.instance.primaryFocus?.unfocus();
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.jumpTo(savedOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent));
      }
    });
  }

  Future<void> _pickTime(bool isAbfahrt) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await Future.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    final skin = AppTheme.of(context);
    final current = isAbfahrt ? _abfahrtZeit : _ankunftZeit;
    TimeOfDay? selected;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      // ── IOSTimePicker aus glass_pickers.dart
      // confirmOnDismiss: true = fahrtenbuch-Verhalten (Zeit auch beim Wegwischen übernehmen) ──
      builder: (_) => IOSTimePicker(
        initialTime: current ?? TimeOfDay.now(),
        skin: skin,
        label: isAbfahrt ? 'Uhrzeit Abfahrt' : 'Uhrzeit Ankunft',
        confirmOnDismiss: true,
        onTimeSelected: (t) => selected = t,
      ),
    );

    FocusManager.instance.primaryFocus?.unfocus();
    if (!mounted || selected == null) return;
    _set(() {
      if (isAbfahrt) { _abfahrtZeit = selected!; }
      else { _ankunftZeit = selected!; _ankunftDatum ??= _abfahrtDatum; }
    });
  }

  String _formatDate(DateTime d) => DateFormat('dd.MM.yy', 'de').format(d);
  String _formatTime(TimeOfDay? t) => t != null ? t.format(context) : '—';

  void _save() {
    _finalized = true;
    final kmStart = int.tryParse(_kmStartCtrl.text) ?? 0;
    final kmEnd = int.tryParse(_kmEndCtrl.text) ?? 0;

    if (_abfahrtZeit != null && _ankunftZeit != null && _ankunftDatum != null) {
      final abfahrt = DateTime(
        _abfahrtDatum.year, _abfahrtDatum.month, _abfahrtDatum.day,
        _abfahrtZeit!.hour, _abfahrtZeit!.minute,
      );
      final ankunft = DateTime(
        _ankunftDatum!.year, _ankunftDatum!.month, _ankunftDatum!.day,
        _ankunftZeit!.hour, _ankunftZeit!.minute,
      );
      if (!ankunft.isAfter(abfahrt)) {
        _finalized = false;
        HapticFeedback.heavyImpact();
        if (_canShowAlert('zeit_reihenfolge'))
  showGlassSnackBar(
    context,
    'Ankunftszeit muss nach der Abfahrtszeit liegen.',
    type: GlassSnackBarType.error,
  );
        return;
      }
    }

    if (kmStart > 0 && kmEnd > 0 && kmEnd <= kmStart) {
      _finalized = false;
      HapticFeedback.heavyImpact();
      if (_canShowAlert('km_reihenfolge'))
  showGlassSnackBar(
    context,
    'Ankunft-KM muss größer als Abfahrt-KM sein.',
    type: GlassSnackBarType.error,
  );
      return;
    }

    final kennzeichen = _kennzeichenCtrl.text.trim().toUpperCase();
    if (kennzeichen.isEmpty) {
      _finalized = false;
      HapticFeedback.heavyImpact();
      if (_canShowAlert('kz_leer'))
  showGlassSnackBar(
    context,
    'Bitte ein Kennzeichen eintragen (z.B. B-UX 157)',
    type: GlassSnackBarType.error,
    duration: const Duration(seconds: 3),
  );
      return;
    }

    final kzValid = RegExp(r'^[A-ZÄÖÜ]{1,3}-[A-ZÄÖÜ]{1,2} \d{1,4}[EH]?$').hasMatch(kennzeichen);
    if (!kzValid) {
      _finalized = false;
      HapticFeedback.heavyImpact();
      if (_canShowAlert('kz_ungueltig'))
  showGlassSnackBar(
    context,
    'Kennzeichen unvollständig (z.B. B-UX 157)',
    type: GlassSnackBarType.error,
    duration: const Duration(seconds: 3),
  );
      return;
    }

    if (_fahrtTypCode.isNotEmpty) {
      FahrtTypManager.recordUsage(_fahrtTypCode);
    }

    DateTime? abfahrtZeit;
    if (_abfahrtZeit != null) {
      abfahrtZeit = DateTime(_abfahrtDatum.year, _abfahrtDatum.month, _abfahrtDatum.day,
          _abfahrtZeit!.hour, _abfahrtZeit!.minute);
    }
    DateTime? ankunftZeit;
    if (_ankunftZeit != null && _ankunftDatum != null) {
      ankunftZeit = DateTime(_ankunftDatum!.year, _ankunftDatum!.month, _ankunftDatum!.day,
          _ankunftZeit!.hour, _ankunftZeit!.minute);
    }

    final fahrt = Fahrt(
      id: widget.isEdit && widget.editingId != null ? widget.editingId! : DateTime.now().millisecondsSinceEpoch.toString(),
      datum: _abfahrtDatum, kmStart: kmStart, kmEnd: kmEnd, kennzeichen: kennzeichen,
      getanktLiter: double.tryParse(_kraftstoffCtrl.text.replaceAll(',', '.')),
      fotoStartPath: _fotoStartPath, fotoEndPath: _fotoEndPath,
      abfahrtZeit: abfahrtZeit, ankunftDatum: _ankunftDatum, ankunftZeit: ankunftZeit,
      fahrtTyp: _fahrtTypCode,
      sonderWegerecht: _sonderWegerecht, autoGewaschen: _autoGewaschen,
      stromKwh: double.tryParse(_stromCtrl.text.replaceAll(',', '.')),
      adblueKwh: double.tryParse(_adblueCtrl.text.replaceAll(',', '.')),
      fahrtZiel: _fahrtZielCtrl.text.trim(),
    );

    widget.onSave(fahrt, editingId: widget.editingId);
    Navigator.pop(context);
  }

  void _confirmDiscard() async {
    FocusScope.of(context).unfocus();
    await Future.delayed(const Duration(milliseconds: 80));
    if (!mounted) return;
    final skin = AppTheme.of(context);

    // ── confirmDeleteDialog aus glass_dialogs.dart ──
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: widget.isEdit ? 'Bearbeitung verwerfen' : 'Eingaben verwerfen',
      message: widget.isEdit
          ? 'Alle Änderungen an dieser Fahrt werden nicht gespeichert.'
          : 'Alle eingegebenen Daten für diese Fahrt werden unwiderruflich gelöscht.',
      cancelLabel: 'Zurück',
      confirmLabel: 'Verwerfen',
    );

    if (confirmed == true && mounted) {
      _finalized = true;
      FocusScope.of(context).unfocus();
      await Future.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
      widget.onDiscard();
      Navigator.pop(context);
    }
  }

  void _confirmDelete() async {
    final skin = AppTheme.of(context);

    // ── confirmDeleteDialog aus glass_dialogs.dart ──
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Fahrt löschen',
      message: 'Diese Fahrt wird unwiderruflich gelöscht. Diese Aktion kann nicht rückgängig gemacht werden.',
    );

    if (confirmed == true && mounted) {
      widget.onDelete?.call();
      Navigator.pop(context);
    }
  }

  void _showFahrtTypPicker() {
    FocusManager.instance.primaryFocus?.unfocus();
    final skin = AppTheme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      builder: (_) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.12),
        child: _FahrtTypPickerSheet(
          skin: skin,
          currentCode: _fahrtTypCode,
          onSelected: (code) {
            setState(() => _fahrtTypCode = code);
            _syncDraft();
            if (code.isNotEmpty) {
              setState(() => _sortedTypes = FahrtTypManager.getSorted());
            }
          },
        ),
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusManager.instance.primaryFocus?.unfocus();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final kmStart = int.tryParse(_kmStartCtrl.text);
    final kmEnd = int.tryParse(_kmEndCtrl.text);
    final selectedTyp = _fahrtTypCode.isNotEmpty ? FahrtTypManager.byCode(_fahrtTypCode) : null;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          if (notification.scrollDelta != null && notification.scrollDelta! < -5) {
            FocusScope.of(context).unfocus();
          }
        }
        return false;
      },
      child: GestureDetector(
        onVerticalDragUpdate: (d) { if (d.delta.dy > 15) FocusScope.of(context).unfocus(); },
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
              child: Container(
                decoration: BoxDecoration(
                  color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgSheet.withValues(alpha: 0.92),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                  border: Border.all(color: skin.glassBorder),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onMinimize,
                        onVerticalDragEnd: (d) { if ((d.primaryVelocity ?? 0) > 100) widget.onMinimize(); },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Center(child: Container(width: 44, height: 5,
                              decoration: BoxDecoration(color: skin.surface(0.22), borderRadius: BorderRadius.circular(3)))),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(width: 36, height: 36,
                            decoration: BoxDecoration(color: skin.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                            child: Icon(Icons.directions_car_outlined, size: 18, color: skin.primary)),
                        const SizedBox(width: 12),
                        Text(widget.isEdit ? 'Fahrt bearbeiten' : 'Fahrt eintragen',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                      ]),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'FAHRZEUG', skin: skin),
                      const SizedBox(height: 8),
                      _KennzeichenInputRow(skin: skin, ctrl: _kennzeichenCtrl),
                      _hint('Doppeltipp'),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'KILOMETERSTAND', skin: skin),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _KmInputCard(
                          label: 'ABFAHRT KM', ctrl: _kmStartCtrl, skin: skin, color: skin.kommenColor,
                          fotoPath: _fotoStartPath, hintKm: _lastKmHint,
                          onTap: () => _openKmInput(_kmStartCtrl, 'Abfahrtkilometer', isStart: true),
                          onCameraPressed: () => _pickPhoto(true),
                          onDoubleTap: () {
                            HapticFeedback.lightImpact();
                            if (_kmStartCtrl.text.isEmpty && _lastKmHint != null) {
                              _set(() => _kmStartCtrl.text = _lastKmHint.toString());
                            } else {
                              _set(() { _kmStartCtrl.clear(); _fotoStartPath = null; _d.fotoStartPath = null; });
                            }
                          },
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _KmInputCard(
                          label: 'ANKUNFT KM', ctrl: _kmEndCtrl, skin: skin, color: skin.gehenColor,
                          fotoPath: _fotoEndPath,
                          onTap: () => _openKmInput(_kmEndCtrl, 'Ankunftkilometer'),
                          onCameraPressed: () => _pickPhoto(false),
                          onDoubleTap: () {
                            HapticFeedback.lightImpact();
                            _set(() { _kmEndCtrl.clear(); _fotoEndPath = null; _d.fotoEndPath = null; });
                          },
                        )),
                      ]),
                      if (kmStart != null && kmEnd != null && kmEnd >= kmStart) ...[
                        const SizedBox(height: 8),
                        Center(child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: skin.primary.withValues(alpha: 0.2)),
                          ),
                          child: Text('${kmEnd - kmStart} km gefahren',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.primary.withValues(alpha: 0.8))),
                        )),
                      ],
                      _hint('Tippen · Doppeltipp · Scannen'),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'ZEITRAUM', skin: skin),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _ZeitBlock(
                          skin: skin, label: 'ABFAHRT', color: skin.kommenColor,
                          datum: _abfahrtDatum, zeit: _abfahrtZeit,
                          datumText: _formatDate(_abfahrtDatum), zeitText: _formatTime(_abfahrtZeit),
                          onDateTap: () => _pickDate(true), onTimeTap: () => _pickTime(true),
                          onDateDoubleTap: () => _set(() {
                            final today = DateTime.now();
                            _abfahrtDatum = DateTime(today.year, today.month, today.day);
                            if (_ankunftDatum != null && _ankunftDatum!.isBefore(_abfahrtDatum)) _ankunftDatum = _abfahrtDatum;
                          }),
                          onTimeDoubleTap: () => _set(() => _abfahrtZeit = TimeOfDay.now()),
                          onSwipeDay: (delta) => _set(() {
                            _abfahrtDatum = _abfahrtDatum.add(Duration(days: delta));
                            if (_ankunftDatum != null && _ankunftDatum!.isBefore(_abfahrtDatum)) _ankunftDatum = _abfahrtDatum;
                          }),
                          onSwipeMinute: (delta) => _set(() {
                            final current = _abfahrtZeit ?? TimeOfDay.now();
                            final total = (current.hour * 60 + current.minute + delta).clamp(0, 23 * 60 + 59);
                            _abfahrtZeit = TimeOfDay(hour: total ~/ 60, minute: total % 60);
                          }),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _ZeitBlock(
                          skin: skin, label: 'ANKUNFT', color: skin.gehenColor,
                          datum: _ankunftDatum, zeit: _ankunftZeit,
                          datumText: _ankunftDatum != null ? _formatDate(_ankunftDatum!) : '—',
                          zeitText: _formatTime(_ankunftZeit),
                          onDateTap: () => _pickDate(false), onTimeTap: () => _pickTime(false),
                          onDateDoubleTap: () => _set(() { final today = DateTime.now(); _ankunftDatum = DateTime(today.year, today.month, today.day); }),
                          onTimeDoubleTap: () => _set(() { _ankunftZeit = TimeOfDay.now(); _ankunftDatum ??= _abfahrtDatum; }),
                          onSwipeDay: (delta) => _set(() { final base = _ankunftDatum ?? _abfahrtDatum; _ankunftDatum = base.add(Duration(days: delta)); }),
                          onSwipeMinute: (delta) => _set(() {
                            final current = _ankunftZeit ?? TimeOfDay.now();
                            final total = (current.hour * 60 + current.minute + delta).clamp(0, 23 * 60 + 59);
                            _ankunftZeit = TimeOfDay(hour: total ~/ 60, minute: total % 60);
                            _ankunftDatum ??= _abfahrtDatum;
                          }),
                        )),
                      ]),
                      _hint('Tippen · Doppeltipp · Wischen'),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'FAHRTTYP', skin: skin),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _showFahrtTypPicker,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: selectedTyp != null
                                    ? skin.primary.withValues(alpha: skin.isLight ? 0.08 : 0.14)
                                    : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity)),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selectedTyp != null ? skin.primary.withValues(alpha: 0.35) : skin.glassBorder,
                                  width: selectedTyp != null ? 1.5 : 1.0,
                                ),
                                boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
                              ),
                              child: Row(children: [
                                Container(
                                  width: 32, height: 32,
                                  decoration: BoxDecoration(
                                    color: selectedTyp != null
                                        ? skin.primary.withValues(alpha: 0.15)
                                        : skin.surface(0.08),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    selectedTyp != null ? Icons.check_rounded : Icons.list_alt_outlined,
                                    size: 16,
                                    color: selectedTyp != null ? skin.primary : skin.surface(0.4),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('FAHRTTYP', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                      color: selectedTyp != null ? skin.primary : skin.surface(0.38), letterSpacing: 1.0)),
                                  const SizedBox(height: 3),
                                  Text(
                                    selectedTyp != null ? '${selectedTyp.code} – ${selectedTyp.label}' : 'Typ auswählen…',
                                    style: TextStyle(
                                      fontSize: 14, fontWeight: FontWeight.w600,
                                      color: selectedTyp != null ? skin.textPrimary : skin.surface(0.3),
                                    ),
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                  ),
                                ])),
                                Icon(Icons.chevron_right, size: 18, color: skin.surface(0.3)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      if (_sortedTypes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 32,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            itemCount: _sortedTypes.take(6).length,
                            separatorBuilder: (_, __) => const SizedBox(width: 6),
                            itemBuilder: (_, i) {
                              final typ = _sortedTypes[i];
                              final selected = _fahrtTypCode == typ.code;
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _set(() => _fahrtTypCode = selected ? '' : typ.code);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: selected ? skin.primary.withValues(alpha: 0.15) : skin.surface(0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
                                      width: selected ? 1.5 : 1.0,
                                    ),
                                  ),
                                  child: Text(
                                    typ.label,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selected ? skin.primary : skin.surface(0.5),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'STATUS', skin: skin),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _ToggleKachel(
                          label: 'Sonder-/Wegerecht', icon: Icons.emergency_outlined,
                          active: _sonderWegerecht, activeColor: const Color(0xFF2962FF),
                          skin: skin, policeLights: true,
                          onTap: () => _set(() => _sonderWegerecht = !_sonderWegerecht),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _ToggleKachel(
                          label: 'Auto gewaschen', icon: Icons.local_car_wash_outlined,
                          active: _autoGewaschen, activeColor: const Color(0xFF4FC3F7),
                          skin: skin,
                          onTap: () => _set(() => _autoGewaschen = !_autoGewaschen),
                        )),
                      ]),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'BETRIEBSSTOFFE', skin: skin),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(child: _BetriebsstoffCard(
                          skin: skin, icon: Icons.local_gas_station_outlined, label: 'KRAFTSTOFF',
                          unit: 'Liter', ctrl: _kraftstoffCtrl, color: const Color(0xFFFFB347),
                          onChanged: _syncDraft,
                          onCameraPressed: _pickFuelPhoto,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _BetriebsstoffCard(
                          skin: skin, icon: Icons.bolt_outlined, label: 'STROM',
                          unit: 'kWh', ctrl: _stromCtrl, color: const Color(0xFF66BB6A), onChanged: _syncDraft,
                        )),
                        const SizedBox(width: 8),
                        Expanded(child: _BetriebsstoffCard(
                          skin: skin, icon: Icons.water_drop_outlined, label: 'ADBLUE',
                          unit: 'Liter', ctrl: _adblueCtrl, color: const Color(0xFF42A5F5), onChanged: _syncDraft,
                        )),
                      ]),
                      _hint('TIppen · Doppeltippen · Scannen'),
                      const SizedBox(height: 20),

                      _SectionLabel(label: 'ZIEL & STRECKE', skin: skin),
                      const SizedBox(height: 8),
                      _FahrtZielInputField(
                        skin: skin,
                        ctrl: _fahrtZielCtrl,
                        knownZiele: _knownZiele,
                        onChanged: _syncDraft,
                      ),
                      _hint('Häufig genutzte Ziele werden vorgeschlagen'),
                      const SizedBox(height: 28),

                      if (widget.isEdit) ...[
                        // ── GlassPrimaryButton aus glass_kit.dart ──
                        GlassPrimaryButton(skin: skin, label: 'Änderungen übernehmen', icon: Icons.check_rounded, onTap: _save),
                        const SizedBox(height: 8),
                        Center(child: GestureDetector(
                          onTap: _confirmDelete,
                          child: ClipRRect(borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: skin.deleteColor.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.delete_outline, color: skin.deleteColor, size: 15),
                                  const SizedBox(width: 7),
                                  Text('Fahrt löschen', style: TextStyle(color: skin.deleteColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ),
                        )),
                      ] else ...[
                        GlassPrimaryButton(skin: skin, label: 'Fahrt anlegen', icon: Icons.save_rounded, onTap: _save, large: true),
                        const SizedBox(height: 10),
                        Center(child: GestureDetector(
                          onTap: _confirmDiscard,
                          child: ClipRRect(borderRadius: BorderRadius.circular(12),
                            child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: skin.deleteColor.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.delete_outline, color: skin.deleteColor, size: 15),
                                  const SizedBox(width: 7),
                                  Text('Abbrechen & verwerfen', style: TextStyle(color: skin.deleteColor, fontSize: 13, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(text, style: TextStyle(fontSize: 10, color: skin.surface(0.28))),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTTYP PICKER SHEET — Vollbild mit Suche
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtTypPickerSheet extends StatefulWidget {
  final AppSkin skin;
  final String currentCode;
  final void Function(String code) onSelected;

  const _FahrtTypPickerSheet({
    required this.skin, required this.currentCode, required this.onSelected,
  });

  @override
  State<_FahrtTypPickerSheet> createState() => _FahrtTypPickerSheetState();
}

class _FahrtTypPickerSheetState extends State<_FahrtTypPickerSheet> {
  String _query = '';
  final _searchCtrl = TextEditingController();
  late List<FahrtTyp> _allSorted;

  @override
  void initState() {
    super.initState();
    _allSorted = FahrtTypManager.getSorted();
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  List<FahrtTyp> get _filtered {
    if (_query.isEmpty) return _allSorted;
    final q = _query.toLowerCase();
    return _allSorted.where((t) =>
        t.code.toLowerCase().contains(q) || t.label.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final filtered = _filtered;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.95) : skin.bgSheet.withValues(alpha: 0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Column(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    child: Center(
                      child: Container(
                        width: 44, height: 5,
                        decoration: BoxDecoration(
                          color: skin.surface(0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: Text('Fahrttyp wählen',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: skin.textPrimary))),
                  if (widget.currentCode.isNotEmpty)
                    GestureDetector(
                      onTap: () { widget.onSelected(''); Navigator.pop(context); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.2)),
                        ),
                        child: Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: skin.isLight ? Colors.white.withValues(alpha: 0.7) : skin.bgCard.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: skin.glassBorder),
                      ),
                      child: Row(children: [
                        Icon(Icons.search, size: 18, color: skin.surface(0.4)),
                        const SizedBox(width: 8),
                        Expanded(child: TextField(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _query = v),
                          style: TextStyle(color: skin.textPrimary, fontSize: 15),
                          decoration: InputDecoration(
                            hintText: 'Code oder Bezeichnung suchen…',
                            hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 14),
                            border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                          ),
                        )),
                        if (_query.isNotEmpty)
                          GestureDetector(
                            onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                            child: Icon(Icons.close, size: 16, color: skin.surface(0.4)),
                          ),
                      ]),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ]),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final typ = filtered[i];
                  final isSelected = widget.currentCode == typ.code;
                  final mruList = FahrtTypManager._loadMru();
                  final isMru = mruList.contains(typ.code);

                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      FahrtTypManager.recordUsage(typ.code);
                      widget.onSelected(typ.code);
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? skin.primary.withValues(alpha: skin.isLight ? 0.10 : 0.18)
                            : (skin.isLight ? Colors.white.withValues(alpha: 0.6) : skin.bgCard.withValues(alpha: 0.5)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected ? skin.primary.withValues(alpha: 0.4) : skin.glassBorder,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? skin.primary.withValues(alpha: 0.15) : skin.surface(0.07),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(typ.code,
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                                  color: isSelected ? skin.primary : skin.surface(0.5), letterSpacing: 0.3)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(typ.label,
                            style: TextStyle(fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: isSelected ? skin.textPrimary : skin.textPrimary.withValues(alpha: 0.8)))),
                        if (isMru && !isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: skin.primary.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('zuletzt', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: skin.primary.withValues(alpha: 0.6))),
                          ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.check_circle_rounded, color: skin.primary, size: 18),
                        ],
                      ]),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KM CANDIDATE HELPER
// ─────────────────────────────────────────────────────────────────────────────

class _KmCandidate {
  final int value;
  final double yPosition;
  final int digitCount;
  _KmCandidate({required this.value, required this.yPosition, required this.digitCount});
}

// ─────────────────────────────────────────────────────────────────────────────
// KENNZEICHEN 3-FELDER EINGABE
// ─────────────────────────────────────────────────────────────────────────────

class _KennzeichenInputRow extends StatefulWidget {
  final AppSkin skin;
  final TextEditingController ctrl;
  const _KennzeichenInputRow({required this.skin, required this.ctrl});

  @override
  State<_KennzeichenInputRow> createState() => _KennzeichenInputRowState();
}

class _KennzeichenInputRowState extends State<_KennzeichenInputRow> {
  final _ortCtrl = TextEditingController();
  final _buchCtrl = TextEditingController();
  final _numCtrl  = TextEditingController();

  final _ortFocus  = FocusNode();
  final _buchFocus = FocusNode();
  final _numFocus  = FocusNode();

  List<String> _known = [];

  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _known = KennzeichenHelper.loadKnownKennzeichen();

    // Beim Start: vorhandenen Wert aus ctrl aufsplitten
    _splitIntoFields(widget.ctrl.text);

    // Wenn ctrl von außen gesetzt wird (z.B. KM-Scan-Erkennung)
    widget.ctrl.addListener(_onExternalChange);

    _ortCtrl.addListener(_onFieldChange);
    _buchCtrl.addListener(_onFieldChange);
    _numCtrl.addListener(_onFieldChange);
  }

  void _onExternalChange() {
    if (_syncing) return;
    // Nur reagieren wenn sich der zusammengesetzte Wert wirklich unterscheidet
    final assembled = _assemble();
    if (widget.ctrl.text != assembled) {
      _splitIntoFields(widget.ctrl.text);
    }
  }

  /// Zerlegt "B-UX 157" oder "BUX157" in die drei Felder
  void _splitIntoFields(String raw) {
    if (raw.isEmpty) {
      _ortCtrl.text  = '';
      _buchCtrl.text = '';
      _numCtrl.text  = '';
      return;
    }

    final upper = raw.trim().toUpperCase();

    // ── Strategie 1: Format "ORT-BUCH NR" mit Bindestrich als Anker ──
    // Bindestrich trennt Ort von Buchstaben zuverlässig
    final dashMatch = RegExp(
      r'^([A-ZÄÖÜ]{1,3})\-([A-ZÄÖÜ]{1,2})\s*(\d{1,4}[EH]?)$',
    ).firstMatch(upper);
    if (dashMatch != null) {
      _ortCtrl.text  = dashMatch.group(1)!;
      _buchCtrl.text = dashMatch.group(2)!;
      _numCtrl.text  = dashMatch.group(3)!;
      return;
    }

    // ── Strategie 2: Format "ORT-BUCH" ohne Nummer ──
    final dashNoNumMatch = RegExp(
      r'^([A-ZÄÖÜ]{1,3})\-([A-ZÄÖÜ]{1,2})$',
    ).firstMatch(upper);
    if (dashNoNumMatch != null) {
      _ortCtrl.text  = dashNoNumMatch.group(1)!;
      _buchCtrl.text = dashNoNumMatch.group(2)!;
      _numCtrl.text  = '';
      return;
    }

    // ── Strategie 3: Kein Bindestrich — nur Buchstabenblock + Zahlen ──
    // Hier ist Ambiguität unvermeidbar; wir nehmen max 3 für Ort,
    // dann max 2 für Buchstaben, dann Zahlen
    final cleaned = upper.replaceAll(RegExp(r'[\s\-]'), '');
    final noSepMatch = RegExp(
      r'^([A-ZÄÖÜ]{1,3})([A-ZÄÖÜ]{1,2})(\d{1,4}[EH]?)$',
    ).firstMatch(cleaned);
    if (noSepMatch != null) {
      _ortCtrl.text  = noSepMatch.group(1)!;
      _buchCtrl.text = noSepMatch.group(2)!;
      _numCtrl.text  = noSepMatch.group(3)!;
      return;
    }

    // ── Fallback: nur Buchstaben, kein Muster erkannt ──
    _ortCtrl.text  = cleaned.length >= 1
        ? cleaned.replaceAll(RegExp(r'\d'), '').substring(
            0, cleaned.replaceAll(RegExp(r'\d'), '').length.clamp(0, 3))
        : '';
    _buchCtrl.text = '';
    _numCtrl.text  = cleaned.replaceAll(RegExp(r'[^\d]'), '').substring(
        0, cleaned.replaceAll(RegExp(r'[^\d]'), '').length.clamp(0, 4));
  }

  String _assemble() {
    final ort  = _ortCtrl.text.trim().toUpperCase();
    final buch = _buchCtrl.text.trim().toUpperCase();
    final num  = _numCtrl.text.trim();
    if (ort.isEmpty && buch.isEmpty && num.isEmpty) return '';
    if (ort.isNotEmpty && buch.isEmpty && num.isEmpty) return ort;
    if (ort.isNotEmpty && buch.isNotEmpty && num.isEmpty) return '$ort-$buch';
    return '$ort-$buch $num';
  }

  void _onFieldChange() {
    _syncing = true;
    widget.ctrl.value = TextEditingValue(
      text: _assemble(),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _syncing = false;
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onExternalChange);
    _ortCtrl.dispose();
    _buchCtrl.dispose();
    _numCtrl.dispose();
    _ortFocus.dispose();
    _buchFocus.dispose();
    _numFocus.dispose();
    super.dispose();
  }

  /// Chip antippen → alle Felder befüllen
  void _applyKennzeichen(String kz) {
    HapticFeedback.selectionClick();
    _splitIntoFields(kz);
    _onFieldChange();
    setState(() {});
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    // Vorschläge aus bekannten Kennzeichen
    final chips = _known.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 3-Felder Zeile ──────────────────────────────────────────────
        GestureDetector(
          onDoubleTap: () {
            HapticFeedback.mediumImpact();
            _ortCtrl.clear();
            _buchCtrl.clear();
            _numCtrl.clear();
            _onFieldChange();
            setState(() {});
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? Colors.white.withValues(alpha: skin.glassOpacity)
                      : skin.bgCard.withValues(alpha: skin.glassOpacity),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.directions_car_outlined, size: 18, color: skin.primary),
                      const SizedBox(width: 10),
                      Text(
                        'KENNZEICHEN',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _KzField(
                            skin: skin,
                            ctrl: _ortCtrl,
                            focus: _ortFocus,
                            hint: 'B',
                            sublabel: 'ORT',
                            maxLen: 3,
                            lettersOnly: true,
                            onChanged: (v) {
                              if (v.length == 3) {
                                FocusScope.of(context).requestFocus(_buchFocus);
                              }
                              _onFieldChange();
                              setState(() {});
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '–',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w300,
                              color: skin.surface(0.4),
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: _KzField(
                            skin: skin,
                            ctrl: _buchCtrl,
                            focus: _buchFocus,
                            hint: 'AB',
                            sublabel: 'BUCHST.',
                            maxLen: 2,
                            lettersOnly: true,
                            onChanged: (v) {
                              if (v.length == 2) {
                                FocusScope.of(context).requestFocus(_numFocus);
                              }
                              _onFieldChange();
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 3,
                          child: _KzField(
                            skin: skin,
                            ctrl: _numCtrl,
                            focus: _numFocus,
                            hint: '1234',
                            sublabel: 'NR.',
                            maxLen: 4,
                            lettersOnly: false,
                            onChanged: (v) {
                              if (v.length == 4) {
                                FocusManager.instance.primaryFocus?.unfocus();
                              }
                              _onFieldChange();
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // ── Chips: zuletzt benutzte Kennzeichen ────────────────────────
        if (chips.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              itemCount: chips.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final kz = chips[i];
                final isActive = _assemble().toUpperCase() == kz.toUpperCase();
                return GestureDetector(
                  onTap: () => _applyKennzeichen(kz),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isActive
                          ? skin.primary.withValues(alpha: 0.14)
                          : skin.surface(0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive
                            ? skin.primary.withValues(alpha: 0.45)
                            : skin.surface(0.12),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Text(
                      kz,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isActive ? skin.primary : skin.surface(0.5),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ── Einzelnes KZ-Eingabefeld ──────────────────────────────────────────────────

class _KzField extends StatelessWidget {
  final AppSkin skin;
  final TextEditingController ctrl;
  final FocusNode focus;
  final String hint;
  final String sublabel;
  final int maxLen;
  final bool lettersOnly;
  final void Function(String) onChanged;

  const _KzField({
    required this.skin,
    required this.ctrl,
    required this.focus,
    required this.hint,
    required this.sublabel,
    required this.maxLen,
    required this.lettersOnly,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () {
        HapticFeedback.lightImpact();
        ctrl.clear();
        onChanged('');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w600,
              color: skin.surface(0.35),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            focusNode: focus,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            keyboardType: lettersOnly
                ? TextInputType.text
                : TextInputType.number,
            inputFormatters: lettersOnly
                ? [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-ZÄÖÜa-zäöü]')),
                    TextInputFormatter.withFunction((old, nw) {
                      return nw.copyWith(text: nw.text.toUpperCase());
                    }),
                    LengthLimitingTextInputFormatter(maxLen),
                  ]
                : [
                    FilteringTextInputFormatter.digitsOnly,
                    // Keine führende Null
                    TextInputFormatter.withFunction((old, nw) {
                      final t = nw.text;
                      if (t.length > 1 && t.startsWith('0')) {
                        return old;
                      }
                      return nw;
                    }),
                    LengthLimitingTextInputFormatter(maxLen),
                  ],
            onChanged: onChanged,
            style: TextStyle(
              color: skin.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: skin.surface(0.22),
                fontSize: 17,
                fontWeight: FontWeight.w400,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: skin.glassBorder, width: 1.0),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: skin.glassBorder, width: 1.0),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: skin.primary.withValues(alpha: 0.6), width: 1.5),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              filled: true,
              fillColor: skin.isLight
                  ? Colors.white.withValues(alpha: 0.5)
                  : Colors.white.withValues(alpha: 0.05),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ZEIT BLOCK
// ─────────────────────────────────────────────────────────────────────────────

class _ZeitBlock extends StatefulWidget {
  final AppSkin skin;
  final String label;
  final Color color;
  final DateTime? datum;
  final TimeOfDay? zeit;
  final String datumText, zeitText;
  final VoidCallback onDateTap, onTimeTap, onDateDoubleTap, onTimeDoubleTap;
  final ValueChanged<int> onSwipeDay, onSwipeMinute;

  const _ZeitBlock({
    required this.skin, required this.label, required this.color,
    required this.datum, required this.zeit,
    required this.datumText, required this.zeitText,
    required this.onDateTap, required this.onTimeTap,
    required this.onDateDoubleTap, required this.onTimeDoubleTap,
    required this.onSwipeDay, required this.onSwipeMinute,
  });

  @override
  State<_ZeitBlock> createState() => _ZeitBlockState();
}

class _ZeitBlockState extends State<_ZeitBlock> {
  double _hAccum = 0, _vAccum = 0;
  static const double _pxPerDay = 70, _pxPerMin = 12;

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final color = widget.color;

    return GestureDetector(
      onHorizontalDragStart: (_) => _hAccum = 0,
      onHorizontalDragUpdate: (d) {
        _hAccum += d.delta.dx;
        while (_hAccum >= _pxPerDay) { _hAccum -= _pxPerDay; widget.onSwipeDay(1); HapticFeedback.selectionClick(); }
        while (_hAccum <= -_pxPerDay) { _hAccum += _pxPerDay; widget.onSwipeDay(-1); HapticFeedback.selectionClick(); }
      },
      onVerticalDragStart: (_) => _vAccum = 0,
      onVerticalDragUpdate: (d) {
        _vAccum += -d.delta.dy;
        while (_vAccum >= _pxPerMin) { _vAccum -= _pxPerMin; widget.onSwipeMinute(1); HapticFeedback.selectionClick(); }
        while (_vAccum <= -_pxPerMin) { _vAccum += _pxPerMin; widget.onSwipeMinute(-1); HapticFeedback.selectionClick(); }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.30), width: 1.0),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(widget.label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.2)),
                const Spacer(),
                Icon(Icons.unfold_more_rounded, size: 13, color: skin.surface(0.3)),
              ]),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: widget.onDateTap,
                onDoubleTap: () { HapticFeedback.selectionClick(); widget.onDateDoubleTap(); },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
                  child: Row(children: [
                    Icon(Icons.calendar_today_outlined, size: 12, color: color),
                    const SizedBox(width: 6),
                    Text(widget.datumText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: widget.datumText == '—' ? skin.surface(0.3) : skin.textPrimary)),
                  ]),
                ),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: widget.onTimeTap,
                onDoubleTap: () { HapticFeedback.selectionClick(); widget.onTimeDoubleTap(); },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.2))),
                  child: Row(children: [
                    Icon(Icons.access_time_outlined, size: 12, color: color),
                    const SizedBox(width: 6),
                    Text(widget.zeitText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: widget.zeitText == '—' ? skin.surface(0.3) : skin.textPrimary)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BETRIEBSSTOFF CARD
// ─────────────────────────────────────────────────────────────────────────────

class _BetriebsstoffCard extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label, unit;
  final TextEditingController ctrl;
  final Color color;
  final VoidCallback? onChanged;
  final VoidCallback? onCameraPressed;

  const _BetriebsstoffCard({
    required this.skin, required this.icon, required this.label, required this.unit,
    required this.ctrl, required this.color, this.onChanged,
    this.onCameraPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
            boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 12, offset: const Offset(0, 3))],
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onDoubleTap: () { HapticFeedback.lightImpact(); ctrl.clear(); onChanged?.call(); },
            onLongPress: ctrl.text.isEmpty && onCameraPressed != null
                ? onCameraPressed
                : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(icon, size: 16, color: color),
                  if (onCameraPressed != null)
                    GestureDetector(
                      onTap: onCameraPressed,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.camera_alt_outlined, size: 11, color: skin.surface(0.4)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.8)),
              const SizedBox(height: 4),
              AnimatedBuilder(
                animation: ctrl,
                builder: (_, __) => TextField(
                  controller: ctrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    hintText: '—', hintStyle: TextStyle(color: skin.surface(0.25), fontSize: 15),
                    border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    suffix: Text(unit, style: TextStyle(color: skin.surface(0.35), fontSize: 9, fontWeight: FontWeight.w500)),
                  ),
                  onChanged: (_) => onChanged?.call(),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION LABEL
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionLabel({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: skin.surface(0.38), letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KM INPUT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _KmInputCard extends StatefulWidget {
  final String label;
  final TextEditingController ctrl;
  final AppSkin skin;
  final Color color;
  final String? fotoPath;
  final VoidCallback onTap, onCameraPressed;
  final VoidCallback? onDoubleTap;
  final int? hintKm;

  const _KmInputCard({
    required this.label, required this.ctrl, required this.skin, required this.color,
    required this.onTap, required this.onCameraPressed, this.onDoubleTap, this.fotoPath, this.hintKm,
  });

  @override
  State<_KmInputCard> createState() => _KmInputCardState();
}

class _KmInputCardState extends State<_KmInputCard> {

  void _showFotoPreview(BuildContext context) {
    HapticFeedback.mediumImpact();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1.0).animate(
            CurvedAnimation(parent: anim, curve: Curves.easeOut),
          ),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, __) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  dartio.File(widget.fotoPath!),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 60),
                ),
              ),
              const SizedBox(height: 20),
              if (widget.ctrl.text.isNotEmpty)
                Text(
                  '${widget.ctrl.text} km',
                  style: TextStyle(
                    color: widget.color,
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    decoration: TextDecoration.none,
                  ),
                ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.pop(ctx);
                        widget.onCameraPressed();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: widget.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: widget.color.withValues(alpha: 0.4)),
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt_outlined,
                                  color: widget.color, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Neu scannen',
                                style: TextStyle(
                                  color: widget.color,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 14, horizontal: 20),
                      decoration: BoxDecoration(
                        color: widget.skin.surface(0.08),
borderRadius: BorderRadius.circular(14),
border: Border.all(color: widget.skin.glassBorder),
                      ),
                      child: Text('Schließen', style: TextStyle(
  color: widget.skin.textPrimary,
  fontSize: 14,
  fontWeight: FontWeight.w600,
  decoration: TextDecoration.none,
),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatKm(int km) {
    if (km >= 1000) return '${km ~/ 1000}.${(km % 1000).toString().padLeft(3, '0')}';
    return km.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (context, _) {
        final isEmpty = widget.ctrl.text.isEmpty;
        final hasFoto = widget.fotoPath != null;
        final br = BorderRadius.circular(20);

        Widget? fotoWidget;
        if (hasFoto) {
          try {
            fotoWidget = ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(dartio.File(widget.fotoPath!), width: 36, height: 36, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(Icons.broken_image_outlined, size: 18, color: widget.color.withValues(alpha: 0.5))),
            );
          } catch (_) { fotoWidget = null; }
        }

        return SelectionContainer.disabled(
          child: GestureDetector(
            onTap: widget.onTap,
            onDoubleTap: widget.onDoubleTap,
            onLongPress: widget.fotoPath != null ? () => _showFotoPreview(context) : null,
            child: ClipRRect(
              borderRadius: br,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: widget.skin.isLight
                      ? Colors.white.withValues(alpha: widget.skin.glassOpacity)
                      : widget.skin.bgCard.withValues(alpha: widget.skin.glassOpacity),
                  borderRadius: br,
                  border: Border.all(
                    color: isEmpty ? widget.skin.glassBorder : widget.color.withValues(alpha: 0.38),
                    width: isEmpty ? 1.0 : 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(color: widget.skin.glassShadow, blurRadius: 24, offset: const Offset(0, 6)),
                    BoxShadow(color: widget.skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
                  ],
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(widget.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: widget.color, letterSpacing: 1.2)),
                    GestureDetector(
                      onTap: widget.onCameraPressed,
                      child: hasFoto && fotoWidget != null
                          ? Stack(children: [
                              fotoWidget,
                              Positioned(right: 0, bottom: 0, child: Container(
                                width: 14, height: 14,
                                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                                child: const Icon(Icons.check, size: 9, color: Colors.white),
                              )),
                            ])
                          : Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(color: widget.skin.surface(0.06), borderRadius: BorderRadius.circular(8)),
                              child: Icon(Icons.camera_alt_outlined, size: 14, color: widget.skin.surface(0.4)),
                            ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  if (isEmpty && widget.hintKm != null && widget.hintKm! > 0)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_formatKm(widget.hintKm!)} km',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: widget.skin.surface(0.18), letterSpacing: -0.5)),
                      const SizedBox(height: 2),
                      Text('↑ Doppeltipp zum Übernehmen',
                          style: TextStyle(fontSize: 9, color: widget.skin.surface(0.25), fontWeight: FontWeight.w500)),
                    ])
                  else
                    Text(
                      isEmpty ? '—' : '${widget.ctrl.text} km',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700,
                          color: isEmpty ? widget.skin.surface(0.2) : widget.skin.textPrimary, letterSpacing: -0.5),
                    ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INPUT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _InputRow extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label, hint;
  final TextEditingController ctrl;
  final TextCapitalization capitalize;
  final TextInputType? keyboardType;

  const _InputRow({
    required this.skin, required this.icon, required this.label, required this.ctrl, required this.hint,
    this.capitalize = TextCapitalization.none, this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: () { HapticFeedback.lightImpact(); ctrl.clear(); },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity) : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: skin.glassBorder),
              boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4))],
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: skin.primary),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 1.0)),
                const SizedBox(height: 4),
                AnimatedBuilder(
                  animation: ctrl,
                  builder: (_, __) => TextField(
                    controller: ctrl, keyboardType: keyboardType, textCapitalization: capitalize,
                    style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      hintText: hint, hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 15),
                      border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ])),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FAHRTZIEL INPUT MIT AUTOCOMPLETE
// ─────────────────────────────────────────────────────────────────────────────

class _FahrtZielInputField extends StatefulWidget {
  final AppSkin skin;
  final TextEditingController ctrl;
  final List<String> knownZiele;
  final VoidCallback? onChanged;

  const _FahrtZielInputField({
    required this.skin,
    required this.ctrl,
    required this.knownZiele,
    this.onChanged,
  });

  @override
  State<_FahrtZielInputField> createState() => _FahrtZielInputFieldState();
}

class _FahrtZielInputFieldState extends State<_FahrtZielInputField> {
  final _focusNode = FocusNode();
  bool _showSuggestions = false;
  List<String> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _updateSuggestions(widget.ctrl.text);
        setState(() => _showSuggestions = true);
      } else {
        setState(() => _showSuggestions = false);
      }
    });
    widget.ctrl.addListener(() {
      if (_focusNode.hasFocus) {
        _updateSuggestions(widget.ctrl.text);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _updateSuggestions(String input) {
    setState(() {
      _suggestions = FahrtZielHelper.suggestions(input, widget.knownZiele);
    });
  }

  void _selectSuggestion(String ziel) {
    widget.ctrl.text = ziel;
    widget.ctrl.selection = TextSelection.collapsed(offset: ziel.length);
    widget.onChanged?.call();
    _focusNode.unfocus();
    setState(() => _showSuggestions = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final hasSuggestions = _showSuggestions && _suggestions.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focusNode.hasFocus
                      ? skin.primary.withValues(alpha: 0.4)
                      : skin.glassBorder,
                  width: _focusNode.hasFocus ? 1.5 : 1.0,
                ),
                boxShadow: [
                  BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.map_outlined, size: 16, color: skin.primary),
                  const SizedBox(width: 8),
                  Text('FAHRTZIEL & WEG',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.0)),
                  const Spacer(),
                  if (widget.ctrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        widget.ctrl.clear();
                        widget.onChanged?.call();
                        setState(() {});
                      },
                      child: Icon(Icons.close, size: 14, color: skin.surface(0.35)),
                    ),
                ]),
                const SizedBox(height: 8),
                TextField(
                  controller: widget.ctrl,
                  focusNode: _focusNode,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.5),
                  decoration: InputDecoration(
                    hintText: 'z.B. Hauptbahnhof → Krankenhaus Mitte...',
                    hintStyle: TextStyle(
                        color: skin.surface(0.3),
                        fontSize: 13,
                        fontWeight: FontWeight.w400),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onChanged: (_) => widget.onChanged?.call(),
                ),
              ]),
            ),
          ),
        ),

        if (hasSuggestions) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
              child: Container(
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? Colors.white.withValues(alpha: 0.92)
                      : skin.bgCard.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: skin.glassBorder),
                  boxShadow: [
                    BoxShadow(color: skin.glassShadow, blurRadius: 16, offset: const Offset(0, 4)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.map((ziel) {
                    return GestureDetector(
                      onTap: () => _selectSuggestion(ziel),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              color: _suggestions.last == ziel
                                  ? Colors.transparent
                                  : skin.glassBorder,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(children: [
                          Icon(Icons.history_rounded,
                              size: 14, color: skin.surface(0.35)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              ziel,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: skin.textPrimary),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.north_west_rounded,
                              size: 12, color: skin.surface(0.3)),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}