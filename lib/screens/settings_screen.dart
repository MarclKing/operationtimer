import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';
import '../models/relationship_style.dart';
import '../services/notification_service.dart';
import '../screens/welcome_screen.dart' show RelationshipOptionCard, showReadOnlyModeWelcome;
import '../widgets/glass_pickers.dart' show IOSTimePicker;
import '../screens/dictation_help_screen.dart';
import '../screens/speech_log_screen.dart';
import '../screens/admin_rules_screen.dart';
import 'package:OpTimes/main.dart';
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
import '../services/event_group_store.dart';
import '../models/calendar_event.dart';
import '../services/sync_service.dart';
import '../services/calendar_sync_handshake.dart';
import 'dart:convert';
import '../services/apple_calendar_sync_service.dart';


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

    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(keys: ['name', 'read_only_mode']),
      builder: (context, box, _) {
        final name = box.get('name', defaultValue: '') as String;
        final readOnly = box.get('read_only_mode', defaultValue: false) as bool;

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
                            if (!readOnly)
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
                            if (AuthService.instance.isAdmin)
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
                                subtitle: 'Entwickler-Modus',
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
                              title: 'Kalender & Aufgaben',
                              subtitle: 'Gruppen · Diktat · Sprach-Analyse',
                              trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                              onTap: () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) => const TasksDictationSettingsScreen()),
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
                          child: Text('OpTimes v1.4.2',
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
      },
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
  final bool autoCapitalizeFirst;

  const _TiTextField({
    required this.skin,
    required this.controller,
    required this.hint,
    this.onChanged,
    this.onSubmitted,
    this.autoCapitalizeFirst = false,
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
        textCapitalization: autoCapitalizeFirst
            ? TextCapitalization.sentences
            : TextCapitalization.none,
        inputFormatters: autoCapitalizeFirst
            ? [_FirstLetterUppercaseFormatter()]
            : null,
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

/// Erzwingt Großbuchstaben am Anfang — greift auch bei Autokorrektur/
/// Diktat, wo textCapitalization allein (nur Tastatur-Hinweis) nicht reicht.
class _FirstLetterUppercaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (newValue.text.isEmpty) return newValue;
    final text = newValue.text;
    final capitalized = text[0].toUpperCase() + text.substring(1);
    if (capitalized == text) return newValue;
    return newValue.copyWith(text: capitalized, selection: newValue.selection);
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

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isReader = role == 'reader';
    final color = isReader ? const Color(0xFF3DD6C8) : const Color(0xFF5B8DEF);
    final icon = isReader ? Icons.link_rounded : Icons.smartphone_rounded;
    final label = isReader ? 'Verknüpftes Gerät (Kopie)' : 'Hauptgerät';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
      ]),
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
  final String? role;

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
    required this.role,
  });

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (role != null) _RoleBadge(role: role!),
          if (role != null) const SizedBox(height: 12),
          // Header
          Row(
            children: [
              Icon(
                role == 'reader' ? Icons.link_rounded : Icons.sync_rounded,
                size: 18,
                color: role == 'reader' ? const Color(0xFF3DD6C8) : skin.primary,
              ),
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
  late RelationshipStyle _selectedStyle;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    final name = box.get('name', defaultValue: '') as String;
    _nameController = TextEditingController(text: name);
    _selectedStyle = RelationshipStyleStore.load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _selectStyle(RelationshipStyle style) {
    setState(() => _selectedStyle = style);
    RelationshipStyleStore.save(style);
    HapticFeedback.selectionClick();
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
                    const _SectionHeader(label: 'Persönliche Daten'),
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(skin: skin, icon: Icons.person_outline_rounded, label: 'Name'),
                          const SizedBox(height: 12),
                          Text('Dein Name wird in Benachrichtigungen und im Dienstplan verwendet.',
                              style: TextStyle(fontSize: 13, color: skin.textMuted, height: 1.5)),
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
                              case RelationshipStyle.bro: return 'Locker';
                              case RelationshipStyle.vorname: return 'Vorname';
                              case RelationshipStyle.familie: return 'Formell';
                            }
                          },
                          items: [
                            GlassDropdownItem(value: RelationshipStyle.bro, label: 'Locker', icon: Icons.bolt_rounded),
                            GlassDropdownItem(value: RelationshipStyle.vorname, label: 'Normal', icon: Icons.waving_hand_outlined),
                            GlassDropdownItem(value: RelationshipStyle.familie, label: 'Formell', icon: Icons.workspace_premium_outlined),
                          ],
                          onChanged: _selectStyle,
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
  late bool _eveningEnabled;
  late TimeOfDay _eveningTime;
  late bool _showAllDayBanner; // NEU

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
    _eveningEnabled = DailyOverviewSettings.eveningPreviewEnabled;
    _showAllDayBanner = Hive.box('einstellungen')
        .get('notif_center_show_allday_banner', defaultValue: true) as bool; // NEU
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

  void _setShowAllDayBanner(bool v) {
    setState(() => _showAllDayBanner = v);
    Hive.box('einstellungen').put('notif_center_show_allday_banner', v);
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

                    const SizedBox(height: 24),
                    const _SectionHeader(label: 'Benachrichtigungscenter'),
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        GlassListItem(
                          leading: Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(
                              color: const Color(0xFF8B5CF6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.view_day_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Ganztägige Termine als Banner',
                          subtitle: 'Sonst als normaler Eintrag unter Kalender',
                          isLast: true,
                          switchValue: _showAllDayBanner,
                          onSwitchChanged: _setShowAllDayBanner,
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
                    const _SectionHeader(label: 'Rundung'),
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
                    const SizedBox(height: 20),
                    const _SectionHeader(label: 'Modi'),
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
// SYNC TOKEN & READ ONLY SECTION
// ─────────────────────────────────────────────────────────────────────────────

class _SyncTokenAndReadOnlySection extends StatefulWidget {
  const _SyncTokenAndReadOnlySection();
  @override
  State<_SyncTokenAndReadOnlySection> createState() => _SyncTokenAndReadOnlySectionState();
}

class _SyncTokenAndReadOnlySectionState extends State<_SyncTokenAndReadOnlySection> {
  late TextEditingController _tokenInputController;
  String? _syncToken;
  bool _isGenerating = false;
  bool _isLinking = false;
  bool _showTokenInput = false;
  String? _linkFeedback;
  bool _linkSuccess = false;
  bool _readOnlyMode = false;

  bool get _canUseReadOnlyMode =>
      _readOnlyMode || (_syncToken != null && SyncTokenService.role == 'reader');

  @override
  void initState() {
    super.initState();
    _tokenInputController = TextEditingController();
    _readOnlyMode = Hive.box('einstellungen').get('read_only_mode', defaultValue: false) as bool;
    _loadToken();
  }

  Future<void> _loadToken() async {
    final token = SyncTokenService.instance.localToken;
    if (mounted) setState(() => _syncToken = token);
  }

  @override
  void dispose() {
    _tokenInputController.dispose();
    super.dispose();
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

    // NEU: Sicherheits-Reset — verhindert den Datenverlust-Bug, bei dem
    // ein aktiver Apple-Import nach einer Token-Verknüpfung dauerhaft
    // leer blieb (verwaiste Apple-Mappings nach einem späteren
    // Lesemodus-Reset). Betrifft NUR die OpTimes-seitige Kopie — die
    // echten Termine im Apple-Kalender bleiben unberührt.
    if (AppleCalendarSyncService.instance.hasAnyAppleLink) {
      final skin = AppTheme.of(context);
      final confirmed = await confirmActionDialog(
        context: context,
        skin: skin,
        icon: Icons.apple,
        title: 'Apple-Kalender-Freigabe zurücksetzen?',
        message: 'Diese Verknüpfung setzt die aktive "Mit Apple-Kalender '
            'teilen"-Einstellung zurück und entfernt alle bisher importierten '
            'Apple-Termine aus OpTimes. Deine Termine im echten Apple-Kalender '
            'bleiben davon unberührt. Du kannst die Freigabe danach im '
            'Lesemodus jederzeit wieder aktivieren.',
        cancelLabel: 'Abbrechen',
        confirmLabel: 'Zurücksetzen & verknüpfen',
      );
      if (confirmed != true) return;
      await AppleCalendarSyncService.instance.disconnectAllForSafeReset();
    }

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
        _readOnlyMode = false;
      });
    }
  }

  void _copyToken() {
    if (_syncToken == null) return;
    Clipboard.setData(ClipboardData(text: _syncToken!));
    HapticFeedback.lightImpact();
    setState(() { _linkSuccess = true; _linkFeedback = '✓ Token kopiert!'; });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _linkFeedback = null);
    });
  }

  void _shareToken() {
    if (_syncToken == null) return;
    Share.share(
      'Mein OpTimes Sync-Token: $_syncToken\n\nGib diesen Token in OpTimes unter Einstellungen → Datenverwaltung → Geräte-Synchronisation ein, um unsere Daten zu synchronisieren.',
      subject: 'OpTimes Sync-Token',
    );
  }

  Future<void> _confirmEnableReadOnly() async {
    final skin = AppTheme.of(context);
    final confirmed = await confirmActionDialog(
      context: context,
      skin: skin,
      icon: Icons.visibility_outlined,
      title: 'Lesemodus aktivieren?',
      message: 'Zeigt nur noch den Dienstplan zum Ansehen. Arbeitszeiterfassung, '
          'Monat, Fahrtenbuch und Backup/Export werden ausgeblendet. Aufgaben '
          'und Kalender laufen ab jetzt getrennt vom Original.\n\n'
          'Deaktivieren nur mit Code möglich.',
      cancelLabel: 'Abbrechen',
      confirmLabel: 'Aktivieren',
    );
    if (confirmed != true) return;

    // NEU (Punkt 5): Splash SOFORT über den kompletten Navigator legen —
    // verdeckt den kompletten Umbau (Reset, Pop, Tab-Wechsel), damit der
    // Nutzer keine Zwischenzustände sieht.
    final navContext = MyApp.navigatorKey.currentContext;
    if (navContext == null) return;

    Navigator.of(navContext).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => const _ReadOnlyActivationSplash(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 180),
      ),
    );
    await Future.delayed(const Duration(milliseconds: 80));

    await Hive.box('einstellungen').put('read_only_mode', true);
    SyncService.instance.onReadOnlyModeChanged();
    TaskStore.saveAll([]);
    TaskStore.changesSignal.value++;
    await AppleCalendarSyncService.instance.disconnectAllForSafeReset(); // NEU
    CalendarEventStore.resetLocal();
    EventGroupStore.resetToDefaultsLocal();
    if (mounted) setState(() => _readOnlyMode = true);

    // Mindestanzeigedauer, damit der Splash nicht flackert.
    await Future.delayed(const Duration(milliseconds: 500));

    final rootContext = MyApp.navigatorKey.currentContext;
    if (rootContext == null) return;
    Navigator.of(rootContext).popUntil((route) => route.isFirst);
    MyApp.mainScreenKey.currentState?.goToHomeTab();

    await Future.delayed(const Duration(milliseconds: 150));
    final freshContext = MyApp.navigatorKey.currentContext;
    if (freshContext != null) await showReadOnlyModeWelcome(freshContext);
  }

  void _showDisableReadOnlyCodeSheet() {
    final skin = AppTheme.of(context);
    final ctrl = TextEditingController();
    String? error;

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
              void tryUnlock() {
                if (ctrl.text.trim() == '1951') {
                  final token = SyncTokenService.instance.localToken;
                  if (token != null && CalendarSyncHandshake.instance.state.value != CalendarSyncState.off) {
                    CalendarSyncHandshake.instance.disconnect(token);
                  }
                  Hive.box('einstellungen').put('read_only_mode', false);
                  Navigator.pop(context);
                  if (mounted) setState(() => _readOnlyMode = false);
                  SyncService.instance.restoreFullMirrorAfterReadOnlyDisabled();
                } else {
                  setSheetState(() => error = 'Falscher Code.');
                }
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: SheetHandle(skin: skin)),
                    const SizedBox(height: 16),
                    Text('Lesemodus deaktivieren',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Bitte Code eingeben.', style: TextStyle(fontSize: 13, color: skin.textMuted)),
                    if (CalendarSyncHandshake.instance.state.value != CalendarSyncState.off) ...[
                      const SizedBox(height: 4),
                      Text('Kalender-Sync wird dabei ebenfalls beendet.',
                          style: TextStyle(fontSize: 11.5, color: skin.textMuted)),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: skin.surface(0.05),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: skin.borderSubtle),
                      ),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: TextStyle(color: skin.textPrimary, fontSize: 20, letterSpacing: 4, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          hintText: '••••',
                          hintStyle: TextStyle(color: skin.textHint, fontSize: 20, letterSpacing: 4),
                          border: InputBorder.none, isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onSubmitted: (_) => tryUnlock(),
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: TextStyle(fontSize: 12.5, color: skin.deleteColor)),
                    ],
                    const SizedBox(height: 16),
                    GlassPrimaryButton(skin: skin, label: 'Entsperren', onTap: tryUnlock),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          onToggleInput: () => setState(() { _showTokenInput = !_showTokenInput; _linkFeedback = null; }),
          onLink: _linkToken,
          onUnlink: _unlinkToken,
          role: SyncTokenService.role,
        ),
        const SizedBox(height: 8),
        const _SectionFootnote(
          text: 'Der Sync-Token ist dein persönlicher Schlüssel. Teile ihn nur mit Geräten, die du selbst verwendest. Wer den Token kennt, hat Lesezugriff auf deine Daten.',
        ),

        if (_syncToken != null && SyncTokenService.role == 'original')
          ValueListenableBuilder<int>(
            valueListenable: SyncService.instance.pendingConflictsCount,
            builder: (context, count, _) {
              if (count == 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 16),
                child: GlassSurface(
                  borderRadius: 18,
                  padding: EdgeInsets.zero,
                  child: GlassListItem(
                    leading: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: const Color(0xFFFFB347), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 18),
                    ),
                    title: 'Sync-Konflikte',
                    subtitle: '$count offene Änderung(en) vom Kopiergerät',
                    isLast: true,
                    trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                    onTap: () => Navigator.push(context, CupertinoPageRoute(builder: (_) => const SyncConflictsScreen())),
                  ),
                ),
              );
            },
          ),

        if (_canUseReadOnlyMode) ...[
          const SizedBox(height: 24),
          const _SectionHeader(label: 'Lesemodus'),
          GlassSurface(
            borderRadius: 18,
            padding: EdgeInsets.zero,
            child: Column(children: [
              if (!_readOnlyMode)
                GlassListItem(
                  leading: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF8B8B9E), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.visibility_outlined, color: Colors.white, size: 18),
                  ),
                  title: 'Lesemodus aktivieren',
                  subtitle: 'Dienstplan schreibgeschützt anzeigen',
                  isLast: true,
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                  onTap: _confirmEnableReadOnly,
                )
              else
                GlassListItem(
                  leading: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFFEF5B5B), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.lock_outline_rounded, color: Colors.white, size: 18),
                  ),
                  title: 'Lesemodus aktiv',
                  subtitle: 'Code erforderlich zum Deaktivieren',
                  isLast: true,
                  trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                  onTap: _showDisableReadOnlyCodeSheet,
                ),
            ]),
          ),
          if (_readOnlyMode) ...[
            const SizedBox(height: 8),
            const _SectionFootnote(
              text: 'Nur Dienstplan-Ansicht aktiv. Monat & Fahrtenbuch sind ausgeblendet, Aufgaben bleiben voll nutzbar.',
            ),
          ],
        ],

        if (AuthService.instance.isAdmin) ...[
          const SizedBox(height: 20),
          Center(
            child: Text('Admin · Lesemodus-Code: 1951',
                style: TextStyle(fontSize: 11, color: skin.textMuted, fontWeight: FontWeight.w600)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPLASH BEIM AKTIVIEREN DES LESEMODUS (Punkt 5)
// ─────────────────────────────────────────────────────────────────────────────

class _ReadOnlyActivationSplash extends StatelessWidget {
  const _ReadOnlyActivationSplash();

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.visibility_outlined, color: skin.primary, size: 48),
            const SizedBox(height: 22),
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: skin.primary),
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
      confirmLabel: 'Importieren',
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
    final readOnly = box.get('read_only_mode', defaultValue: false) as bool;

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
                    const _SyncTokenAndReadOnlySection(),
                    const SizedBox(height: 24),
                    const _SectionHeader(label: 'Aufbewahrung'),

                    if (!readOnly) ...[
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
                    ],

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

                    if (!readOnly) ...[
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
                    ],

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

                    if (!readOnly) ...[
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
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        // NEU: feste Zeilenhöhe statt Aspect Ratio — verhindert
                        // Overflow unabhängig von der Bildschirmbreite, da die
                        // Höhe exakt zum Karteninhalt (Mockup + Footer) passt.
                        mainAxisExtent: 178,
                      ),
                      itemCount: skins.length,
                      itemBuilder: (context, i) {
                        final s = skins[i];
                        return _SkinPreviewCard(
                          previewSkin: s,
                          isSelected: s.key == _activeSkin,
                          onTap: () => _setSkin(s.key),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
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
// SKIN-VORSCHAU-KARTE (Mini-UI-Mockup pro Design)
// ─────────────────────────────────────────────────────────────────────────────

class _SkinPreviewCard extends StatelessWidget {
  final AppSkin previewSkin;
  final bool isSelected;
  final VoidCallback onTap;

  const _SkinPreviewCard({
    required this.previewSkin,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final radius = BorderRadius.circular(18);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(
            color: isSelected ? skin.primary : skin.glassBorder,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: skin.primary.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 4)),
                ]
              : [],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SkinMockupUI(previewSkin: previewSkin),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: skin.isLight
                    ? Colors.white.withValues(alpha: skin.glassOpacity)
                    : skin.bgCard.withValues(alpha: skin.glassOpacity),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        previewSkin.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: isSelected ? skin.primary : skin.textPrimary,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded,
                          size: 16, color: skin.primary)
                    else
                      Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: skin.surface(0.25), width: 1.5),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reines Balken-Mockup — keine echten Icons/Texte, nur Formen in den
/// Farben des jeweiligen Skins (wie FL Studios Theme-Vorschau).
class _SkinMockupUI extends StatelessWidget {
  final AppSkin previewSkin;
  const _SkinMockupUI({required this.previewSkin});

  Widget _bar({
    required double width,
    required double height,
    required Color color,
    double radius = 3,
  }) {
    return Container(
      width: width,
      height: height,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
    );
  }

  Widget _row({
    required Color iconColor,
    required double titleWidth,
    required double subtitleWidth,
  }) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
              color: iconColor, borderRadius: BorderRadius.circular(5)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _bar(
                width: titleWidth,
                height: 6,
                color: previewSkin.textPrimary
                    .withValues(alpha: previewSkin.isLight ? 0.65 : 0.55),
              ),
              const SizedBox(height: 4),
              _bar(
                width: subtitleWidth,
                height: 4.5,
                color: previewSkin.textMuted.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // NEU: keine feste Höhe + Expanded mehr — der Inhalt bestimmt seine
    // Höhe selbst (mainAxisSize.min). Das verhindert Overflow zuverlässig,
    // unabhängig von künftigen Anpassungen an Zeilen/Abständen.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      color: previewSkin.bgBase,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Kopfzeile: Avatar-Kreis · Titel-Balken · sekundärer Chip
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                decoration:
                    BoxDecoration(color: previewSkin.primary, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              _bar(
                width: 46,
                height: 7,
                color: previewSkin.textPrimary
                    .withValues(alpha: previewSkin.isLight ? 0.7 : 0.6),
              ),
              const Spacer(),
              _bar(
                width: 14,
                height: 14,
                color: previewSkin.secondary.withValues(alpha: 0.55),
                radius: 4,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // "Card"-Fläche mit zwei Listen-Zeilen-Platzhaltern
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 9),
            decoration: BoxDecoration(
              color: previewSkin.bgCard
                  .withValues(alpha: previewSkin.isLight ? 0.9 : 0.7),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: previewSkin.borderSubtle),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _row(iconColor: previewSkin.primary, titleWidth: 40, subtitleWidth: 28),
                const SizedBox(height: 6),
                _row(
                    iconColor: previewSkin.statComplete,
                    titleWidth: 34,
                    subtitleWidth: 22),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Primär-Button-Platzhalter
          _bar(
            width: double.infinity,
            height: 10,
            color: previewSkin.primary
                .withValues(alpha: previewSkin.isLight ? 0.30 : 0.42),
            radius: 6,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KALENDER-SYNC KARTE
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarSyncCard extends StatefulWidget {
  final AppSkin skin;
  const _CalendarSyncCard({required this.skin});

  @override
  State<_CalendarSyncCard> createState() => _CalendarSyncCardState();
}

class _CalendarSyncCardState extends State<_CalendarSyncCard> {
  String? get _token => SyncTokenService.instance.localToken;
  bool get _readOnly => Hive.box('einstellungen').get('read_only_mode', defaultValue: false) as bool;

  Future<void> _confirmDisconnect(String token) async {
    final skin = widget.skin;
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Kalender-Sync trennen?',
      message: 'Die Verbindung wird auf beiden Geräten beendet. Beide Seiten müssen '
          'erneut zustimmen, um wieder zu synchronisieren.',
      confirmLabel: 'Trennen',
    );
    if (confirmed == true) {
      await CalendarSyncHandshake.instance.disconnect(token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final token = _token;
    if (token == null) return const SizedBox.shrink();

    return ValueListenableBuilder<CalendarSyncState>(
      valueListenable: CalendarSyncHandshake.instance.state,
      builder: (context, state, _) {
        final isReader = SyncTokenService.role == 'reader';
        final isOriginal = SyncTokenService.role == 'original';
        if (!isReader && !isOriginal) return const SizedBox.shrink();

        // ── Verbunden: für beide Seiten identisch (grün, Pairing-Symbol) ──
        if (state == CalendarSyncState.active) {
          return GlassSurface(
            borderRadius: 18,
            padding: EdgeInsets.zero,
            child: GlassListItem(
              leading: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFF3DD68C), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.link_rounded, color: Colors.white, size: 18),
              ),
              title: 'Kalender synchronisieren',
              subtitle: isReader ? 'Verbunden mit Original' : 'Verbunden mit Lesemodus-Gerät',
              isLast: true,
              trailing: GestureDetector(
                onTap: () => _confirmDisconnect(token),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: skin.deleteColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.close_rounded, size: 16, color: skin.deleteColor),
                ),
              ),
            ),
          );
        }

        // ── Lesemodus-Gerät: wartet auf Bestätigung → Pending-Punkte ─────
        if (isReader && state == CalendarSyncState.waitingForApproval) {
          return GlassSurface(
            borderRadius: 18,
            padding: EdgeInsets.zero,
            child: GlassListItem(
              leading: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFF3DD6C8), borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
              ),
              title: 'Kalender synchronisieren',
              subtitle: 'Warte auf Bestätigung des Original-Geräts',
              isLast: true,
              trailing: const _PendingDots(),
            ),
          );
        }

        // ── Lesemodus-Gerät: aus → Schalter zum Anfragen (wie bisher) ────
        if (isReader) {
          final enabled = _readOnly;
          return Opacity(
            opacity: enabled ? 1.0 : 0.4,
            child: IgnorePointer(
              ignoring: !enabled,
              child: GlassSurface(
                borderRadius: 18,
                padding: EdgeInsets.zero,
                child: GlassListItem(
                  leading: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF3DD6C8), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                  ),
                  title: 'Kalender synchronisieren',
                  subtitle: enabled ? 'Kalender-Gruppen mit "Sync" teilen' : 'Nur im Lesemodus verfügbar',
                  isLast: true,
                  switchValue: false,
                  onSwitchChanged: (v) {
                    HapticFeedback.selectionClick();
                    CalendarSyncHandshake.instance.setReaderRequest(token, v);
                  },
                ),
              ),
            ),
          );
        }

        // ── Original: angefragt → deutliche Handlungsaufforderung
        if (isOriginal && state == CalendarSyncState.waitingForApproval) {
          return GlassSurface(
            borderRadius: 18,
            padding: const EdgeInsets.all(14),
            borderColor: skin.primary.withValues(alpha: 0.5),
            borderWidth: 1.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(color: const Color(0xFF3DD6C8), borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Kalender synchronisieren', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                        const SizedBox(height: 2),
                        Text('Lesemodus-Gerät möchte Kalender teilen', style: TextStyle(fontSize: 12, color: skin.textMuted)),
                      ],
                    ),
                  ),
                  const _PendingDots(),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        CalendarSyncHandshake.instance.setOriginalApproval(token, false);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: skin.surface(0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.borderSubtle),
                        ),
                        child: Center(child: Text('Ablehnen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textMuted))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.mediumImpact();
                        CalendarSyncHandshake.instance.setOriginalApproval(token, true);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3DD6C8).withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF3DD6C8).withValues(alpha: 0.5)),
                        ),
                        child: const Center(child: Text('Bestätigen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF3DD6C8)))),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          );
        }

        // ── Original: aus → ausgegraut, wie bisher ───────────────────────
        return Opacity(
          opacity: 0.4,
          child: IgnorePointer(
            ignoring: true,
            child: GlassSurface(
              borderRadius: 18,
              padding: EdgeInsets.zero,
              child: GlassListItem(
                leading: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: const Color(0xFF3DD6C8), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                ),
                title: 'Kalender synchronisieren',
                subtitle: 'Warte auf Anfrage vom Lesemodus-Gerät',
                isLast: true,
                switchValue: false,
                onSwitchChanged: (_) {},
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── 3 pulsierende Punkte, solange eine Sync-Bestätigung aussteht ─────────
class _PendingDots extends StatefulWidget {
  const _PendingDots();
  @override
  State<_PendingDots> createState() => _PendingDotsState();
}

class _PendingDotsState extends State<_PendingDots> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final t = ((_ctrl.value - i * 0.2) % 1.0 + 1.0) % 1.0;
            final pulse = (1 - (t - 0.5).abs() * 2).clamp(0.0, 1.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: 0.4 + 0.6 * pulse,
                child: Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: skin.primary),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Kalender Sync Footnote
// ─────────────────────────────────────────────────────────────────────────────
class _CalendarSyncFootnote extends StatelessWidget {
  const _CalendarSyncFootnote();

  @override
  Widget build(BuildContext context) {
    final token = SyncTokenService.instance.localToken;
    if (token == null) return const SizedBox.shrink();

    return ValueListenableBuilder<CalendarSyncState>(
      valueListenable: CalendarSyncHandshake.instance.state,
      builder: (context, state, _) {
        final isReader = SyncTokenService.role == 'reader';
        final isOriginal = SyncTokenService.role == 'original';

        final bool active = isReader
            ? state != CalendarSyncState.off
            : isOriginal
                ? state == CalendarSyncState.active
                : false;

        if (!active) return const SizedBox.shrink();

        return const _SectionFootnote(
          text: 'Erlaubt es, ausgewählte Kalender-Gruppen (Scope "Sync") zwischen '
                'Original-Gerät und Lesemodus-Gerät zu teilen. Beide Seiten müssen '
                'zustimmen, bevor der Sync aktiv wird.',
        );
      },
    );
  }
}

class _DefaultEventGroupDropdown extends StatefulWidget {
  const _DefaultEventGroupDropdown();

  @override
  State<_DefaultEventGroupDropdown> createState() => _DefaultEventGroupDropdownState();
}

class _DefaultEventGroupDropdownState extends State<_DefaultEventGroupDropdown> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = EventGroupStore.defaultGroup().key;
  }

  @override
  Widget build(BuildContext context) {
    final groups = EventGroupStore.loadSelectable();
    // Falls die zuvor gewählte Standard-Gruppe zwischenzeitlich gelöscht
    // wurde, auf die erste verfügbare Gruppe zurückfallen.
    if (!groups.any((g) => g.key == _selected)) {
      _selected = groups.first.key;
    }
    return GlassSurface(
      borderRadius: 18,
      padding: EdgeInsets.zero,
      child: Column(children: [
        GlassDropdownButton<String>(
          value: _selected,
          label: 'Standard-Gruppe',
          subtitle: 'Vorausgewählt bei neuen Ereignissen',
          icon: Icons.label_outline_rounded,
          iconBg: const Color(0xFF2FD3C7),
          isLast: true,
          displayBuilder: (key) => EventGroupStore.byKey(key).name,
          items: groups.map((g) => GlassDropdownItem(value: g.key, label: g.name)).toList(),
          onChanged: (key) {
            setState(() => _selected = key);
            EventGroupStore.setDefaultGroupKey(key);
          },
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: AUFGABEN & KALENDER
// ─────────────────────────────────────────────────────────────────────────────

class TasksDictationSettingsScreen extends StatelessWidget {
  const TasksDictationSettingsScreen();

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isAdmin = AuthService.instance.isAdmin;
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Kalender & Aufgaben',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Kalender ──────────────────────────────────────
                    const _SectionHeader(label: 'Kalender'),
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
                            child: const Icon(Icons.palette_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Kalender-Gruppen verwalten',
                          subtitle: 'Eigene Gruppen anlegen, umbenennen, färben, löschen',
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(builder: (_) => const _EventGroupSettingsScreen())),
                        ),
                        _DefaultEventGroupRow(isLast: false),   // GEÄNDERT: war true
                        const _AppleCalendarSyncRow(isLast: true),  // <- HIER ist der Apple-Schalter
  ]),
                    ),

                    if (SyncTokenService.instance.localToken != null) ...[
                      const SizedBox(height: 14),
                      const _SectionHeader(label: 'Kalender-Synchronisation'),
                      _CalendarSyncCard(skin: skin),
                      const SizedBox(height: 8),
                      const _CalendarSyncFootnote(),
                    ],

                    const SizedBox(height: 24),

                    // ── Aufgaben & Diktieren ──────────────────────────
                    const _SectionHeader(label: 'Aufgaben & Diktieren'),
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
                          isLast: !isAdmin,
                          trailing: Icon(Icons.chevron_right_rounded, size: 18, color: skin.surface(0.28)),
                          onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                  builder: (_) => const SpeechLogScreen())),
                        ),
                        if (isAdmin)
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

/// NEU: dieselbe Standard-Gruppen-Auswahl wie zuvor, aber als schlanke Row
/// zum Einbetten in die "Kalender"-GlassSurface (statt eigener Card).
class _DefaultEventGroupRow extends StatefulWidget {
  final bool isLast;
  const _DefaultEventGroupRow({required this.isLast});

  @override
  State<_DefaultEventGroupRow> createState() => _DefaultEventGroupRowState();
}

class _DefaultEventGroupRowState extends State<_DefaultEventGroupRow> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = EventGroupStore.defaultGroup().key;
  }

  @override
  Widget build(BuildContext context) {
    final groups = EventGroupStore.loadSelectable();
    if (!groups.any((g) => g.key == _selected)) {
      _selected = groups.first.key;
    }
    return GlassDropdownButton<String>(
      value: _selected,
      label: 'Standard-Gruppe',
      subtitle: 'Vorausgewählt bei neuen Ereignissen',
      icon: Icons.label_outline_rounded,
      iconBg: const Color(0xFF2FD3C7),
      isLast: widget.isLast,
      displayBuilder: (key) => EventGroupStore.byKey(key).name,
      items: groups.map((g) => GlassDropdownItem(value: g.key, label: g.name)).toList(),
      onChanged: (key) {
        setState(() => _selected = key);
        EventGroupStore.setDefaultGroupKey(key);
      },
    );
  }
}

