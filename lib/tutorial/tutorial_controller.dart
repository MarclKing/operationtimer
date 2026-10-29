import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../services/feature_flags.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TUTORIAL – Schritte, Keys und Ablaufsteuerung
//
// Neuen Schritt ergänzen:
//   1) Eintrag in TutorialStepId
//   2) GlobalKey in TutorialKeys + am Ziel-Widget setzen
//   3) Step in buildTutorialSteps()
//   4) Navigation in MainScreen._tutorialEnter / _tutorialLeave
//
// Start: TutorialController.instance.start(kind)            (manuell, z. B. Einstellungen)
//        TutorialTriggers.maybeStart(kind)                   (einmalig, automatisch)
// Im Text bedeutet **so** = hervorgehoben (fett + blau).
// ─────────────────────────────────────────────────────────────────────────────

class TutorialKeys {
  static final overlay = GlobalKey(debugLabel: 'tutorialOverlay');
  // Tutorial "Arbeitszeit"
  static final monthTabSwitcher = GlobalKey(debugLabel: 'tutMonthTabSwitcher');
  static final menuPanel = GlobalKey(debugLabel: 'tutMenuPanel');
  static final bvaItem = GlobalKey(debugLabel: 'tutBvaItem');
  // Tutorial "Dienstplan"
  static final dayCard = GlobalKey(debugLabel: 'tutDayCard');
  static final colleaguesBlock = GlobalKey(debugLabel: 'tutColleaguesBlock');
  static final planDemoTop = GlobalKey(debugLabel: 'tutPlanDemoTop');
  static final orgSwitcher = GlobalKey(debugLabel: 'tutOrgSwitcher');
  static final importItem = GlobalKey(debugLabel: 'tutImportItem');
  // Tutorial "Ereignis" / "Karte groß"
  static final eventLocation = GlobalKey(debugLabel: 'tutEventLocation');
  static final eventLocationRow = GlobalKey(debugLabel: 'tutEventLocationRow');
  static final eventMapExpand = GlobalKey(debugLabel: 'tutEventMapExpand');
  static final mapAdjust = GlobalKey(debugLabel: 'tutMapAdjust');
  static final mapFavorite = GlobalKey(debugLabel: 'tutMapFavorite');
  // Tutorial "Fahrtenbuch" / "Export"
  static final fahrtKennzeichen = GlobalKey(debugLabel: 'tutFahrtKz');
  static final fahrtKm = GlobalKey(debugLabel: 'tutFahrtKm');
  static final fahrtExportSel = GlobalKey(debugLabel: 'tutFahrtExportSel');
  static final exportGuideItem = GlobalKey(debugLabel: 'tutExportGuideItem');
}

enum TutorialKind { main, schedule, event, map, fahrtenbuch, export, all }

enum TutorialStepId {
  monthSwitcher,
  bvaMenu,
  scheduleDayCard,
  scheduleColleagues,
  scheduleImport,
  schedulePlan,
  eventLocation,
  eventMap,
  mapAdjust,
  mapFavorite,
  fahrtKennzeichen,
  fahrtKm,
  exportSelect,
  exportMenu,
}

class TutorialStep {
  final TutorialStepId id;
  final String title;
  final String body;

  /// Optionaler Zusatzhinweis (eigene Box mit Icon im selben Panel).
  final String? note;
  final IconData? noteIcon;

  /// Dieses Element wird freigestellt (Aussparung im Overlay).
  final GlobalKey target;

  /// Optional: Element, das zusätzlich mit einem Rahmen markiert wird.
  final GlobalKey? accent;

  /// Wartezeit nach der Navigation, bis das Ziel gemessen wird.
  final Duration settle;

  TutorialStep({
    required this.id,
    required this.title,
    required this.body,
    required this.target,
    this.note,
    this.noteIcon,
    this.accent,
    this.settle = const Duration(milliseconds: 250),
  });
}

