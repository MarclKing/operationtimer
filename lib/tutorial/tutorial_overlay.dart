import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'tutorial_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TUTORIAL-OVERLAY
// Weißes Panel mit Aussparung für das erklärte Element + Text.
// Liegt das Element oben/mittig → Panel oben (Text darunter, Navigation im Panel).
// Liegt es unten → Panel unten (Text darüber, Aussparung, Navigation darunter).
// Das X sitzt immer oben rechts im weißen Panel.
// ─────────────────────────────────────────────────────────────────────────────

const Color _kPanel = Colors.white;
const Color _kInk = Color(0xFF1B1D24);
const Color _kInkSoft = Color(0xFF4A4F5C);
const double _kHolePad = 6;
const Duration _kMove = Duration(milliseconds: 380);

class TutorialOverlay extends StatelessWidget {
  const TutorialOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final c = TutorialController.instance;
    return KeyedSubtree(
      key: TutorialKeys.overlay,
      child: ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          if (!c.active) return const SizedBox.shrink();
          final step = c.shown;
          final hole = c.hole;
          if (step == null || hole == null) {
            return const AbsorbPointer(child: SizedBox.expand());
          }
          return _TutorialLayer(controller: c, step: step);
        },
      ),
    );
  }
}

class _TutorialLayer extends StatelessWidget {
  final TutorialController controller;
  final TutorialStep step;
  const _TutorialLayer({required this.controller, required this.step});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final skin = AppTheme.of(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    final target = c.hole!.inflate(_kHolePad);
    final accent = c.accent?.inflate(3);
    final bottomMode = (screenH - target.bottom) < 300 && target.top > 230;
    // genug Platz unter der Aussparung für Indikator + Pfeil?
    final navBelow = (screenH - target.bottom) >= 96 + bottomPad;

    void next() {
      HapticFeedback.selectionClick();
      c.next();
    }

    void stop() {
      HapticFeedback.selectionClick();
      c.stop();
    }

    final navRow = _NavRow(c: c, skin: skin, onNext: next);

    return Material(
      type: MaterialType.transparency,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        builder: (context, fade, child) =>
            Opacity(opacity: fade, child: child),
        child: TweenAnimationBuilder<Rect?>(
          tween: RectTween(end: target),
          duration: _kMove,
          curve: Curves.easeInOutCubic,
          builder: (context, animated, _) {
            final hole = animated ?? target;
            final ring = accent ?? target;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Abdunkelung (mit Aussparung)
                Positioned.fill(
                  child: ClipPath(
                    clipper: _CutoutClipper(hole: hole, panel: false),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.5)),
                    ),
                  ),
                ),

                // Tipps auf das freigestellte Element werden geschluckt
                Positioned.fromRect(
                  rect: hole,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                  ),
                ),

                if (!bottomMode)
                  // ── Panel oben ──
                  Align(
                    alignment: Alignment.topCenter,
                    child: ClipPath(
                      clipper: _CutoutClipper(hole: hole, panel: true),
                      child: Container(
                        width: double.infinity,
                        color: _kPanel,
                        child: Stack(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(height: hole.bottom + 22),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 28),
                                  child: _StepText(step: step),
                                ),
                                const SizedBox(height: 20),
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(28, 0, 20, 24),
                                  child: navRow,
                                ),
                              ],
                            ),
                            Positioned(
                              top: topPad + 6,
                              right: 10,
                              child: _CloseBtn(color: _kInk, onTap: stop),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else ...[
                  // ── Panel unten: Text über der Aussparung, X oben rechts im Panel ──
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: ClipPath(
                      clipper: _CutoutClipper(
                          hole: hole,
                          panel: true,
                          fromBottom: true,
                          screenH: screenH),
                      child: Container(
                        width: double.infinity,
                        color: _kPanel,
                        child: Stack(
                          children: [
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 48),
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 28),
                                  child: _StepText(step: step),
                                ),
                                const SizedBox(height: 18),
                                if (!navBelow) ...[
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(28, 0, 20, 0),
                                    child: navRow,
                                  ),
                                  const SizedBox(height: 18),
                                ],
                                SizedBox(height: (screenH - hole.top) + 18),
                              ],
                            ),
                            Positioned(
                              top: 8,
                              right: 10,
                              child: _CloseBtn(color: _kInk, onTap: stop),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Indikator links unten, Pfeil rechts unten (nur wenn Platz unter der Aussparung)
                  if (navBelow)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomPad + 14,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 0, 20, 0),
                        child: navRow,
                      ),
                    ),
                ],

                // Rahmen um ein Detail innerhalb der Aussparung (z. B. BVA)
                AnimatedPositioned(
                  duration: _kMove,
                  curve: Curves.easeInOutCubic,
                  left: ring.left,
                  top: ring.top,
                  width: ring.width,
                  height: ring.height,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: accent == null ? 0 : 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.primary, width: 2),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CloseBtn extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _CloseBtn({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(Icons.close_rounded, color: color, size: 28),
      ),
    );
  }
}

