import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../models/relationship_style.dart';
import '../services/notification_service.dart';
import '../screens/welcome_screen.dart' show RelationshipOptionCard;
import '../widgets/glass_pickers.dart' show IOSTimePicker;
import '../screens/dictation_help_screen.dart';
import '../screens/speech_log_screen.dart';
import '../screens/admin_rules_screen.dart';
import '../services/auth_service.dart';
import 'package:share_plus/share_plus.dart';
import '../services/sync_token_service.dart';
import '../services/weather_service.dart';
import '../services/travel_mode_service.dart';
import '../widgets/glass_kit.dart';
import '../widgets/glass_snackbar.dart';
import '../widgets/glass_dialogs.dart';
import '../utils/time_rounding.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../services/backup_service.dart';
import 'tasks_screen.dart' show TaskStore;

// ─────────────────────────────────────────────────────────────────────────────
// EINSTIEGSPUNKT — Apple-artige Kachel-Übersicht
// ─────────────────────────────────────────────────────────────────────────────

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final box = Hive.box('einstellungen');
    final name = box.get('name', defaultValue: '') as String;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: 'Einstellungen', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Profil-Banner ────────────────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B8DEF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
                          ),
                          title: name.isEmpty ? 'Profil' : name,
                          subtitle: name.isEmpty ? 'Name & Dienstplan-Name' : 'Profil & Dienstplan-Name',
                          isLast: true,
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _ProfileSettingsScreen()),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 24),

                    // ── Hauptgruppe ────────────────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF5B5B),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Benachrichtigungen',
                          subtitle: 'Tagesvorschau · Erinnerungszeit',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _NotificationSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B8DEF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.dashboard_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Startbildschirm',
                          subtitle: 'Wetter · Aufgabe hinzufügen',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _HomescreenSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6CFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.access_time_filled_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Arbeitszeiterfassung',
                          subtitle: 'Nachtschicht · Reisemodus',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _WorkTimeSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB347),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Dienstplan',
                          subtitle: 'Import · Entwickler-Modus',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _ScheduleSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3DD68C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.task_alt_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Aufgaben & Diktieren',
                          subtitle: 'Diktat · Log · Sprach-Analyse',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _TasksDictationSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B8B9E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.folder_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Datenverwaltung',
                          subtitle: 'Aufbewahrung · Auto-Löschung',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _DataManagementSettingsScreen()),
                          ),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3DD6C8),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.palette_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Design',
                          subtitle: 'Farbschema',
                          isLast: true,
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const _DesignSettingsScreen()),
                          ),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 40),
                    Center(
                      child: Text('OpTimes v1.4.0',
                          style: TextStyle(fontSize: 12, color: skin.textHint)),
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

// ─────────────────────────────────────────────────────────────────────────────
// GEMEINSAME BAUSTEINE — Header, Section-Labels, etc.
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const _SettingsHeader(
      {required this.title, required this.onBack}) : trailing = null;

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                  child: Icon(Icons.arrow_back_ios_new, size: 18)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: skin.textPrimary,
                    letterSpacing: -0.5)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: skin.textMuted,
              letterSpacing: 0.6)),
    );
  }
}

class _SectionFootnote extends StatelessWidget {
  final String text;
  const _SectionFootnote({required this.text});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, color: skin.textMuted, height: 1.5)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIEDERVERWENDBARE CARD-BAUSTEINE FÜR UNTERMENÜS
// ─────────────────────────────────────────────────────────────────────────────

class _TiCard extends StatelessWidget {
  final AppSkin skin;
  final Widget child;

  const _TiCard({required this.skin, required this.child});

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: child,
    );
  }
}

class _TiCardHeader extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;

  const _TiCardHeader(
      {required this.skin, required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: skin.primary),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: skin.textPrimary)),
      ],
    );
  }
}

class _TiTextField extends StatelessWidget {
  final AppSkin skin;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  const _TiTextField({
    required this.skin,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: skin.surface(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyle(
            color: skin.textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: skin.textHint),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }
}

class _TiToggleRow extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final bool value;
  final Color activeColor;
  final ValueChanged<bool> onChanged;

  const _TiToggleRow({
    required this.skin,
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: value ? activeColor : skin.textMuted)),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: activeColor,
          activeTrackColor: activeColor.withValues(alpha: 0.25),
          inactiveThumbColor: skin.textMuted,
          inactiveTrackColor: skin.surface(0.08),
        ),
      ],
    );
  }
}

/// Skin-Auswahl-Picker — zeigt alle verfügbaren AppSkins als auswählbare
/// Vorschau-Karten mit Farbverlauf und Namen.
class _TiSkinPicker extends StatelessWidget {
  final String activeSkin;
  final ValueChanged<String> onSelect;

