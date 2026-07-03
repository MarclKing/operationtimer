import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import 'glass_kit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GEMEINSAME DATUM/ZEIT-PICKER
//
// Vorher: _IOSTimePicker komplett dupliziert in home_screen.dart UND
// fahrtenbuch_screen.dart (134 Zeilen, fast 1:1), dazu der Monats-Jahr-Picker
// (CupertinoPicker-Doppelspalte) inline nochmal in fahrtenbuch_screen.dart,
// month_screen.dart, schedule_screen.dart UND pdf_service.dart.
//
// Die einzige tatsächliche Verhaltens-Abweichung zwischen den beiden
// IOSTimePicker-Kopien: ob die ausgewählte Zeit auch beim Wegwischen/
// Schließen ohne "Übernehmen"-Tap übernommen wird. Das ist hier über den
// Parameter `confirmOnDismiss` abgebildet:
//   - home_screen.dart Verhalten      → confirmOnDismiss: false (Standard)
//   - fahrtenbuch_screen.dart Verhalten → confirmOnDismiss: true
// ─────────────────────────────────────────────────────────────────────────────

/// iOS-artiger Stunden:Minuten-Scrollpicker in einem Glass-Sheet.
///
/// [onTimeSelected] wird immer aufgerufen, wenn der Nutzer aktiv auf
/// "Übernehmen" tippt. Wenn [confirmOnDismiss] true ist, wird die zuletzt
/// gescrollte Zeit zusätzlich beim Schließen des Sheets (Wegwischen, Tap
/// außerhalb, Zurück-Geste) übernommen — das entspricht dem bisherigen
/// Verhalten in fahrtenbuch_screen.dart. Bei false (Standard, entspricht
/// dem bisherigen Verhalten in home_screen.dart) passiert beim Wegwischen
/// nichts; nur ein expliziter Tap auf "Übernehmen" zählt.
class IOSTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final AppSkin skin;
  final ValueChanged<TimeOfDay> onTimeSelected;
  final String label;
  final bool confirmOnDismiss;

  /// Schrittweite des Minuten-Rads in Minuten (1, 5, 10 oder 15).
  /// Bei z.B. 5 zeigt das Rad nur noch 00, 05, 10, … 55 — kein
  /// Vorbeiscrollen an 59 Einzelminuten mehr. Default 1 = unverändertes
  /// Verhalten (jede einzelne Minute wählbar).
  final int minuteInterval;

  const IOSTimePicker({
    super.key,
    required this.initialTime,
    required this.skin,
    required this.onTimeSelected,
    this.label = 'Uhrzeit auswählen',
    this.confirmOnDismiss = false,
    this.minuteInterval = 1,
  });

  @override
  State<IOSTimePicker> createState() => _IOSTimePickerState();
}

class _IOSTimePickerState extends State<IOSTimePicker> {
  late int _selectedHour, _selectedMinute;
  late FixedExtentScrollController _hourController, _minuteController;
  static const int _hourLoopOffset = 500, _minuteLoopOffset = 500;

  /// Wird true, sobald der Nutzer aktiv "Übernehmen" getippt hat — verhindert,
  /// dass dispose() bei confirmOnDismiss==true ein zweites Mal aufruft.
  bool _confirmedViaButton = false;

  /// Anzahl der Einträge im Minuten-Rad (z.B. 12 bei 5er-Schritten
  /// statt 60 bei Einzelminuten).
  int get _minuteCount => 60 ~/ widget.minuteInterval;

  /// Rad-Index → tatsächliche Minute
  int _minuteForIndex(int index) => (index % _minuteCount) * widget.minuteInterval;

