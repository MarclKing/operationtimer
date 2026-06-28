import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../main.dart' show MyApp;

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SNACK BAR
//
// Rendert IMMER über einen globalen Overlay (MyApp.navigatorKey), unabhängig
// davon ob aktuell ein Sheet/Dialog offen ist. Das löst das Problem, dass
// ScaffoldMessenger-basierte Snackbars hinter offenen BottomSheets verschwinden.
//
// Verwendung bleibt unverändert:
//   showGlassSnackBar(context, 'Eintrag gespeichert', type: GlassSnackBarType.success);
// ─────────────────────────────────────────────────────────────────────────────

enum GlassSnackBarType { success, error, warning, info, loading }

OverlayEntry? _activeSnackEntry;
Timer? _activeSnackTimer;

void showGlassSnackBar(
  BuildContext context,
  String message, {
  GlassSnackBarType type = GlassSnackBarType.info,
  Duration duration = const Duration(milliseconds: 2500),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  final overlayState = MyApp.navigatorKey.currentState?.overlay;
  if (overlayState == null) return;

  final skin = AppTheme.of(context);

  // Vorherige Snackbar sofort entfernen, damit sie nicht überlappen.
  _activeSnackTimer?.cancel();
  _activeSnackEntry?.remove();
  _activeSnackEntry = null;

  final Color color = switch (type) {
    GlassSnackBarType.success => skin.statComplete,
    GlassSnackBarType.error => skin.deleteColor,
    GlassSnackBarType.warning => const Color(0xFFFFB347),
    GlassSnackBarType.info => skin.primary,
    GlassSnackBarType.loading => skin.textMuted,
  };

  final bgColor = skin.isLight
      ? Colors.white.withValues(alpha: 0.92)
      : const Color(0xFF14161D).withValues(alpha: 0.95);

  final borderColor = color.withValues(alpha: skin.isLight ? 0.35 : 0.30);

  void remove() {
    _activeSnackTimer?.cancel();
    _activeSnackEntry?.remove();
    _activeSnackEntry = null;
  }

  final entry = OverlayEntry(
    builder: (ctx) => _GlassSnackOverlay(
      message: message,
      color: color,
      bgColor: bgColor,
      borderColor: borderColor,
      isLoading: type == GlassSnackBarType.loading,
      textColor: skin.isLight ? skin.textPrimary : Colors.white,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              remove();
              onAction();
            },
    ),
  );

  _activeSnackEntry = entry;
  overlayState.insert(entry);

  final effectiveDuration =
      type == GlassSnackBarType.loading ? const Duration(seconds: 30) : duration;
  _activeSnackTimer = Timer(effectiveDuration, remove);
}

// Shortcut zum Ausblenden – z.B. nach PDF-Erstellung
void hideGlassSnackBar(BuildContext context) {
  _activeSnackTimer?.cancel();
  _activeSnackEntry?.remove();
  _activeSnackEntry = null;
}

class _GlassSnackOverlay extends StatefulWidget {
  final String message;
  final Color color;
  final Color bgColor;
  final Color borderColor;
  final Color textColor;
  final bool isLoading;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GlassSnackOverlay({
    required this.message,
    required this.color,
    required this.bgColor,
    required this.borderColor,
    required this.textColor,
    required this.isLoading,
    this.actionLabel,
    this.onAction,
  });

  @override
  State<_GlassSnackOverlay> createState() => _GlassSnackOverlayState();
}

class _GlassSnackOverlayState extends State<_GlassSnackOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPad + 100,
      child: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, child) => Opacity(
            opacity: _ctrl.value,
            child: Transform.translate(
              offset: Offset(0, 12 * (1 - _ctrl.value)),
              child: child,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: widget.bgColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: widget.borderColor, width: 1.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (widget.isLoading)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: widget.color),
                        )
                      else
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: widget.color,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: widget.color.withValues(alpha: 0.5),
                                  blurRadius: 6,
                                  spreadRadius: 1),
                            ],
                          ),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: TextStyle(
                            color: widget.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ),
                      if (widget.actionLabel != null && widget.onAction != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onAction,
                          child: Text(
                            widget.actionLabel!,
                            style: TextStyle(
                                color: widget.color, fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}