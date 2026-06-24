import 'dart:math';
import '../models/relationship_style.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PHRASES — zentrales Phrasenbuch für ALLE Notification-Texte.
//
// ZWECK DIESER DATEI:
// Jeder Textbaustein (Begrüßung, Wetter-Satz, Task-Hinweis, ...) ist eine
// LISTE von Varianten pro RelationshipStyle. Beim Senden einer Notification
// wird zufällig EINE Variante aus der passenden Liste gewählt (s. `pick()`).
//
// SO ERWEITERST DU DAS SPÄTER:
// Einfach einen neuen String in die passende Liste einfügen — fertig. Kein
// anderer Code muss angefasst werden. Du kannst pro Liste beliebig viele
// Einträge ergänzen, auch nur für einen einzelnen Stil.
//
// Beispiel: Mehr "Bro"-Begrüßungen gewünscht? → einfach in `_greetingBro`
// unten eine neue Zeile einfügen.
//
// PLATZHALTER:
// {name}      → Vorname oder Nachname, je nach Stil (wird vom Aufrufer
//               bereits eingesetzt, bevor der String genutzt wird — s.
//               `applyName()`)
// {temp}      → Temperatur in Grad, z.B. "25°" (nur Wetter-Sätze)
// {task}      → Titel einer konkreten Aufgabe (nur Task-Sätze)
// {shift}     → Schichtcode, z.B. "P1" (nur Dienst-Sätze)
// {count}     → Anzahl offener Aufgaben (nur Sammel-Sätze)
// ─────────────────────────────────────────────────────────────────────────────

final _rng = Random();

/// Wählt zufällig einen Eintrag aus einer nicht-leeren Liste.
/// Fällt auf einen Fallback-String zurück, falls die Liste (versehentlich)
/// leer sein sollte, damit die App nie crasht, nur weil eine Liste mal
/// kurzzeitig leer ist.
String pick(List<String> options, {String fallback = ''}) {
  if (options.isEmpty) return fallback;
  return options[_rng.nextInt(options.length)];
}

/// Ersetzt {name} im String. Bei leerem Namen wird die Lücke entfernt und
/// umgebende doppelte Leerzeichen/Kommas bereinigt, damit kein "Hey , wie"
/// entsteht.
String applyName(String text, String name) {
  if (name.trim().isEmpty) {
    return text
        .replaceAll(', {name}:', ':')
        .replaceAll('{name}, ', '')
        .replaceAll(', {name}', '')
        .replaceAll('{name} ', '')
        .replaceAll('{name}', '')
        .replaceAll('  ', ' ')
        .trim();
  }
  return text.replaceAll('{name}', name);
}

String applyTemp(String text, String temp) => text.replaceAll('{temp}', temp);
String applyTask(String text, String task) => text.replaceAll('{task}', task);
String applyShift(String text, String shift) => text.replaceAll('{shift}', shift);
String applyCount(String text, int count) => text.replaceAll('{count}', count.toString());

// ─────────────────────────────────────────────────────────────────────────────
// WETTER-KATEGORIEN
//
// Mappt den Open-Meteo weatherCode (s. WeatherData) auf eine grobe Kategorie.
// Kälte hat Vorrang vor der Wetterlage selbst (s. categoryFor()) — bei
// niedrigen Temperaturen ist "es ist kalt" wichtiger als "es ist bedeckt".
// ─────────────────────────────────────────────────────────────────────────────

enum WeatherCategory {
  sonnig,
  wechselhaftBewoelkt,
  bedeckt,
  nebel,
  regenLeicht,
  regenStark,
  schnee,
  gewitter,
  kalt, // Override bei niedriger Temperatur, unabhängig vom Code
}

