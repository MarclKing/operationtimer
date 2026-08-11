import 'dart:math';
import '../models/relationship_style.dart';

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFICATION PHRASES — zentrales Phrasenbuch für ALLE Notification-Texte.
// ─────────────────────────────────────────────────────────────────────────────

final _rng = Random();

String pick(List<String> options, {String fallback = ''}) {
  if (options.isEmpty) return fallback;
  return options[_rng.nextInt(options.length)];
}

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
  kalt,
}

WeatherCategory categoryFor(int weatherCode, double tempC, {
  double coldThresholdC = 5.0,
  bool isDay = true,
}) {
  if (tempC <= coldThresholdC) return WeatherCategory.kalt;
  if (!isDay) {
    if (weatherCode == 0) return WeatherCategory.bedeckt;
    if (weatherCode <= 2) return WeatherCategory.wechselhaftBewoelkt;
    if (weatherCode == 3) return WeatherCategory.bedeckt;
    if (weatherCode <= 49) return WeatherCategory.nebel;
    if (weatherCode <= 59 || (weatherCode >= 80 && weatherCode <= 82)) return WeatherCategory.regenLeicht;
    if (weatherCode <= 69) return WeatherCategory.regenStark;
    if (weatherCode <= 86) return WeatherCategory.schnee;
    if (weatherCode <= 99) return WeatherCategory.gewitter;
    return WeatherCategory.bedeckt;
  }
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
  'Wakey wakey! 🌅',
  'Moin du Langschläfer! ☕',
  'Guten Morgen, Schlafmütze!',
  'Na, Frischling!',
  'Hallo Sonnenschein, rise & shine!',
  'Ey, Schnarchnase — der Tag ruft! 📣',
  'Die Tagwache ruft! 🫡',
];

const List<String> _greetingVorname = [
  'Guten Morgen, {name}!',
  'Schön, dass du da bist.',
  'Hey {name}, los geht\'s in den Tag.',
  'Guten Morgen ☀️',
  'Moin, {name}! ☕',
  'Guten Morgen, {name} — schön, dass du da bist.',
  'Hallo {name}, ein neuer Tag wartet. ☀️',
  'Hey {name}, guten Morgen!',
  'Rise & shine, {name}! 🌅',
];