  const _TiSkinPicker(
      {required this.activeSkin, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    const skins = [skinShield, skinChrome, skinCrystal, skinTitanium];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: skins.map((s) {
        final isSelected = s.key == activeSkin;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            onSelect(s.key);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [s.primary, s.bgBase],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? skin.primary
                    : skin.glassBorder,
                width: isSelected ? 2.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: s.primary.withValues(alpha: 0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
                    ]
                  : [],
            ),
            child: Stack(
              children: [
                if (isSelected)
                  const Positioned(
                    top: 6,
                    right: 6,
                    child: Icon(Icons.check_circle_rounded,
                        size: 16, color: Colors.white),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.28),
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14)),
                    ),
                    child: Text(
                      s.displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SYNC TOKEN CARD — ausgelagerter Widget für Übersichtlichkeit
// ─────────────────────────────────────────────────────────────────────────────

class _SyncTokenCard extends StatelessWidget {
  final AppSkin skin;
  final String? syncToken;
  final bool isGenerating;
  final bool isLinking;
  final bool showTokenInput;
  final TextEditingController tokenInputController;
  final String? linkFeedback;
  final bool linkSuccess;
  final VoidCallback onGenerate;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onToggleInput;
  final VoidCallback onLink;
  final VoidCallback onUnlink;

  const _SyncTokenCard({
    required this.skin,
    required this.syncToken,
    required this.isGenerating,
    required this.isLinking,
    required this.showTokenInput,
    required this.tokenInputController,
    required this.linkFeedback,
    required this.linkSuccess,
    required this.onGenerate,
    required this.onCopy,
    required this.onShare,
    required this.onToggleInput,
    required this.onLink,
    required this.onUnlink,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.sync_rounded, size: 18, color: skin.primary),
              const SizedBox(width: 8),
              Text('Sync-Token',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, color: skin.textPrimary)),
              const Spacer(),
              if (syncToken != null)
                GestureDetector(
                  onTap: onUnlink,
                  child: Text('Trennen',
                      style: TextStyle(
                          fontSize: 12,
                          color: skin.deleteColor,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            syncToken == null
                ? 'Generiere einen Token, um deine Daten auf mehreren Geräten zu synchronisieren. Gib denselben Token auf einem anderen Gerät ein.'
                : 'Dein Sync-Token. Gib ihn auf einem anderen Gerät ein, um die Daten zu synchronisieren.',
            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
          ),
          const SizedBox(height: 16),

          if (syncToken == null) ...[
            // ── Kein Token — zwei Optionen ─────────────────────────────

            // Neuen generieren
            if (isGenerating)
              Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: skin.primary),
                ),
              )
            else
              GlassPrimaryButton(
                skin: skin,
                label: 'Neuen Token generieren',
                icon: Icons.add_circle_outline_rounded,
                onTap: onGenerate,
              ),

            const SizedBox(height: 10),

            // Bestehenden verknüpfen
            GlassSecondaryButton(
              skin: skin,
              label: 'Token verknüpfen',
              onTap: onToggleInput,
            ),

            // Token-Eingabe (aufklappbar)
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 240),
              crossFadeState: showTokenInput
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: skin.surface(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.borderSubtle),
                    ),
                    child: TextField(
                      controller: tokenInputController,
                      autofocus: showTokenInput,
                      style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Token eingeben (22 Zeichen)',
                        hintStyle: TextStyle(color: skin.textHint, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => onLink(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isLinking)
                    Center(
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: skin.primary),
                      ),
                    )
                  else
                    GlassPrimaryButton(
                      skin: skin,
                      label: 'Verknüpfen',
                      onTap: onLink,
                    ),
                  if (linkFeedback != null) ...[
                    const SizedBox(height: 10),
                    _FeedbackBadge(
                        skin: skin,
                        message: linkFeedback!,
                        isSuccess: linkSuccess),
                  ],
                ],
              ),
            ),
          ] else ...[
            // ── Token vorhanden — anzeigen + Aktionen ──────────────────

            // Token-Anzeige
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.60)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: skin.glassBorder),
              ),
              child: Row(
                children: [
                  Icon(Icons.vpn_key_rounded,
                      size: 16,
                      color: skin.primary.withValues(alpha: 0.7)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      syncToken!,
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        letterSpacing: 0.8,
                        color: skin.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Aktions-Row: Kopieren + Teilen
            Row(
              children: [
                Expanded(
                  child: GlassSecondaryButton(
                    skin: skin,
                    label: (linkFeedback != null && linkSuccess) ? 'Kopiert!' : 'Kopieren',
                    onTap: onCopy,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GlassPrimaryButton(
                    skin: skin,
                    label: 'Teilen',
                    icon: Icons.ios_share_rounded,
                    onTap: onShare,
                  ),
                ),
              ],
            ),

            // Weiteres Gerät verknüpfen (aufklappbar)
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onToggleInput,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    showTokenInput
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.add_link_rounded,
                    size: 15,
                    color: skin.textMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    showTokenInput ? 'Schließen' : 'Anderen Token eingeben',
                    style: TextStyle(
                        fontSize: 12,
                        color: skin.textMuted,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 240),
              crossFadeState: showTokenInput
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: skin.surface(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.borderSubtle),
                    ),
                    child: TextField(
                      controller: tokenInputController,
                      autofocus: showTokenInput,
                      style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 14,
                        fontFamily: 'monospace',
                        letterSpacing: 0.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Token eingeben (22 Zeichen)',
                        hintStyle: TextStyle(color: skin.textHint, fontSize: 13),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: (_) => onLink(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (isLinking)
                    Center(
                      child: SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: skin.primary),
                      ),
                    )
                  else
                    GlassPrimaryButton(
                      skin: skin,
                      label: 'Verknüpfen',
                      onTap: onLink,
                    ),
                  if (linkFeedback != null) ...[
                    const SizedBox(height: 10),
                    _FeedbackBadge(
                        skin: skin,
                        message: linkFeedback!,
                        isSuccess: linkSuccess),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Kleines Feedback-Badge (Erfolg / Fehler) ──────────────────────────────────

class _FeedbackBadge extends StatelessWidget {
  final AppSkin skin;
  final String message;
  final bool isSuccess;

  const _FeedbackBadge(
      {required this.skin, required this.message, required this.isSuccess});

  @override
  Widget build(BuildContext context) {
    final color = isSuccess ? const Color(0xFF3DD68C) : skin.deleteColor;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isSuccess ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12, color: color.withValues(alpha: 0.85), height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: PROFIL (mit Sync-Token)
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSettingsScreen extends StatefulWidget {
  const _ProfileSettingsScreen();

  @override
  State<_ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<_ProfileSettingsScreen> {
  late TextEditingController _nameController;
  late TextEditingController _tokenInputController;
  late RelationshipStyle _selectedStyle;

  String? _syncToken;
  bool _isGenerating = false;
  bool _isLinking = false;
  bool _showTokenInput = false;
  String? _linkFeedback;
  bool _linkSuccess = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    final name = box.get('name', defaultValue: '') as String;
    _nameController = TextEditingController(text: name);
    _tokenInputController = TextEditingController();
    _selectedStyle = RelationshipStyleStore.load();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = SyncTokenService.instance.localToken; 
    if (mounted) setState(() => _syncToken = token);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _tokenInputController.dispose();
    super.dispose();
  }

  void _selectStyle(RelationshipStyle style) {
    setState(() => _selectedStyle = style);
    RelationshipStyleStore.save(style);
    HapticFeedback.selectionClick();
  }

  Future<void> _generateToken() async {
    setState(() => _isGenerating = true);
    try {
      final token = await SyncTokenService.instance.generateAndRegister();
      if (mounted) setState(() { _syncToken = token; _isGenerating = false; });
    } catch (e) {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _linkToken() async {
    final input = _tokenInputController.text.trim();
    if (input.isEmpty) return;
    setState(() { _isLinking = true; _linkFeedback = null; });
    try {
      final result = await SyncTokenService.instance.linkExistingToken(input);
      if (mounted) {
        setState(() {
          _isLinking = false;
          _linkSuccess = result.isSuccess;
          _linkFeedback = result.userMessage;
          if (result.isSuccess) {
            _syncToken = input;
            _showTokenInput = false;
            _tokenInputController.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLinking = false;
          _linkSuccess = false;
          _linkFeedback = 'Fehler beim Verknüpfen. Bitte versuche es erneut.';
        });
      }
    }
  }

  Future<void> _unlinkToken() async {
    await SyncTokenService.instance.unlinkToken();
    if (mounted) {
      setState(() {
        _syncToken = null;
        _showTokenInput = false;
        _tokenInputController.clear();
        _linkFeedback = null;
      });
    }
  }

  void _copyToken() {
    if (_syncToken == null) return;
    Clipboard.setData(ClipboardData(text: _syncToken!));
    HapticFeedback.lightImpact();
    setState(() {
      _linkSuccess = true;
      _linkFeedback = '✓ Token kopiert!';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkFeedback = null);
    });
  }

  void _shareToken() {
    if (_syncToken == null) return;
    Share.share(
      'Mein OpTimes Sync-Token: $_syncToken\n\nGib diesen Token in OpTimes unter Einstellungen → Profil → Geräte-Synchronisation ein, um unsere Daten zu synchronisieren.',
      subject: 'OpTimes Sync-Token',
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final box = Hive.box('einstellungen');

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: 'Profil', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Name ──────────────────────────────────────────────
                    const _SectionHeader(label: 'Persönliche Daten'),
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.person_outline_rounded,
                              label: 'Name'),
                          const SizedBox(height: 12),
                          Text(
                            'Dein Name wird in Benachrichtigungen und im Dienstplan verwendet.',
                            style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          _TiTextField(
                            skin: skin,
                            controller: _nameController,
                            hint: 'Vor- und Nachname',
                            onChanged: (v) => box.put('name', v.trim()),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Anrede ─────────────────────────────────────────────
                    const _SectionHeader(label: 'Anrede'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<RelationshipStyle>(
                          value: _selectedStyle,
                          label: 'Umgangsform',
                          icon: Icons.chat_bubble_outline_rounded,
                          iconBg: const Color(0xFF5B8DEF),
                          isLast: true,
                          displayBuilder: (s) {
                            switch (s) {
                              case RelationshipStyle.bro:     return 'Locker';
                              case RelationshipStyle.vorname: return 'Vorname';
                              case RelationshipStyle.familie: return 'Formell';
                            }
                          },
                          items: [
                            GlassDropdownItem(value: RelationshipStyle.bro,     label: 'Locker',   icon: Icons.bolt_rounded),
                            GlassDropdownItem(value: RelationshipStyle.vorname, label: 'Normal',               icon: Icons.waving_hand_outlined),
                            GlassDropdownItem(value: RelationshipStyle.familie, label: 'Formell',    icon: Icons.workspace_premium_outlined),
                          ],
                          onChanged: _selectStyle,
                        ),
                      ]),
                    ),

                    const SizedBox(height: 24),

                    // ── Sync-Token ────────────────────────────────────────
                    const _SectionHeader(label: 'Geräte-Synchronisation'),
                    _SyncTokenCard(
                      skin: skin,
                      syncToken: _syncToken,
                      isGenerating: _isGenerating,
                      isLinking: _isLinking,
                      showTokenInput: _showTokenInput,
                      tokenInputController: _tokenInputController,
                      linkFeedback: _linkFeedback,
                      linkSuccess: _linkSuccess,
                      onGenerate: _generateToken,
                      onCopy: _copyToken,
                      onShare: _shareToken,
                      onToggleInput: () => setState(() {
                        _showTokenInput = !_showTokenInput;
                        _linkFeedback = null;
                      }),
                      onLink: _linkToken,
                      onUnlink: _unlinkToken,
                    ),

                    const SizedBox(height: 8),
                    const _SectionFootnote(
                      text:
                          'Der Sync-Token ist dein persönlicher Schlüssel. Teile ihn nur mit Geräten, die du selbst verwendest. Wer den Token kennt, hat Lesezugriff auf deine Daten.',
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: BENACHRICHTIGUNGEN
// ─────────────────────────────────────────────────────────────────────────────

class _NotificationSettingsScreen extends StatefulWidget {
  const _NotificationSettingsScreen();

  @override
  State<_NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<_NotificationSettingsScreen> {
  late RelationshipStyle _selectedStyle;
  late bool _overviewEnabled;
  late String _mode;
  late TimeOfDay _morningTime;
  late bool _onlyIfRelevant;
  late bool _eveningEnabled;
  late TimeOfDay _eveningTime;

  String get _fullName =>
      (Hive.box('einstellungen').get('name', defaultValue: '') as String)
          .trim();

  @override
  void initState() {
    super.initState();
    _selectedStyle = RelationshipStyleStore.load();
    _overviewEnabled = DailyOverviewSettings.enabled;
    _mode = DailyOverviewSettings.mode;
    _morningTime = TimeOfDay(
        hour: DailyOverviewSettings.hour,
        minute: DailyOverviewSettings.minute);
    _onlyIfRelevant = DailyOverviewSettings.onlyIfRelevant;
    _eveningEnabled = DailyOverviewSettings.eveningPreviewEnabled;
    _eveningTime = TimeOfDay(
        hour: DailyOverviewSettings.eveningHour,
        minute: DailyOverviewSettings.eveningMinute);
  }

  void _selectStyle(RelationshipStyle style) {
    setState(() => _selectedStyle = style);
    RelationshipStyleStore.save(style);
    HapticFeedback.selectionClick();
  }

  Future<void> _applyChanges() async {
    await NotificationService.instance
        .applyDailyOverviewSettingsChanged();
  }

  void _setOverviewEnabled(bool v) {
    setState(() => _overviewEnabled = v);
    DailyOverviewSettings.enabled = v;
    _applyChanges();
  }

  void _setMode(String v) {
    setState(() => _mode = v);
    DailyOverviewSettings.mode = v;
    _applyChanges();
  }

  void _setOnlyIfRelevant(bool v) {
    setState(() => _onlyIfRelevant = v);
    DailyOverviewSettings.onlyIfRelevant = v;
    _applyChanges();
  }

  void _setEveningEnabled(bool v) {
    setState(() => _eveningEnabled = v);
    DailyOverviewSettings.eveningPreviewEnabled = v;
    _applyChanges();
  }

  Future<void> _pickMorningTime() async {
    final skin = AppTheme.of(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: _morningTime,
        skin: skin,
        label: 'Uhrzeit der Tagesvorschau',
        onTimeSelected: (t) {
          setState(() => _morningTime = t);
          DailyOverviewSettings.hour = t.hour;
          DailyOverviewSettings.minute = t.minute;
          _applyChanges();
        },
      ),
    );
  }

  Future<void> _pickEveningTime() async {
    final skin = AppTheme.of(context);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IOSTimePicker(
        initialTime: _eveningTime,
        skin: skin,
        label: 'Uhrzeit der Vorabend-Vorschau',
        onTimeSelected: (t) {
          setState(() => _eveningTime = t);
          DailyOverviewSettings.eveningHour = t.hour;
          DailyOverviewSettings.eveningMinute = t.minute;
          _applyChanges();
        },
      ),
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Benachrichtigungen',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(label: 'Tagesvorschau'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6CFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.today_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Tagesvorschau aktiv',
                          subtitle: 'Zeigt täglich Dienst & fällige Aufgaben',
                          switchValue: _overviewEnabled,
                          onSwitchChanged: _setOverviewEnabled,
                          isLast: !_overviewEnabled,
                        ),
                        if (_overviewEnabled) ...[
                          // ── Modus-Auswahl ──────────────────────────────
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                14, 4, 14, 12),
                            child: Row(children: [
                              const SizedBox(width: 46),
                              Expanded(
                                child: GlassSegmentedControl<String>(
  value: _mode,
  items: const [
    GlassSegmentItem(value: 'fixed_time', label: 'Feste Uhrzeit'),
    GlassSegmentItem(value: 'app_start',  label: 'Bei App-Start'),
  ],
  onChanged: _setMode,
),
                              ),
                            ]),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.only(left: 60),
                            child: Divider(
                                height: 0.5, color: skin.glassBorder),
                          ),

                          if (_mode == 'fixed_time')
                            GlassListItem(
                              leading: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF5B8DEF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                              ),
                              title: 'Uhrzeit',
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_formatTime(_morningTime),
                                      style: TextStyle(fontSize: 14, color: skin.textMuted)),
                                  const SizedBox(width: 6),
                                  Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                                ],
                              ),
                              onTap: _pickMorningTime,
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 4, 14, 12),
                              child: Row(children: [
                                const SizedBox(width: 46),
                                Expanded(
                                  child: Text(
                                    'Wird einmal pro Tag direkt beim Öffnen der App angezeigt.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: skin.textMuted,
                                        height: 1.4),
                                  ),
                                ),
                              ]),
                            ),

                          Padding(
                            padding:
                                const EdgeInsets.only(left: 60),
                            child: Divider(
                                height: 0.5, color: skin.glassBorder),
                          ),
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B8B9E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.filter_alt_outlined, color: Colors.white, size: 18),
                            ),
                            title: 'Nur wenn relevant',
                            subtitle: 'Sonst auch "Heute ist nichts geplant"',
                            switchValue: _onlyIfRelevant,
                            onSwitchChanged: _setOnlyIfRelevant,
                          ),
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6D7ADF),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.nightlight_round, color: Colors.white, size: 18),
                            ),
                            title: 'Vorabend-Vorschau',
                            subtitle: 'Zusätzlich abends Vorschau auf morgen',
                            switchValue: _eveningEnabled,
                            onSwitchChanged: _setEveningEnabled,
                            isLast: !_eveningEnabled,
                          ),
                          if (_eveningEnabled)
                            GlassListItem(
                              leading: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6D7ADF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.schedule_rounded, color: Colors.white, size: 18),
                              ),
                              title: 'Uhrzeit (abends)',
                              isLast: true,
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(_formatTime(_eveningTime),
                                      style: TextStyle(fontSize: 14, color: skin.textMuted)),
                                  const SizedBox(width: 6),
                                  Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                                ],
                              ),
                              onTap: _pickEveningTime,
                            ),
                        ],
                      ]),
                    ),
                    const _SectionFootnote(
                      text:
                          'Die Tagesvorschau kombiniert deinen Dienst aus dem Dienstplan mit fälligen Aufgaben des jeweiligen Tages.',
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: ARBEITSZEITERFASSUNG
// ─────────────────────────────────────────────────────────────────────────────

class _WorkTimeSettingsScreen extends StatefulWidget {
  const _WorkTimeSettingsScreen();

  @override
  State<_WorkTimeSettingsScreen> createState() =>
      _WorkTimeSettingsScreenState();
}

class _WorkTimeSettingsScreenState
    extends State<_WorkTimeSettingsScreen> {
  bool _nachtschichtModus = false;
  bool _reisemodus = false;
  String _rundung = TimeRounding.defaultRule;

  // ── Debug-Testzonen für Reisemodus ──────────────────────────────────
  static const _debugZones = {
    'Berlin (Home)': 'Europe/Berlin',
    'New York': 'America/New_York',
    'Los Angeles': 'America/Los_Angeles',
    'Tokio': 'Asia/Tokyo',
  };

  @override
void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nachtschichtModus =
        box.get('nachtschicht_modus', defaultValue: false) as bool;
    _reisemodus = TravelModeService.isEnabled;
    _rundung = box.get(TimeRounding.hiveKey, defaultValue: TimeRounding.defaultRule) as String;
  }

  void _setNachtschichtModus(bool value) {
    setState(() => _nachtschichtModus = value);
    Hive.box('einstellungen').put('nachtschicht_modus', value);
  }

  void _setReisemodus(bool value) async {
    try {
      if (value) {
        await TravelModeService.enableAndSeed();
      } else {
        await TravelModeService.disable();
      }
      if (mounted) setState(() => _reisemodus = value);
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Reisemodus-Fehler: $e', type: GlassSnackBarType.warning);
      }
    }
  }

  // NEU — neue Methode in _WorkTimeSettingsScreenState
  void _showTimeZonePickerSheet(BuildContext context, AppSkin skin) {
    final ctrl = TextEditingController();

    bool isVerifying = false;
    ({String tzId, String displayLabel})? verified;
    String? errorMsg;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: GlassSheet(
          skin: skin,
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> doVerify() async {
                final input = ctrl.text.trim();
                if (input.isEmpty) return;
                setSheetState(() {
                  isVerifying = true;
                  errorMsg = null;
                  verified = null;
                });
                final result = await TravelModeService.verifyLocationTimeZone(input);
                setSheetState(() {
                  isVerifying = false;
                  if (result != null) {
                    verified = result;
                  } else {
                    errorMsg = 'Ort nicht gefunden. Bitte prüfe die Schreibweise.';
                  }
                });
              }

              void saveAndClose() {
                if (verified == null) return;
                TravelModeService.setActiveTz(verified!.tzId);
                Navigator.pop(context);
                setState(() {}); // Subtitle im Screen aktualisieren
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: SheetHandle(skin: skin)),
                    const SizedBox(height: 16),
                    Text('Zeitzone wählen',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                            color: skin.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Wird sofort als aktuelle Zone übernommen.',
                        style: TextStyle(fontSize: 13, color: skin.textMuted)),
                    const SizedBox(height: 16),
                    _TiTextField(
                      skin: skin,
                      controller: ctrl,
                      hint: 'z.B. Washington, Tokio, New York',
                      onChanged: (_) => setSheetState(() {
                        verified = null;
                        errorMsg = null;
                      }),
                      onSubmitted: (_) => doVerify(),
                    ),

                    if (isVerifying) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: skin.primary),
                          ),
                          const SizedBox(width: 10),
                          Text('Prüfe Ort…',
                              style: TextStyle(fontSize: 13, color: skin.textMuted)),
                        ],
                      ),
                    ],
                    if (verified != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DD68C).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline_rounded,
                                size: 16, color: Color(0xFF3DD68C)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Gefunden: ${verified!.displayLabel} · ${verified!.tzId} '
                                '(${TravelModeService.offsetLabelFor(verified!.tzId)})',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF3DD68C),
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (errorMsg != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: skin.deleteColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.error_outline_rounded, size: 16, color: skin.deleteColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(errorMsg!,
                                  style: TextStyle(
                                      fontSize: 12.5, color: skin.deleteColor, height: 1.4)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),

                    if (verified == null)
                      GestureDetector(
                        onTap: isVerifying ? null : doVerify,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(alpha: skin.isLight ? 0.12 : 0.20),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: skin.primary.withValues(alpha: skin.isLight ? 0.30 : 0.45)),
                          ),
                          child: Center(
                            child: Text('Prüfen',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                    color: skin.primary)),
                          ),
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: saveAndClose,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3DD68C).withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.45)),
                          ),
                          child: const Center(
                            child: Text('Übernehmen',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                    color: Color(0xFF3DD68C))),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Arbeitszeiterfassung',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E7D32),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.dark_mode_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Nachtschicht-Modus',
                          subtitle: 'Teilt Nachtschichten auf zwei Tage auf',
                          switchValue: _nachtschichtModus,
                          onSwitchChanged: _setNachtschichtModus,
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6D7ADF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.flight_takeoff_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Reisemodus',
                          subtitle: _reisemodus
                              ? 'Aktiv · ${TravelModeService.activeTzId}'
                              : 'Zeitzonen-Anpassung',
                          isLast: !_reisemodus,
                          switchValue: _reisemodus,
                          onSwitchChanged: _setReisemodus,
                        ),
                        if (_reisemodus)
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF5B9EF5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.edit_location_alt_outlined, color: Colors.white, size: 18),
                            ),
                            title: 'Zeitzone manuell wählen',
                            subtitle: 'Aktuell: ${TravelModeService.activeTzId}',
                            isLast: true,
                            trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                            onTap: () => _showTimeZonePickerSheet(context, skin),
                          ),
                      ]),
                    ),
                    const _SectionFootnote(
                      text: 'Nachtschicht: Kommen bis 23:59 (selber Tag) + 00:00 bis Gehen (nächster Tag). '
                            'Reisemodus: die Schreib-Zeitzone wechselt erst beim nächsten Dienstbeginn nach einem Feierabend.',
                    ),

                    if (_reisemodus && AuthService.instance.isAdmin) ...[
                      const SizedBox(height: 20),
                      const _SectionHeader(label: 'Debug · Reisemodus testen'),
                      _ReisemodusDebugCard(onChanged: () => setState(() {})),
                    ],

                    const SizedBox(height: 14),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<String>(
                          value: _rundung,
                          label: 'Rundung',
                          subtitle: 'Kommen-Zeit auf runden',
                          icon: Icons.timer_outlined,
                          iconBg: const Color(0xFF2D6CFF),
                          isLast: true,
                          displayBuilder: TimeRounding.label,
                          items: const [
                            GlassDropdownItem(value: 'exact', label: 'Genau (keine Rundung)'),
                            GlassDropdownItem(value: '5',     label: '5 Minuten'),
                            GlassDropdownItem(value: '10',    label: '10 Minuten'),
                            GlassDropdownItem(value: '15',    label: '15 Minuten'),
                          ],
                          onChanged: (v) {
                            setState(() => _rundung = v);
                            Hive.box('einstellungen').put(TimeRounding.hiveKey, v);
                          },
                        ),
                      ]),
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: DIENSTPLAN
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleSettingsScreen extends StatefulWidget {
  const _ScheduleSettingsScreen();

  @override
  State<_ScheduleSettingsScreen> createState() =>
      _ScheduleSettingsScreenState();
}

