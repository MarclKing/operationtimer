import 'package:flutter/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SWIPE-TO-POSITION ANIMATION MIXIN
//
// Vorher: 4 Stellen (_FahrtCardState in fahrtenbuch_screen.dart,
// _DayCardState und _SlidableRowState in schedule_screen.dart / month_screen.dart,
// _DraftBannerState in fahrtenbuch_screen.dart) hatten je eine eigene
// _animateTo()-Methode, die den Swipe-Offset per Future.delayed(12ms)-Schleife
// "animierte":
//
//   void _animateTo(double target) {
//     final start = _swipeOffset;
//     final dist = target - start;
//     int step = 0;
//     const steps = 12;
//     Future.doWhile(() async {
//       await Future.delayed(const Duration(milliseconds: 12));
//       step++;
//       final t = step / steps;
//       final eased = 1 - (1 - t) * (1 - t);
//       setState(() => _swipeOffset = start + dist * eased);
//       if (step >= steps) { setState(() => _swipeOffset = target); return false; }
//       return true;
//     });
//   }
//
// Probleme damit:
//   1. Future.delayed ist NICHT an den Vsync/Render-Takt der Engine gekoppelt
//      → auf langsameren Geräten oder bei Last können Frames "ruckeln"
//        (Jank), weil die Timer ungenau feuern und mit dem eigentlichen
//        Frame-Rendering nicht synchronisiert sind.
//   2. Jeder Schritt löst ein volles setState() + Rebuild aus (12x pro
//      Animation) statt die Animation über addListener() an genau einen
//      Rebuild-Zyklus pro tatsächlichem Frame zu koppeln.
//   3. Es gibt keine Möglichkeit, die Animation sauber abzubrechen/zu
//      ersetzen, wenn während des Laufens ein neuer Zielwert kommt (z. B.
//      schnelles Hin-und-Her-Wischen) — Future.doWhile läuft stur weiter.
//
// Mit einem echten AnimationController:
//   - Animationen sind an SchedulerBinding/Vsync gekoppelt → ruckelfrei.
//   - .animateTo() bricht eine laufende Animation sauber ab und ersetzt sie.
//   - Curve wird deklarativ angegeben statt von Hand "eased" berechnet.
//
// VERWENDUNG (ersetzt die bisherige private _animateTo-Methode 1:1):
//
//   class _FahrtCardState extends State<_FahrtCard>
//       with SingleTickerProviderStateMixin, SwipeAnimationMixin {
//
//     @override
//     void initState() {
//       super.initState();
//       initSwipeAnimation(vsync: this); // statt eigenem AnimationController
//     }
//
//     @override
//     void dispose() {
//       disposeSwipeAnimation();
//       super.dispose();
//     }
//
//     // Statt `setState(() => _swipeOffset = ...)` liest man jetzt einfach
//     // `swipeOffset` direkt im build() — der Mixin ruft bei jedem Tick
//     // automatisch setState auf.
//
//     void _onPanEnd(DragEndDetails d) {
//       if (shouldSnapOpen) {
//         animateSwipeTo(-_rightRevealWidth);
//       } else {
//         animateSwipeTo(0);
//       }
//     }
//   }
//
// Für Widgets, die schon eine eigene `vsync`-Quelle/einen eigenen
// AnimationController für etwas anderes haben (z. B. den Lösch-Animations-
// controller in _FahrtCardState), kann man `initSwipeAnimation` einfach mit
// demselben `TickerProvider` aufrufen (SingleTickerProviderStateMixin reicht
// dafür nicht mehr aus — dann braucht es TickerProviderStateMixin, da pro
// AnimationController ein eigener Ticker nötig ist).
// ─────────────────────────────────────────────────────────────────────────────

mixin SwipeAnimationMixin<T extends StatefulWidget> on State<T> {
  late AnimationController _swipeController;
  late Animation<double> _swipeAnimation;
  double _swipeTarget = 0;

  /// Aktueller Swipe-Offset in Pixeln. Während eines aktiven Drags wird
  /// dieser Wert direkt von außen über [setSwipeOffsetImmediate] gesetzt;
  /// während einer Animation (z. B. nach Loslassen) liefert er den
  /// interpolierten Wert des Controllers.
  double get swipeOffset => _isAnimating ? _swipeAnimation.value : _swipeTarget;

  bool _isAnimating = false;

  /// Muss in initState() aufgerufen werden, bevor [swipeOffset] gelesen wird.
  /// [duration] entspricht standardmäßig in etwa der Laufzeit der alten
  /// 12-Schritte-Animation (12 Schritte × 12ms ≈ 144ms), leicht aufgerundet
  /// für ein etwas weicheres Gefühl.
  void initSwipeAnimation({
    required TickerProvider vsync,
    Duration duration = const Duration(milliseconds: 180),
    Curve curve = Curves.easeOutCubic,
  }) {
    _swipeController = AnimationController(vsync: vsync, duration: duration);
    _swipeAnimation = CurvedAnimation(parent: _swipeController, curve: curve);
    _swipeController.addListener(() {
      if (mounted) setState(() {});
    });
  }

  /// Muss in dispose() aufgerufen werden.
  void disposeSwipeAnimation() {
    _swipeController.dispose();
  }

  /// Setzt den Offset sofort ohne Animation — für die direkte
  /// onPanUpdate-Verfolgung des Fingers während eines aktiven Drags.
  void setSwipeOffsetImmediate(double value) {
    _isAnimating = false;
    setState(() => _swipeTarget = value);
  }

  /// Animiert geschmeidig vom aktuellen Offset zu [target], z. B. beim
  /// Einrasten nach Loslassen ("snap to open/closed").
  Future<void> animateSwipeTo(double target) async {
    final start = swipeOffset;
    _swipeTarget = target;
    _swipeAnimation = Tween<double>(begin: start, end: target).animate(
      CurvedAnimation(parent: _swipeController, curve: Curves.easeOutCubic),
    );
    _isAnimating = true;
    await _swipeController.forward(from: 0);
    _isAnimating = false;
    if (mounted) setState(() => _swipeTarget = target);
  }
}