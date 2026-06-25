import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/bug_report_service.dart';
import '../services/auth_service.dart';
import 'bug_admin_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LIQUID GLASS EXTENSION
// ─────────────────────────────────────────────────────────────────────────────

extension _AppSkinGlass on AppSkin {
  double get glassBlur => isLight ? 18.0 : 22.0;
  double get glassOpacity => isLight ? 0.62 : 0.55;
  Color get glassHighlight =>
      isLight ? Colors.white.withValues(alpha: 0.70) : Colors.white.withValues(alpha: 0.12);
  Color get glassBorder =>
      isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16);
  Color get glassShadow =>
      Colors.black.withValues(alpha: isLight ? 0.08 : 0.35);
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _messageController = TextEditingController();
  bool _sending = false;

  // ── Bug-Report State ──
  final _bugTitleCtrl = TextEditingController();
  final _bugDescCtrl = TextEditingController();
  File? _bugScreenshot;
  bool _submittingBug = false;

  @override
  void dispose() {
    _messageController.dispose();
    _bugTitleCtrl.dispose();
    _bugDescCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendSupport() async {
    if (_messageController.text.trim().isEmpty) {
      final skin = AppTheme.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte eine Nachricht eingeben'),
          backgroundColor: skin.deleteColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
      return;
    }

    setState(() => _sending = true);

    final subject = Uri.encodeComponent('OperationTimer Support Anfrage');
    final body = Uri.encodeComponent(_messageController.text.trim());
    final uri = Uri.parse('mailto:iPunched7@gmail.com?subject=$subject&body=$body');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      _messageController.clear();
    } else {
      if (mounted) {
        final skin = AppTheme.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Keine Mail-App gefunden'),
            backgroundColor: skin.deleteColor,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          ),
        );
      }
    }

    setState(() => _sending = false);
  }

  // ── Bug-Report Methoden ──

  Future<void> _submitBug() async {
    final title = _bugTitleCtrl.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Bitte einen Titel eingeben'),
        backgroundColor: AppTheme.of(context).deleteColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));
      return;
    }
    setState(() => _submittingBug = true);
    try {
      await BugReportService.submit(
        title: title,
        description: _bugDescCtrl.text.trim(),
        screenshot: _bugScreenshot,
      );
      _bugTitleCtrl.clear();
      _bugDescCtrl.clear();
      setState(() => _bugScreenshot = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✓ Bug gemeldet – Danke!'),
          backgroundColor: AppTheme.of(context).statComplete,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Fehler: $e'),
          backgroundColor: AppTheme.of(context).deleteColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
      }
    }
    setState(() => _submittingBug = false);
  }

  Future<void> _pickScreenshot() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null) setState(() => _bugScreenshot = File(picked.path));
  }

  @override
  Widget build(BuildContext contRext) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    // Zurück — nur Hitbox, kein Rahmen
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_ios_new,
                            color: skin.textPrimary,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Support',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: skin.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Scroll-Inhalt ───────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Info-Kachel ─────────────────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                              sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: skin.isLight
                                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: skin.glassBorder, width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                    color: skin.glassShadow,
                                    blurRadius: 24,
                                    spreadRadius: 0,
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
                                const Text('🆘',
                                    style: TextStyle(fontSize: 32)),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Wir helfen dir gerne!',
                                        style: TextStyle(
                                            color: skin.textPrimary,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Beschreibe dein Problem oder deine Frage – wir melden uns so schnell wie möglich.',
                                        style: TextStyle(
                                            color: skin.textMuted,
                                            fontSize: 13,
                                            height: 1.4),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Label ───────────────────────────────────────────────
                      Text(
                        'DEINE NACHRICHT',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: skin.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // ── Textfeld-Kachel ─────────────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(
                              sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: skin.isLight
                                  ? Colors.white.withValues(alpha: skin.glassOpacity)
                                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: skin.glassBorder, width: 1.0),
                              boxShadow: [
                                BoxShadow(
                                    color: skin.glassShadow,
                                    blurRadius: 24,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 6)),
                                BoxShadow(
                                    color: skin.glassHighlight,
                                    blurRadius: 0,
                                    spreadRadius: -1,
                                    offset: const Offset(0, 1)),
                              ],
                            ),
                            child: TextField(
                              controller: _messageController,
                              maxLines: 8,
                              style: TextStyle(
                                  color: skin.textPrimary,
                                  fontSize: 15,
                                  height: 1.5),
                              decoration: InputDecoration(
                                hintText:
                                    'Beschreibe hier dein Anliegen so genau wie möglich...',
                                hintStyle: TextStyle(
                                    color: skin.surface(0.25),
                                    fontSize: 15),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // ── Send-Button — Glass Primary ─────────────────────────
                      GestureDetector(
                        onTap: _sending ? null : _sendSupport,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 17),
                          decoration: BoxDecoration(
                            color: _sending
                                ? skin.surface(0.05)
                                : (skin.isLight
                                    ? skin.primary.withValues(alpha: 0.13)
                                    : skin.primary.withValues(alpha: 0.22)),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _sending
                                  ? skin.glassBorder
                                  : (skin.isLight
                                      ? skin.primary.withValues(alpha: 0.28)
                                      : skin.primary.withValues(alpha: 0.45)),
                              width: 1.5,
                            ),
                            boxShadow: _sending
                                ? []
                                : [
                                    BoxShadow(
                                        color: skin.glassShadow,
                                        blurRadius: 24,
                                        spreadRadius: 0,
                                        offset: const Offset(0, 6)),
                                    BoxShadow(
                                        color: skin.glassHighlight,
                                        blurRadius: 0,
                                        spreadRadius: -1,
                                        offset: const Offset(0, 1)),
                                  ],
                          ),
                          child: Center(
                            child: _sending
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: skin.primary),
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.email_outlined,
                                        color: skin.isLight
                                            ? skin.primary
                                                .withValues(alpha: 0.65)
                                            : skin.primary
                                                .withValues(alpha: 0.70),
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Nachricht senden',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: skin.isLight
                                              ? skin.primary
                                                  .withValues(alpha: 0.90)
                                              : skin.primary
                                                  .withValues(alpha: 0.85),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      Center(
                        child: Text(
                          'Die Nachricht wird per Mail gesendet',
                          style: TextStyle(
                              fontSize: 12, color: skin.surface(0.28)),
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ── Bug-Report Divider ──────────────────────────────────────
                      Row(children: [
                        Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text('BUG MELDEN',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                  color: skin.surface(0.35), letterSpacing: 1.2)),
                        ),
                        Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
                      ]),

                      const SizedBox(height: 16),

                      // ── Bug Titel ──────────────────────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                              color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity)
                                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: skin.glassBorder),
                            ),
                            child: TextField(
                              controller: _bugTitleCtrl,
                              style: TextStyle(color: skin.textPrimary, fontSize: 15),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Kurzer Titel *',
                                hintStyle: TextStyle(color: skin.surface(0.28), fontSize: 15),
                                border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Bug Beschreibung ───────────────────────────────────────
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            decoration: BoxDecoration(
                              color: skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity)
                                  : skin.bgCard.withValues(alpha: skin.glassOpacity),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: skin.glassBorder),
                            ),
                            child: TextField(
                              controller: _bugDescCtrl,
                              maxLines: 4, minLines: 2,
                              style: TextStyle(color: skin.textPrimary, fontSize: 14, height: 1.4),
                              textCapitalization: TextCapitalization.sentences,
                              decoration: InputDecoration(
                                hintText: 'Beschreibung (optional)',
                                hintStyle: TextStyle(color: skin.surface(0.26), fontSize: 14),
                                border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 10),

                      // ── Screenshot Picker ──────────────────────────────────────
                      GestureDetector(
                        onTap: _pickScreenshot,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                              decoration: BoxDecoration(
                                color: _bugScreenshot != null
                                    ? skin.primary.withValues(alpha: 0.10)
                                    : (skin.isLight ? Colors.white.withValues(alpha: skin.glassOpacity)
                                        : skin.bgCard.withValues(alpha: skin.glassOpacity)),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: _bugScreenshot != null
                                      ? skin.primary.withValues(alpha: 0.35) : skin.glassBorder),
                              ),
                              child: Row(children: [
                                Icon(
                                  _bugScreenshot != null ? Icons.image_rounded : Icons.add_photo_alternate_outlined,
                                  size: 18,
                                  color: _bugScreenshot != null ? skin.primary : skin.surface(0.4),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(
                                  _bugScreenshot != null ? 'Screenshot ausgewählt ✓' : 'Screenshot hinzufügen (optional)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: _bugScreenshot != null ? skin.primary : skin.surface(0.4),
                                    fontWeight: _bugScreenshot != null ? FontWeight.w600 : FontWeight.w400,
                                  ),
                                )),
                                if (_bugScreenshot != null)
                                  GestureDetector(
                                    onTap: () => setState(() => _bugScreenshot = null),
                                    child: Icon(Icons.close_rounded, size: 16, color: skin.surface(0.4)),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // ── Bug Senden Button ──────────────────────────────────────
                      GestureDetector(
                        onTap: _submittingBug ? null : _submitBug,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF5B5B).withValues(alpha: skin.isLight ? 0.10 : 0.18),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFEF5B5B).withValues(alpha: 0.35), width: 1.3),
                          ),
                          child: Center(child: _submittingBug
                              ? SizedBox(width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: const Color(0xFFEF5B5B)))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(Icons.bug_report_outlined, color: const Color(0xFFEF5B5B), size: 18),
                                  const SizedBox(width: 8),
                                  Text('Bug melden', style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700,
                                    color: const Color(0xFFEF5B5B))),
                                ])),
                        ),
                      ),

                      // ── Admin: Bug-Liste ───────────────────────────────────────
                      if (AuthService.instance.isAdmin) ...[
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => BugAdminScreen())),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: skin.surface(0.05),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: skin.surface(0.12)),
                            ),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(Icons.admin_panel_settings_outlined, size: 16, color: skin.surface(0.45)),
                              const SizedBox(width: 8),
                              Text('Admin: Bug-Reports ansehen →',
                                  style: TextStyle(fontSize: 13, color: skin.surface(0.45), fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}