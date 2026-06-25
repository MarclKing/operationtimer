import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

extension AppSkinGlass on AppSkin {
  double get glassBlur => isLight ? 18.0 : 22.0;
  double get glassOpacity => isLight ? 0.62 : 0.55;
  Color get glassHighlight =>
      isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12);
  Color get glassBorder =>
      isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16);
  Color get glassShadow => Colors.black.withValues(alpha: isLight ? 0.08 : 0.35);
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SURFACE
// ─────────────────────────────────────────────────────────────────────────────

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool useBlur;
  final bool highlighted;
  final Color? overrideColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.useBlur = true,
    this.highlighted = false,
    this.overrideColor,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final br = BorderRadius.circular(borderRadius);
    final baseColor = overrideColor ??
        (skin.isLight
            ? Colors.white.withValues(alpha: skin.glassOpacity)
            : skin.bgCard.withValues(alpha: skin.glassOpacity));

    final decoration = BoxDecoration(
      color: baseColor,
      borderRadius: br,
      border: Border.all(
        color: highlighted ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder,
        width: highlighted ? 1.5 : 1.0,
      ),
      boxShadow: [
        BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
        BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
      ],
    );

    final inner = Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: decoration,
      child: child,
    );

    if (!useBlur) return ClipRRect(borderRadius: br, child: inner);
    return ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: inner,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SHEET
// ─────────────────────────────────────────────────────────────────────────────

class GlassSheet extends StatelessWidget {
  final AppSkin skin;
  final Widget child;
  const GlassSheet({super.key, required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.82) : skin.bgSheet.withValues(alpha: 0.88),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: child,
        ),
      ),
    );
  }
}

typedef GlassBottomSheet = GlassSheet;

// ─────────────────────────────────────────────────────────────────────────────
// SHEET HANDLE
// ─────────────────────────────────────────────────────────────────────────────