const List<String> _greetingFamilie = [
  'Guten Morgen {name}.',
  'Einen guten Morgen, {name}.',
  'Ich hoffe, Sie haben gut geschlafen, {name}.',
  'Guten Morgen, {name} — schön, Sie zu sehen.',
  'Einen wunderschönen guten Morgen, {name}.',
  'Guten Morgen, {name}. Ich hoffe, der Start in den Tag gelingt gut.',
  'Guten Morgen ☀️',
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
// BAUSTEIN: SUBTITLE
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _subtitleBro = [
  'Bereit, die Welt zu retten?',
  'Auf geht\'s, reiß den Tag an dich!',
  'Lass den Laden brennen 🔥',
  'Zeit, Gas zu geben!',
  'Die Bundesrepublik braucht dich!',
  'Kann dein Land heute auf dich zählen?',
  'Dein Kommando zählt auf dich! 🫡',
  'Der Tag wartet nicht — du schon?',
  'Heute wird geliefert, nicht gejammert.',
  'Niemand rettet sich selbst — also los!',
  'Mach was draus, Bro. 💪',
  'Wo kein Schnee liegt, kann gelaufen werden!',
];

const List<String> _subtitleVorname = [
  'Hier ist dein Überblick für heute:',
  'Damit du gut vorbereitet bist:',
  'Ein kurzer Blick auf deinen Tag:',
  'Was heute auf dich zukommt:',
  'Dein Tag auf einen Blick:',
  'Hier ist alles Wichtige für heute:',
  'Gut vorbereitet in den Tag starten.',
];

const List<String> _subtitleFamilie = [
  'Hier ist Ihre Übersicht für den heutigen Tag:',
  'Darf ich Ihnen einen kurzen Überblick geben?',
  'Ihre Tagesübersicht im Folgenden:',
  'Ihr Tagesüberblick für heute, {name}:',
  'Alles Wichtige für Ihren heutigen Tag:',
  'Damit Sie bestens vorbereitet sind:',
  'Ein kurzer Blick auf Ihren heutigen Tag:',
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
// BAUSTEIN: DIENST-ZEILE
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _shiftBroWork = [
  'Heute steht {shift} für dich an.',
  'DU hast heute: {shift}.',
  'Heute hast du {shift}.',
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
  'Heute hast du frei — genieß es!',
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
  'Heute ist kein Dienstplan hinterlegt.',
];
const List<String> _shiftVornameUnknown = [
  'Für heute ist kein Dienst hinterlegt.',
];
const List<String> _shiftFamilieUnknown = [
  'Für den heutigen Tag liegt kein Dienst vor.',
];

List<String> shiftLine(RelationshipStyle style, {required bool hasShift, required bool isFree}) {
  if (!hasShift) {
    switch (style) {
      case RelationshipStyle.bro:     return _shiftBroUnknown;
      case RelationshipStyle.vorname: return _shiftVornameUnknown;
      case RelationshipStyle.familie: return _shiftFamilieUnknown;
    }
  }
  if (isFree) {
    switch (style) {
      case RelationshipStyle.bro:     return _shiftBroFree;
      case RelationshipStyle.vorname: return _shiftVornameFree;
      case RelationshipStyle.familie: return _shiftFamilieFree;
    }
  }
  switch (style) {
    case RelationshipStyle.bro:     return _shiftBroWork;
    case RelationshipStyle.vorname: return _shiftVornameWork;
    case RelationshipStyle.familie: return _shiftFamilieWork;
  }
}

/// Simpler, stilunabhängiger Dienst-Header für die Tagesvorschau.
/// Wird als Notification-TITEL genutzt — bewusst ohne Stil-Varianten.
String simpleShiftHeader({
  required bool hasShift,
  required bool isFree,
  String? shiftCode,
}) {
  if (!hasShift) return 'Für heute ist kein Dienst hinterlegt.';
  if (isFree) return 'Du hast heute frei.';
  return 'Du hast heute ${shiftCode ?? "Dienst"}.';
}

// ─────────────────────────────────────────────────────────────────────────────
// BAUSTEIN: WETTER-ZEILE
// ─────────────────────────────────────────────────────────────────────────────

const Map<WeatherCategory, List<String>> _weatherBro = {
  WeatherCategory.sonnig: [
    'Draußen warten sonnige {temp} — Sonnencreme nicht vergessen!',
    'Bombenwetter da draußen: {temp} und Sonne satt.',
    'Bei {temp} den Bikini nicht vergessen!',
  ],
  WeatherCategory.wechselhaftBewoelkt: [
    'Draußen ist es wechselhaft bei unentspannten {temp}.',
    'Mal Sonne, mal Wolken — {temp} draußen.',
  ],
  WeatherCategory.bedeckt: [
    'Draußen ist es bedeckt, {temp} - Sonnenbrille brauchst du wohl nicht.',
    'Grauer Himmel heute, {temp} sind angesagt.',
  ],
  WeatherCategory.nebel: [
    'Nebel draußen — {temp} und schlechte Sicht und Augen auf.',
  ],
  WeatherCategory.regenLeicht: [
    'Ein bisschen Regen heute, {temp} — Kapuze aufsetzen.',
  ],
  WeatherCategory.regenStark: [
    'Ordentlich Regen da draußen, {temp} — Schirm nicht vergessen!',
  ],
  WeatherCategory.schnee: [
    'Schnee ist angesagt, {temp} — warm anziehen!',
  ],
  WeatherCategory.gewitter: [
    'Gewitter im Anmarsch, {temp} draußen — pass auf dich auf!',
  ],
  WeatherCategory.kalt: [
    'Es fröstelt es ordentlich, {temp} — pack kugelsichere Socken ein!',
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
// BAUSTEIN: AUFGABEN-ZEILE
// ─────────────────────────────────────────────────────────────────────────────

const List<String> _taskOneOnlyBro = [
  '📌 Heute steht an: {task}.',
  '📌 Nicht vergessen, du Schnarchnase: {task}.',
];
const List<String> _taskOneOnlyVorname = [
  '📌 Heute steht an: {task}.',
  '📌 Denk daran: {task}.',
];
const List<String> _taskOneOnlyFamilie = [
  '📌 Für heute steht an: {task}.',
  '📌 Bitte denken Sie an: {task}.',
];

const List<String> _taskOnePlusFewBro = [
  '📌 Heute steht an: {task}. Die anderen Aufgaben erfüllen sich auch nicht  allein.',
];
const List<String> _taskOnePlusFewVorname = [
  '📌 Heute steht an: {task}. Schau auch mal bei den anderen Aufgaben vorbei.',
];
const List<String> _taskOnePlusFewFamilie = [
  '📌 Für heute steht an: {task}. Ein Blick auf die weiteren offenen Aufgaben lohnt sich ebenfalls.',
];

const List<String> _taskOnePlusManyBro = [
  '📌 Heute steht an: {task}. Da warten aber noch mehr Aufgaben auf dich.',
  '📌 {task} steht für heute an. Aber es gibt noch mehr zu tun.',
];
const List<String> _taskOnePlusManyVorname = [
  '📌 Heute steht an: {task}. Schau mal in die Aufgaben rein.',
];
const List<String> _taskOnePlusManyFamilie = [
  '📌 Für heute steht an: {task}. Bitte schauen Sie auch in Ihre Aufgaben.',
];

const List<String> _taskManyBro = [
  '📌 {count} Aufgaben fällig — ran an den Speck!',
  '📌 {count} Aufgaben heute — faulenzen gibt es nicht!',
];
const List<String> _taskManyVorname = [
  '📌 {count} Aufgaben heute fällig.',
  '📌 {count} Aufgaben warten heute.',
];
const List<String> _taskManyFamilie = [
  '📌 {count} Aufgaben stehen heute an.',
  '📌 Heute sind {count} Aufgaben fällig.',
];

const List<String> _taskNoneTodayButOpenBro = [
  '✅ Heute ist nichts fällig, aber der Rest mach sich auch nicht durch Nichtstun!',
  '✅ Heute keine Fristen, die anderen Aufgaben sind trotzdem nicht aus der Welt!',
  '✅ Heute ist nichts fällig, aber fürs nichtstun wirst du auch nicht bezahlt!',
];
const List<String> _taskNoneTodayButOpenVorname = [
  '✅ Heute ist nichts fällig, aber es sind noch Aufgaben offen — schau mal vorbei.',
];
const List<String> _taskNoneTodayButOpenFamilie = [
  '✅ Für heute liegt nichts an, es sind jedoch noch Aufgaben offen — ein Blick lohnt sich.',
];

List<String>? taskLine(
  RelationshipStyle style, {
  required int dueTodayCount,
  String? dueTodayTaskTitle,
  required int otherOpenCount,
}) {
  if (dueTodayCount == 1) {
    if (otherOpenCount == 0) {
      switch (style) {
        case RelationshipStyle.bro:     return _taskOneOnlyBro;
        case RelationshipStyle.vorname: return _taskOneOnlyVorname;
        case RelationshipStyle.familie: return _taskOneOnlyFamilie;
      }
    }
    if (otherOpenCount <= 2) {
      switch (style) {
        case RelationshipStyle.bro:     return _taskOnePlusFewBro;
        case RelationshipStyle.vorname: return _taskOnePlusFewVorname;
        case RelationshipStyle.familie: return _taskOnePlusFewFamilie;
      }
    }
    switch (style) {
      case RelationshipStyle.bro:     return _taskOnePlusManyBro;
      case RelationshipStyle.vorname: return _taskOnePlusManyVorname;
      case RelationshipStyle.familie: return _taskOnePlusManyFamilie;
    }
  }
  if (dueTodayCount > 1) {
    switch (style) {
      case RelationshipStyle.bro:     return _taskManyBro;
      case RelationshipStyle.vorname: return _taskManyVorname;
      case RelationshipStyle.familie: return _taskManyFamilie;
    }
  }
  if (otherOpenCount > 0) {
    switch (style) {
      case RelationshipStyle.bro:     return _taskNoneTodayButOpenBro;
      case RelationshipStyle.vorname: return _taskNoneTodayButOpenVorname;
      case RelationshipStyle.familie: return _taskNoneTodayButOpenFamilie;
    }
  }
  return null;
}

// ─────────────────────────────────────────────────────────────────────────────
// TASK-NOTIFICATIONS
//
// TITEL-KONVENTION (gilt für ALLE Stile):
//   Reminder / Heute fällig / Überfällig → 'Kurze Erinnerung 📌'
//   Dringend                              → 'Dringende Erinnerung 🚨'
//
// Nur der BODY variiert je nach Stil und Case.
// ─────────────────────────────────────────────────────────────────────────────

const String _reminderTitle = 'Kurze Erinnerung 📌';
const String _urgentTitle   = 'Dringende Erinnerung 🚨';

// ── Reminder Body ──────────────────────────────────────────────────────────

const List<String> _reminderBodyBro = [
  '"{task}" steht an — kümmer dich drum!',
  '"{task}" wartet auf dich!',
  'Hey Schnarchnase — hast du "{task}" noch auf\'m Schirm?',
  'Na Schlafmütze, "{task}" erledigt sich nicht von allein!',
  'Also ich kann "{task}" nicht für dich erledigen!',
  'Ey Frischling — "{task}" liegt noch an. Wird das heute was?',
  '"{task}" wartet schon ne Weile. Zeit wird\'s!',
  'Nicht vergessen, Sonnenschein: "{task}" steht noch aus.',
];
const List<String> _reminderBodyVorname = [
  '{name}, "{task}" steht bald an.',
  '"{task}" steht bald an.',
  'Denk daran, {name}: "{task}" wartet noch auf dich.',
  '"{task}" sollte bald erledigt sein, {name}.',
  'Noch nicht vergessen: "{task}" steht noch aus.',
  '{name}, hast du "{task}" noch auf dem Schirm?',
];
const List<String> _reminderBodyFamilie = [
  '{name}, "{task}" steht bald an.',
  'Für Sie steht "{task}" bald an, {name}.',
  'Bitte beachten Sie, {name}: "{task}" steht noch aus.',
  'Darf ich Sie daran erinnern, {name}: "{task}" ist noch offen.',
  '"{task}" steht in Kürze an, {name} — ich wollte kurz darauf hinweisen.',
  'Eine freundliche Erinnerung, {name}: "{task}" wartet noch auf Sie.',
];

// ── Heute fällig Body ──────────────────────────────────────────────────────

const List<String> _dueTodayBodyBro = [
  '"{task}" ist heute fällig — ran an die Sache!',
  '"{task}" muss heute laufen!',
  'Schnarchnase, heute ist Schluss mit Ausreden — "{task}" ist dran!',
  '"{task}" — fällig heute. Die Uhr tickt! ⏱️',
  'Ey Frischling, "{task}" ist heute dran. Nicht verbaseln!',
  '"{task}" wartet auf seinen großen Auftritt — heute ist der Tag!',
  'Na Schlafmütze, "{task}" erledigt sich nicht von allein!',
  'Wozu wirst du bezahlt, wenn du "{task}" nicht erledigst?',
];
const List<String> _dueTodayBodyVorname = [
  '{name}, denk daran: "{task}" ist heute fällig.',
  '"{task}" ist heute fällig.',
  'Heute ist der Tag für "{task}", {name}.',
  '"{task}" — heute fällig. Am besten gleich angehen!',
  '{name}, "{task}" ist heute dran — nicht vergessen!',
];
const List<String> _dueTodayBodyFamilie = [
  'Zur Erinnerung, {name}: "{task}" ist heute fällig.',
  '"{task}" ist heute fällig, {name}.',
  'Heute ist die Frist für "{task}", {name} — bitte nicht vergessen.',
  '"{task}" ist für den heutigen Tag vorgesehen, {name}.',
  'Bitte denken Sie daran, {name}: "{task}" steht heute an.',
];

// ── Überfällig Body ────────────────────────────────────────────────────────

const List<String> _overdueBodyBro = [
  '"{task}" ist überfällig — schieb das nicht weiter auf!',
  '"{task}" hängt schon überfällig rum!',
  '"{task}" ist durch die Frist gerutscht — wirds heute noch was?',
  'Schnarchnase, "{task}" ist überfällig. Die Uhr lief schon ab! ⏰',
  '"{task}" wartet schon länger als erlaubt. Jetzt aber!',
  'Ey Frischling — "{task}" hätte gestern fertig sein sollen. Go!',
  'Mach mal was für dein Geld, "{task}" muss gestern erledigt sein!',
];
const List<String> _overdueBodyVorname = [
  '{name}, Achtung: "{task}" ist bereits überfällig.',
  '"{task}" ist bereits überfällig.',
  '"{task}" hat seine Frist verpasst, {name} — bitte kümmere dich darum.',
  'Die Frist für "{task}" ist abgelaufen — jetzt aber, {name}!',
  '"{task}" wartet schon zu lange, {name}.',
];
const List<String> _overdueBodyFamilie = [
  'Bitte beachten Sie, {name}: "{task}" ist überfällig.',
  '"{task}" ist leider bereits überfällig, {name}.',
  'Die Frist für "{task}" ist verstrichen, {name} — bitte erledigen Sie dies zeitnah.',
  '"{task}" wartet bereits länger als geplant auf Sie, {name}.',
  'Darf ich darauf hinweisen, {name}: "{task}" ist überfällig.',
];

// ── Dringend Body ──────────────────────────────────────────────────────────

const List<String> _urgentBodyBro = [
  '"{task}" steht immer noch an — Zeit, das zu erledigen!',
  '"{task}" wartet weiterhin auf dich.',
  'Ey Schnarchnase — "{task}" ist immer noch dringend. Was ist los?',
  '"{task}" brennt noch, Bro. Wird das heute noch was? 🔥',
  'Frischling, "{task}" ist dringend — und wartet immer noch auf dich!',
  '"{task}" steht noch auf der Kippe — jetzt wäre ein guter Moment, Bro.',
];
const List<String> _urgentBodyVorname = [
  '{name}, "{task}" ist weiterhin als dringend markiert.',
  '"{task}" steht noch offen und ist dringend.',
  '"{task}" ist weiterhin offen — bitte nicht vergessen, {name}.',
  '{name}, "{task}" wartet immer noch — schieb das nicht weiter auf.',
  '"{task}" ist dringend und noch nicht erledigt, {name}.',
];
const List<String> _urgentBodyFamilie = [
  '"{task}" ist weiterhin als dringend markiert, {name}.',
  'Bitte beachten Sie, {name}, dass "{task}" weiterhin dringend ist.',
  '"{task}" steht weiterhin aus, {name} — eine zeitnahe Erledigung wäre wünschenswert.',
  'Darf ich Sie nochmals daran erinnern, {name}: "{task}" ist dringend und noch offen.',
  '"{task}" wartet weiterhin auf Ihre Aufmerksamkeit, {name}.',
];

// ── Getter: Titel (für alle Stile identisch) ──────────────────────────────

List<String> taskReminderTitle(RelationshipStyle style)        => [_reminderTitle];
List<String> taskDueTodayTitle(RelationshipStyle style)        => [_reminderTitle];
List<String> taskOverdueTitle(RelationshipStyle style)         => [_reminderTitle];
List<String> taskUrgentRecurringTitle(RelationshipStyle style) => [_urgentTitle];

// ── Getter: Body (stilabhängig) ───────────────────────────────────────────

List<String> taskReminderBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro     => _reminderBodyBro,
  RelationshipStyle.vorname => _reminderBodyVorname,
  RelationshipStyle.familie => _reminderBodyFamilie,
};

List<String> taskDueTodayBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro     => _dueTodayBodyBro,
  RelationshipStyle.vorname => _dueTodayBodyVorname,
  RelationshipStyle.familie => _dueTodayBodyFamilie,
};

List<String> taskOverdueBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro     => _overdueBodyBro,
  RelationshipStyle.vorname => _overdueBodyVorname,
  RelationshipStyle.familie => _overdueBodyFamilie,
};

List<String> taskUrgentRecurringBody(RelationshipStyle style) => switch (style) {
  RelationshipStyle.bro     => _urgentBodyBro,
  RelationshipStyle.vorname => _urgentBodyVorname,
  RelationshipStyle.familie => _urgentBodyFamilie,
};

// ─────────────────────────────────────────────────────────────────────────
// KALENDER-TERMIN — bewusst OHNE Stil-Varianten (neutral für alle
// RelationshipStyle), wie vereinbart. Eigener Baustein, damit die
// Formulierung ("beginnt um") sich klar von Aufgaben ("fällig") abhebt.
// ─────────────────────────────────────────────────────────────────────────

const String eventReminderTitle = 'Termin-Erinnerung 📅';

String eventReminderBody(String title, String timeLabel) =>
    'Termin "$title" beginnt um $timeLabel.';