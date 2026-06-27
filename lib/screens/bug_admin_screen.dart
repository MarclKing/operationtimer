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
                          showGeneralDialog(
                            context: context,
                            barrierDismissible: true,
                            barrierLabel: 'Schließen',
                            barrierColor: Colors.black.withValues(alpha: 0.75),
                            transitionDuration: const Duration(milliseconds: 220),
                            transitionBuilder: (ctx, anim, _, child) =>
                                FadeTransition(opacity: anim, child: child),
                            pageBuilder: (ctx, _, __) => GestureDetector(
                              onTap: () => Navigator.pop(ctx),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.network(r.screenshotUrl!),
                                  ),
                                ),
                              ),
                            ),
                          );
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

// ── Bug Card mit Swipe-Delete über GlassSwipeCard ──────────────────────────

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

class _BugCardState extends State<_BugCard> {
  // Verweis auf das GlassSwipeCard-Widget, das die eigentliche
  // Wisch- und Lösch-Animation übernimmt.
  final _swipeKey = GlobalKey<GlassSwipeCardState>();

  /// Wird vom Eltern-Screen (BugAdminScreen._deleteWithAnimation) aufgerufen,
  /// NACHDEM der Nutzer im Dialog "Löschen" bestätigt hat.
  /// Reicht den Befehl einfach an GlassSwipeCard weiter.
  void animateOutAndDelete(VoidCallback onDone) {
    _swipeKey.currentState?.animateOutAndDelete(onDone);
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final r = widget.report;
    final dateStr = DateFormat('dd.MM.yy · HH:mm').format(r.createdAt);

    return GlassSwipeCard(
      key: _swipeKey,
      cardKey: r.id,
      onDelete: widget.onDelete,
      animateDelete: false,
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
                    : skin.deleteColor.withValues(alpha: 0.30),
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
    );
  }
}