/// NEU: globaler "Mit Apple-Kalender teilen"-Schalter. Importiert beim
/// Aktivieren ALLE bestehenden Apple-Kalender als neue App-Gruppen und
/// hält sie danach laufend synchron (beide Richtungen).
class _AppleCalendarSyncRow extends StatefulWidget {
  final bool isLast;
  const _AppleCalendarSyncRow({required this.isLast});

  @override
  State<_AppleCalendarSyncRow> createState() => _AppleCalendarSyncRowState();
}

class _AppleCalendarSyncRowState extends State<_AppleCalendarSyncRow> {
  bool _loading = false;
  // NEU (Punkt 2): NICHT persistiert — lebt nur, solange dieser Screen
  // geöffnet ist. Verlässt der Nutzer die Einstellungen und kommt zurück,
  // ist der Vorschlag automatisch weg (neue State-Instanz). Erscheint
  // erst wieder nach erneutem Aktivieren + Deaktivieren.
  bool _justDisabled = false;
  bool _deleting = false;

  Future<void> _confirmDeleteImports() async {
    final skin = AppTheme.of(context);
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Apple-Importe löschen?',
      message: 'Löscht alle Termine, die über "Mit Apple-Kalender teilen" importiert wurden, '
          'sowie die dafür automatisch angelegten Gruppen. Deine Apple-Kalender selbst bleiben unangetastet.',
      confirmLabel: 'Löschen',
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    await AppleCalendarSyncService.instance.deleteAllGlobalImports();
    if (mounted) {
      setState(() { _deleting = false; _justDisabled = false; });
      showGlassSnackBar(context, '✓ Apple-Importe gelöscht', type: GlassSnackBarType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final linked = AppleCalendarSyncService.instance.isGloballyEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassListItem(
          leading: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.apple, color: Colors.white, size: 18),
          ),
          title: 'Mit Apple-Kalender teilen',
          subtitle: linked
              ? 'Aktiv — wird laufend synchronisiert'
              : 'Importiert alle Apple-Kalender & hält sie synchron',
          isLast: widget.isLast && !_justDisabled,
          trailing: _loading
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Switch(
                  value: linked,
                  onChanged: (v) async {
                    setState(() => _loading = true);
                    bool ok = true;
                    if (v) {
                      ok = await AppleCalendarSyncService.instance.enableGlobalSync();
                    } else {
                      await AppleCalendarSyncService.instance.disableGlobalSync();
                    }
                    if (mounted) {
                      setState(() {
                        _loading = false;
                        _justDisabled = !v && ok;
                      });
                    }
                    if (!ok && mounted) {
                      showGlassSnackBar(
                        context,
                        'Zugriff auf den Kalender wurde nicht erlaubt.',
                        type: GlassSnackBarType.warning,
                      );
                    }
                  },
                  activeThumbColor: skin.primary,
                ),
        ),
        if (_justDisabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: GestureDetector(
              onTap: _deleting ? null : _confirmDeleteImports,
              child: Row(
                children: [
                  if (_deleting)
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: skin.deleteColor))
                  else
                    Icon(Icons.delete_outline_rounded, size: 15, color: skin.deleteColor),
                  const SizedBox(width: 8),
                  Text('Importierte Apple-Termine jetzt löschen',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: skin.deleteColor)),
                ],
              ),
            ),
          ),
      ],
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
  bool _compactTiles = false;
  late TextEditingController _cityCtrl;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _weatherBig = box.get('homescreen_weather_big', defaultValue: false) as bool;
    _weatherUseGps = box.get('weather_use_gps', defaultValue: true) as bool;
    _taskAddMode = box.get('homescreen_task_add_mode', defaultValue: 'dictate') as String;
    _weatherCity = box.get('weather_city', defaultValue: '') as String;
    _compactTiles = box.get('homescreen_compact_tiles', defaultValue: false) as bool;
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
                    // NEU:
                    _TiTextField(
                      skin: skin,
                      controller: ctrl,
                      hint: 'z.B. Berlin, München, Hamburg',
                      autoCapitalizeFirst: true,
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
                            WeatherService.instance.invalidateCache();
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

                    // ── Kacheln (zusammengefasst) ────────────────────────
                    const _SectionHeader(label: 'Kacheln'),
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
                              color: const Color(0xFF8B8B9E),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.view_agenda_outlined, color: Colors.white, size: 18),
                          ),
                          title: 'Kleine Kacheln',
                          subtitle: 'Fahrtenbuch, Stempeluhr & Aufgabe kompakter — Aufgabenliste größer',
                          switchValue: _compactTiles,
                          onSwitchChanged: (v) {
                            setState(() => _compactTiles = v);
                            _set('homescreen_compact_tiles', v);
                          },
                        ),
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
                          subtitle: 'Nutzt Schnell-Diktieren statt manuellem Formular',
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
// UNTERMENÜ: KALENDER-GRUPPEN
// ─────────────────────────────────────────────────────────────────────────────