List<TutorialStep> buildTutorialSteps([TutorialKind kind = TutorialKind.main]) {
  final readOnly = Hive.box('einstellungen')
      .get('read_only_mode', defaultValue: false) as bool;
  if (readOnly) return [];

  switch (kind) {
    case TutorialKind.main:
      return [
        TutorialStep(
          id: TutorialStepId.monthSwitcher,
          title: 'Arbeitszeit erfassen',
          body: 'Hier erfasst du deine Arbeitszeit. Mit dieser Leiste wechselst '
              'du zwischen der Zeiterfassung und der Monatsübersicht.',
          target: TutorialKeys.monthTabSwitcher,
        ),
        if (FeatureFlags.bvaEnabled)
          TutorialStep(
            id: TutorialStepId.bvaMenu,
            title: 'BVA-Dienstreise',
            body: 'Im Menü oben rechts kannst du ein Blanko-Dienstreiseformular '
                'erstellen. Das vereinfacht dir die Beantragung im Dienstrechner.',
            target: TutorialKeys.menuPanel,
            accent: TutorialKeys.bvaItem,
            settle: const Duration(milliseconds: 400),
          ),
      ];

    case TutorialKind.schedule:
      return [
        TutorialStep(
          id: TutorialStepId.scheduleDayCard,
          title: 'Dein Dienstplan',
          body: 'Halte einen Eintrag **gedrückt**, um die Notizen zu diesem Tag '
              'zu öffnen. Mit **Doppeltippen** kommst du zur Kollegen-Übersicht.',
          target: TutorialKeys.dayCard,
          settle: const Duration(milliseconds: 600),
        ),
        TutorialStep(
          id: TutorialStepId.scheduleColleagues,
          title: 'Kollegen-Übersicht',
          body: 'Nach dem Doppeltippen siehst du, **wer an diesem Tag** mit dir '
              'im Dienst ist. Über „Alle Kollegen“ findest du alle übrigen.',
          target: TutorialKeys.colleaguesBlock,
          settle: const Duration(milliseconds: 750),
        ),
        TutorialStep(
          id: TutorialStepId.scheduleImport,
          title: 'Dienstplan importieren',
          body: 'Im Menü oben rechts importierst du jederzeit einen neuen '
              '**Dienstplan** als PDF.',
          note: 'Du kannst eine **PDF** auch direkt aus einer anderen App '
              '(z. B. Mail oder Dateien) per **Teilen** an OpTimes senden. '
              'Der Dienstplan wird dann sofort importiert.',
          noteIcon: Icons.ios_share_rounded,
          target: TutorialKeys.menuPanel,
          accent: TutorialKeys.importItem,
          settle: const Duration(milliseconds: 450),
        ),
        TutorialStep(
          id: TutorialStepId.schedulePlan,
          title: 'Tagesplan',
          body: 'Hier kannst du deinen Tagesplan genau einbauen. Mit '
              '**Live Traffic** berechnet OpTimes die Fahrtzeit zwischen den '
              'Ereignissen automatisch.',
          target: TutorialKeys.planDemoTop,
          settle: const Duration(milliseconds: 500),
        ),
      ];

    case TutorialKind.event:
      return [
        TutorialStep(
          id: TutorialStepId.eventLocation,
          title: 'Ereignis anlegen',
          body: 'Hier trägst du **Ereignisse des Tages** ein und timest sie '
              '**genau**. Den Ort findest du per **Freitext-Suche**: einfach '
              'tippen und den Vorschlag antippen.',
          target: TutorialKeys.eventLocation,
          settle: const Duration(milliseconds: 1000),
        ),
        TutorialStep(
          id: TutorialStepId.eventMap,
          title: 'Karte öffnen',
          body: 'Mit dem **Karten-Symbol** rechts im Ortsfeld öffnest du die '
              'Karte im **Vollbild** und wählst den Ort direkt dort aus.',
          target: TutorialKeys.eventLocationRow,
          settle: const Duration(milliseconds: 700),
        ),
      ];

    case TutorialKind.map:
      return [
        TutorialStep(
          id: TutorialStepId.mapAdjust,
          title: 'Position anpassen',
          body: 'Mit diesem Symbol verschiebst du die Nadel und passt den Ort '
              '**exakt auf die gewünschte Koordinate** an.',
          target: TutorialKeys.mapAdjust,
          settle: const Duration(milliseconds: 1100),
        ),
        TutorialStep(
          id: TutorialStepId.mapFavorite,
          title: 'Favoriten',
          body: 'Mit dem Stern speicherst du **häufig genutzte, wiederkehrende '
              'Orte** als Favoriten. Bearbeiten kannst du sie im **Hauptmenü** '
              'unter **Favoriten** (im Dienstplan).',
          target: TutorialKeys.mapFavorite,
          settle: const Duration(milliseconds: 300),
        ),
      ];

    case TutorialKind.fahrtenbuch:
      return [
        TutorialStep(
          id: TutorialStepId.fahrtKennzeichen,
          title: 'Kennzeichen',
          body: 'Trage hier das **Kennzeichen** ein. **Häufig genutzte** werden '
              'vorne vorgeschlagen und der **KM-Stand** wird automatisch '
              'übernommen.',
          target: TutorialKeys.fahrtKennzeichen,
          settle: const Duration(milliseconds: 1000),
        ),
        TutorialStep(
          id: TutorialStepId.fahrtKm,
          title: 'Kilometerstand',
          body: 'Den KM-Stand übernimmst du per **Doppeltipp** aus dem '
              'Kennzeichen, trägst ihn **manuell** ein oder erfasst ihn per '
              '**Fotoerkennung** (Kamera-Symbol).',
          target: TutorialKeys.fahrtKm,
          settle: const Duration(milliseconds: 400),
        ),
      ];

    case TutorialKind.export:
      return [
        TutorialStep(
          id: TutorialStepId.exportSelect,
          title: 'Fahrten exportieren',
          body: 'Halte eine Fahrt **gedrückt**, um sie zu markieren. Unten erscheint '
              'die Leiste: Mit dem Haken setzt du sie auf **eingetragen**, mit dem '
              'Pfeil **exportierst** du alle markierten Fahrten.',
          target: TutorialKeys.fahrtExportSel,
          settle: const Duration(milliseconds: 800),
        ),
        TutorialStep(
          id: TutorialStepId.exportMenu,
          title: 'Exportanleitung',
          body: 'Im Menü oben rechts findest du die **Exportanleitung**: alles, '
              'was du für ein einfaches Setup zum Übertragen der Daten am '
              '**Dienstrechner** brauchst.',
          target: TutorialKeys.menuPanel,
          accent: TutorialKeys.exportGuideItem,
          settle: const Duration(milliseconds: 450),
        ),
      ];

    case TutorialKind.all:
      return [
        for (final k in const [
          TutorialKind.main,
          TutorialKind.schedule,
          TutorialKind.event,
          TutorialKind.map,
          TutorialKind.fahrtenbuch,
          TutorialKind.export,
        ])
          ...buildTutorialSteps(k),
      ];
  }
}