  /// Rundet eine beliebige Minute auf die nächste Rad-Position.
  int _nearestMinuteIndex(int minute) =>
      (minute / widget.minuteInterval).round() % _minuteCount;

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = _minuteForIndex(_nearestMinuteIndex(widget.initialTime.minute));
    _hourController = FixedExtentScrollController(initialItem: _hourLoopOffset * 24 + _selectedHour);
    _minuteController = FixedExtentScrollController(
        initialItem: _minuteLoopOffset * _minuteCount + _nearestMinuteIndex(widget.initialTime.minute));
  }

  @override
  void dispose() {
    if (widget.confirmOnDismiss && !_confirmedViaButton) {
      widget.onTimeSelected(TimeOfDay(hour: _selectedHour, minute: _selectedMinute));
    }
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _setCurrentTime() {
    final now = DateTime.now();
    final nowHour = now.hour;
    final nowMinuteIdx = _nearestMinuteIndex(now.minute);
    final nowMinute = _minuteForIndex(nowMinuteIdx);

    final currentHourIdx = _hourController.selectedItem;
    final currentHourBase = (currentHourIdx ~/ 24) * 24;
    int targetHourIdx = currentHourBase + nowHour;
    if (targetHourIdx < currentHourIdx) targetHourIdx += 24;

    final currentMinuteIdx = _minuteController.selectedItem;
    final currentMinuteBase = (currentMinuteIdx ~/ _minuteCount) * _minuteCount;
    int targetMinuteIdx = currentMinuteBase + nowMinuteIdx;
    if (targetMinuteIdx < currentMinuteIdx) targetMinuteIdx += _minuteCount;

    _hourController.animateToItem(targetHourIdx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    _minuteController.animateToItem(targetMinuteIdx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    setState(() {
      _selectedHour = nowHour;
      _selectedMinute = nowMinute;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return GlassSheet(
      skin: skin,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SheetHandle(skin: skin),
        const SizedBox(height: 16),
        Text(widget.label, style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        SizedBox(
          height: 200,
          child: Row(children: [
            Expanded(
              child: CupertinoPicker(
                scrollController: _hourController,
                magnification: 1.2,
                backgroundColor: Colors.transparent,
                itemExtent: 40,
                looping: true,
                onSelectedItemChanged: (index) => setState(() => _selectedHour = index % 24),
                children: List.generate(
                    24,
                    (h) => Center(
                        child: Text(h.toString().padLeft(2, '0'),
                            style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: _selectedHour == h ? skin.primary : skin.surface(0.5))))),
              ),
            ),
            Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: skin.primary)),
            Expanded(
              child: CupertinoPicker(
                scrollController: _minuteController,
                magnification: 1.2,
                backgroundColor: Colors.transparent,
                itemExtent: 40,
                looping: true,
                onSelectedItemChanged: (index) =>
                    setState(() => _selectedMinute = _minuteForIndex(index)),
                children: List.generate(
                    _minuteCount,
                    (i) {
                      final m = i * widget.minuteInterval;
                      return Center(
                          child: Text(m.toString().padLeft(2, '0'),
                              style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: _selectedMinute == m ? skin.primary : skin.surface(0.5))));
                    }),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(children: [
            Expanded(child: GlassSecondaryButton(skin: skin, label: 'Jetzt', onTap: _setCurrentTime)),
            const SizedBox(width: 10),
            Expanded(
                child: GlassPrimaryButton(
                    skin: skin,
                    label: 'Übernehmen',
                    onTap: () {
                      _confirmedViaButton = true;
                      widget.onTimeSelected(TimeOfDay(hour: _selectedHour, minute: _selectedMinute));
                      Navigator.pop(context);
                    })),
          ]),
        ),
        const SizedBox(height: 28),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MONAT & JAHR PICKER
//
// Vorher: identischer CupertinoPicker-Doppelspalten-Code (Monat + Jahr,
// "Aktuell"/"Auswählen"-Buttons) inline kopiert in fahrtenbuch_screen.dart
// (_showMonthPicker), month_screen.dart (_showMonthPicker),
// schedule_screen.dart (_showMonthPicker) und pdf_service.dart
// (showMonthPickerAndExport). Jetzt: ein Funktionsaufruf.
//
// showMonthYearPicker zeigt das Sheet und liefert den gewählten Monat
// zurück (1. Tag des Monats) oder null, wenn der Nutzer abgebrochen hat.
// "Aktuell" liefert den aktuellen Monat zurück, genau wie "Auswählen".
// ─────────────────────────────────────────────────────────────────────────────

Future<DateTime?> showMonthYearPicker({
  required BuildContext context,
  required AppSkin skin,
  required DateTime initialMonth,
}) {
  int pickedYear = initialMonth.year;
  int pickedMonth = initialMonth.month - 1;
  final yearCount = DateTime.now().year - 2020 + 2;
  final monthCtrl = FixedExtentScrollController(initialItem: 1000 * 12 + pickedMonth);
  final yearCtrl = FixedExtentScrollController(initialItem: pickedYear - 2020);

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setSheet) => GlassSheet(
        skin: skin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHandle(skin: skin),
            const SizedBox(height: 12),
Text('Monat & Jahr', style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
const SizedBox(height: 8),
SizedBox(
  height: 160,
  child: Row(children: [
    Expanded(
      flex: 2,
      child: CupertinoPicker(
        scrollController: monthCtrl,
        itemExtent: 32,
        squeeze: 1.45,
        diameterRatio: 1.07,
        magnification: 1.2,
        looping: true,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: (i) => setSheet(() => pickedMonth = i % 12),
        children: List.generate(
          12,
          (i) => Center(
            child: Text(
              DateFormat('MMMM', 'de').format(DateTime(2024, i + 1)),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: skin.textPrimary),
            ),
          ),
        ),
      ),
    ),
    Expanded(
      child: CupertinoPicker(
        scrollController: yearCtrl,
        itemExtent: 32,
        squeeze: 1.45,
        diameterRatio: 1.07,
        magnification: 1.2,
        looping: false,
        backgroundColor: Colors.transparent,
        onSelectedItemChanged: (i) => setSheet(() => pickedYear = 2020 + i.clamp(0, yearCount - 1)),
        children: List.generate(
          yearCount,
          (i) => Center(
            child: Text(
              '${2020 + i}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: skin.textPrimary),
            ),
          ),
        ),
      ),
    ),
  ]),
),
const SizedBox(height: 8),
Padding(
  padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
  child: Row(children: [
    Expanded(
      child: GlassSecondaryButton(
        skin: skin,
        label: 'Aktuell',
        onTap: () {
          final now = DateTime.now();
          Navigator.pop(ctx, DateTime(now.year, now.month));
        },
      ),
    ),
    const SizedBox(width: 10),
    Expanded(
      child: GlassPrimaryButton(
        skin: skin,
        label: 'Auswählen',
        onTap: () => Navigator.pop(ctx, DateTime(pickedYear, pickedMonth + 1)),
      ),
    ),
  ]),
),
const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// EINFACHER DATUMS-PICKER (Tag/Monat/Jahr) — z. B. für "Datum auswählen" in
// home_screen.dart und fahrtenbuch_screen.dart (_pickDate). Beide Stellen
// nutzten exakt denselben CupertinoDatePicker-Aufbau mit "Heute"/"Übernehmen".
// ─────────────────────────────────────────────────────────────────────────────

Future<DateTime?> showSingleDatePicker({
  required BuildContext context,
  required AppSkin skin,
  required DateTime initialDate,
  DateTime? minimumDate,
  DateTime? maximumDate,
}) {
  DateTime tempDate = initialDate;
  UniqueKey pickerKey = UniqueKey();

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => GlassSheet(
        skin: skin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHandle(skin: skin),
            const SizedBox(height: 8),
            Text('Datum auswählen', style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SizedBox(
              height: 160,
              child: CupertinoDatePicker(
                key: pickerKey,
                mode: CupertinoDatePickerMode.date,
                initialDateTime: tempDate,
                minimumDate: minimumDate ?? DateTime(2020),
                maximumDate: maximumDate ?? DateTime(2030),
                backgroundColor: Colors.transparent,
                onDateTimeChanged: (d) => tempDate = d,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Row(children: [
                Expanded(
                  child: GlassSecondaryButton(
                    skin: skin,
                    label: 'Heute',
                    onTap: () {
                      tempDate = DateTime.now();
                      pickerKey = UniqueKey();
                      setDialogState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassPrimaryButton(
                    skin: skin,
                    label: 'Übernehmen',
                    onTap: () => Navigator.pop(context, tempDate),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}