class _EventGroupSettingsScreen extends StatefulWidget {
  const _EventGroupSettingsScreen();
  @override
  State<_EventGroupSettingsScreen> createState() => _EventGroupSettingsScreenState();
}

class _EventGroupSettingsScreenState extends State<_EventGroupSettingsScreen> {
  static const _palette = [
    0xFF2D6CFF, 0xFF34C759, 0xFF2FD3C7, 0xFFFFB347,
    0xFFEF5B5B, 0xFF8B5CF6, 0xFF5B9EF5, 0xFF8B8B9E,
  ];

  List<EventGroupDef> get _groups => EventGroupStore.loadAll();

  void _showEditSheet({EventGroupDef? existing}) {
    final skin = AppTheme.of(context);
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    int selectedColor = existing?.colorValue ?? _palette.first;
    GroupScope selectedScope = existing?.scope ?? GroupScope.local;
    bool appleLinked = existing != null &&
        AppleCalendarSyncService.instance.isGroupAppleLinked(existing.key); // NEU
    bool appleLoading = false;  

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: GlassSheet(
          skin: skin,
          child: StatefulBuilder(
            builder: (context, setSheetState) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: SheetHandle(skin: skin)),
                  const SizedBox(height: 16),
                  Text(existing == null ? 'Neue Gruppe' : 'Gruppe bearbeiten',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: skin.textPrimary)),
                  const SizedBox(height: 16),
                  _TiTextField(skin: skin, controller: nameCtrl, hint: 'Name der Gruppe', autoCapitalizeFirst: true),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: _palette.map((c) {
                      final selected = selectedColor == c;
                      return GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() => selectedColor = c);
                        },
                        child: Container(
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: selected ? Border.all(color: skin.textPrimary, width: 2.5) : null,
                          ),
                          child: selected ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() => selectedScope = GroupScope.local);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: selectedScope == GroupScope.local
                                ? skin.primary.withValues(alpha: 0.14)
                                : skin.surface(0.05),
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
                            border: Border.all(
                              color: selectedScope == GroupScope.local
                                  ? skin.primary.withValues(alpha: 0.45)
                                  : skin.borderSubtle,
                            ),
                          ),
                          child: Center(
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.smartphone_rounded, size: 13,
                                  color: selectedScope == GroupScope.local ? skin.primary : skin.textMuted),
                              const SizedBox(width: 5),
                              Text('Lokal', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                                  color: selectedScope == GroupScope.local ? skin.primary : skin.textMuted)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setSheetState(() => selectedScope = GroupScope.sync);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 9),
                          decoration: BoxDecoration(
                            color: selectedScope == GroupScope.sync
                                ? skin.primary.withValues(alpha: 0.14)
                                : skin.surface(0.05),
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(10)),
                            border: Border.all(
                              color: selectedScope == GroupScope.sync
                                  ? skin.primary.withValues(alpha: 0.45)
                                  : skin.borderSubtle,
                            ),
                          ),
                          child: Center(
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.sync_rounded, size: 13,
                                  color: selectedScope == GroupScope.sync ? skin.primary : skin.textMuted),
                              const SizedBox(width: 5),
                              Text('Sync', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                                  color: selectedScope == GroupScope.sync ? skin.primary : skin.textMuted)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    selectedScope == GroupScope.sync
                        ? 'Termine dieser Gruppe werden mit dem Lesemodus-Gerät geteilt.'
                        : 'Termine dieser Gruppe bleiben nur auf diesem Gerät.',
                    style: TextStyle(fontSize: 10.5, color: skin.textMuted),
                  ),
                  // NEU: die feste Sammel-Gruppe "Apple" verwaltet ihre
                  // Apple-Verknüpfung ausschließlich über den globalen
                  // Schalter — kein zusätzlicher manueller Toggle hier.
                  if (existing != null && existing.key != AppleCalendarSyncService.appleImportGroupKey) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(Icons.apple, size: 16, color: skin.textMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Mit Apple-Kalender teilen',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: skin.textPrimary)),
                        ),
                        if (appleLoading)
                          SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: skin.primary),
                          )
                        else
                          Switch(
                            value: appleLinked,
                            onChanged: (v) async {
                              setSheetState(() => appleLoading = true);
                              bool success = true;
                              if (v) {
                                success = await AppleCalendarSyncService.instance.linkGroup(existing);
                              } else {
                                await AppleCalendarSyncService.instance.unlinkGroup(existing.key);
                              }
                              setSheetState(() {
                                appleLoading = false;
                                if (success) appleLinked = v;
                              });
                              if (!success && context.mounted) {
                                showGlassSnackBar(
                                  context,
                                  'Zugriff auf den Kalender wurde nicht erlaubt.',
                                  type: GlassSnackBarType.warning,
                                );
                              }
                            },
                            activeThumbColor: skin.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Legt einen eigenen Apple-Kalender „OpTimes – ${existing.name}" an und '
                      'gleicht Termine dieser Gruppe automatisch ab.',
                      style: TextStyle(fontSize: 10.5, color: skin.textMuted),
                    ),
                  ],

                  const SizedBox(height: 16),
                  GlassPrimaryButton(
                    skin: skin,
                    label: existing == null ? 'Anlegen' : 'Speichern',
                    onTap: () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) return;

                      // WICHTIG: Der Scope (Sync/Lokal) wirkt sich nur im
                      // Lesemodus-Handshake aus (siehe SyncService.
                      // pushCalendarEvent → _eventIsSyncScoped). Auf dem
                      // Original oder einem vollen Zweitgerät (Lesemodus
                      // aus) hat der Wechsel ohnehin keinen Effekt.
                      final isReadOnlyDevice = Hive.box('einstellungen')
                          .get('read_only_mode', defaultValue: false) as bool;

                      // NEU (Variante B — komplettes Verbot): Ein Wechsel
                      // Sync → Lokal ist untersagt, solange die Gruppqe noch
                      // Termine enthält, die vom JEWEILS ANDEREN Gerät
                      // stammen. Ein Unsync würde diese sonst beim
                      // nächsten Abgleich beim Partner-Gerät löschen, ohne
                      // dass der eigentliche Besitzer dem zugestimmt hat.
                      // Eigene Termine in derselben Gruppe sind davon
                      // NICHT betroffen — der Scope-Wechsel ist erlaubt,
                      // sobald keine fremden Termine mehr enthalten sind.
                      if (isReadOnlyDevice &&
                          existing != null &&
                          existing.scope == GroupScope.sync &&
                          selectedScope == GroupScope.local &&
                          SyncService.instance.groupHasForeignEvents(existing.key)) {
                        showGlassSnackBar(
                          context,
                          'Sync kann nicht deaktiviert werden — die Gruppe enthält Termine vom anderen Gerät.',
                          type: GlassSnackBarType.warning,
                        );
                        return;
                      }

                      if (existing == null) {
                        EventGroupStore.add(EventGroupDef(
                          key: EventGroupStore.newKey(),
                          name: name,
                          colorValue: selectedColor,
                          scope: selectedScope,
                        ));
                      } else {
                        EventGroupStore.update(EventGroupDef(
                          key: existing.key,
                          name: name,
                          colorValue: selectedColor,
                          scope: selectedScope,
                        ));
                      }
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(EventGroupDef g) async {
    final skin = AppTheme.of(context);
    if (_groups.length <= 1) {
      showGlassSnackBar(context, 'Es muss mindestens eine Gruppe geben.', type: GlassSnackBarType.warning);
      return;
    }
    final confirmed = await confirmDeleteDialog(
      context: context,
      skin: skin,
      title: 'Gruppe löschen',
      message: 'Termine mit dieser Gruppe werden automatisch der ersten verbleibenden Gruppe zugeordnet.',
    );
    if (confirmed == true) {
      // NEU: awaiten, da EventGroupStore.delete() jetzt Future<void>
      // zurückgibt (wegen des saveAllExternal-Awaits). Ohne await würde
      // setState() schon laufen, bevor der Apple-Abgleich der
      // umgehängten Termine fertig ist — meist unproblematisch, aber
      // sauberer und vorhersehbarer so.
      await EventGroupStore.delete(g.key);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final groups = _groups;

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: 'Kalender-Gruppen', onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassSurface(
                      borderRadius: 18,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: groups.asMap().entries.map((entry) {
                          final i = entry.key;
                          final g = entry.value;
                          final isLast = i == groups.length - 1;
                          final isAppleGroup = g.key == EventGroupStore.appleImportGroupKey;
                          return GlassListItem(
                            leading: Container(
                              width: 24, height: 24,
                              decoration: BoxDecoration(color: g.color, shape: BoxShape.circle),
                            ),
                            title: g.name,
                            subtitle: isAppleGroup
                                ? 'Alle importierten Apple-Termine · nicht auswählbar'
                                : (g.isSync ? 'Sync' : null),
                            isLast: isLast,
                            trailing: isAppleGroup
                                ? Icon(Icons.lock_outline_rounded, size: 18, color: skin.textMuted)
                                : GestureDetector(
                                    onTap: () => _confirmDelete(g),
                                    child: Icon(Icons.delete_outline_rounded, size: 18, color: skin.deleteColor.withValues(alpha: 0.7)),
                                  ),
                            onTap: isAppleGroup ? null : () => _showEditSheet(existing: g),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GlassSecondaryButton(
                      skin: skin,
                      label: 'Neue Gruppe anlegen',
                      onTap: () => _showEditSheet(),
                    ),
                    const _SectionFootnote(
                      text: 'Löschen einer Gruppe verschiebt zugehörige Termine automatisch in die erste verbleibende Gruppe.',
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: SYNC-KONFLIKTE (nur Original-Gerät, nur bei Bedarf sichtbar)
// ─────────────────────────────────────────────────────────────────────────────

class SyncConflictsScreen extends StatefulWidget {
  const SyncConflictsScreen({super.key});
  @override
  State<SyncConflictsScreen> createState() => _SyncConflictsScreenState();
}

class _SyncConflictsScreenState extends State<SyncConflictsScreen> {
  static const _labels = {
    'fahrten': 'Fahrtenbuch',
    'schedule': 'Dienstplan',
    'arbeitszeiten': 'Arbeitszeiten',
    'tasks': 'Aufgaben',
    'calendar_events': 'Kalender',
  };

  /// Konkreter, einzeiliger Inhalts-Vorschau je Konflikt-Eintrag: zeigt die
  /// wichtigsten fachlichen Details statt eines generischen Platzhalter-
  /// textes — Kacheln bleiben dabei genauso groß wie zuvor.
  String _previewFor(SyncConflictItem c) {
    final p = c.payload;
    switch (c.collection) {
      case 'schedule':
        if (p is Map) {
          final incoming = Map<String, dynamic>.from(p);
          final localRaw = Hive.box('einstellungen').get('schedule_${c.docId}');
          final local = localRaw is Map ? Map<String, dynamic>.from(localRaw) : <String, dynamic>{};
          final changed = <String>[];
          final allKeys = {...incoming.keys, ...local.keys}.toList()..sort();
          for (final k in allKeys) {
            final oldV = (local[k] ?? '').toString().trim().toUpperCase();
            final newV = (incoming[k] ?? '').toString().trim().toUpperCase();
            if (oldV != newV) {
              final day = k.length >= 10 ? k.substring(8, 10) : k;
              final month = k.length >= 7 ? k.substring(5, 7) : '';
              changed.add('$day.$month: ${newV.isEmpty ? '–' : newV}');
            }
          }
          if (changed.isEmpty) return 'Keine erkennbaren Änderungen';
          final preview = changed.take(3).join(', ');
          return changed.length > 3 ? '$preview … (+${changed.length - 3})' : preview;
        }
        break;
      case 'fahrten':
        if (p is List) {
          final count = p.length;
          int totalKm = 0;
          final kennzeichen = <String>{};
          final dates = <DateTime>[];
          for (final e in p) {
            if (e is Map) {
              final start = (e['kmStart'] as num?)?.toInt() ?? 0;
              final end = (e['kmEnd'] as num?)?.toInt() ?? 0;
              if (end > start) totalKm += (end - start);
              final kz = e['kennzeichen']?.toString();
              if (kz != null && kz.isNotEmpty) kennzeichen.add(kz);
              final datumRaw = e['datum']?.toString();
              if (datumRaw != null) {
                final dt = DateTime.tryParse(datumRaw);
                if (dt != null) dates.add(dt);
              }
            }
          }
          String dateLabel = '';
          if (dates.isNotEmpty) {
            dates.sort();
            String fmt(DateTime d) =>
                '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.';
            final first = dates.first, last = dates.last;
            dateLabel = (first.day == last.day && first.month == last.month)
                ? ' · ${fmt(first)}'
                : ' · ${fmt(first)}–${fmt(last)}';
          }
          final kzLabel = kennzeichen.isEmpty ? '' : ' · ${kennzeichen.take(2).join(', ')}';
          return '$count Fahrt(en)$dateLabel · $totalKm km$kzLabel';
        }
        break;
      case 'arbeitszeiten':
        if (p is List) {
          final parts = <String>[];
          for (final e in p.take(2)) {
            if (e is Map) {
              final k = (e['kommen'] ?? '').toString();
              final g = (e['gehen'] ?? '').toString();
              if (k.isNotEmpty || g.isNotEmpty) {
                parts.add('${k.isEmpty ? '--:--' : k}–${g.isEmpty ? '--:--' : g}');
              }
            }
          }
          final extra = p.length > 2 ? ' (+${p.length - 2})' : '';
          return parts.isEmpty ? '${p.length} Eintrag/-träge' : '${parts.join(', ')}$extra';
        }
        break;
      case 'calendar_events':
        if (p is Map) {
          final startRaw = (p['start'] ?? '').toString();
          final title = (p['title'] ?? '').toString();
          final dt = DateTime.tryParse(startRaw);
          if (dt != null) {
            final dateStr =
                '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            return title.isEmpty ? dateStr : '$title · $dateStr';
          }
          return title.isEmpty ? 'Kalender-Ereignis' : title;
        }
        break;
      case 'tasks':
        if (p is Map) {
          final parts = <String>[];
          final dueRaw = (p['dueDate'] ?? '').toString();
          if (dueRaw.isNotEmpty) {
            final dt = DateTime.tryParse(dueRaw);
            if (dt != null) {
              parts.add('Fällig: ${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}');
            }
          }
          final notes = (p['notes'] ?? '').toString().trim();
          if (notes.isNotEmpty) parts.add(notes);
          return parts.isEmpty ? 'Keine weiteren Details' : parts.join(' · ');
        }
        break;
    }
    return 'Vom Kopiergerät übermittelter Stand.';
  }

  // ── NEU: lesbare Überschrift je Konflikt-Eintrag statt Roh-ID ───────────
  String _formatDateKey(String key) {
    final parts = key.split('-');
    if (parts.length == 3) {
      return '${parts[2]}.${parts[1]}.${parts[0]}';
    }
    return key;
  }

  String _formatMonthKey(String key) {
    const months = [
      '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ];
    final parts = key.split('-');
    if (parts.length == 2) {
      final year = parts[0];
      final month = int.tryParse(parts[1]) ?? 0;
      if (month >= 1 && month <= 12) return '${months[month]} $year';
    }
    return key;
  }

  String _titleFor(SyncConflictItem c) {
    switch (c.collection) {
      case 'schedule':
      case 'fahrten':
        return _formatMonthKey(c.docId);
      case 'arbeitszeiten':
        return _formatDateKey(c.docId);
      case 'tasks':
        final p = c.payload;
        if (p is Map) {
          final title = (p['title'] ?? '').toString();
          if (title.isNotEmpty) return title;
        }
        return 'Aufgabe';
      case 'calendar_events':
        final p = c.payload;
        if (p is Map) {
          final title = (p['title'] ?? '').toString();
          if (title.isNotEmpty) return title;
        }
        return 'Ereignis';
      default:
        return c.docId;
    }
  }

  Future<void> _accept(String collection, String docId) async {
    await SyncService.instance.acceptConflict(collection, docId);
    setState(() {});
  }

  Future<void> _reject(String collection, String docId) async {
    await SyncService.instance.rejectConflict(collection, docId);
    setState(() {});
  }

  Future<void> _acceptAll(String collection) async {
    await SyncService.instance.acceptAllConflicts(collection);
    setState(() {});
  }

  Future<void> _rejectAll(String collection) async {
    await SyncService.instance.rejectAllConflicts(collection);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final items = SyncService.instance.listPendingConflicts();
    final grouped = <String, List<SyncConflictItem>>{};
    for (final it in items) {
      grouped.putIfAbsent(it.collection, () => []).add(it);
    }
    // NEU (Punkt 4): feste Reihenfolge entlang der App-Struktur.
    const _sectionOrder = ['arbeitszeiten', 'schedule', 'fahrten', 'tasks', 'calendar_events'];
    final orderedGrouped = <String, List<SyncConflictItem>>{
      for (final key in _sectionOrder)
        if (grouped.containsKey(key)) key: grouped[key]!,
    };

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(title: 'Sync-Konflikte', onBack: () => Navigator.pop(context)),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('Keine offenen Konflikte',
                          style: TextStyle(color: skin.surface(0.3), fontSize: 15)),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: orderedGrouped.entries.map((entry) {
                          final collection = entry.key;
                          final label = _labels[collection] ?? collection;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    _SectionHeader(label: label),
                                    Row(children: [
                                      GestureDetector(
                                        onTap: () => _rejectAll(collection),
                                        child: Text('Alle verwerfen',
                                            style: TextStyle(fontSize: 12.5, color: skin.deleteColor, fontWeight: FontWeight.w600)),
                                      ),
                                      const SizedBox(width: 14),
                                      GestureDetector(
                                        onTap: () => _acceptAll(collection),
                                        child: Text('Alle übernehmen',
                                            style: TextStyle(fontSize: 12.5, color: skin.primary, fontWeight: FontWeight.w600)),
                                      ),
                                    ]),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ...entry.value.map((c) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: GlassSurface(
                                        borderRadius: 16,
                                        padding: const EdgeInsets.all(14),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Expanded(
                                                  child: Text(_titleFor(c),
                                                      style: TextStyle(
                                                          fontSize: 13.5,
                                                          fontWeight: FontWeight.w700,
                                                          color: skin.textPrimary),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis),
                                                ),
                                                if ((c.authorName ?? '').trim().isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: skin.primary.withValues(alpha: 0.10),
                                                      borderRadius: BorderRadius.circular(8),
                                                    ),
                                                    child: Text(c.authorName!,
                                                        style: TextStyle(
                                                            fontSize: 10.5,
                                                            fontWeight: FontWeight.w600,
                                                            color: skin.primary),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(_previewFor(c),
                                                style: TextStyle(fontSize: 12, color: skin.textMuted),
                                                maxLines: 1, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 10),
                                            Row(children: [
                                              Expanded(
                                                child: GlassSecondaryButton(
                                                  skin: skin,
                                                  label: 'Verwerfen',
                                                  onTap: () => _reject(c.collection, c.docId),
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: GlassPrimaryButton(
                                                  skin: skin,
                                                  label: 'Übernehmen',
                                                  onTap: () => _accept(c.collection, c.docId),
                                                ),
                                              ),
                                            ]),
                                          ],
                                        ),
                                      ),
                                    )),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}