// lib/widgets/share_location_sheet.dart
// Sheet "Ort übernehmen": ein geteilter Ort (Google/Apple Maps) wird einem Tag
// zugeordnet — entweder einem bestehenden Ereignis oder einem neuen.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/location_info.dart';
import '../theme/app_theme.dart';
import 'day_plan.dart';
import 'glass_dialogs.dart';
import 'glass_kit.dart';
import 'glass_pickers.dart';
import 'glass_snackbar.dart';

/// Text, der als `location` im Ereignis gespeichert wird (wie im Ortsfeld).
String locationDisplayText(LocationInfo loc) {
  if (loc.singleLine.isNotEmpty) return loc.singleLine;
  final n = (loc.name ?? '').trim();
  if (n.isNotEmpty) return n;
  if (loc.hasCoords) {
    return '${loc.lat!.toStringAsFixed(5)}, ${loc.lng!.toStringAsFixed(5)}';
  }
  return loc.rawInput.trim();
}

/// Öffnet das Sheet. [onChanged] wird nach dem Speichern aufgerufen
/// (z. B. damit die Tageskarte ihr Plan-Symbol aktualisiert).
Future<void> showShareLocationSheet(
  BuildContext context, {
  required AppSkin skin,
  required LocationInfo loc,
  VoidCallback? onChanged,
}) {
  FocusManager.instance.primaryFocus?.unfocus();
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    useSafeArea: false,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
    builder: (_) => ShareLocationSheet(skin: skin, loc: loc, onChanged: onChanged),
  );
}

class ShareLocationSheet extends StatefulWidget {
  final AppSkin skin;
  final LocationInfo loc;
  final VoidCallback? onChanged;
  const ShareLocationSheet({super.key, required this.skin, required this.loc, this.onChanged});

  @override
  State<ShareLocationSheet> createState() => _ShareLocationSheetState();
}

class _ShareLocationSheetState extends State<ShareLocationSheet> {
  DateTime? _day;
  List<DayPlanItem> _items = [];
  bool _busy = false;

  AppSkin get skin => widget.skin;

  @override
  void initState() {
    super.initState();
    // Heute ist vorausgewählt, die Ereignisse des Tages sind sofort sichtbar
    final now = DateTime.now();
    _day = DateTime(now.year, now.month, now.day);
    _items = DayPlanStore.load(_dateKey);
  }
  String get _dateKey => DateFormat('yyyy-MM-dd').format(_day!);

