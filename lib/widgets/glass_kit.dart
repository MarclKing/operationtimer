import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';
import 'swipe_animation_mixin.dart';

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

  /// Optionaler Override für die Border-Farbe — z. B. für Status-Indikatoren
  /// wie einen roten Rahmen bei offenen Bug-Reports (bug_admin_screen.dart).
  /// Hat Vorrang vor [highlighted].
  final Color? borderColor;

  /// Optionale Border-Breite, nur relevant zusammen mit [borderColor].
  /// Ohne [borderColor] gilt weiterhin die bestehende highlighted-Logik (1.0/1.5).
  final double? borderWidth;

  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding,
    this.useBlur = true,
    this.highlighted = false,
    this.overrideColor,
    this.borderColor,
    this.borderWidth,
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
        color: borderColor ?? (highlighted ? skin.primary.withValues(alpha: 0.45) : skin.glassBorder),
        width: borderWidth ?? (highlighted ? 1.5 : 1.0),
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
  final IconData? icon;
  final VoidCallback onTap;
  const GlassSecondaryButton({super.key, required this.skin, required this.label, required this.onTap, this.icon});

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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 17, color: skin.textPrimary),
              const SizedBox(width: 8),
            ],
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: skin.textPrimary)),
          ],
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

  /// Optional: maximale Höhe des Popups, ab der gescrollt wird.
  /// null (Standard) = altes Verhalten, keine Begrenzung, kein Scroll.
  final double? maxPopupHeight;

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
    this.maxPopupHeight,
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
    double popupLeft = rightEdge - popupMaxWidth - 16;
    if (popupLeft < 16) popupLeft = 16;

    double popupTop = offset.dy + size.height * 0.5 - 8;
    final rawHeight = widget.items.length * 48.0 + 16;
    final estimatedHeight = widget.maxPopupHeight != null
        ? (rawHeight < widget.maxPopupHeight! ? rawHeight : widget.maxPopupHeight!)
        : rawHeight;
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
        maxHeight: widget.maxPopupHeight,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: skin.textMuted),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    widget.displayBuilder(widget.value),
                    style: TextStyle(fontSize: 15, color: skin.textMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                  ),
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

class _DropdownOverlay<T> extends StatefulWidget {
  final AnimationController animCtrl;
  final List<GlassDropdownItem<T>> items;
  final T currentValue;
  final double left;
  final double top;
  final double maxWidth;
  final double minWidth;
  final double? maxHeight;
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
    this.maxHeight,
    required this.onSelect,
    required this.onDismiss,
  });

  @override
  State<_DropdownOverlay<T>> createState() => _DropdownOverlayState<T>();
}