class _ScheduleSettingsScreenState
    extends State<_ScheduleSettingsScreen> {
  bool _dienstplanDevMode = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _dienstplanDevMode =
        box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Dienstplan',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (AuthService.instance.isAdmin) ...[
                      GlassSurface(
                        borderRadius: 18,
                        padding: EdgeInsets.zero,
                        child: Column(children: [
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF5B5B),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.code_rounded, color: Colors.white, size: 18),
                            ),
                            title: 'Entwickler-Modus',
                            subtitle: 'Erweiterte Fehlermeldungen beim PDF-Import',
                            isLast: true,
                            switchValue: _dienstplanDevMode,
                            onSwitchChanged: (v) {
                              setState(() => _dienstplanDevMode = v);
                              Hive.box('einstellungen')
                                  .put('dienstplan_dev_placeholder', v);
                            },
                          ),
                        ]),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const _SectionFootnote(
                      text:
                          'Der Dienstplan-Import befindet sich noch in der Beta-Phase.',
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: DATENVERWALTUNG
// ─────────────────────────────────────────────────────────────────────────────

class _DataManagementSettingsScreen extends StatefulWidget {
  const _DataManagementSettingsScreen();
  @override
  State<_DataManagementSettingsScreen> createState() => _DataManagementSettingsScreenState();
}

class _DataManagementSettingsScreenState extends State<_DataManagementSettingsScreen> {
  int _zeitDeleteMonths = 3;
  int _dienstplanDeleteMonths = 3;
  int _fahrtenbuchDeleteMonths = 3;
  String _taskAutoDelete = '1d';

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _zeitDeleteMonths = box.get('deleteAfterMonths_zeit', defaultValue: 3) as int;
    _dienstplanDeleteMonths = box.get('deleteAfterMonths_dienstplan', defaultValue: 3) as int;
    _fahrtenbuchDeleteMonths = box.get('deleteAfterMonths_fahrtenbuch', defaultValue: 3) as int;
    _taskAutoDelete = box.get('task_auto_delete', defaultValue: '1d') as String;
  }

  String _monthLabel(int m) {
    switch (m) {
      case 1:  return '1 Monat';
      case 3:  return '3 Monate';
      case 6:  return '6 Monate';
      case 12: return '1 Jahr';
      default: return '$m Monate';
    }
  }

  String _taskLabel(String k) {
    switch (k) {
      case 'never': return 'Nie';
      case '1d':    return '1 Tag';
      case '2d':    return '2 Tage';
      case '1w':    return '1 Woche';
      case '1m':    return '1 Monat';
      default:      return k;
    }
  }

  Future<void> _exportBackup() async {
    try {
      await BackupService.exportBackup();
    } catch (e) {
      if (mounted) {
        showGlassSnackBar(context, 'Export fehlgeschlagen: $e', type: GlassSnackBarType.warning);
      }
    }
  }

  Future<void> _pickAndImportBackup() async {
    final skin = AppTheme.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;

    final preview = await BackupService.readBackupFile(path);
    if (preview == null) {
      if (mounted) {
        showGlassSnackBar(context, 'Ungültige oder beschädigte Backup-Datei.',
            type: GlassSnackBarType.warning);
      }
      return;
    }

    if (!mounted) return;
    final exportedLabel = preview.exportedAt != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(preview.exportedAt!)
        : 'unbekannt';

    final confirmed = await confirmActionDialog(
      context: context,
      skin: skin,
      icon: Icons.upload_file_outlined,
      title: 'Backup importieren?',
      message: 'Backup vom $exportedLabel mit ${preview.settingsCount} Einstellungs- '
          'und ${preview.zeitenCount} Zeiterfassungs-Einträgen. Alle aktuellen Daten '
          'auf diesem Gerät werden dabei ÜBERSCHRIEBEN.',
      cancelLabel: 'Abbrechen',
      confirmLabel: 'Überschreiben',
    );
    if (confirmed != true) return;

    await BackupService.applyBackup(preview);
    TaskStore.changesSignal.value++;

    if (!mounted) return;
    showGlassSnackBar(
      context,
      '✓ Backup importiert — App bitte neu starten',
      type: GlassSnackBarType.success,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final box = Hive.box('einstellungen');

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: 'Datenverwaltung', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Zeiterfassung ──────────────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<int>(
                          value: _zeitDeleteMonths,
                          label: 'Zeiterfassung',
                          subtitle: 'Einträge löschen nach',
                          icon: Icons.access_time_outlined,
                          iconBg: const Color(0xFF2D6CFF),
                          isLast: true,
                          displayBuilder: _monthLabel,
                          items: [1, 3, 6, 12]
                              .map((m) => GlassDropdownItem(value: m, label: _monthLabel(m)))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _zeitDeleteMonths = v);
                            box.put('deleteAfterMonths_zeit', v);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // ── Dienstplan ─────────────────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<int>(
                          value: _dienstplanDeleteMonths,
                          label: 'Dienstplan',
                          subtitle: 'Daten löschen nach',
                          icon: Icons.calendar_month_outlined,
                          iconBg: const Color(0xFFFFB347),
                          isLast: true,
                          displayBuilder: _monthLabel,
                          items: [1, 3, 6, 12]
                              .map((m) => GlassDropdownItem(value: m, label: _monthLabel(m)))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _dienstplanDeleteMonths = v);
                            box.put('deleteAfterMonths_dienstplan', v);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // ── Fahrtenbuch ────────────────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<int>(
                          value: _fahrtenbuchDeleteMonths,
                          label: 'Fahrtenbuch',
                          subtitle: 'Eingetr. Fahrten löschen nach',
                          icon: Icons.directions_car_outlined,
                          iconBg: const Color(0xFF8B8B9E),
                          isLast: true,
                          displayBuilder: _monthLabel,
                          items: [1, 3, 6, 12]
                              .map((m) => GlassDropdownItem(value: m, label: _monthLabel(m)))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _fahrtenbuchDeleteMonths = v);
                            box.put('deleteAfterMonths_fahrtenbuch', v);
                          },
                        ),
                      ]),
                    ),
                    const SizedBox(height: 14),

                    // ── Erledigte Aufgaben ──────────────────────────────
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassDropdownButton<String>(
                          value: _taskAutoDelete,
                          label: 'Erledigte Aufgaben',
                          subtitle: 'Automatisch löschen nach',
                          icon: Icons.task_alt_outlined,
                          iconBg: const Color(0xFF3DD68C),
                          isLast: true,
                          displayBuilder: _taskLabel,
                          items: const [
                            GlassDropdownItem(value: 'never', label: 'Nie'),
                            GlassDropdownItem(value: '1d',    label: '1 Tag'),
                            GlassDropdownItem(value: '2d',    label: '2 Tage'),
                            GlassDropdownItem(value: '1w',    label: '1 Woche'),
                            GlassDropdownItem(value: '1m',    label: '1 Monat'),
                          ],
                          onChanged: (v) {
                            setState(() => _taskAutoDelete = v);
                            box.put('task_auto_delete', v);
                          },
                        ),
                      ]),
                    ),

                    const SizedBox(height: 8),
                    const _SectionFootnote(
                      text:
                          'Jeder Bereich hat eine eigene Aufbewahrungsfrist. '
                          'Erledigte Aufgaben werden standardmäßig nach 1 Tag gelöscht.',
                    ),

                    const SizedBox(height: 24),
                    const _SectionHeader(label: 'Backup'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3DD68C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.ios_share_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Backup exportieren',
                          subtitle: 'Als JSON-Datei teilen/speichern',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: _exportBackup,
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6CFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.upload_file_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Backup importieren',
                          subtitle: 'Überschreibt aktuelle Daten',
                          isLast: true,
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: _pickAndImportBackup,
                        ),
                      ]),
                    ),
                    const _SectionFootnote(
                      text: 'Ein Import überschreibt alle Einstellungen, Zeiten, Aufgaben und '
                            'den Dienstplan auf diesem Gerät vollständig.',
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: DESIGN
// ─────────────────────────────────────────────────────────────────────────────

class _DesignSettingsScreen extends StatefulWidget {
  const _DesignSettingsScreen();

  @override
  State<_DesignSettingsScreen> createState() =>
      _DesignSettingsScreenState();
}

class _DesignSettingsScreenState
    extends State<_DesignSettingsScreen> {
  String _activeSkin = 'chrome';

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _activeSkin =
        box.get(AppTheme.hiveKey, defaultValue: 'chrome') as String;
  }

  void _setSkin(String key) {
    setState(() => _activeSkin = key);
    Hive.box('einstellungen').put(AppTheme.hiveKey, key);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    const skins = [skinShield, skinChrome, skinCrystal, skinTitanium];

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Design', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionHeader(label: 'Farbschema'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: skins.asMap().entries.map((entry) {
                          final i = entry.key;
                          final s = entry.value;
                          final isSelected = s.key == _activeSkin;
                          final isLast = i == skins.length - 1;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _setSkin(s.key);
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      // Farbvorschau-Dot
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: [s.primary, s.bgBase],
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          border: isSelected
                                              ? Border.all(
                                                  color: skin.primary,
                                                  width: 2.0)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          s.displayName,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: isSelected
                                                ? skin.primary
                                                : skin.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isSelected)
                                        Icon(Icons.check_rounded,
                                            size: 18, color: skin.primary),
                                    ],
                                  ),
                                ),
                              ),
                              if (!isLast)
                                Padding(
                                  padding: const EdgeInsets.only(left: 60),
                                  child: Divider(
                                      height: 0.5, color: skin.glassBorder),
                                ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    const _SectionFootnote(
                        text: 'Änderung wird sofort übernommen.'),
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: AUFGABEN & DIKTIEREN
// ─────────────────────────────────────────────────────────────────────────────

class _TasksDictationSettingsScreen extends StatelessWidget {
  const _TasksDictationSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Aufgaben & Diktieren',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2D6CFF),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.mic_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Sprachbefehle & Hilfe',
                          subtitle: 'Muster, Beispiele und Tipps',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                  builder: (_) => const DictationHelpScreen())),
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B9EF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 18),
                          ),
                          title: 'Sprach-Log',
                          subtitle: 'Alle Diktiereingaben & Erkennungsrate',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                  builder: (_) => const SpeechLogScreen())),
                        ),
                        if (AuthService.instance.isAdmin)
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.auto_awesome_outlined, color: Colors.white, size: 18),
                            ),
                            title: 'Sprach-Analyse',
                            subtitle: 'Eingaben analysieren · Regeln lernen',
                            isLast: true,
                            trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                            onTap: () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                    builder: (_) => const AdminRulesScreen())),
                          )
                        else
                          const SizedBox.shrink(),
                      ]),
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: HOMESCREEN
// ─────────────────────────────────────────────────────────────────────────────