  // ── Datum (Pflicht) ─────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    HapticFeedback.selectionClick();
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showSingleDatePicker(
      context: context,
      skin: skin,
      initialDate: _day ?? DateTime.now(),
    );
    if (picked == null || !mounted) return;
    final d = DateTime(picked.year, picked.month, picked.day);
    setState(() {
      _day = d;
      _items = DayPlanStore.load(DateFormat('yyyy-MM-dd').format(d));
    });
  }

  // ── Bestehendes Ereignis: Ort setzen ────────────────────────────────────

  String _currentLocationText(DayPlanItem it) {
    final l = it.loc;
    if (l != null && l.singleLine.isNotEmpty) return l.singleLine;
    return it.location.trim();
  }

  Future<void> _assignTo(DayPlanItem it) async {
    if (_busy || _day == null) return;
    HapticFeedback.selectionClick();

    // Hat das Ereignis schon einen Ort → erst bestätigen
    if (it.location.trim().isNotEmpty || it.loc != null) {
      final old = _currentLocationText(it);
      final ok = await confirmActionDialog(
        context: context,
        skin: skin,
        title: 'Ort überschreiben?',
        message: '„${it.title}“ hat bereits den Ort „$old“. '
            'Er wird durch den neuen Ort ersetzt.',
        icon: Icons.place_outlined,
        confirmLabel: 'Überschreiben',
      );
      if (ok != true || !mounted) return;
    }

    _busy = true;
    final key = _dateKey;
    await DayPlanStore.upsert(
      key,
      DayPlanItem(
        id: it.id,
        title: it.title,
        start: it.start,
        end: it.end,
        location: locationDisplayText(widget.loc),
        loc: widget.loc,
      ),
    );
    if (!mounted) return;
    widget.onChanged?.call();
    showGlassSnackBar(context, 'Ort bei „${it.title}“ übernommen', type: GlassSnackBarType.success);
    Navigator.pop(context);
  }

  // ── Neues Ereignis ──────────────────────────────────────────────────────

  Future<void> _createNew() async {
    if (_busy || _day == null) return;
    HapticFeedback.selectionClick();
    final day = _day!;
    final key = _dateKey;
    final loc = widget.loc;

    // Titel = Ortsname (sonst Straße)
    final name = (loc.name ?? '').trim();
    final title = name.isNotEmpty ? name : loc.line1;

    Future<void>? saving;
    FocusManager.instance.primaryFocus?.unfocus();
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: false,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.92),
      builder: (_) => DayPlanItemSheet(
        skin: skin,
        day: day,
        initialStart: DayPlanStore.suggestedStart(key, day),
        initialTitle: title.isEmpty ? null : title,
        initialLocation: locationDisplayText(loc),
        initialLoc: loc,
        onSave: (item) {
          saving = DayPlanStore.upsert(key, item);
        },
      ),
    );

    if (saving == null) return; // abgebrochen
    await saving;
    if (!mounted) return;
    widget.onChanged?.call();
    showGlassSnackBar(context, 'Ereignis mit Ort angelegt', type: GlassSnackBarType.success);
    Navigator.pop(context);
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  Widget _sectionLabel(IconData icon, String label) => Row(children: [
        Icon(icon, size: 11, color: skin.primary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 0.8)),
      ]);

  Widget _locationCard() {
    final loc = widget.loc;
    final name = (loc.name ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: skin.surface(0.04), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (name.isNotEmpty)
            Text(name, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: skin.textPrimary)),
          if (loc.line1.isNotEmpty)
            Text(loc.line1, style: TextStyle(fontSize: 13.5, color: skin.textPrimary)),
          if (loc.line2.isNotEmpty)
            Text(loc.line2, style: TextStyle(fontSize: 13.5, color: skin.surface(0.6))),
          if (name.isEmpty && !loc.hasAddress)
            Text(locationDisplayText(loc), style: TextStyle(fontSize: 13.5, color: skin.surface(0.6))),
        ],
      ),
    );
  }

  String _itemSubtitle(DayPlanItem it) {
    final fmt = DateFormat('HH:mm');
    final time = '${fmt.format(it.start)} – ${fmt.format(it.end)}';
    final loc = _currentLocationText(it);
    return loc.isEmpty ? time : '$time\n$loc';
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final hasDay = _day != null;

    return GlassSheet(
      skin: skin,
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: SheetHandle(skin: skin)),
            const SizedBox(height: 14),
            Row(children: [
              Icon(Icons.place_outlined, color: skin.primary, size: 20),
              const SizedBox(width: 10),
              Text('Ort übernehmen',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: skin.textPrimary)),
            ]),
            const SizedBox(height: 14),
            _locationCard(),
            const SizedBox(height: 18),

            // ── 1. Datum (Pflicht) ──
            _sectionLabel(Icons.calendar_today_outlined, 'DATUM'),
            const SizedBox(height: 8),
            GlassSurface(
              padding: EdgeInsets.zero,
              child: GlassListItem(
                title: 'Tag',
                isLast: true,
                onTap: _pickDate,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                    hasDay ? DateFormat('EEE, dd. MMMM yyyy', 'de').format(_day!) : 'Wählen',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.primary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                ]),
              ),
            ),

            if (!hasDay) ...[
              const SizedBox(height: 12),
              Text('Wähle zuerst einen Tag, dann kannst du ein Ereignis auswählen oder ein neues anlegen.',
                  style: TextStyle(fontSize: 12.5, color: skin.textMuted, height: 1.4)),
            ] else ...[
              const SizedBox(height: 18),

              // ── 2. Bestehende Ereignisse ──
              _sectionLabel(Icons.schedule_outlined, 'EREIGNIS AUSWÄHLEN'),
              const SizedBox(height: 8),
              if (_items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text('Für diesen Tag gibt es noch keine Ereignisse.',
                      style: TextStyle(fontSize: 12.5, color: skin.textMuted)),
                )
              else
                GlassSurface(
                  padding: EdgeInsets.zero,
                  child: Column(children: [
                    for (int i = 0; i < _items.length; i++)
                      GlassListItem(
                        title: _items[i].title,
                        subtitle: _itemSubtitle(_items[i]),
                        isLast: i == _items.length - 1,
                        leading: Icon(Icons.schedule_outlined, size: 22, color: skin.primary),
                        trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                        onTap: () => _assignTo(_items[i]),
                      ),
                  ]),
                ),
              const SizedBox(height: 14),

              // ── 3. Neues Ereignis ──
              GlassPrimaryButton(
                skin: skin,
                label: 'Neues Ereignis erstellen',
                icon: Icons.add_rounded,
                onTap: _createNew,
              ),
            ],
          ],
        ),
      ),
    );
  }
}