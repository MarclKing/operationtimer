import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

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

  @override
  void dispose() {
    _messageController.dispose();
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
                      child: SizedBox(
                        width: 42,
                        height: 42,
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