class _DropdownOverlayState<T> extends State<_DropdownOverlay<T>> {
  Widget _buildItemsColumn(AppSkin skin) {
    return Column(
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
                  children: [
                    SizedBox(
                      width: 22,
                      child: isSelected
                          ? Icon(Icons.check_rounded, size: 16, color: skin.primary)
                          : null,
                    ),
                    if (item.icon != null) ...[
                      Icon(
                        item.icon,
                        size: 16,
                        color: isSelected ? skin.primary : skin.surface(0.45),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          color: isSelected ? skin.primary : skin.textPrimary,
                        ),
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
    );
  }

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
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
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
                      child: widget.maxHeight != null
                          ? ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: widget.maxHeight!),
                              child: SingleChildScrollView(
                                child: _buildItemsColumn(skin),
                              ),
                            )
                          : _buildItemsColumn(skin),
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

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SWIPE ACTION
//
// Beschreibt einen einzelnen Aktions-Button der beim Swipe seitlich erscheint.
// Wird als Liste an GlassSwipeCard.leftActions übergeben.
//
// Beispiel:
//   GlassSwipeAction(
//     icon: Icons.edit_outlined,
//     label: 'Bearb.',
//     color: skin.editColor,
//     onTap: () => _editEntry(entry),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassSwipeAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const GlassSwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS SWIPE CARD
//
// Einheitlicher Swipe-Container für alle Listen-Cards in der App.
// Ersetzt die duplizierten Swipe-Implementierungen in:
//   • _SlidableRow     (month_screen.dart)
//   • _FahrtCard       (fahrtenbuch_screen.dart)
//   • _DayCard         (schedule_screen.dart)
//
// Verhalten:
//   • Links-Wischen  → zeigt [leftActions] (Bearbeiten, Teilen, etc.)
//   • Rechts-Wischen → zeigt Löschen-Button (immer gleich: rot, Mülleimer)
//                      nur wenn [onDelete] nicht null ist
//   • Swipe-Animation läuft über SwipeAnimationMixin (kein Future.doWhile)
//   • Lösch-Animation: SlideOut → FadeOut → HeightCollapse
//
// [height]: Feste Kartenhöhe. null = automatisch (wrap_content).
// [leftRevealWidth]: Gesamtbreite des linken Reveal-Bereichs.
//   Wird automatisch durch Anzahl der Actions geteilt.
// [rightRevealWidth]: Breite des rechten Löschen-Buttons.
// [snapThreshold]: Ab wie vielen px einrasten.
// [externallyOpen]: Externaler Schlüssel; wenn != [cardKey], wird die Card
//   automatisch geschlossen (für "nur eine Card offen"-Logik).
// [cardKey]: Der Schlüssel dieser Card für [externallyOpen].
// [onCardSwiped]: Callback mit cardKey wenn geöffnet, null wenn geschlossen.
//
// Screen-spezifische Extras wie Long-Press-Glow (_DayCard) oder
// Auswahl-Overlay (_FahrtCard im SelectionMode) werden als [foregroundLayer]
// übergeben und über die Hauptkarte gelegt.
//
// Verwendung:
//
//   GlassSwipeCard(
//     height: 90,
//     cardKey: fahrt.id,
//     externallyOpen: _openSwipedFahrtId,
//     onCardSwiped: (key) => setState(() => _openSwipedFahrtId = key),
//     leftActions: [
//       GlassSwipeAction(
//         icon: Icons.edit_outlined,
//         label: 'Bearb.',
//         color: skin.editColor,
//         onTap: _editFahrt,
//       ),
//       GlassSwipeAction(
//         icon: Icons.ios_share_outlined,
//         label: 'Teilen',
//         color: skin.statComplete,
//         onTap: _shareFahrt,
//       ),
//     ],
//     onDelete: _deleteFahrt,
//     onDoubleTap: _editFahrt,
//     child: _FahrtCardContent(fahrt: fahrt),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassSwipeCard extends StatefulWidget {
  /// Der eigentliche Karteninhalt (Datum, Zeiten, etc.).
  final Widget child;

  /// Optionale Aktions-Buttons die links (beim Rechts-Wischen) erscheinen.
  /// Leer = kein Links-Wischen möglich.
  final List<GlassSwipeAction> leftActions;

  /// Callback für den rechten Löschen-Button.
  /// null = kein Rechts-Wischen / kein Löschen möglich.
  final VoidCallback? onDelete;

  /// Wenn true, wird beim onDelete-Tap zuerst die Lösch-Animation abgespielt
  /// (SlideOut + FadeOut + HeightCollapse), bevor [onDelete] aufgerufen wird.
  final bool animateDelete;

  /// Wird nach Abschluss der Lösch-Animation aufgerufen (nur bei animateDelete).
  /// Ideal für setState() + Listen-Update im Parent.
  final VoidCallback? onDeleteAnimationDone;

  /// Optionaler Double-Tap Handler auf die Hauptkarte.
  final VoidCallback? onDoubleTap;

  /// Optionaler Long-Press Handler.
  final VoidCallback? onLongPress;

  /// Optionaler Tap Handler (nur aktiv wenn die Card geschlossen ist).
  final VoidCallback? onTap;

  /// Feste Kartenhöhe in Pixeln. null = wrap_content.
  final double? height;

  /// Eindeutiger Schlüssel dieser Card für die "nur eine Card offen"-Logik.
  final String? cardKey;

  /// Externer offener Schlüssel. Wenn != [cardKey], wird diese Card
  /// automatisch geschlossen.
  final String? externallyOpen;

  /// Callback wenn die Card durch Wischen geöffnet/geschlossen wird.
  /// Parameter: cardKey wenn geöffnet, null wenn geschlossen.
  final void Function(String?)? onCardSwiped;

  /// Gesamtbreite des linken Reveal-Bereichs (wird durch Anzahl Actions geteilt).
  final double leftRevealWidth;

  /// Breite des rechten Löschen-Buttons.
  final double rightRevealWidth;

  /// Schwellwert in Pixeln ab dem die Card einrastet.
  final double snapThreshold;