/// Bestimmt die Wetterkategorie aus Code + Temperatur.
/// `coldThresholdC`: ab welcher Temperatur (inkl.) "kalt" Vorrang bekommt.
WeatherCategory categoryFor(int weatherCode, double tempC, {
  double coldThresholdC = 5.0,
  bool isDay = true, // NEU
}) {
  if (tempC <= coldThresholdC) return WeatherCategory.kalt;
  if (!isDay) {
    // Nachts: nur zwischen klar/bewölkt/Niederschlag unterscheiden
    if (weatherCode == 0) return WeatherCategory.bedeckt; // "klare Nacht" → neutral
    if (weatherCode <= 2) return WeatherCategory.wechselhaftBewoelkt;
    if (weatherCode == 3) return WeatherCategory.bedeckt;
    if (weatherCode <= 49) return WeatherCategory.nebel;
    if (weatherCode <= 59 || (weatherCode >= 80 && weatherCode <= 82)) return WeatherCategory.regenLeicht;
    if (weatherCode <= 69) return WeatherCategory.regenStark;
    if (weatherCode <= 86) return WeatherCategory.schnee;
    if (weatherCode <= 99) return WeatherCategory.gewitter;
    return WeatherCategory.bedeckt;
  }
  // Tag — wie bisher
  if (weatherCode == 0) return WeatherCategory.sonnig;
  if (weatherCode <= 2) return WeatherCategory.wechselhaftBewoelkt;
  if (weatherCode == 3) return WeatherCategory.bedeckt;
  if (weatherCode <= 49) return WeatherCategory.nebel;
  if (weatherCode <= 59 || (weatherCode >= 80 && weatherCode <= 82)) return WeatherCategory.regenLeicht;
  if (weatherCode <= 69) return WeatherCategory.regenStark;
  if (weatherCode <= 86) return WeatherCategory.schnee;
  if (weatherCode <= 99) return WeatherCategory.gewitter;
  return WeatherCategory.wechselhaftBewoelkt;
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: BEGRÜSSUNG (Notification-Titel der Tagesvorschau)
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _greetingBro = [
  'Aufstehen, Schlafmütze ☀️',
  'Yo, Zeit zum Ranklotzen!',
  'Na, ausgeschlafen? Los geht\'s!',
  'Wakey wakey, Bro!',
];

const List<String> _greetingVorname = [
  'Guten Morgen, {name}!',
  'Schön, dass du da bist.',
  'Hey {name}, los geht\'s in den Tag.',
  'Guten Morgen ☀️',
];

// Hinweis: "Familie"-Stil siezt, spricht aber mit dem VORNAMEN an (nicht
// Nachname + Anrede-Titel) — vermeidet jedes Genus-Problem ("Werter/Werte")
// und klingt trotzdem persönlich-förmlich, z.B. "Guten Morgen Olaf, Sie
// haben heute folgenden Dienst." Der Aufrufer übergibt hier also bereits
// den VORNAMEN als {name}, nicht den Nachnamen.
const List<String> _greetingFamilie = [
  'Guten Morgen {name}.',
  'Einen guten Morgen, {name}.',
  'Ich hoffe, Sie haben gut geschlafen, {name}.',
];

List<String> greeting(RelationshipStyle style) {
  switch (style) {
    case RelationshipStyle.bro:
      return _greetingBro;
    case RelationshipStyle.vorname:
      return _greetingVorname;
    case RelationshipStyle.familie:
      return _greetingFamilie;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: SUBTITLE (zweite Zeile, kleiner Spruch unter der Begrüßung)
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _subtitleBro = [
  'Bereit, die Welt zu retten?',
  'Auf geht\'s, reiß den Tag an dich!',
  'Lass den Laden brennen 🔥',
  'Zeit, Gas zu geben!',
];

const List<String> _subtitleVorname = [
  'Hier ist dein Überblick für heute.',
  'Damit du gut vorbereitet bist.',
  'Ein kurzer Blick auf deinen Tag.',
];

const List<String> _subtitleFamilie = [
  'Hier ist Ihre Übersicht für den heutigen Tag.',
  'Darf ich Ihnen einen kurzen Überblick geben?',
  'Ihre Tagesübersicht im Folgenden.',
];

List<String> subtitle(RelationshipStyle style) {
  switch (style) {
    case RelationshipStyle.bro:
      return _subtitleBro;
    case RelationshipStyle.vorname:
      return _subtitleVorname;
    case RelationshipStyle.familie:
      return _subtitleFamilie;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: DIENST-ZEILE (Body, Zeile 1)
// ─────────────────────────────────────────────────────────────────────────────

// Hinweis: P/F ohne Artikel, T/U/X/DA/VK/IS ausgeschrieben oder mit Artikel
const List<String> _shiftBroWork = [
  'Heute steht {shift} an, Bro.',
  'Dein Ding heute: {shift}.',
  'Heute läuft {shift}.',
];
const List<String> _shiftVornameWork = [
  'Heute steht {shift} an.',
  'Heute hast du {shift}.',
];
const List<String> _shiftFamilieWork = [
  'Heute steht {shift} an, {name}.',
  'Für Sie steht heute {shift} an, {name}.',
];

const List<String> _shiftBroFree = [
  'Heute ist frei, Bro — genieß es!',
  'Kein Dienst heute, einfach mal chillen.',
];

const List<String> _shiftVornameFree = [
  'Heute hast du frei.',
  'Kein Dienst für dich heute.',
];

const List<String> _shiftFamilieFree = [
  'Heute haben Sie keinen Dienst, {name}.',
  'Für Sie ist heute dienstfrei, {name}.',
];

const List<String> _shiftBroUnknown = [
  'Kein Dienstplan für heute hinterlegt, Bro.',
];

const List<String> _shiftVornameUnknown = [
  'Für heute ist kein Dienst hinterlegt.',
];

const List<String> _shiftFamilieUnknown = [
  'Für den heutigen Tag liegt kein Dienst vor.',
];

/// `shiftCode` == null → kein Dienstplan-Eintrag vorhanden.
/// `shiftCode` == 'frei' (oder leer behandelt vom Aufrufer) → dienstfrei.
List<String> shiftLine(RelationshipStyle style, {required bool hasShift, required bool isFree}) {
  if (!hasShift) {
    switch (style) {
      case RelationshipStyle.bro:
        return _shiftBroUnknown;
      case RelationshipStyle.vorname:
        return _shiftVornameUnknown;
      case RelationshipStyle.familie:
        return _shiftFamilieUnknown;
    }
  }
  if (isFree) {
    switch (style) {
      case RelationshipStyle.bro:
        return _shiftBroFree;
      case RelationshipStyle.vorname:
        return _shiftVornameFree;
      case RelationshipStyle.familie:
        return _shiftFamilieFree;
    }
  }
  switch (style) {
    case RelationshipStyle.bro:
      return _shiftBroWork;
    case RelationshipStyle.vorname:
      return _shiftVornameWork;
    case RelationshipStyle.familie:
      return _shiftFamilieWork;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: NOTIZ-HINWEIS (Body, nur falls eine Notiz hinterlegt ist)
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _noteHintBro = [
  '📝 Schau mal in deine Notizen für heute, Bro.',
  '📝 Da war doch was — guck in die Notiz von heute.',
];

const List<String> _noteHintVorname = [
  '📝 Schau mal in deine Notizen für heute.',
  '📝 Es gibt eine Notiz für heute — kurz reinschauen lohnt sich.',
];

const List<String> _noteHintFamilie = [
  '📝 Für den heutigen Tag liegt eine Notiz vor — ein Blick lohnt sich.',
  '📝 Bitte beachten Sie die Notiz für den heutigen Tag.',
];

List<String> noteHintLine(RelationshipStyle style) {
  switch (style) {
    case RelationshipStyle.bro:
      return _noteHintBro;
    case RelationshipStyle.vorname:
      return _noteHintVorname;
    case RelationshipStyle.familie:
      return _noteHintFamilie;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: WETTER-ZEILE (Body)
//
// Ganze Sätze mit {temp}-Platzhalter, gruppiert nach Wetterkategorie. Pro
// Kategorie reichen wenige Varianten (1-3), da das Wetter selbst täglich
// für Abwechslung sorgt — die Kategorie bestimmt den Satz, die Temperatur
// ist nur eine Ergänzung darin.
// ─────────────────────────────────────────────────────────────────────────────

const Map<WeatherCategory, List<String>> _weatherBro = {
  WeatherCategory.sonnig: [
    'Draußen warten sonnige {temp}, Bro — Sonnencreme nicht vergessen!',
    'Bombenwetter da draußen: {temp} und Sonne satt.',
  ],
  WeatherCategory.wechselhaftBewoelkt: [
    'Draußen ist es wechselhaft bei {temp}, Bro.',
    'Mal Sonne, mal Wolken — {temp} draußen.',
  ],
  WeatherCategory.bedeckt: [
    'Draußen ist es bedeckt, {temp}, Bro.',
    'Grauer Himmel heute, {temp} sind angesagt.',
  ],
  WeatherCategory.nebel: [
    'Nebel draußen, Bro — {temp} und schlechte Sicht.',
  ],
  WeatherCategory.regenLeicht: [
    'Ein bisschen Regen heute, {temp} — Kapuze einpacken, Bro.',
  ],
  WeatherCategory.regenStark: [
    'Ordentlich Regen da draußen, {temp} — Schirm nicht vergessen, Bro!',
  ],
  WeatherCategory.schnee: [
    'Schnee ist angesagt, {temp} — warm anziehen, Bro!',
  ],
  WeatherCategory.gewitter: [
    'Gewitter im Anmarsch, {temp} draußen — pass auf dich auf, Bro.',
  ],
  WeatherCategory.kalt: [
    'Es fröstelt ordentlich, {temp} — zieh dich warm an, Bro!',
  ],
};

const Map<WeatherCategory, List<String>> _weatherVorname = {
  WeatherCategory.sonnig: [
    'Draußen werden sonnige {temp}, denk an Sonnencreme.',
    'Schönes Wetter heute: {temp} und Sonnenschein.',
  ],
  WeatherCategory.wechselhaftBewoelkt: [
    'Draußen ist es wechselhaft bei {temp}.',
  ],
  WeatherCategory.bedeckt: [
    'Draußen ist es bedeckt, bei {temp}.',
  ],
  WeatherCategory.nebel: [
    'Es ist neblig draußen, {temp}.',
  ],
  WeatherCategory.regenLeicht: [
    'Es regnet etwas, {temp} — nimm einen Schirm mit.',
  ],
  WeatherCategory.regenStark: [
    'Es regnet ordentlich, {temp} — Schirm einpacken!',
  ],
  WeatherCategory.schnee: [
    'Es schneit, {temp} — zieh dich warm an.',
  ],
  WeatherCategory.gewitter: [
    'Es zieht ein Gewitter auf, {temp}.',
  ],
  WeatherCategory.kalt: [
    'Draußen fröstelt es etwas, wir haben {temp} — zieh dich warm an.',
  ],
};

const Map<WeatherCategory, List<String>> _weatherFamilie = {
  WeatherCategory.sonnig: [
    'Draußen erwarten Sie sonnige {temp}.',
    'Es zeigt sich heute sonniges Wetter bei {temp}.',
  ],
  WeatherCategory.wechselhaftBewoelkt: [
    'Es zeigt sich heute wechselhaftes Wetter bei {temp}.',
  ],
  WeatherCategory.bedeckt: [
    'Der Himmel ist heute bedeckt, bei {temp}.',
  ],
  WeatherCategory.nebel: [
    'Es ist heute neblig, bei {temp}.',
  ],
  WeatherCategory.regenLeicht: [
    'Es ist mit etwas Regen zu rechnen, bei {temp}.',
  ],
  WeatherCategory.regenStark: [
    'Es ist mit stärkerem Regen zu rechnen, bei {temp} — ein Schirm wird empfohlen.',
  ],
  WeatherCategory.schnee: [
    'Es ist mit Schneefall zu rechnen, bei {temp} — bitte warm anziehen.',
  ],
  WeatherCategory.gewitter: [
    'Es zieht ein Gewitter auf, bei {temp}.',
  ],
  WeatherCategory.kalt: [
    'Es ist heute kühl, bei {temp} — bitte denken Sie an warme Kleidung.',
  ],
};

List<String> weatherLine(RelationshipStyle style, WeatherCategory category) {
  final Map<WeatherCategory, List<String>> table;
  switch (style) {
    case RelationshipStyle.bro:
      table = _weatherBro;
      break;
    case RelationshipStyle.vorname:
      table = _weatherVorname;
      break;
    case RelationshipStyle.familie:
      table = _weatherFamilie;
      break;
  }
  return table[category] ?? table[WeatherCategory.wechselhaftBewoelkt]!;
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: AUFGABEN-ZEILE (Body, letzte Zeile der Tagesvorschau)
//
// Drei Fälle:
//  - genau 1 Aufgabe heute fällig    → konkreten Titel nennen
//  - mehrere Aufgaben heute fällig   → Anzahl nennen
//  - keine Aufgabe heute, aber andere offene Aufgaben existieren
//                                     → genereller Hinweis, mal in Aufgaben
//                                       vorbeizuschauen
//  - gar keine offenen Aufgaben      → kein Hinweis nötig (Aufrufer lässt
//                                       die Zeile in diesem Fall einfach weg)
// ─────────────────────────────────────────────────────────────────────────────

// ── Fall: genau 1 Aufgabe heute fällig, keine anderen offenen Aufgaben ──
const List<String> _taskOneOnlyBro = [
  '📌 Heute steht an: {task}.',
  '📌 Nicht vergessen, Bro: {task}.',
];
const List<String> _taskOneOnlyVorname = [
  '📌 Heute steht an: {task}.',
  '📌 Denk daran: {task}.',
];
const List<String> _taskOneOnlyFamilie = [
  '📌 Für heute steht an: {task}.',
  '📌 Bitte denken Sie an: {task}.',
];

// ── Fall: 1 Aufgabe heute fällig + 1-2 andere offene (kurzer Zusatz passt) ──
const List<String> _taskOnePlusFewBro = [
  '📌 Heute steht an: {task}. Schau auch mal bei den anderen Aufgaben vorbei, Bro.',
];
const List<String> _taskOnePlusFewVorname = [
  '📌 Heute steht an: {task}. Schau auch mal bei den anderen Aufgaben vorbei.',
];
const List<String> _taskOnePlusFewFamilie = [
  '📌 Für heute steht an: {task}. Ein Blick auf die weiteren offenen Aufgaben lohnt sich ebenfalls.',
];

// ── Fall: 1 Aufgabe heute fällig + 3 oder mehr andere offene (kein Platz
// mehr für Details, nur knapper Verweis) ──
const List<String> _taskOnePlusManyBro = [
  '📌 Heute steht an: {task}. Schau mal in die Aufgaben rein, Bro.',
];
const List<String> _taskOnePlusManyVorname = [
  '📌 Heute steht an: {task}. Schau mal in die Aufgaben rein.',
];
const List<String> _taskOnePlusManyFamilie = [
  '📌 Für heute steht an: {task}. Bitte schauen Sie auch in Ihre Aufgaben.',
];

// ── Fall: mehrere Aufgaben heute fällig (≥2) — keine Einzelnennung mehr ──
const List<String> _taskManyBro = [
  '📌 {count} Aufgaben fällig — ran an den Speck!',
  '📌 {count} Aufgaben heute — los, Bro!',
];
const List<String> _taskManyVorname = [
  '📌 {count} Aufgaben heute fällig.',
  '📌 {count} Aufgaben warten heute.',
];
const List<String> _taskManyFamilie = [
  '📌 {count} Aufgaben stehen heute an.',
  '📌 Heute sind {count} Aufgaben fällig.',
];

// ── Fall: heute nichts fällig, aber andere offene Aufgaben existieren ──
const List<String> _taskNoneTodayButOpenBro = [
  '✅ Heute ist nichts fällig, aber es liegen noch Aufgaben offen — schau mal vorbei, Bro.',
  '✅ Heute hast du frei von Fristen, trotzdem stehen noch ein paar Aufgaben offen.',
];
const List<String> _taskNoneTodayButOpenVorname = [
  '✅ Heute ist nichts fällig, aber es sind noch Aufgaben offen — schau mal vorbei.',
];
const List<String> _taskNoneTodayButOpenFamilie = [
  '✅ Für heute liegt nichts an, es sind jedoch noch Aufgaben offen — ein Blick lohnt sich.',
];

/// Liefert die passende Aufgaben-Zeile für die Tagesvorschau, oder null,
/// wenn gar keine Zeile nötig ist (keine fälligen Aufgaben heute UND keine
/// sonstigen offenen Aufgaben).
///
/// `dueTodayCount`     — Anzahl Aufgaben mit Frist genau heute
/// `dueTodayTaskTitle` — Titel der einzigen heute fälligen Aufgabe (nur
///                       relevant, wenn dueTodayCount == 1)
/// `otherOpenCount`    — Anzahl anderer offener Aufgaben (NICHT heute
///                       fällig — weder mit Frist an einem anderen Tag,
///                       siehe Aufrufer-Logik in notification_service.dart,
///                       noch ohne Frist)
List<String>? taskLine(
  RelationshipStyle style, {
  required int dueTodayCount,
  String? dueTodayTaskTitle,
  required int otherOpenCount,
}) {
  if (dueTodayCount == 1) {
    if (otherOpenCount == 0) {
      switch (style) {
        case RelationshipStyle.bro: return _taskOneOnlyBro;
        case RelationshipStyle.vorname: return _taskOneOnlyVorname;
        case RelationshipStyle.familie: return _taskOneOnlyFamilie;
      }
    }
    if (otherOpenCount <= 2) {
      switch (style) {
        case RelationshipStyle.bro: return _taskOnePlusFewBro;
        case RelationshipStyle.vorname: return _taskOnePlusFewVorname;
        case RelationshipStyle.familie: return _taskOnePlusFewFamilie;
      }
    }
    switch (style) {
      case RelationshipStyle.bro: return _taskOnePlusManyBro;
      case RelationshipStyle.vorname: return _taskOnePlusManyVorname;
      case RelationshipStyle.familie: return _taskOnePlusManyFamilie;
    }
  }
  if (dueTodayCount > 1) {
    switch (style) {
      case RelationshipStyle.bro: return _taskManyBro;
      case RelationshipStyle.vorname: return _taskManyVorname;
      case RelationshipStyle.familie: return _taskManyFamilie;
    }
  }
  if (otherOpenCount > 0) {
    switch (style) {
      case RelationshipStyle.bro: return _taskNoneTodayButOpenBro;
      case RelationshipStyle.vorname: return _taskNoneTodayButOpenVorname;
      case RelationshipStyle.familie: return _taskNoneTodayButOpenFamilie;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK-NOTIFICATIONS — Reminder / heute fällig / überfällig / dringend (6h)
// ─────────────────────────────────────────────────────────────────────────────

// ── Reminder (Hinweisen vor Frist oder relativ) ──
const List<String> _reminderTitleBro = ['🔥 Yo, nicht vergessen!', '🔥 Reminder, Bro!'];
const List<String> _reminderTitleVorname = ['📌 Erinnerung', '📌 Kleine Erinnerung'];
const List<String> _reminderTitleFamilie = ['📌 Eine Erinnerung für Sie', '📌 Freundliche Erinnerung'];

const List<String> _reminderBodyBro = [
  '"{task}" steht an, Bro — kümmer dich drum!',
  '"{task}" wartet auf dich, Bro!',
];
const List<String> _reminderBodyVorname = [
  '{name}, "{task}" steht bald an.',
  '"{task}" steht bald an.',
];
const List<String> _reminderBodyFamilie = [
  '{name}, "{task}" steht bald an.',
  'Für Sie steht "{task}" bald an, {name}.',
];

// ── Heute fällig ──
const List<String> _dueTodayTitleBro = ['⏰ Heute ist der Tag, Bro', '⏰ Showtime, Bro!'];
const List<String> _dueTodayTitleVorname = ['⏰ Heute fällig', '⏰ Heute dran'];
const List<String> _dueTodayTitleFamilie = ['⏰ Fällig am heutigen Tag', '⏰ Heute zu erledigen'];

const List<String> _dueTodayBodyBro = [
  '"{task}" ist heute fällig — ran an die Sache!',
  '"{task}" muss heute laufen, Bro!',
];
const List<String> _dueTodayBodyVorname = [
  '{name}, denk daran: "{task}" ist heute fällig.',
  '"{task}" ist heute fällig.',
];
const List<String> _dueTodayBodyFamilie = [
  'Zur Erinnerung, {name}: "{task}" ist heute fällig.',
  '"{task}" ist heute fällig, {name}.',
];

// ── Überfällig ──
const List<String> _overdueTitleBro = ['🚨 Läuft schon, Bro!', '🚨 Achtung, überfällig!'];
const List<String> _overdueTitleVorname = ['🚨 Überfällig', '🚨 Aufgepasst, überfällig'];
const List<String> _overdueTitleFamilie = ['🚨 Frist bereits verstrichen', '🚨 Bitte um Beachtung'];

const List<String> _overdueBodyBro = [
  '"{task}" ist überfällig — schieb das nicht weiter auf!',
  '"{task}" hängt schon überfällig rum, Bro!',
];
const List<String> _overdueBodyVorname = [
  '{name}, Achtung: "{task}" ist bereits überfällig.',
  '"{task}" ist bereits überfällig.',
];
const List<String> _overdueBodyFamilie = [
  'Bitte beachten Sie, {name}: "{task}" ist überfällig.',
  '"{task}" ist leider bereits überfällig, {name}.',
];

// ── Dringend, wiederkehrend alle 6h ──
const List<String> _urgentTitleBro = ['🚨 Immer noch offen, Bro!', '🚨 Dringend — geht das heute noch?'];
const List<String> _urgentTitleVorname = ['🚨 Weiterhin dringend', '🚨 Noch offen'];
const List<String> _urgentTitleFamilie = ['🚨 Weiterhin als dringend markiert', '🚨 Bitte um zeitnahe Erledigung'];

const List<String> _urgentBodyBro = [
  '"{task}" steht immer noch an, Bro — Zeit, das zu erledigen!',
  '"{task}" wartet weiterhin auf dich.',
];
const List<String> _urgentBodyVorname = [
  '{name}, "{task}" ist weiterhin als dringend markiert.',
  '"{task}" steht noch offen und ist dringend.',
];
const List<String> _urgentBodyFamilie = [
  '"{task}" ist weiterhin als dringend markiert, {name}.',
  'Bitte beachten Sie, {name}, dass "{task}" weiterhin dringend ist.',
];

List<String> taskReminderTitle(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _reminderTitleBro,
  RelationshipStyle.vorname => _reminderTitleVorname,
  RelationshipStyle.familie => _reminderTitleFamilie,
};
List<String> taskReminderBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _reminderBodyBro,
  RelationshipStyle.vorname => _reminderBodyVorname,
  RelationshipStyle.familie => _reminderBodyFamilie,
};

List<String> taskDueTodayTitle(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _dueTodayTitleBro,
  RelationshipStyle.vorname => _dueTodayTitleVorname,
  RelationshipStyle.familie => _dueTodayTitleFamilie,
};
List<String> taskDueTodayBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _dueTodayBodyBro,
  RelationshipStyle.vorname => _dueTodayBodyVorname,
  RelationshipStyle.familie => _dueTodayBodyFamilie,
};

List<String> taskOverdueTitle(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _overdueTitleBro,
  RelationshipStyle.vorname => _overdueTitleVorname,
  RelationshipStyle.familie => _overdueTitleFamilie,
};
List<String> taskOverdueBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _overdueBodyBro,
  RelationshipStyle.vorname => _overdueBodyVorname,
  RelationshipStyle.familie => _overdueBodyFamilie,
};

List<String> taskUrgentRecurringTitle(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _urgentTitleBro,
  RelationshipStyle.vorname => _urgentTitleVorname,
  RelationshipStyle.familie => _urgentTitleFamilie,
};
List<String> taskUrgentRecurringBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro => _urgentBodyBro,
  RelationshipStyle.vorname => _urgentBodyVorname,
  RelationshipStyle.familie => _urgentBodyFamilie,
};