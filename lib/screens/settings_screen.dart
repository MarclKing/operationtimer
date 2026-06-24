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
import '../widgets/glass_kit.dart';

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
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.person_rounded,
                        iconBg: const Color(0xFF5B8DEF),
                        label: name.isEmpty ? 'Profil' : name,
                        subtitle: name.isEmpty ? 'Name & Dienstplan-Name' : 'Profil & Dienstplan-Name',
                        isLast: true,
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _ProfileSettingsScreen()),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 24),

                    // ── Hauptgruppe ────────────────────────────────────────
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.notifications_rounded,
                        iconBg: const Color(0xFFEF5B5B),
                        label: 'Benachrichtigungen',
                        subtitle: 'Tagesvorschau · Erinnerungszeit',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _NotificationSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.dashboard_rounded,
                        iconBg: const Color(0xFF5B8DEF),
                        label: 'Startbildschirm',
                        subtitle: 'Wetter · Aufgabe hinzufügen',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _HomescreenSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.access_time_filled_rounded,
                        iconBg: const Color(0xFF2D6CFF),
                        label: 'Arbeitszeiterfassung',
                        subtitle: 'Nachtschicht · Reisemodus',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _WorkTimeSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.calendar_month_rounded,
                        iconBg: const Color(0xFFFFB347),
                        label: 'Dienstplan',
                        subtitle: 'Import · Entwickler-Modus',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _ScheduleSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.task_alt_rounded,
                        iconBg: const Color(0xFF3DD68C),
                        label: 'Aufgaben & Diktieren',
                        subtitle: 'Diktat · Log · Sprach-Analyse',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _TasksDictationSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.folder_rounded,
                        iconBg: const Color(0xFF8B8B9E),
                        label: 'Datenverwaltung',
                        subtitle: 'Aufbewahrung · Auto-Löschung',
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _DataManagementSettingsScreen()),
                        ),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.palette_rounded,
                        iconBg: const Color(0xFF3DD6C8),
                        label: 'Design',
                        subtitle: 'Farbschema',
                        isLast: true,
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const _DesignSettingsScreen()),
                        ),
                      ),
                    ]),

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
// GEMEINSAME BAUSTEINE — Header, Tile-Gruppe, Tile, SwitchTile, Section-Labels
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;
  final Widget? trailing;

  const _SettingsHeader(
      {required this.title, required this.onBack, this.trailing});

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
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _SettingsTileGroup extends StatelessWidget {
  final AppSkin skin;
  final List<Widget> children;

  const _SettingsTileGroup(
      {required this.skin, required this.children});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: skin.glassBorder, width: 1.0),
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
          child: Column(children: children),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final String? trailingValue;
  final bool isLast;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.skin,
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.trailingValue,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(8)),
                  child:
                      Icon(icon, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: skin.textPrimary)),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(subtitle!,
                            style: TextStyle(
                                fontSize: 12, color: skin.textMuted)),
                      ],
                    ],
                  ),
                ),
                if (trailingValue != null) ...[
                  Text(trailingValue!,
                      style: TextStyle(
                          fontSize: 14, color: skin.textMuted)),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: skin.surface(0.28)),
              ],
            ),
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Divider(height: 0.5, color: skin.glassBorder),
          ),
      ],
    );
  }
}