class _StepText extends StatelessWidget {
  final TutorialStep step;
  const _StepText({required this.step});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: Column(
        key: ValueKey(step.id),
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _kInk,
            ),
          ),
          const SizedBox(height: 10),
          _RichBody(text: step.body),
          if (step.note != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5FF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x332D6CFF)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0x1F2D6CFF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(step.noteIcon ?? Icons.info_outline_rounded,
                        size: 19, color: const Color(0xFF2D6CFF)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RichBody(
                        text: step.note!, align: TextAlign.left, size: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final TutorialController c;
  final AppSkin skin;
  final VoidCallback onNext;
  const _NavRow({required this.c, required this.skin, required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Row(
          children: List.generate(
            c.stepCount,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.only(right: 6),
              width: i == c.index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == c.index ? skin.primary : const Color(0xFFD5D8E0),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onNext,
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: skin.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              c.isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
              color: skin.onGradient,
              size: 26,
            ),
          ),
        ),
      ],
    );
  }
}

class _CutoutClipper extends CustomClipper<Path> {
  final Rect hole;
  final bool panel;
  final bool fromBottom;
  final double screenH;
  const _CutoutClipper({
    required this.hole,
    required this.panel,
    this.fromBottom = false,
    this.screenH = 0,
  });

  @override
  Path getClip(Size size) {
    final outer = Path();
    if (panel) {
      const r = Radius.circular(32);
      outer.addRRect(RRect.fromRectAndCorners(
        Offset.zero & size,
        topLeft: fromBottom ? r : Radius.zero,
        topRight: fromBottom ? r : Radius.zero,
        bottomLeft: fromBottom ? Radius.zero : r,
        bottomRight: fromBottom ? Radius.zero : r,
      ));
    } else {
      outer.addRect(Offset.zero & size);
    }
    // Panel unten: Overlay-Koordinaten → lokale Panel-Koordinaten
    final h = fromBottom ? hole.shift(Offset(0, -(screenH - size.height))) : hole;
    final rad = math.min(18.0, h.shortestSide / 2);
    final cut = Path()
      ..addRRect(RRect.fromRectAndRadius(h, Radius.circular(rad)));
    return Path.combine(PathOperation.difference, outer, cut);
  }

  @override
  bool shouldReclip(_CutoutClipper old) =>
      old.hole != hole ||
      old.panel != panel ||
      old.fromBottom != fromBottom ||
      old.screenH != screenH;
}

/// Text mit **hervorgehobenen** Teilen (fett + blau).
class _RichBody extends StatelessWidget {
  final String text;
  final TextAlign align;
  final double size;
  const _RichBody(
      {required this.text, this.align = TextAlign.center, this.size = 14.5});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(fontSize: size, height: 1.45, color: _kInkSoft);
    const accent =
        TextStyle(color: Color(0xFF2D6CFF), fontWeight: FontWeight.w800);
    final spans = <TextSpan>[];
    var last = 0;
    for (final m in RegExp(r'\*\*(.+?)\*\*').allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: accent));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      textAlign: align,
    );
  }
}
