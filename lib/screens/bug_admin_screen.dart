import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_dialogs.dart';
import '../services/bug_report_service.dart';

class BugAdminScreen extends StatefulWidget {
  const BugAdminScreen({super.key});
  @override
  State<BugAdminScreen> createState() => _BugAdminScreenState();
}

class _BugAdminScreenState extends State<BugAdminScreen> {
  // Löschen mit Slide-Out-Animation – analog zu TaskCard
  final Map<String, GlobalKey<_BugCardState>> _cardKeys = {};

  void _deleteWithAnimation(BugReport report) {
    final key = _cardKeys[report.id];
    if (key?.currentState != null) {
      key!.currentState!.animateOutAndDelete(() async {
        await BugReportService.delete(report.id);
        _cardKeys.remove(report.id);
      });
    } else {
      BugReportService.delete(report.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: SizedBox(width: 48, height: 48,
                    child: Center(child: Icon(Icons.arrow_back_ios_new,
                        color: skin.textPrimary, size: 18))),
              ),
              const SizedBox(width: 8),
              Text('Bug-Reports', style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700, color: skin.textPrimary)),
            ]),
          ),
          const SizedBox(height: 12),
          // Liste
          Expanded(
            child: StreamBuilder<List<BugReport>>(
              stream: BugReportService.streamAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: skin.primary));
                }
                final reports = snap.data ?? [];
                if (reports.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.bug_report_outlined, size: 46, color: skin.surface(0.18)),
                    const SizedBox(height: 12),
                    Text('Keine Bug-Reports', style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                  ]));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                  itemCount: reports.length,
                  itemBuilder: (context, i) {
                    final r = reports[i];
                    _cardKeys.putIfAbsent(r.id, () => GlobalKey<_BugCardState>());
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BugCard(
                        key: _cardKeys[r.id],
                        report: r,
                        skin: skin,
                        onToggleResolved: () {
                          HapticFeedback.lightImpact();
                          BugReportService.markResolved(r.id, !r.resolved);
                        },
                        onDelete: () async {
                          final confirmed = await confirmDeleteDialog(
                            context: context, skin: skin,
                            title: 'Bug-Report löschen',
                            message: 'Diesen Bug-Report unwiderruflich löschen?',
                          );
                          if (confirmed == true) _deleteWithAnimation(r);
                        },
                        onViewScreenshot: r.screenshotUrl != null ? () {
                          showDialog(context: context, builder: (_) => Dialog(
                            backgroundColor: Colors.transparent,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(r.screenshotUrl!),
                            ),
                          ));
                        } : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Bug Card mit Swipe-Delete (analog TaskCard) ────────────────────────────

class _BugCard extends StatefulWidget {
  final BugReport report;
  final AppSkin skin;
  final VoidCallback onToggleResolved;
  final VoidCallback onDelete;
  final VoidCallback? onViewScreenshot;

  const _BugCard({
    super.key,
    required this.report,
    required this.skin,
    required this.onToggleResolved,
    required this.onDelete,
    this.onViewScreenshot,
  });

  @override
  State<_BugCard> createState() => _BugCardState();
}

class _BugCardState extends State<_BugCard> with TickerProviderStateMixin {
  static const double _revealWidth = 80.0;
  static const double _snapThreshold = 40.0;
  double _swipeOffset = 0.0;
  bool _isOpen = false;
  bool _dragging = false;
  double _dragStartX = 0, _dragStartY = 0;

  late AnimationController _deleteCtrl;
  late Animation<double> _slideOut, _fadeOut, _heightCollapse;

  @override
  void initState() {
    super.initState();
    _deleteCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideOut = Tween<double>(begin: 0, end: -420).animate(
        CurvedAnimation(parent: _deleteCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeInBack)));
    _fadeOut = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteCtrl, curve: const Interval(0.25, 0.7, curve: Curves.easeOut)));
    _heightCollapse = Tween<double>(begin: 1, end: 0).animate(
        CurvedAnimation(parent: _deleteCtrl, curve: const Interval(0.6, 1.0, curve: Curves.easeInOut)));
    _deleteCtrl.addListener(() { if (mounted) setState(() {}); });
  }

  @override
  void dispose() {
    _deleteCtrl.dispose();
    super.dispose();
  }

  void animateOutAndDelete(VoidCallback onDone) {
    _deleteCtrl.forward().then((_) => onDone());
  }

  void _onPanStart(DragStartDetails d) {
    _dragging = false;
    _dragStartX = d.globalPosition.dx;
    _dragStartY = d.globalPosition.dy;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final dx = d.globalPosition.dx - _dragStartX;
    final dy = (d.globalPosition.dy - _dragStartY).abs();
    if (!_dragging) {
      if (dy > dx.abs() || dx > 0 || dx.abs() < 8) return;
      _dragging = true;
    }
    setState(() => _swipeOffset = ((_isOpen ? -_revealWidth : 0) + (d.globalPosition.dx - _dragStartX))
        .clamp(-_revealWidth, 0.0));
  }

  void _onPanEnd(DragEndDetails d) {
    if (!_dragging) return;
    _dragging = false;
    final v = d.primaryVelocity ?? 0;
    if (_swipeOffset < -_snapThreshold || v < -400) {
      setState(() { _swipeOffset = -_revealWidth; _isOpen = true; });
    } else {
      setState(() { _swipeOffset = 0; _isOpen = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final r = widget.report;
    final dateStr = DateFormat('dd.MM.yy · HH:mm').format(r.createdAt);

    return AnimatedBuilder(
      animation: _deleteCtrl,
      builder: (context, child) => SizeTransition(
        sizeFactor: _heightCollapse,
        axisAlignment: -1,
        child: Opacity(
          opacity: _fadeOut.value,
          child: Transform.translate(offset: Offset(_slideOut.value, 0), child: child!),
        ),
      ),
      child: GestureDetector(
        onHorizontalDragStart: _onPanStart,
        onHorizontalDragUpdate: _onPanUpdate,
        onHorizontalDragEnd: _onPanEnd,
        onTap: _isOpen ? () => setState(() { _swipeOffset = 0; _isOpen = false; }) : null,
        child: ClipRect(
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            // Delete-Bereich
            Positioned(
              right: 0, top: 4, bottom: 4, width: _revealWidth,
              child: GestureDetector(
                onTap: () {
                  setState(() { _swipeOffset = 0; _isOpen = false; });
                  widget.onDelete();
                },
                child: Opacity(
                  opacity: (_swipeOffset.abs() / _revealWidth).clamp(0.0, 1.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        margin: const EdgeInsets.only(left: 6),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.delete_outline, color: skin.deleteColor, size: 20),
                          const SizedBox(height: 3),
                          Text('Löschen', style: TextStyle(
                              color: skin.deleteColor, fontSize: 10, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Card
            Transform.translate(
              offset: Offset(_swipeOffset, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: r.resolved
                          ? skin.surface(0.04)
                          : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity)
                              : skin.bgCard.withValues(alpha: skin.glassOpacity)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: r.resolved
                            ? skin.surface(0.12)
                            : const Color(0xFFEF5B5B).withValues(alpha: 0.30),
                        width: r.resolved ? 0.8 : 1.3,
                      ),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        // Resolved-Toggle
                        GestureDetector(
                          onTap: widget.onToggleResolved,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 22, height: 22,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: r.resolved ? skin.statComplete : Colors.transparent,
                              border: Border.all(
                                color: r.resolved ? skin.statComplete : skin.surface(0.28),
                                width: 1.8),
                            ),
                            child: r.resolved
                                ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(r.title,
                          style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: r.resolved ? skin.surface(0.35) : skin.textPrimary,
                            decoration: r.resolved ? TextDecoration.lineThrough : null,
                            decorationColor: skin.surface(0.35),
                          ))),
                        if (r.screenshotUrl != null)
                          GestureDetector(
                            onTap: widget.onViewScreenshot,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(Icons.image_outlined, size: 18, color: skin.primary),
                            ),
                          ),
                      ]),
                      if (r.description.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(left: 32),
                          child: Text(r.description,
                            style: TextStyle(fontSize: 13, color: skin.surface(0.5), height: 1.4),
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Row(children: [
                          Icon(Icons.access_time_outlined, size: 11, color: skin.surface(0.3)),
                          const SizedBox(width: 4),
                          Text(dateStr, style: TextStyle(fontSize: 11, color: skin.surface(0.3))),
                          if (r.resolved) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: skin.statComplete.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text('Erledigt',
                                  style: TextStyle(fontSize: 10, color: skin.statComplete,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}