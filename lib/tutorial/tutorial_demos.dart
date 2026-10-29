import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/location_info.dart';
import 'tutorial_controller.dart';

/// Einmalige, automatische Auslösung der Tutorials (Flag je Tutorial in Hive).
class TutorialTriggers {
  TutorialTriggers._();

  static Box get _box => Hive.box('einstellungen');
  static String _k(TutorialKind k) => 'tut_seen_${k.name}';

  static bool seen(TutorialKind k) => _box.get(_k(k), defaultValue: false) as bool;

  /// Startet das Tutorial genau einmal pro Installation. Läuft gerade eines,
  /// oder ist Lesemodus aktiv, passiert nichts (Flag bleibt dann ungesetzt).
  static void maybeStart(TutorialKind kind,
      {Duration delay = const Duration(milliseconds: 800)}) {
    if (seen(kind)) return;
    final c = TutorialController.instance;
    if (c.active) return;
    if (buildTutorialSteps(kind).isEmpty) return;
    _box.put(_k(kind), true);
    Future.delayed(delay, () {
      if (!c.active) c.start(kind, true);
    });
  }
}

/// Gemeinsame Demo-Daten/-Widgets für die Tutorials.
class TutorialDemo {
  /// Ereignis-Tutorial: 0 = Tipp-Animation + Vorschlag, 2 = leeres Feld, Karten-Symbol pulsiert
  static final ValueNotifier<int> eventStage = ValueNotifier<int>(0);

  static const String bundestagLine = 'Platz der Republik 1, 11011 Berlin';

  static LocationInfo bundestag() => LocationInfo(
        rawInput: bundestagLine,
        name: 'Deutscher Bundestag',
        street: 'Platz der Republik 1',
        postalCode: '11011',
        city: 'Berlin',
        lat: 52.5186,
        lng: 13.3762,
      );
}

/// Lässt das Kind im Loop größer und kleiner werden.
class TutorialPulse extends StatefulWidget {
  final Widget child;
  final bool active;
  final double maxScale;
  const TutorialPulse({
    super.key,
    required this.child,
    this.active = true,
    this.maxScale = 1.35,
  });

  @override
  State<TutorialPulse> createState() => _TutorialPulseState();
}

class _TutorialPulseState extends State<TutorialPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant TutorialPulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _c
        ..value = 0
        ..repeat(reverse: true);
    } else if (!widget.active && oldWidget.active) {
      _c
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.scale(
        scale: 1 + (widget.maxScale - 1) * Curves.easeInOut.transform(_c.value),
        child: child,
      ),
      child: widget.child,
    );
  }
}