class _SettingsSwitchTile extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final Color iconBg;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool isLast;

  const _SettingsSwitchTile({
    required this.skin,
    required this.icon,
    required this.iconBg,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: skin.textPrimary)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style: TextStyle(
                              fontSize: 12,
                              color: skin.textMuted,
                              height: 1.35)),
                    ],
                  ],
                ),
              ),
              Switch(
                value: value,
                onChanged: onChanged,
                activeThumbColor: skin.primary,
                activeTrackColor: skin.primary.withValues(alpha: 0.28),
                inactiveThumbColor: skin.textMuted,
                inactiveTrackColor: skin.surface(0.08),
              ),
            ],
          ),
        ),
        if (!isLast)
          Padding(
            padding: const EdgeInsets.only(left: 60),
            child: Divider(height: 0.5, color: skin.glassBorder),
          ),
      ],
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter:
            ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [
              BoxShadow(
                  color: skin.glassShadow,
                  blurRadius: 24,
                  offset: const Offset(0, 6)),
            ],
          ),
          child: child,
        ),
      ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 24, offset: const Offset(0, 6)),
            ],
          ),
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
                GestureDetector(
                  onTap: isGenerating ? null : onGenerate,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: skin.primary.withValues(alpha: skin.isLight ? 0.10 : 0.18),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: skin.primary.withValues(alpha: skin.isLight ? 0.25 : 0.40)),
                    ),
                    child: Center(
                      child: isGenerating
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: skin.primary))
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.add_circle_outline_rounded,
                                    size: 16,
                                    color: skin.primary.withValues(
                                        alpha: skin.isLight ? 0.85 : 0.90)),
                                const SizedBox(width: 7),
                                Text('Neuen Token generieren',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: skin.primary.withValues(
                                            alpha: skin.isLight ? 0.85 : 0.90))),
                              ],
                            ),
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // Bestehenden verknüpfen
                GestureDetector(
                  onTap: onToggleInput,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: skin.isLight
                          ? Colors.white.withValues(alpha: 0.60)
                          : Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.glassBorder),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link_rounded, size: 16, color: skin.textMuted),
                          const SizedBox(width: 7),
                          Text('Token verknüpfen',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: skin.textPrimary)),
                        ],
                      ),
                    ),
                  ),
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
                      GestureDetector(
                        onTap: isLinking ? null : onLink,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(
                                alpha: skin.isLight ? 0.10 : 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: skin.primary.withValues(
                                    alpha: skin.isLight ? 0.25 : 0.40)),
                          ),
                          child: Center(
                            child: isLinking
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: skin.primary))
                                : Text('Verknüpfen',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: skin.primary.withValues(
                                            alpha:
                                                skin.isLight ? 0.85 : 0.90))),
                          ),
                        ),
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
                      child: GestureDetector(
                        onTap: onCopy,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: (linkFeedback != null && linkSuccess)
                                ? const Color(0xFF3DD68C).withValues(alpha: 0.12)
                                : (skin.isLight
                                    ? Colors.white.withValues(alpha: 0.60)
                                    : Colors.white.withValues(alpha: 0.06)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: (linkFeedback != null && linkSuccess)
                                  ? const Color(0xFF3DD68C).withValues(alpha: 0.4)
                                  : skin.glassBorder,
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                (linkFeedback != null && linkSuccess)
                                    ? Icons.check_rounded
                                    : Icons.copy_rounded,
                                size: 15,
                                color: (linkFeedback != null && linkSuccess)
                                    ? const Color(0xFF3DD68C)
                                    : skin.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (linkFeedback != null && linkSuccess)
                                    ? 'Kopiert!'
                                    : 'Kopieren',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: (linkFeedback != null && linkSuccess)
                                      ? const Color(0xFF3DD68C)
                                      : skin.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: onShare,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(
                                alpha: skin.isLight ? 0.10 : 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: skin.primary.withValues(
                                    alpha: skin.isLight ? 0.25 : 0.40)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.ios_share_rounded,
                                  size: 15,
                                  color: skin.primary
                                      .withValues(alpha: skin.isLight ? 0.85 : 0.90)),
                              const SizedBox(width: 6),
                              Text('Teilen',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: skin.primary.withValues(
                                          alpha: skin.isLight ? 0.85 : 0.90))),
                            ],
                          ),
                        ),
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
                      GestureDetector(
                        onTap: isLinking ? null : onLink,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          decoration: BoxDecoration(
                            color: skin.primary.withValues(
                                alpha: skin.isLight ? 0.10 : 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: skin.primary.withValues(
                                    alpha: skin.isLight ? 0.25 : 0.40)),
                          ),
                          child: Center(
                            child: isLinking
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: skin.primary))
                                : Text('Verknüpfen',
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: skin.primary.withValues(
                                            alpha:
                                                skin.isLight ? 0.85 : 0.90))),
                          ),
                        ),
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
        ),
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
_SettingsTileGroup(skin: skin, children: [
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
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.today_rounded,
                        iconBg: const Color(0xFF2D6CFF),
                        label: 'Tagesvorschau aktiv',
                        subtitle: 'Zeigt täglich Dienst & fällige Aufgaben',
                        value: _overviewEnabled,
                        onChanged: _setOverviewEnabled,
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
                              child: ClipRRect(
                                borderRadius:
                                    BorderRadius.circular(12),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(
                                      sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: skin.isLight
                                          ? Colors.white.withValues(
                                              alpha: 0.45)
                                          : Colors.white.withValues(
                                              alpha: 0.06),
                                      borderRadius:
                                          BorderRadius.circular(12),
                                      border: Border.all(
                                          color: skin.glassBorder),
                                    ),
                                    child: Row(children: [
                                      Expanded(
                                        child: _ModeSegment(
                                          skin: skin,
                                          label: 'Feste Uhrzeit',
                                          selected:
                                              _mode == 'fixed_time',
                                          onTap: () =>
                                              _setMode('fixed_time'),
                                        ),
                                      ),
                                      Expanded(
                                        child: _ModeSegment(
                                          skin: skin,
                                          label: 'Bei App-Start',
                                          selected:
                                              _mode == 'app_start',
                                          onTap: () =>
                                              _setMode('app_start'),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ),
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
                          _SettingsTile(
                            skin: skin,
                            icon: Icons.schedule_rounded,
                            iconBg: const Color(0xFF5B8DEF),
                            label: 'Uhrzeit',
                            trailingValue: _formatTime(_morningTime),
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
                        _SettingsSwitchTile(
                          skin: skin,
                          icon: Icons.filter_alt_outlined,
                          iconBg: const Color(0xFF8B8B9E),
                          label: 'Nur wenn relevant',
                          subtitle:
                              'Sonst auch "Heute ist nichts geplant"',
                          value: _onlyIfRelevant,
                          onChanged: _setOnlyIfRelevant,
                        ),
                        _SettingsSwitchTile(
                          skin: skin,
                          icon: Icons.nightlight_round,
                          iconBg: const Color(0xFF6D7ADF),
                          label: 'Vorabend-Vorschau',
                          subtitle:
                              'Zusätzlich abends Vorschau auf morgen',
                          value: _eveningEnabled,
                          onChanged: _setEveningEnabled,
                          isLast: !_eveningEnabled,
                        ),
                        if (_eveningEnabled)
                          _SettingsTile(
                            skin: skin,
                            icon: Icons.schedule_rounded,
                            iconBg: const Color(0xFF6D7ADF),
                            label: 'Uhrzeit (abends)',
                            trailingValue: _formatTime(_eveningTime),
                            isLast: true,
                            onTap: _pickEveningTime,
                          ),
                      ],
                    ]),
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

class _ModeSegment extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeSegment(
      {required this.skin,
      required this.label,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? (skin.isLight
                  ? Colors.white.withValues(alpha: 0.80)
                  : Colors.white.withValues(alpha: 0.14))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: selected
              ? Border.all(color: skin.glassBorder)
              : null,
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected
                    ? FontWeight.w700
                    : FontWeight.w400,
                color: selected
                    ? skin.primary
                    : skin.surface(0.45),
              )),
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

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nachtschichtModus =
        box.get('nachtschicht_modus', defaultValue: false) as bool;
    _reisemodus =
        box.get('reisemodus', defaultValue: false) as bool;
  }

  void _setNachtschichtModus(bool value) {
    setState(() => _nachtschichtModus = value);
    Hive.box('einstellungen').put('nachtschicht_modus', value);
  }

  void _setReisemodus(bool value) {
    setState(() => _reisemodus = value);
    Hive.box('einstellungen').put('reisemodus', value);
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
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.dark_mode_outlined,
                        iconBg: const Color(0xFF2E7D32),
                        label: 'Nachtschicht-Modus',
                        subtitle: 'Teilt Nachtschichten auf zwei Tage auf',
                        value: _nachtschichtModus,
                        onChanged: _setNachtschichtModus,
                      ),
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.flight_takeoff_rounded,
                        iconBg: const Color(0xFF6D7ADF),
                        label: 'Reisemodus',
                        subtitle: 'Zeitzonen-Anpassung · In Entwicklung',
                        value: _reisemodus,
                        isLast: true,
                        onChanged: _setReisemodus,
                      ),
                    ]),
                    const _SectionFootnote(
                      text: 'Nachtschicht: Kommen bis 23:59 (selber Tag) + 00:00 bis Gehen (nächster Tag). '
                            'Reisemodus hat aktuell noch keine Auswirkung.',
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

  static int _pinFailCount = 0;
  static DateTime? _pinCooldownUntil;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _dienstplanDevMode =
        box.get('dienstplan_dev_placeholder', defaultValue: false)
            as bool;
  }

  Future<void> _toggleDevMode(bool desiredValue) async {
    if (!desiredValue) {
      setState(() => _dienstplanDevMode = false);
      Hive.box('einstellungen')
          .put('dienstplan_dev_placeholder', false);
      return;
    }
    final granted = await _showPinDialog();
    if (granted) {
      setState(() => _dienstplanDevMode = true);
      Hive.box('einstellungen')
          .put('dienstplan_dev_placeholder', true);
    }
  }

  Future<bool> _showPinDialog() async {
    if (_pinCooldownUntil != null &&
        DateTime.now().isBefore(_pinCooldownUntil!)) {
      await _showPinBlockedAlert();
      return false;
    }

    final skin = AppTheme.of(context);
    final controller = TextEditingController();
    bool result = false;
    bool dialogClosed = false;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          void trySubmit(String value) {
            if (value.length != 4 || dialogClosed) return;
            if (value == '2210') {
              dialogClosed = true;
              _pinFailCount = 0;
              _pinCooldownUntil = null;
              result = true;
              Navigator.pop(ctx);
            } else {
              _pinFailCount++;
              controller.clear();
              if (_pinFailCount >= 3) {
                dialogClosed = true;
                _pinCooldownUntil = DateTime.now()
                    .add(const Duration(minutes: 1));
                _pinFailCount = 0;
                Navigator.pop(ctx);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showPinBlockedAlert();
                });
              } else {
                setDialog(() {});
              }
            }
          }

          return GestureDetector(
            onTap: () => FocusScope.of(ctx).unfocus(),
            behavior: HitTestBehavior.translucent,
            child: AlertDialog(
              backgroundColor: skin.bgCard,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24)),
              title: Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5B5B)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFEF5B5B)
                            .withValues(alpha: 0.3)),
                  ),
                  child: const Text('DEV',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEF5B5B),
                          letterSpacing: 0.8)),
                ),
                const SizedBox(width: 10),
                Text('Entwickler-Modus',
                    style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bitte gib den Entwickler-Code ein:',
                      style: TextStyle(
                          color: skin.textMuted, fontSize: 13)),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: skin.surface(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: skin.borderSubtle),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      maxLength: 4,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      style: TextStyle(
                          color: skin.textPrimary,
                          fontSize: 22,
                          letterSpacing: 8),
                      decoration: InputDecoration(
                        hintText: '••••',
                        hintStyle: TextStyle(
                            color: skin.textHint,
                            letterSpacing: 8),
                        border: InputBorder.none,
                        isDense: true,
                        counterText: '',
                      ),
                      textAlign: TextAlign.center,
                      onChanged: trySubmit,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    dialogClosed = true;
                    Navigator.pop(ctx);
                  },
                  child: Text('Abbrechen',
                      style: TextStyle(color: skin.textMuted)),
                ),
              ],
            ),
          );
        },
      ),
    );

    return result;
  }

  Future<void> _showPinBlockedAlert() async {
    if (!mounted) return;
    final skin = AppTheme.of(context);
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: skin.bgCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          const Icon(Icons.lock_outline,
              color: Color(0xFFEF5B5B), size: 20),
          const SizedBox(width: 8),
          Text('Nicht zugelassen',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Text('PIN zu oft falsch eingegeben.',
            style: TextStyle(color: skin.textMuted, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: TextStyle(
                    color: skin.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
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
                title: 'Dienstplan',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.code_rounded,
                        iconBg: const Color(0xFFEF5B5B),
                        label: 'Entwickler-Modus',
                        subtitle: 'Erweiterte Fehlermeldungen beim PDF-Import',
                        value: _dienstplanDevMode,
                        isLast: true,
                        onChanged: _toggleDevMode,
                      ),
                    ]),
                    const _SectionFootnote(
                      text: 'Der Dienstplan-Import befindet sich noch in der Beta-Phase.',
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
                    _SettingsTileGroup(skin: skin, children: [
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
                    const SizedBox(height: 14),

                    // ── Dienstplan ─────────────────────────────────────────
                    _SettingsTileGroup(skin: skin, children: [
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
                    const SizedBox(height: 14),

                    // ── Fahrtenbuch ────────────────────────────────────────
                    _SettingsTileGroup(skin: skin, children: [
                      GlassDropdownButton<int>(
                        value: _fahrtenbuchDeleteMonths,
                        label: 'Fahrtenbuch',
                        subtitle: 'Einegtragene Fahrten löschen nach',
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
                    const SizedBox(height: 14),

                    // ── Erledigte Aufgaben — jetzt als Tile + Dropdown ─────
                    _SettingsTileGroup(skin: skin, children: [
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

                    const SizedBox(height: 8),
                    const _SectionFootnote(
                      text:
                          'Jeder Bereich hat eine eigene Aufbewahrungsfrist. '
                          'Erledigte Aufgaben werden standardmäßig nach 1 Tag gelöscht.',
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
                  _SettingsTileGroup(
                    skin: skin,
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
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.mic_outlined,
                        iconBg: const Color(0xFF2D6CFF),
                        label: 'Sprachbefehle & Hilfe',
                        subtitle: 'Muster, Beispiele und Tipps',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) => const DictationHelpScreen())),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.bar_chart_rounded,
                        iconBg: const Color(0xFF5B9EF5),
                        label: 'Sprach-Log',
                        subtitle: 'Alle Diktiereingaben & Erkennungsrate',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) => const SpeechLogScreen())),
                      ),
                      if (AuthService.instance.isAdmin)
                        _SettingsTile(
                          skin: skin,
                          icon: Icons.auto_awesome_outlined,
                          iconBg: const Color(0xFF8B5CF6),
                          label: 'Sprach-Analyse',
                          subtitle: 'Eingaben analysieren · Regeln lernen',
                          isLast: true,
                          onTap: () => Navigator.push(
                              context,
                              CupertinoPageRoute(
                                  builder: (_) => const AdminRulesScreen())),
                        )
                      else
                        const SizedBox.shrink(),
                    ]),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.92)
                    : skin.bgCard.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: skin.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      decoration: BoxDecoration(
                        color: skin.surface(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
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
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () {
                      final city = ctrl.text.trim();
                      setState(() => _weatherCity = city);
                      _set('weather_city', city);
                      Hive.box('einstellungen').delete('weather_cache');
                      Navigator.pop(context);
                    },
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
                        child: Text('Übernehmen',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                                color: skin.primary)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.wb_sunny_outlined,
                        iconBg: const Color(0xFFFFB347),
                        label: 'Wetter als große Kachel',
                        subtitle: 'Zeigt mehr Wetterinformationen',
                        value: _weatherBig,
                        onChanged: (v) {
                          setState(() => _weatherBig = v);
                          _set('homescreen_weather_big', v);
                        },
                      ),
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.location_on_outlined,
                        iconBg: const Color(0xFF5B9EF5),
                        label: 'Per GPS-Standort',
                        subtitle: 'Automatisch aktueller Standort',
                        value: _weatherUseGps,
                        onChanged: (v) {
                          setState(() => _weatherUseGps = v);
                          _set('weather_use_gps', v);
                          Hive.box('einstellungen').delete('weather_cache');
                          if (v) {
                            WeatherService.instance.invalidateCache();
                          }
                        },
                        isLast: _weatherUseGps,
                      ),
                      if (!_weatherUseGps)
                        _SettingsTile(
                          skin: skin,
                          icon: Icons.location_city_outlined,
                          iconBg: const Color(0xFF8B8B9E),
                          label: 'Stadt',
                          trailingValue: _weatherCity.isNotEmpty ? _weatherCity : 'nicht gesetzt',
                          isLast: true,
                          onTap: () => _showCityInputSheet(context, skin),
                        ),
                    ]),
                    _SectionFootnote(
                      text: _weatherUseGps
                          ? 'Wetter wird per GPS geladen — immer aktuell für deinen Standort.'
                          : 'Wetter wird für die eingetragene Stadt geladen.',
                    ),

                    const SizedBox(height: 24),

                    // ── Aufgabe hinzufügen ────────────────────────────
                    const _SectionHeader(label: 'Aufgabe hinzufügen'),
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsSwitchTile(
                        skin: skin,
                        icon: Icons.mic_outlined,
                        iconBg: const Color(0xFF3DD68C),
                        label: 'Diktieren',
                        subtitle: 'Nutzt Schnell-Diktieren Funktion statt manuellem Formular',
                        value: _taskAddMode == 'dictate',
                        isLast: true,
                        onChanged: (v) {
                          final mode = v ? 'dictate' : 'sheet';
                          setState(() => _taskAddMode = mode);
                          _set('homescreen_task_add_mode', mode);
                        },
                      ),
                    ]),
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