class SheetHandle extends StatelessWidget {
  final AppSkin skin;
  const SheetHandle({super.key, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: 40,
      height: 4,
      decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS PRIMARY BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class GlassPrimaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool large;

  const GlassPrimaryButton({
    super.key,
    required this.skin,
    required this.label,
    required this.onTap,
    this.icon,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = skin.isLight ? skin.primary.withValues(alpha: 0.13) : skin.primary.withValues(alpha: 0.22);
    final borderColor = skin.isLight ? skin.primary.withValues(alpha: 0.28) : skin.primary.withValues(alpha: 0.45);
    final textColor = skin.isLight ? skin.primary.withValues(alpha: 0.90) : skin.primary.withValues(alpha: 0.85);
    final iconColor = skin.isLight ? skin.primary.withValues(alpha: 0.65) : skin.primary.withValues(alpha: 0.70);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: large ? 17 : 14, horizontal: 20),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(large ? 20 : 14),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6)),
            BoxShadow(color: skin.glassHighlight, blurRadius: 0, spreadRadius: -1, offset: const Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: iconColor, size: large ? 20 : 17),
              const SizedBox(width: 8),
            ],
            Text(label,
                style: TextStyle(
                    fontSize: large ? 16 : 15, fontWeight: FontWeight.w700, color: textColor, letterSpacing: 0.2)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SECONDARY BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class GlassSecondaryButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback onTap;
  const GlassSecondaryButton({super.key, required this.skin, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        decoration: BoxDecoration(
          color: skin.isLight ? Colors.white.withValues(alpha: 0.75) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: skin.glassBorder, width: 1.0),
          boxShadow: [BoxShadow(color: skin.glassShadow, blurRadius: 24, spreadRadius: 0, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
        ),
      ),
    );
  }
}

typedef GlassButton = GlassSecondaryButton;

// ─────────────────────────────────────────────────────────────────────────────
// GLASS ICON BADGE
// ─────────────────────────────────────────────────────────────────────────────

class GlassIconBadge extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final VoidCallback? onTap;
  const GlassIconBadge({super.key, required this.skin, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Icon(icon, size: 16, color: skin.surface(0.45)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS STAT CARD
// ─────────────────────────────────────────────────────────────────────────────

class GlassStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const GlassStatCard({super.key, required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Expanded(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: skin.isLight ? 0.10 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(fontSize: 11, color: skin.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

typedef StatCard = GlassStatCard;

// ─────────────────────────────────────────────────────────────────────────────
// FADING LIST VIEW
// ─────────────────────────────────────────────────────────────────────────────

class FadingListView extends StatelessWidget {
  final Widget child;
  final double fadeFromBottom;
  const FadingListView({super.key, required this.child, required this.fadeFromBottom});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) {
        final h = bounds.height;
        final startStop = ((h - (fadeFromBottom - 30)) / h).clamp(0.0, 1.0);
        final endStop = ((h - (fadeFromBottom - 70)) / h).clamp(0.0, 1.0);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Colors.white, Colors.white, Colors.black26, Colors.transparent, Colors.transparent],
          stops: [0.0, startStop, (startStop + endStop) / 2, endStop, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SEGMENTED CONTROL
// Ersetzt den alten manuellen Row-Segmented-Picker (z.B. "Erledigte Aufgaben")
// Verwendung:
//   GlassSegmentedControl<String>(
//     value: _taskAutoDelete,
//     items: [
//       GlassSegmentItem(value: 'never', label: 'Nie'),
//       GlassSegmentItem(value: '1d',    label: '1T'),
//       GlassSegmentItem(value: '2d',    label: '2T'),
//       GlassSegmentItem(value: '1w',    label: '1W'),
//       GlassSegmentItem(value: '1m',    label: '1M'),
//     ],
//     onChanged: (v) { setState(() => _taskAutoDelete = v); box.put('task_auto_delete', v); },
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassSegmentItem<T> {
  final T value;
  final String label;
  const GlassSegmentItem({required this.value, required this.label});
}

class GlassSegmentedControl<T> extends StatelessWidget {
  final T value;
  final List<GlassSegmentItem<T>> items;
  final ValueChanged<T> onChanged;

  const GlassSegmentedControl({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Row(
            children: items.map((item) {
              final isSelected = item.value == value;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onChanged(item.value);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (skin.isLight
                              ? Colors.white.withValues(alpha: 0.80)
                              : Colors.white.withValues(alpha: 0.14))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected ? Border.all(color: skin.glassBorder) : null,
                    ),
                    child: Center(
                      child: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? skin.primary : skin.surface(0.45),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS DROPDOWN — Apple-style Overlay Popup
// ─────────────────────────────────────────────────────────────────────────────

class GlassDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  const GlassDropdownItem({required this.value, required this.label, this.icon});
}

class GlassDropdownButton<T> extends StatefulWidget {
  final T value;
  final List<GlassDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? iconBg;
  final String Function(T) displayBuilder;
  final bool isLast;

  const GlassDropdownButton({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.label,
    required this.displayBuilder,
    this.subtitle,
    this.icon,
    this.iconBg,
    this.isLast = false,
  });

  @override
  State<GlassDropdownButton<T>> createState() => _GlassDropdownButtonState<T>();
}

class _GlassDropdownButtonState<T> extends State<GlassDropdownButton<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  final _triggerKey = GlobalKey();
  bool _open = false;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _removeOverlay();
    _animCtrl.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Future<void> _close() async {
    await _animCtrl.reverse();
    _removeOverlay();
    if (mounted) setState(() => _open = false);
  }

  void _openOverlay() {
    final box = _triggerKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context);
    final size = box.size;
    final offset = box.localToGlobal(Offset.zero);
    final screenHeight = MediaQuery.of(context).size.height;

    const popupMaxWidth = 260.0;
    const popupMinWidth = 160.0;

    final rightEdge = offset.dx + size.width;
double popupLeft = rightEdge - popupMaxWidth - 16; // ← -16 hier
if (popupLeft < 16) popupLeft = 16;

    double popupTop = offset.dy + size.height * 0.5 - 8;
    final estimatedHeight = widget.items.length * 48.0 + 16;
    if (popupTop + estimatedHeight > screenHeight - 32) {
      popupTop = screenHeight - estimatedHeight - 32;
    }
    if (popupTop < 60) popupTop = 60;

    _animCtrl.value = 0;
    setState(() => _open = true);

    _overlayEntry = OverlayEntry(
      builder: (_) => _DropdownOverlay<T>(
        animCtrl: _animCtrl,
        items: widget.items,
        currentValue: widget.value,
        left: popupLeft,
        top: popupTop,
        maxWidth: popupMaxWidth,
        minWidth: popupMinWidth,
        onSelect: (val) {
          HapticFeedback.selectionClick();
          widget.onChanged(val);
          _close();
        },
        onDismiss: _close,
      ),
    );

    overlay.insert(_overlayEntry!);
    _animCtrl.forward();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: _triggerKey,
          onTap: _toggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.iconBg ?? skin.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(widget.icon, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 14),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: skin.textPrimary,
                        ),
                      ),
                      if (widget.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.subtitle!,
                          style: TextStyle(fontSize: 12, color: skin.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                Text(
                  widget.displayBuilder(widget.value),
                  style: TextStyle(fontSize: 15, color: skin.textMuted),
                ),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _open ? 0.25 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: skin.surface(0.28),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!widget.isLast)
          Padding(
            padding: EdgeInsets.only(left: widget.icon != null ? 60.0 : 14.0),
            child: Divider(
              height: 0.5,
              color: skin.isLight
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.16),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OVERLAY POPUP — FIX: Material() wrapper verhindert gelbe Unterstreichungen
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownOverlay<T> extends StatefulWidget {
  final AnimationController animCtrl;
  final List<GlassDropdownItem<T>> items;
  final T currentValue;
  final double left;
  final double top;
  final double maxWidth;
  final double minWidth;
  final ValueChanged<T> onSelect;
  final VoidCallback onDismiss;

  const _DropdownOverlay({
    required this.animCtrl,
    required this.items,
    required this.currentValue,
    required this.left,
    required this.top,
    required this.maxWidth,
    required this.minWidth,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_DropdownOverlay<T>> createState() => _DropdownOverlayState<T>();
}

class _DropdownOverlayState<T> extends State<_DropdownOverlay<T>> {
  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    final scaleAnim = CurvedAnimation(
      parent: widget.animCtrl,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );
    final fadeAnim = CurvedAnimation(
      parent: widget.animCtrl,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    return Stack(
      children: [
        // Dismiss-Fläche
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),

        // Popup
        Positioned(
          left: widget.left,
          top: widget.top,
          child: AnimatedBuilder(
            animation: widget.animCtrl,
            builder: (_, child) => Transform.scale(
              scale: 0.88 + scaleAnim.value * 0.12,
              alignment: Alignment.topRight,
              child: Opacity(
                opacity: fadeAnim.value.clamp(0.0, 1.0),
                child: child,
              ),
            ),
            // ── FIX: Material() wrapper ──────────────────────────────────
            // Ohne Material-Ancestor zeigt Flutter alle Texte im Overlay
            // mit gelben Debug-Unterstreichungen (DefaultTextStyle-Fallback).
            child: Material(
              color: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: widget.minWidth,
                  maxWidth: widget.maxWidth,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                    child: Container(
                      decoration: BoxDecoration(
                        color: skin.isLight
                            ? Colors.white.withValues(alpha: 0.94)
                            : const Color(0xFF2A2A2E).withValues(alpha: 0.97),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: skin.isLight
                              ? Colors.white.withValues(alpha: 0.55)
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.28),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: widget.items.asMap().entries.map((entry) {
                          final i = entry.key;
                          final item = entry.value;
                          final isSelected = item.value == widget.currentValue;
                          final isLast = i == widget.items.length - 1;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () => widget.onSelect(item.value),
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 22,
                                        child: isSelected
                                            ? Icon(
                                                Icons.check_rounded,
                                                size: 16,
                                                color: skin.primary,
                                              )
                                            : null,
                                      ),
                                      if (item.icon != null) ...[
                                        Icon(
                                          item.icon,
                                          size: 16,
                                          color: isSelected
                                              ? skin.primary
                                              : skin.surface(0.45),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Text(
                                        item.label,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: isSelected
                                              ? skin.primary
                                              : skin.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isLast)
                                Container(
                                  height: 0.4,
                                  margin: const EdgeInsets.only(left: 38),
                                  color: skin.isLight
                                      ? Colors.black.withValues(alpha: 0.08)
                                      : Colors.white.withValues(alpha: 0.08),
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}