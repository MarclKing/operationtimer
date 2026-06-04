import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Bitte eine Nachricht eingeben'),
          backgroundColor: const Color(0xFFFF6B6B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Keine Mail-App gefunden'),
            backgroundColor: const Color(0xFFFF6B6B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isChromeSkin = skin.key == 'chrome';

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: skin.surface(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.borderSubtle),
                      ),
                      child: Icon(Icons.arrow_back_ios_new, color: skin.textPrimary, size: 16),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Support',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: skin.textPrimary),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),

                    // Info Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: skin.primaryWithAlpha(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: skin.primaryWithAlpha(0.2)),
                      ),
                      child: Row(
                        children: [
                          const Text('🆘', style: TextStyle(fontSize: 32)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Wir helfen dir gerne!',
                                  style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Beschreibe dein Problem oder deine Frage – wir melden uns so schnell wie möglich.',
                                  style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.4),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Nachricht
                    Text(
                      'DEINE NACHRICHT',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: skin.primary, letterSpacing: 1.0),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: skin.surface(0.04),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: skin.borderSubtle),
                      ),
                      child: TextField(
                        controller: _messageController,
                        maxLines: 8,
                        style: TextStyle(color: skin.textPrimary, fontSize: 15, height: 1.5),
                        decoration: InputDecoration(
                          hintText: 'Beschreibe hier dein Anliegen so genau wie möglich...',
                          hintStyle: TextStyle(color: skin.textHint, fontSize: 15),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // 🔥 Send Button - Skin-abhängig
                    GestureDetector(
                      onTap: _sending ? null : _sendSupport,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: _sending
                              ? null
                              : (isChromeSkin
                                  ? const LinearGradient(
                                      colors: [Color(0xFF333333), Color(0xFF555555)],
                                      begin: Alignment.centerLeft,
                                      end: Alignment.centerRight,
                                    )
                                  : skin.gradient),
                          color: _sending ? skin.surface(0.05) : null,
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: _sending
                              ? []
                              : [
                                  BoxShadow(
                                    color: isChromeSkin
                                        ? Colors.black.withValues(alpha: 0.3)
                                        : skin.primaryWithAlpha(0.3),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  )
                                ],
                        ),
                        child: Center(
                          child: _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.email_outlined, color: Colors.white, size: 20),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Nachricht senden',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: Text(
                        'Die Nachricht wird per Mail gesendet',
                        style: TextStyle(fontSize: 12, color: skin.textHint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}