class TutorialController extends ChangeNotifier {
  TutorialController._();
  static final TutorialController instance = TutorialController._();

  /// Werden von MainScreen gesetzt (Seitenwechsel, Menü öffnen/schließen).
  Future<void> Function(TutorialStep step)? onEnterStep;
  Future<void> Function(TutorialStep step)? onLeaveStep;

  /// Wird am Ende (Beenden oder Fertig) einmal aufgerufen → aufräumen.
  VoidCallback? onFinished;

  List<TutorialStep> _steps = const [];
  bool _active = false;
  bool _busy = false;
  bool _hosted = false;
  int _token = 0;
  int _index = 0;
  TutorialStep? _shown;
  Rect? _hole;
  Rect? _accent;

  bool get active => _active;

  /// true = aus einem offenen Sheet/Screen heraus gestartet (Auto-Trigger):
  /// dort wird NICHT navigiert, und am Ende bleibt der alte Zustand erhalten.
  bool get hosted => _hosted;
  TutorialStep? get shown => _shown;
  Rect? get hole => _hole;
  Rect? get accent => _accent;
  int get index => _index;
  int get stepCount => _steps.length;
  bool get isLast => _index >= _steps.length - 1;

  /// false, wenn es nichts zu zeigen gibt (z. B. Lesemodus).
  Future<bool> start([TutorialKind kind = TutorialKind.main, bool hosted = false]) async {
    if (_active) return true;
    final steps = buildTutorialSteps(kind);
    if (steps.isEmpty || onEnterStep == null) return false;
    if (kind == TutorialKind.all) {
      // Komplette Tour gesehen → Einzel-Auto-Trigger nicht mehr nötig
      final b = Hive.box('einstellungen');
      for (final k in TutorialKind.values) {
        if (k != TutorialKind.all) b.put('tut_seen_${k.name}', true);
      }
    }
    _steps = steps;
    _hosted = hosted;
    _active = true;
    _index = 0;
    _shown = null;
    _hole = null;
    _accent = null;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 350));
    await _goTo(0);
    return true;
  }

  Future<void> next() async {
    if (!_active || _busy) return;
    if (isLast) {
      await stop();
      return;
    }
    await _goTo(_index + 1);
  }

  Future<void> stop() async {
    if (!_active) return;
    final shown = _shown;
    _active = false;
    _busy = false;
    _token++;
    _shown = null;
    _hole = null;
    _accent = null;
    notifyListeners();
    if (shown != null) await onLeaveStep?.call(shown);
    onFinished?.call();
    _hosted = false;
  }

  /// Beim Dispose von MainScreen – ohne notifyListeners.
  void detachHooks() {
    onEnterStep = null;
    onLeaveStep = null;
    onFinished = null;
    _active = false;
    _hosted = false;
    _token++;
  }

  bool _alive(int token) => _active && token == _token;

  Future<void> _goTo(int i) async {
    if (i >= _steps.length) {
      await stop();
      return;
    }
    final token = ++_token;
    _busy = true;

    final prev = _shown;
    if (prev != null) await onLeaveStep?.call(prev);
    if (!_alive(token)) return;

    final step = _steps[i];
    await onEnterStep?.call(step);
    if (!_alive(token)) return;
    await Future.delayed(step.settle);
    if (!_alive(token)) return;

    var hole = _measure(step.target);
    if (hole == null) {
      await Future.delayed(const Duration(milliseconds: 600));
      if (!_alive(token)) return;
      hole = _measure(step.target);
    }
    if (hole == null) {
      // Ziel nicht vorhanden → Schritt entfernen, damit der Zähler stimmt
      _steps = List<TutorialStep>.of(_steps)..removeAt(i);
      _busy = false;
      await _goTo(i);
      return;
    }
    _index = i;
    _shown = step;
    _hole = hole;
    _accent = step.accent == null ? null : _measure(step.accent!);
    _busy = false;
    notifyListeners();
  }

  /// Rect des Ziels in lokalen Koordinaten des Overlays.
  Rect? _measure(GlobalKey key) {
    final ro = key.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    final topLeft = ro.localToGlobal(Offset.zero);
    final base = (TutorialKeys.overlay.currentContext?.findRenderObject()
                as RenderBox?)
            ?.localToGlobal(Offset.zero) ??
        Offset.zero;
    return (topLeft - base) & ro.size;
  }
}