class _HomescreenSettingsScreen extends StatefulWidget {
  const _HomescreenSettingsScreen();

  @override
  State<_HomescreenSettingsScreen> createState() =>
      _HomescreenSettingsScreenState();
}

class _HomescreenSettingsScreenState extends State<_HomescreenSettingsScreen> {
  bool _weatherBig = false;
  bool _weatherUseGps = true;
  String _taskAddMode = 'dictate';
  String _weatherCity = '';
  late TextEditingController _cityCtrl;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _weatherBig = box.get('homescreen_weather_big', defaultValue: false) as bool;
    _weatherUseGps = box.get('weather_use_gps', defaultValue: true) as bool;
    _taskAddMode = box.get('homescreen_task_add_mode', defaultValue: 'dictate') as String;
    _weatherCity = box.get('weather_city', defaultValue: '') as String;
    _cityCtrl = TextEditingController(text: _weatherCity);
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    super.dispose();
  }

  void _showCityInputSheet(BuildContext context, AppSkin skin) {
  final ctrl = TextEditingController(text: _weatherCity);

  // ── State-Variablen AUSSERHALB des StatefulBuilder-builders ──────────
  bool isVerifying = false;
  String? verifiedLabel;
  String? errorMsg;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSheet(
        skin: skin,
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            // ── keine Deklarationen mehr hier! ─────────────────────────

            Future<void> doVerify() async {
              final input = ctrl.text.trim();
              if (input.isEmpty) return;
              setSheetState(() {
                isVerifying = true;
                errorMsg = null;
                verifiedLabel = null;
              });
              final result = await WeatherService.instance.verifyCityName(input);
              setSheetState(() {
                isVerifying = false;
                if (result != null) {
                  verifiedLabel = result;
                } else {
                  errorMsg = 'Stadt nicht gefunden. Bitte prüfe die Schreibweise.';
                }
              });
            }

            void saveAndClose(String label) {
              setState(() => _weatherCity = ctrl.text.trim());
              _set('weather_city', ctrl.text.trim());
              WeatherService.instance.invalidateCache();
              Navigator.pop(context);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: SheetHandle(skin: skin)),
                  const SizedBox(height: 16),
                  Text('Stadt eingeben',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                          color: skin.textPrimary)),
                  const SizedBox(height: 4),
                  Text('Das Wetter wird für diese Stadt geladen.',
                      style: TextStyle(fontSize: 13, color: skin.textMuted)),
                  const SizedBox(height: 16),
                  _TiTextField(
                    skin: skin,
                    controller: ctrl,
                    hint: 'z.B. Berlin, München, Hamburg',
                    onChanged: (_) => setSheetState(() {
                      verifiedLabel = null;
                      errorMsg = null;
                    }),
                    onSubmitted: (_) => doVerify(),
                  ),

                  // ── Bestätigung / Fehler ──────────────────────────────
                  if (isVerifying) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: skin.primary),
                        ),
                        const SizedBox(width: 10),
                        Text('Prüfe Ort…',
                            style: TextStyle(fontSize: 13, color: skin.textMuted)),
                      ],
                    ),
                  ],
                  if (verifiedLabel != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3DD68C).withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline_rounded,
                              size: 16, color: Color(0xFF3DD68C)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Gefunden: $verifiedLabel',
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFF3DD68C),
                                    fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (errorMsg != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: skin.deleteColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.deleteColor.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded, size: 16, color: skin.deleteColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(errorMsg!,
                                style: TextStyle(
                                    fontSize: 12.5, color: skin.deleteColor, height: 1.4)),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // ── Buttons ───────────────────────────────────────────
                  if (verifiedLabel == null)
                    GestureDetector(
                      onTap: isVerifying ? null : doVerify,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: skin.primary.withValues(alpha: skin.isLight ? 0.12 : 0.20),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: skin.primary.withValues(alpha: skin.isLight ? 0.30 : 0.45)),
                        ),
                        child: Center(
                          child: Text('Prüfen',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: skin.primary)),
                        ),
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => saveAndClose(verifiedLabel!),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DD68C).withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF3DD68C).withValues(alpha: 0.45)),
                        ),
                        child: const Center(
                          child: Text('Übernehmen',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                  color: Color(0xFF3DD68C))),
                        ),
                      ),
                    ),

                  // Fallback: trotzdem ohne Prüfung speichern (falls API down/Ort exotisch)
                  if (errorMsg != null) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: GestureDetector(
                        onTap: () => saveAndClose(ctrl.text.trim()),
                        child: Text('Trotzdem speichern',
                            style: TextStyle(
                                fontSize: 12.5,
                                color: skin.textMuted,
                                fontWeight: FontWeight.w500,
                                decoration: TextDecoration.underline)),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    ),
  );
}

  void _set(String key, dynamic value) =>
      Hive.box('einstellungen').put(key, value);

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Startbildschirm', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Wetter ────────────────────────────────────────
                    const _SectionHeader(label: 'Wetter'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB347),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.wb_sunny_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Wetter als große Kachel',
                          subtitle: 'Zeigt mehr Wetterinformationen',
                          switchValue: _weatherBig,
                          onSwitchChanged: (v) {
                            setState(() => _weatherBig = v);
                            _set('homescreen_weather_big', v);
                          },
                        ),
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B9EF5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.location_on_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Per GPS-Standort',
                          subtitle: 'Automatisch aktueller Standort',
                          switchValue: _weatherUseGps,
                          onSwitchChanged: (v) {
  setState(() => _weatherUseGps = v);
  _set('weather_use_gps', v);
  WeatherService.instance.invalidateCache();   // ← einheitlich, egal ob v true oder false
},
                          isLast: _weatherUseGps,
                        ),
                        if (!_weatherUseGps)
                          GlassListItem(
                            leading: Container(
                              width: 32, height: 32,
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B8B9E),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.location_city_outlined, color: Colors.white, size: 18),
                            ),
                            title: 'Stadt',
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _weatherCity.isNotEmpty ? _weatherCity : 'nicht gesetzt',
                                  style: TextStyle(fontSize: 14, color: skin.textMuted),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                              ],
                            ),
                            isLast: true,
                            onTap: () => _showCityInputSheet(context, skin),
                          ),
                      ]),
                    ),
                    _SectionFootnote(
                      text: _weatherUseGps
                          ? 'Wetter wird per GPS geladen — immer aktuell für deinen Standort.'
                          : 'Wetter wird für die eingetragene Stadt geladen.',
                    ),

                    const SizedBox(height: 24),

                    // ── Aufgabe hinzufügen ────────────────────────────
                    const _SectionHeader(label: 'Aufgabe hinzufügen'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3DD68C),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.mic_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Diktieren',
                          subtitle: 'Nutzt Schnell-Diktieren Funktion statt manuellem Formular',
                          isLast: true,
                          switchValue: _taskAddMode == 'dictate',
                          onSwitchChanged: (v) {
                            final mode = v ? 'dictate' : 'sheet';
                            setState(() => _taskAddMode = mode);
                            _set('homescreen_task_add_mode', mode);
                          },
                        ),
                      ]),
                    ),
                    const _SectionFootnote(
                      text: 'Mit Diktieren: langer Druck auf + öffnet direkt das Mikrofon. '
                            'Ohne: tippt direkt das Formular auf.',
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

// ─────────────────────────────────────────────────────────────────────────────
// DEBUG-KARTE: REISEMODUS SIMULIEREN
// ─────────────────────────────────────────────────────────────────────────────

class _ReisemodusDebugCard extends StatefulWidget {
  final VoidCallback onChanged;
  const _ReisemodusDebugCard({required this.onChanged});

  @override
  State<_ReisemodusDebugCard> createState() => _ReisemodusDebugCardState();
}

class _ReisemodusDebugCardState extends State<_ReisemodusDebugCard> {
  static const _zones = {
    'Berlin (Home)': 'Europe/Berlin',
    'New York': 'America/New_York',
    'Los Angeles': 'America/Los_Angeles',
    'Tokio': 'Asia/Tokyo',
  };

  bool _checking = false;

  Future<void> _setOverride(String? tzId) async {
    TravelModeService.setDebugOverrideTz(tzId);
    setState(() {});
    widget.onChanged();
  }

  Future<void> _triggerCheck() async {
    setState(() => _checking = true);
    final detected = await TravelModeService.checkForTimeZoneChange();
    if (!mounted) return;
    setState(() => _checking = false);
    final skin = AppTheme.of(context);

    if (detected == null) {
      showGlassSnackBar(context, 'Keine neue Zeitzone erkannt (identisch mit aktiver Zone).',
          type: GlassSnackBarType.warning);
      return;
    }
    final label = TravelModeService.offsetLabelFor(detected);
    final confirmed = await confirmActionDialog(
      context: context,
      skin: skin,
      icon: Icons.flight_takeoff_rounded,
      title: '✈️ Neue Zeitzone erkannt',
      message: 'Simuliert: $detected ($label)\n\n'
          'Jetzt als aktive Zone übernehmen?',
      confirmLabel: 'Übernehmen',
      cancelLabel: 'Verwerfen',
    );
    if (confirmed == true) {
      await TravelModeService.setActiveTz(detected);
    }
    setState(() {});
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final override = TravelModeService.debugOverrideTz;

    return _TiCard(
      skin: skin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TiCardHeader(skin: skin, icon: Icons.bug_report_outlined, label: 'Zeitzone simulieren'),
          const SizedBox(height: 10),
          Text(
            'Überschreibt die erkannte Geräte-Zeitzone zum Testen, unabhängig vom echten Standort.',
            style: TextStyle(fontSize: 12.5, color: skin.textMuted, height: 1.4),
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _zones.entries.map((e) {
              final isActive = override == e.value;
              return GestureDetector(
                onTap: () => _setOverride(e.value),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive
                        ? skin.primary.withValues(alpha: 0.20)
                        : skin.surface(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: isActive ? skin.primary : skin.borderSubtle),
                  ),
                  child: Text(e.key,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                          color: isActive ? skin.primary : skin.textPrimary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => _setOverride(null),
            child: Text('Override zurücksetzen (echtes Gerät nutzen)',
                style: TextStyle(
                    fontSize: 12.5,
                    color: skin.textMuted,
                    decoration: TextDecoration.underline)),
          ),

          const SizedBox(height: 16),
          GlassPrimaryButton(
            skin: skin,
            label: _checking ? 'Prüfe…' : 'Jetzt Zeitzonen-Check auslösen',
            icon: Icons.refresh_rounded,
            onTap: _checking ? () {} : _triggerCheck,
          ),

          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: skin.surface(0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: TravelModeService.debugSnapshot.entries.map((e) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(e.key,
                            style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                      ),
                      Expanded(
                        child: Text(e.value,
                            style: TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'monospace',
                                color: skin.textPrimary,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}