  /// Optionaler Layer der über die Hauptkarte gerendert wird.
  /// Für screen-spezifische Extras wie Auswahl-Overlay oder Glow.
  final Widget? foregroundLayer;

  /// Wenn true, reagiert die Card nicht auf horizontale Drags.
  /// Nützlich für Selektion-Modus (z. B. _FahrtCard).
  final bool disableSwipe;

  const GlassSwipeCard({
    super.key,
    required this.child,
    this.leftActions = const [],
    this.onDelete,
    this.animateDelete = true,
    this.onDeleteAnimationDone,
    this.onDoubleTap,
    this.onLongPress,
    this.onTap,
    this.height,
    this.cardKey,
    this.externallyOpen,
    this.onCardSwiped,
    this.leftRevealWidth = 180.0,
    this.rightRevealWidth = 90.0,
    this.snapThreshold = 50.0,
    this.foregroundLayer,
    this.disableSwipe = false,
  });

  @override
  State<GlassSwipeCard> createState() => GlassSwipeCardState();
}

class GlassSwipeCardState extends State<GlassSwipeCard>
    with TickerProviderStateMixin, SwipeAnimationMixin {

  // ── Drag-Tracking ──────────────────────────────────────────────────────────
  bool _dragging = false;
  double _dragStartX = 0;
  double _dragStartY = 0;
  bool _isOpenLeft = false;
  bool _isOpenRight = false;

  // ── Lösch-Animation ────────────────────────────────────────────────────────
  late AnimationController _deleteCtrl;
  late Animation<double> _slideOutAnim;
  late Animation<double> _fadeOutAnim;
  late Animation<double> _heightCollapseAnim;

  @override
  void initState() {
    super.initState();
    initSwipeAnimation(vsync: this);

    _deleteCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _slideOutAnim = Tween<double>(begin: 0, end: -440).animate(
      CurvedAnimation(
        parent: _deleteCtrl,
        curve: const Interval(0.0, 0.6, curve: Curves.easeInBack),
      ),
    );
    _fadeOutAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _deleteCtrl,
        curve: const Interval(0.25, 0.7, curve: Curves.easeOut),
      ),
    );
    _heightCollapseAnim = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(
        parent: _deleteCtrl,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInOut),
      ),
    );

    _deleteCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    disposeSwipeAnimation();
    _deleteCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GlassSwipeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Extern geschlossen werden wenn eine andere Card geöffnet wird
    if (widget.externallyOpen != widget.cardKey && (_isOpenLeft || _isOpenRight)) {
      close();
    }
  }

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Schließt die Card animiert (ersetzt die alte sofortige Variante).
  Future<void> close() async {
    await animateSwipeTo(0);
    if (mounted) setState(() { _isOpenLeft = false; _isOpenRight = false; });
  }

  /// Spielt die Lösch-Animation ab und ruft danach [onDeleteAnimationDone] auf.
  Future<void> animateOutAndDelete(VoidCallback onDone) async {
    await _deleteCtrl.forward();
    onDone();
  }

  // ── Drag-Handler ────────────────────────────────────────────────────────────

  void _onPanStart(DragStartDetails d) {
    _dragging = false;
    _dragStartX = d.globalPosition.dx;
    _dragStartY = d.globalPosition.dy;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final totalDx = d.globalPosition.dx - _dragStartX;
    final totalDy = (d.globalPosition.dy - _dragStartY).abs();

    if (!_dragging) {
      if (totalDy > totalDx.abs()) return; // Vertikaler Scroll → ignorieren
      if (totalDx.abs() < 8) return;       // Todzone
      _dragging = true;
    }

    final hasLeft = widget.leftActions.isNotEmpty;
    final hasRight = widget.onDelete != null;

    final minOffset = hasRight ? -widget.rightRevealWidth : 0.0;
    final maxOffset = hasLeft ? widget.leftRevealWidth : 0.0;

    final newOffset = (swipeOffset + d.delta.dx).clamp(minOffset, maxOffset);
    setSwipeOffsetImmediate(newOffset);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;

    final v = d.primaryVelocity ?? d.velocity.pixelsPerSecond.dx;

    // Links aufgeklappt (positive Richtung = links-Bereich)
    if (widget.leftActions.isNotEmpty &&
        (swipeOffset > widget.snapThreshold || v > 400)) {
      animateSwipeTo(widget.leftRevealWidth);
      setState(() { _isOpenLeft = true; _isOpenRight = false; });
      widget.onCardSwiped?.call(widget.cardKey);
      return;
    }

    // Rechts aufgeklappt (negative Richtung = rechts/Löschen-Bereich)
    if (widget.onDelete != null &&
        (swipeOffset < -widget.snapThreshold || v < -400)) {
      animateSwipeTo(-widget.rightRevealWidth);
      setState(() { _isOpenRight = true; _isOpenLeft = false; });
      widget.onCardSwiped?.call(widget.cardKey);
      return;
    }

    // Zurück zur Mitte
    animateSwipeTo(0);
    setState(() { _isOpenLeft = false; _isOpenRight = false; });
    widget.onCardSwiped?.call(null);
  }

  // ── Delete-Handler ──────────────────────────────────────────────────────────

  void _handleDelete() {
  if (widget.animateDelete && widget.onDeleteAnimationDone != null) {
    // Parent hat explizit eine Animation-Done-Callback übergeben →
    // erst schließen, dann Lösch-Animation abspielen
    animateSwipeTo(0).then((_) {
      animateOutAndDelete(widget.onDeleteAnimationDone!);
    });
  } else {
    // Direkt löschen (Parent kümmert sich selbst um Animation)
    close();
    widget.onDelete?.call();
  }
}

  // ── Reveal-Progress ─────────────────────────────────────────────────────────

  double get _rightRevealProgress =>
      (swipeOffset < 0 ? swipeOffset.abs() / widget.rightRevealWidth : 0.0).clamp(0.0, 1.0);

  double get _leftRevealProgress =>
      (swipeOffset > 0 ? swipeOffset / widget.leftRevealWidth : 0.0).clamp(0.0, 1.0);

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    final cardContent = Stack(
      children: [
        widget.child,
        if (widget.foregroundLayer != null) widget.foregroundLayer!,
      ],
    );

    return AnimatedBuilder(
      animation: _deleteCtrl,
      builder: (context, child) => SizeTransition(
        sizeFactor: _heightCollapseAnim,
        axisAlignment: -1,
        child: Opacity(
          opacity: _fadeOutAnim.value,
          child: Transform.translate(
            offset: Offset(_slideOutAnim.value, 0),
            child: child,
          ),
        ),
      ),
      child: GestureDetector(
        onHorizontalDragStart: widget.disableSwipe ? null : _onPanStart,
        onHorizontalDragUpdate: widget.disableSwipe ? null : _onPanUpdate,
        onHorizontalDragEnd: widget.disableSwipe ? null : _onPanEnd,
        onTap: (_isOpenLeft || _isOpenRight)
            ? () {
                close();
                widget.onCardSwiped?.call(null);
              }
            : widget.onTap,
        onDoubleTap: widget.onDoubleTap,
        onLongPress: widget.onLongPress,
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [

                // ── Linker Reveal-Bereich (erscheint beim Rechts-Wischen) ──
                if (widget.leftActions.isNotEmpty && swipeOffset >= 0)
                  Positioned(
                    left: 0,
                    top: 4,
                    bottom: 4,
                    width: widget.leftRevealWidth,
                    child: Row(
                      children: widget.leftActions.asMap().entries.map((entry) {
                        final i = entry.key;
                        final action = entry.value;
                        final isLast = i == widget.leftActions.length - 1;
                        return Expanded(
                          child: Opacity(
                            opacity: _leftRevealProgress,
                            child: Transform.scale(
                              scale: _leftRevealProgress,
                              alignment: Alignment.centerRight,
                              child: GestureDetector(
  onTap: () {
  close();
  widget.onCardSwiped?.call(null);
  action.onTap();
},
  child: Builder(builder: (context) {
    final content = Container(
      margin: EdgeInsets.only(
        left: i == 0 ? 5 : 5,
        right: isLast ? 5 : 5,
      ),
      decoration: BoxDecoration(
        color: action.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: action.color.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(action.icon, color: action.color, size: 22),
          const SizedBox(height: 4),
          Text(
            action.label,
            style: TextStyle(
              color: action.color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: _leftRevealProgress > 0
          ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: content)
          : content,
    );
  }),
),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                // ── Rechter Reveal-Bereich (Löschen, erscheint beim Links-Wischen) ──
                if (widget.onDelete != null && swipeOffset <= 0)
  Positioned(
    right: 0, top: 4, bottom: 4, width: widget.rightRevealWidth,
    child: Opacity(
      opacity: _rightRevealProgress,
      child: Transform.scale(
        scale: _rightRevealProgress,
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _handleDelete,
          child: Builder(builder: (context) {
            final content = Container(
              margin: const EdgeInsets.only(left: 5),
              decoration: BoxDecoration(
                color: skin.deleteColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.delete_outline, color: skin.deleteColor, size: 22),
                  const SizedBox(height: 4),
                  Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ),
            );
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: _rightRevealProgress > 0
                  ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: content)
                  : content,
            );
          }),
        ),
      ),
    ),
  ),

                // ── Hauptkarte (verschoben mit Swipe-Offset) ──
                Transform.translate(
                  offset: Offset(widget.disableSwipe ? 0 : swipeOffset, 0),
                  child: cardContent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS NAV CARD
//
// Einheitliche Navigationsleiste mit Links/Rechts-Chevrons und zentriertem
// Inhalt. Ersetzt die duplizierten Datums- und Monats-Navigationsblöcke in:
//   • month_screen.dart  (_buildZeiterfassungTab  → Datumskarte)
//   • month_screen.dart  (_buildMonatsuebersichtTab → Monatskarte)
//   • fahrtenbuch_screen.dart (Monatsnavigation)
//   • schedule_screen.dart    (Monatsnavigation)
//
// Verwendung:
//   GlassNavCard(
//     onPrevious: () => _changeMonth(-1),
//     onNext:     () => _changeMonth(1),
//     onTap:      _showMonthPicker,
//     onDoubleTap: () => _setMonth(DateTime(now.year, now.month)),
//     highlighted: false,
//     child: Text(monthName, style: ...),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassNavCard extends StatelessWidget {
  /// Wird beim Tap auf den mittleren Bereich ausgelöst (z. B. Picker öffnen).
  final VoidCallback? onTap;

  /// Wird beim Doppeltap ausgelöst (z. B. zurück zu Heute/aktuellem Monat).
  final VoidCallback? onDoubleTap;

  /// Linker Chevron-Tap.
  final VoidCallback onPrevious;

  /// Rechter Chevron-Tap.
  final VoidCallback onNext;

  /// Wird beim horizontalen Wischen ausgelöst (positiv = rechts = zurück).
  final void Function(double velocity)? onSwipe;

  /// Wenn true, wird der Border in primary-Farbe dargestellt (z. B. "Heute").
  final bool highlighted;

  /// Der zentrierte Inhalt zwischen den Chevrons.
  final Widget child;

  /// Höhe der Card. Standard 52 passt für einzeiligen Text.
  final double height;

  const GlassNavCard({
    super.key,
    required this.onPrevious,
    required this.onNext,
    required this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSwipe,
    this.highlighted = false,
    this.height = 52,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final br = BorderRadius.circular(20);

    return GestureDetector(
      onHorizontalDragEnd: onSwipe == null
          ? null
          : (d) => onSwipe!(d.primaryVelocity ?? 0),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
              borderRadius: br,
              border: Border.all(
                color: highlighted
                    ? skin.primary.withValues(alpha: 0.45)
                    : skin.glassBorder,
                width: highlighted ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                    color: skin.glassShadow,
                    blurRadius: 24,
                    offset: const Offset(0, 6)),
                BoxShadow(
                    color: skin.glassHighlight,
                    blurRadius: 0,
                    spreadRadius: -1,
                    offset: const Offset(0, 1)),
              ],
            ),
            child: Row(
              children: [
                // Linker Chevron
                GestureDetector(
                  onTap: onPrevious,
                  child: SizedBox(
                    width: 44,
                    height: double.infinity,
                    child: Center(
                      child: Icon(
                        Icons.chevron_left,
                        size: 22,
                        color: skin.surface(0.5),
                      ),
                    ),
                  ),
                ),

                // Mittlerer Inhalt
                Expanded(
                  child: GestureDetector(
                    onTap: onTap,
                    onDoubleTap: onDoubleTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      height: double.infinity,
                      alignment: Alignment.center,
                      child: child,
                    ),
                  ),
                ),

                // Rechter Chevron
                GestureDetector(
                  onTap: onNext,
                  child: SizedBox(
                    width: 44,
                    height: double.infinity,
                    child: Center(
                      child: Icon(
                        Icons.chevron_right,
                        size: 22,
                        color: skin.surface(0.5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS INFO CARD
//
// Einheitliche Info/Hinweis-Karte mit Icon-Badge, Titel und Beschreibungstext.
// Ersetzt die 7 verschiedenen Inline-Varianten in dictation_help_screen.dart
// und die Hinweiskarten in export_hinweise_screen.dart.
//
// Verwendung:
//   GlassInfoCard(
//     icon: Icons.mic_outlined,
//     iconColor: skin.primary,
//     title: 'Diktiermodus',
//     description: 'Halte den Knopf gedrückt und sprich...',
//   )
//
//   // Mit onTap (z. B. aufklappbar oder navigierbar):
//   GlassInfoCard(
//     icon: Icons.warning_amber_outlined,
//     iconColor: skin.statOpen,
//     title: 'Hinweis',
//     description: 'Exportiere erst wenn alle Einträge vollständig sind.',
//     onTap: () => ...,
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassInfoCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;

  /// Optionale Hintergrundfarbe des Icon-Badge.
  /// Standard: iconColor mit alpha 0.12.
  final Color? iconBgColor;

  final String title;
  final String description;

  /// Optionaler Tap-Handler (z. B. für Navigation oder Aufklappen).
  final VoidCallback? onTap;

  /// Optionaler trailing Widget (z. B. Chevron, Badge, Switch).
  final Widget? trailing;

  /// Wenn true, wird kein BackdropFilter verwendet (Performance in langen Listen).
  final bool useBlur;

  const GlassInfoCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.iconColor,
    this.iconBgColor,
    this.onTap,
    this.trailing,
    this.useBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final color = iconColor ?? skin.primary;
    final bgColor = iconBgColor ?? color.withValues(alpha: 0.12);
    final br = BorderRadius.circular(16);

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: skin.isLight
            ? Colors.white.withValues(alpha: skin.glassOpacity)
            : skin.bgCard.withValues(alpha: skin.glassOpacity),
        borderRadius: br,
        border: Border.all(color: skin.glassBorder),
        boxShadow: [
          BoxShadow(
              color: skin.glassShadow,
              blurRadius: 16,
              offset: const Offset(0, 4)),
          BoxShadow(
              color: skin.glassHighlight,
              blurRadius: 0,
              spreadRadius: -1,
              offset: const Offset(0, 1)),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Badge
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 13),

          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: skin.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: skin.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),

          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    final clipped = ClipRRect(borderRadius: br, child: content);

    return GestureDetector(
      onTap: onTap,
      child: useBlur
          ? ClipRRect(
              borderRadius: br,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                    sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                child: content,
              ),
            )
          : clipped,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS LIST ITEM
//
// Einheitliche Zeilen-Darstellung für einfache Listen ohne Swipe-Aktionen.
// Ersetzt inline Container-Rows in speech_log_screen.dart und tasks_screen.dart.
//
// Für Swipe-Listen → GlassSwipeCard verwenden.
//
// Verwendung:
//   GlassListItem(
//     leading: Icon(Icons.mic, color: skin.primary),
//     title: 'Sprachnotiz vom 12.06.',
//     subtitle: '0:42 min',
//     trailing: Text('09:14', style: TextStyle(color: skin.textMuted)),
//     onTap: () => _playRecording(entry),
//   )
//
//   // Als letztes Element in einer Gruppe (kein Divider):
//   GlassListItem(..., isLast: true)
//
//   // Gruppe von Items in einer GlassSurface:
//   GlassSurface(
//     padding: EdgeInsets.zero,
//     child: Column(children: [
//       GlassListItem(title: 'Eintrag A', ...),
//       GlassListItem(title: 'Eintrag B', isLast: true, ...),
//     ]),
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassListItem extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool isLast;
  final EdgeInsetsGeometry padding;

  // ── Switch-Support ──────────────────────────────────────────────────────
  /// Wenn gesetzt, wird rechts ein Switch gerendert (trailing wird ignoriert).
  final bool? switchValue;
  final ValueChanged<bool>? onSwitchChanged;
  /// Switch-Farbe. Standard: skin.primary.
  final Color? switchActiveColor;

  const GlassListItem({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.isLast = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.switchValue,
    this.onSwitchChanged,
    this.switchActiveColor,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final activeColor = switchActiveColor ?? skin.primary;
    final hasSwitch = switchValue != null && onSwitchChanged != null;

    final rowContent = Padding(
      padding: padding,
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: skin.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: skin.textMuted,
                      height: 1.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (hasSwitch)
            Switch(
              value: switchValue!,
              onChanged: onSwitchChanged,
              activeThumbColor: activeColor,
              activeTrackColor: activeColor.withValues(alpha: 0.28),
              inactiveThumbColor: skin.textMuted,
              inactiveTrackColor: skin.surface(0.08),
            )
          else if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing!,
          ],
        ],
      ),
    );

    return GestureDetector(
      onTap: hasSwitch
          ? () => onSwitchChanged!(!switchValue!)
          : onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          rowContent,
          if (!isLast)
            Padding(
              padding: EdgeInsets.only(
                left: leading != null ? 14.0 + 12.0 + 24.0 : 14.0,
              ),
              child: Divider(
                height: 0.5,
                thickness: 0.5,
                color: skin.isLight
                    ? Colors.black.withValues(alpha: 0.07)
                    : Colors.white.withValues(alpha: 0.07),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS CHIP
//
// Einheitlicher Filter/Auswahl-Chip. Ersetzt alle inline
// GestureDetector + AnimatedContainer Chip-Muster in:
//   • speech_log_screen.dart  (_FilterChip)
//   • tasks_screen.dart       (_ReminderQuickChips items)
//   • settings_screen.dart    (_ModeSegment, Stil-Chips)
//   • admin_rules_screen.dart (Auswählen/Abbrechen Toggle)
//
// Verwendung:
//   GlassChip(
//     label: 'Alle',
//     active: _filter == LogFilter.all,
//     onTap: () => setState(() => _filter = LogFilter.all),
//   )
//   GlassChip(
//     label: 'Nicht erkannt',
//     active: true,
//     color: skin.deleteColor,       // optional, Standard: skin.primary
//     icon: Icons.close_rounded,     // optional, links vom Label
//     onTap: ...,
//   )
// ─────────────────────────────────────────────────────────────────────────────

class GlassChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  /// Akzentfarbe wenn aktiv. Standard: skin.primary.
  final Color? color;

  /// Optionales Icon links vom Label (nur wenn active oder immer sichtbar).
  final IconData? icon;

  /// Wenn true, wird das Icon auch im inaktiven Zustand angezeigt.
  final bool showIconWhenInactive;

  const GlassChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.color,
    this.icon,
    this.showIconWhenInactive = false,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final c = color ?? skin.primary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? c.withValues(alpha: 0.14)
              : skin.surface(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? c.withValues(alpha: 0.45)
                : skin.surface(0.12),
            width: active ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null && (active || showIconWhenInactive)) ...[
              Icon(
                icon,
                size: 13,
                color: active ? c : skin.surface(0.4),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? c : skin.surface(0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLASS STATUS BADGE
//
// Kleines farbiges Label-Badge mit Border. Ersetzt alle inline
// Container + Text Status-Badges in:
//   • admin_rules_screen.dart  ("ADMIN", "Ausstehend")
//   • speech_log_screen.dart   ("Vollständig", "Nicht erkannt", etc.)
//   • bug_admin_screen.dart    ("Erledigt")
//   • tasks_screen.dart        (kein Badge, aber "DRINGEND" Section-Header)
//
// Verwendung:
//   GlassStatusBadge(label: 'ADMIN', color: Color(0xFF8B5CF6))
//   GlassStatusBadge(label: 'Erledigt', color: skin.statComplete)
//   GlassStatusBadge(label: '✗ Nicht erkannt', color: skin.deleteColor)
//   GlassStatusBadge(label: 'Ausstehend', color: Color(0xFFF59E0B), dot: true)
// ─────────────────────────────────────────────────────────────────────────────

class GlassStatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  /// Wenn true, wird ein kleiner farbiger Dot links vom Label gerendert.
  final bool dot;

  /// Schriftgröße. Standard 10.5 passt für kompakte Badges.
  final double fontSize;

  const GlassStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.dot = false,
    this.fontSize = 10.5,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dot ? 8 : 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: skin.isLight ? 0.10 : 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: skin.isLight ? 0.28 : 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.80),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: label == label.toUpperCase() ? 0.6 : 0.0,
            ),
          ),
        ],
      ),
    );
  }
}

