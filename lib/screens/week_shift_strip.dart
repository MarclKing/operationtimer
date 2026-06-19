import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SHIFT COLOR — 1:1 Übersetzung der Swift-Funktion aus DienstplanWidget.swift
//
// Swift-Original:
//   case "U", "DA", "X": return Color(.systemGray)
//   case "VK": return Color(red: 0.94, green: 0.36, blue: 0.36)
//   default: return Color(red: 0.36, green: 0.55, blue: 0.94)
// ─────────────────────────────────────────────────────────────────────────────

Color shiftColor(String shift) {
  switch (shift.toUpperCase()) {
    case 'U':
    case 'DA':
    case 'X':
      return const Color(0xFF8E8E93); // iOS systemGray-Äquivalent
    case 'VK':
      return const Color.fromRGBO(240, 92, 92, 1); // 0.94, 0.36, 0.36
    default:
      return const Color.fromRGBO(92, 140, 240, 1); // 0.36, 0.55, 0.94
  }
}

/// Liest die Schichtcodes für die aktuelle ISO-Woche (Mo–So) aus Hive.
/// Gibt eine Liste von 7 Einträgen zurück: (datum, code-oder-null).
/// code == null bedeutet: kein Dienstplan-Eintrag für diesen Tag vorhanden.
List<MapEntry<DateTime, String?>> loadCurrentWeekShifts() {
  final box = Hive.box('einstellungen');
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  // Montag der aktuellen Woche (ISO: weekday 1 = Montag)
  final monday = today.subtract(Duration(days: today.weekday - 1));

  final result = <MapEntry<DateTime, String?>>[];
  for (int i = 0; i < 7; i++) {
    final day = monday.add(Duration(days: i));
    final monthKey = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}';
    final dayKey = DateFormat('yyyy-MM-dd').format(day);

    final raw = box.get('schedule_$monthKey');
    String? code;
    if (raw is Map) {
      final value = raw[dayKey];
      if (value != null && value.toString().trim().isNotEmpty) {
        code = value.toString().trim();
      }
    }
    result.add(MapEntry(day, code));
  }
  return result;
}

/// Ob für die aktuelle Woche überhaupt irgendein Dienstplan-Eintrag existiert.
bool currentWeekHasAnySchedule() {
  return loadCurrentWeekShifts().any((e) => e.value != null);
}

// ─────────────────────────────────────────────────────────────────────────────
// WOCHENSTREIFEN-WIDGET
// Zeigt 7 Pillen mit den Schichtcodes der aktuellen Woche.
// Heutiger Tag: voll gefüllt mit Leuchtring.
// Andere Tage: dezent eingefärbt nach shiftColor.
// Fehlt der komplette Dienstplan -> dekoratives Fallback-Element (3 Balken).
// ─────────────────────────────────────────────────────────────────────────────

class WeekShiftStrip extends StatelessWidget {
  final AppSkin skin;
  const WeekShiftStrip({required this.skin});

  @override
  Widget build(BuildContext context) {
    // Pillen-Anzeige deaktiviert — zeigt jetzt immer nur das
    // dekorative Fallback-Element (3 Balken), unabhängig vom
    // Dienstplan-Status.
    return _DecorativeFallback(skin: skin);
  }
}

/// Rein dekoratives Element ohne inhaltliche Aussage — drei abnehmende
/// Balken in der Primärfarbe. Erscheint, wenn für die aktuelle Woche
/// kein Dienstplan-Eintrag existiert.
class _DecorativeFallback extends StatelessWidget {
  final AppSkin skin;
  const _DecorativeFallback({required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 28, height: 4, decoration: BoxDecoration(
          color: skin.primary, borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 4),
        Container(width: 14, height: 4, decoration: BoxDecoration(
          color: skin.primary.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(2),
        )),
        const SizedBox(width: 4),
        Container(width: 7, height: 4, decoration: BoxDecoration(
          color: skin.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2),
        )),
      ],
    );
  }
}