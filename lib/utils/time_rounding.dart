import 'package:flutter/material.dart';

/// Zentrale Rundungslogik für Kommen-/Gehen-Zeiten.
/// rule: 'exact' | '5' | '10' | '15'
class TimeRounding {
  TimeRounding._();

  static const String hiveKey = 'zeit_rundung';
  static const String defaultRule = 'exact';

  static int stepMinutes(String rule) {
  switch (rule) {
    case '5':  return 5;
    case '10': return 10;
    case '15': return 15;
    default:   return 1; // 'exact'
  }
}

/// Berechnet die neue Gesamt-Minutenzahl (0..1439) nach EINEM Swipe-Schritt
  /// in [direction] (+1 = hoch, -1 = runter). Liegt [currentMinutes] noch
  /// nicht auf dem Rundungsraster (z. B. nach Tagesrand-Clamp oder nach
  /// Wechsel der Rundungsregel), wird zuerst in Swipe-Richtung aufs nächste
  /// sinnvolle Raster genormt, statt den Step einfach draufzurechnen.
  static int steppedTotal(int currentMinutes, String rule, int direction) {
    final step = stepMinutes(rule);
    if (step <= 1) {
      return (currentMinutes + direction).clamp(0, 23 * 60 + 59);
    }
    final onGrid = currentMinutes % step == 0;
    final int newTotal;
    if (!onGrid) {
      newTotal = direction > 0
          ? ((currentMinutes ~/ step) + 1) * step
          : (currentMinutes ~/ step) * step;
    } else {
      newTotal = currentMinutes + direction * step;
    }
    return newTotal.clamp(0, 23 * 60 + 59);
  }

  static String label(String rule) {
    switch (rule) {
      case '5':  return '5 Minuten';
      case '10': return '10 Minuten';
      case '15': return '15 Minuten';
      default:   return 'Genau (keine Rundung)';
    }
  }

  static DateTime round(DateTime dt, String rule) {
  final step = stepMinutes(rule);
    if (step <= 1) return DateTime(dt.year, dt.month, dt.day, dt.hour, dt.minute);
    final totalMinutes = dt.hour * 60 + dt.minute;
    final roundedMinutes = (totalMinutes / step).round() * step;
    return DateTime(dt.year, dt.month, dt.day).add(Duration(minutes: roundedMinutes));
  }

  static TimeOfDay roundTimeOfDay(TimeOfDay t, String rule) {
  final step = stepMinutes(rule);
    if (step <= 1) return t;
    final totalMinutes = t.hour * 60 + t.minute;
    final roundedMinutes = ((totalMinutes / step).round() * step).clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: roundedMinutes ~/ 60, minute: roundedMinutes % 60);
  }
}