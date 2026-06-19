import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_kit.dart';

class ExportHinweiseScreen extends StatefulWidget {
  const ExportHinweiseScreen({super.key});

  @override
  State<ExportHinweiseScreen> createState() => _ExportHinweiseScreenState();
}

class _ExportHinweiseScreenState extends State<ExportHinweiseScreen> {
  final _emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _emailCtrl.text = box.get('export_email', defaultValue: '') as String;
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _saveEmail() {
    final box = Hive.box('einstellungen');
    box.put('export_email', _emailCtrl.text.trim());
    FocusScope.of(context).unfocus();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('E-Mail gespeichert ✓'),
      backgroundColor: const Color(0xFF3DD6C8),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 40),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: skin.surface(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: skin.glassBorder),
                      ),
                      child: Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: skin.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text('Hinweise Exportieren',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // E-Mail Eingabe
                    _SectionHeader(label: 'ZIEL-E-MAIL', skin: skin),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: skin.isLight
                                ? Colors.white.withValues(alpha: skin.glassOpacity)
                                : skin.bgCard.withValues(alpha: skin.glassOpacity),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: skin.glassBorder),
                          ),
                          child: Row(children: [
                            Icon(Icons.mail_outline_rounded, size: 18, color: skin.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('DIENSTLICHE E-MAIL',
                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                        color: skin.primary, letterSpacing: 1.0)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: _emailCtrl,
                                  keyboardType: TextInputType.emailAddress,
                                  autocorrect: false,
                                  style: TextStyle(color: skin.textPrimary, fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: 'z.B. name@behoerde.de',
                                    hintStyle: TextStyle(color: skin.surface(0.3), fontSize: 15),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  onSubmitted: (_) => _saveEmail(),
                                ),
                              ]),
                            ),
                            GestureDetector(
                              onTap: _saveEmail,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: skin.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: skin.primary.withValues(alpha: 0.3)),
                                ),
                                child: Text('Speichern',
                                    style: TextStyle(color: skin.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('Diese Adresse wird beim Export automatisch als Empfänger eingetragen.',
                        style: TextStyle(fontSize: 11, color: skin.surface(0.3))),

                    const SizedBox(height: 28),

                    // So funktioniert es
                    _SectionHeader(label: 'SO FUNKTIONIERT DER EXPORT', skin: skin),
                    const SizedBox(height: 12),

                    _StepCard(
                      number: '1',
                      title: 'Fahrten auswählen',
                      body: 'Halte eine Fahrt-Kachel im Fahrtenbuch gedrückt, um den Auswahlmodus zu aktivieren. Tippe dann weitere Kacheln an. Oder nutze "Alle Fahrten exportieren" am unteren Ende der Liste.',
                      icon: Icons.touch_app_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '2',
                      title: 'Mail wird vorbereitet',
                      body: 'Die App erstellt eine HTML-Datei mit allen ausgewählten Fahrten und öffnet deine Mail-App. Empfänger, Betreff und Anhang sind bereits vorausgefüllt – du tippst nur noch auf Senden.',
                      icon: Icons.mail_outline_rounded,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '3',
                      title: 'Am Dienstrechner: Mail öffnen',
                      body: 'Öffne die Mail auf dem Dienstrechner und klicke auf den HTML-Anhang – er öffnet sich direkt im Browser.',
                      icon: Icons.computer_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '4',
                      title: 'Fahrt kopieren',
                      body: 'Im Browser siehst du alle Fahrten übersichtlich. Klicke bei der gewünschten Fahrt auf "Kopieren" – das JSON liegt jetzt in der Zwischenablage.',
                      icon: Icons.copy_outlined,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '5',
                      title: 'Bookmarklet: Fahrt importieren',
                      body: 'Wechsle zu FleetPortal und klicke das Bookmarklet. Tippe auf "📋 Fahrt importieren" – die kopierten Daten werden eingefügt. Dann "Felder ausfüllen" und das Formular füllt sich automatisch.',
                      icon: Icons.bookmark_outline_rounded,
                      skin: skin,
                    ),
                    const SizedBox(height: 10),
                    _StepCard(
                      number: '6',
                      title: 'Nächste Fahrt',
                      body: 'Zurück zum Browser-Tab, nächste Fahrt kopieren, Bookmarklet erneut öffnen, "Fahrt importieren", fertig. Pro Fahrt: 3 Klicks.',
                      icon: Icons.repeat_rounded,
                      skin: skin,
                    ),

                    const SizedBox(height: 28),

                    // Bookmarklet Hinweis
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(alpha: 0.07),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: skin.primary.withValues(alpha: 0.22)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: skin.primary, size: 18),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Bookmarklet benötigt',
                                      style: TextStyle(color: skin.primary, fontSize: 13, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Das Bookmarklet muss einmalig auf dem Dienstrechner in der Lesezeichenleiste des Browsers installiert sein. Die Installationsseite wurde dir separat bereitgestellt.',
                                    style: TextStyle(color: skin.textMuted, fontSize: 12, height: 1.5),
                                  ),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
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

class _SectionHeader extends StatelessWidget {
  final String label;
  final AppSkin skin;
  const _SectionHeader({required this.label, required this.skin});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
          color: skin.surface(0.38), letterSpacing: 1.2)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: skin.surface(0.12))),
    ]);
  }
}

class _StepCard extends StatelessWidget {
  final String number, title, body;
  final IconData icon;
  final AppSkin skin;

  const _StepCard({
    required this.number, required this.title,
    required this.body, required this.icon, required this.skin,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: skin.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(number,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: skin.primary)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, size: 14, color: skin.primary),
                    const SizedBox(width: 6),
                    Expanded(child: Text(title,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: skin.textPrimary))),
                  ]),
                  const SizedBox(height: 4),
                  Text(body, style: TextStyle(fontSize: 12, color: skin.textMuted, height: 1.5)),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}