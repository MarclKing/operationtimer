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
                    // ── Profil-Banner (Apple-ID-artig) ────────────────────
                    _SettingsTileGroup(skin: skin, children: [
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.person_rounded,
                        iconBg: const Color(0xFF5B8DEF),
                        label: name.isEmpty ? 'Profil' : name,
                        subtitle: name.isEmpty
                            ? 'Name & Dienstplan-Name'
                            : 'Profil & Dienstplan-Name',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) => const _ProfileSettingsScreen())),
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
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) =>
                                    const _NotificationSettingsScreen())),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.access_time_filled_rounded,
                        iconBg: const Color(0xFF2D6CFF),
                        label: 'Arbeitszeiterfassung',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) =>
                                    const _WorkTimeSettingsScreen())),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.calendar_month_rounded,
                        iconBg: const Color(0xFFFFB347),
                        label: 'Dienstplan',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) =>
                                    const _ScheduleSettingsScreen())),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.folder_rounded,
                        iconBg: const Color(0xFF8B8B9E),
                        label: 'Datenverwaltung',
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) =>
                                    const _DataManagementSettingsScreen())),
                      ),
                      _SettingsTile(
                        skin: skin,
                        icon: Icons.palette_rounded,
                        iconBg: const Color(0xFF3DD6C8),
                        label: 'Design',
                        isLast: true,
                        onTap: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                                builder: (_) =>
                                    const _DesignSettingsScreen())),
                      ),
                    ]),

                    const SizedBox(height: 40),
                    Center(
                      child: Text('OpTimes v1.3.0',
                          style:
                              TextStyle(fontSize: 12, color: skin.textHint)),
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
            child: const SizedBox(
              width: 42,
              height: 42,
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
// Dieselben Glass-Cards wie im alten Settings-Screen, jetzt zentral definiert.
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
// UNTERMENÜ: PROFIL
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileSettingsScreen extends StatefulWidget {
  const _ProfileSettingsScreen();

  @override
  State<_ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends State<_ProfileSettingsScreen> {
  final _nameController = TextEditingController();
  final _scheduleNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nameController.text = box.get('name', defaultValue: '');
    _scheduleNameController.text =
        box.get('dienstplan_name', defaultValue: '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleNameController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  String _capitalizeEachWord(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  void _onNameChanged(String value) {
    final cursor = _nameController.selection.baseOffset;
    final formatted = _capitalizeEachWord(value);
    if (formatted != value) {
      _nameController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset:
              cursor > formatted.length ? formatted.length : cursor,
        ),
      );
    }
  }

  void _autoSaveName() {
    final box = Hive.box('einstellungen');
    final formatted = _capitalizeEachWord(_nameController.text);
    _nameController.text = formatted;
    final existingName =
        box.get('name', defaultValue: '') as String;
    final isNew = existingName.isEmpty;
    if (formatted == existingName) return;
    box.put('name', formatted);
    final skin = AppTheme.of(context);
    final message = isNew ? 'Name gespeichert ✓' : 'Name geändert ✓';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: skin.primary == Colors.white
          ? const Color(0xFF3DD6C8)
          : skin.primary,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(milliseconds: 1500),
    ));
  }

  void _autoSaveScheduleName() {
    final box = Hive.box('einstellungen');
    final trimmed = _scheduleNameController.text.trim();
    box.put('dienstplan_name', trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: GestureDetector(
          onTap: _dismissKeyboard,
          child: Column(
            children: [
              _SettingsHeader(
                  title: 'Profil',
                  onBack: () => Navigator.pop(context)),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TiCard(
                        skin: skin,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _TiCardHeader(
                                skin: skin,
                                icon: Icons.person_outline_rounded,
                                label: 'Benutzername'),
                            const SizedBox(height: 12),
                            Text(
                              'Vor- und Nachname — erscheint in der Begrüßung, im PDF und für die Dienstplan-Erkennung.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: skin.textMuted,
                                  height: 1.5),
                            ),
                            const SizedBox(height: 14),
                            Focus(
                              onFocusChange: (hasFocus) {
                                if (!hasFocus) _autoSaveName();
                              },
                              child: _TiTextField(
                                skin: skin,
                                controller: _nameController,
                                hint: 'z.B. Max Mustermann',
                                onChanged: _onNameChanged,
                                onSubmitted: (_) {
                                  _dismissKeyboard();
                                  _autoSaveName();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _TiCard(
                        skin: skin,
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            _TiCardHeader(
                                skin: skin,
                                icon: Icons.badge_outlined,
                                label: 'Dienstplan-Name'),
                            const SizedBox(height: 12),
                            Text(
                              'Nur ausfüllen, falls dein Name im Dienstplan-PDF anders geschrieben ist (z.B. Spitzname, Kürzel).',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: skin.textMuted,
                                  height: 1.5),
                            ),
                            const SizedBox(height: 14),
                            Focus(
                              onFocusChange: (hasFocus) {
                                if (!hasFocus)
                                  _autoSaveScheduleName();
                              },
                              child: _TiTextField(
                                skin: skin,
                                controller:
                                    _scheduleNameController,
                                hint: 'optional',
                                onSubmitted: (_) {
                                  _dismissKeyboard();
                                  _autoSaveScheduleName();
                                },
                              ),
                            ),
                          ],
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
    final fullName = _fullName;
    final vorname = firstNameFrom(fullName);
    final nachname = lastNameFrom(fullName);

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
                    // ── Anrede & Umgangsform ───────────────────────────
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.chat_bubble_outline_rounded,
                              label: 'Anrede & Umgangsform'),
                          const SizedBox(height: 8),
                          Text(
                            'Bestimmt, wie OpTimes in Benachrichtigungen mit dir spricht.',
                            style: TextStyle(
                                fontSize: 13,
                                color: skin.textMuted,
                                height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          RelationshipOptionCard(
                            skin: skin,
                            icon: Icons.bolt_rounded,
                            text:
                                'Hilf mir einfach bei der Arbeit, Bro!',
                            selected: _selectedStyle ==
                                RelationshipStyle.bro,
                            onTap: () =>
                                _selectStyle(RelationshipStyle.bro),
                          ),
                          const SizedBox(height: 10),
                          RelationshipOptionCard(
                            skin: skin,
                            icon: Icons.waving_hand_outlined,
                            text: vorname.isEmpty
                                ? 'Du kannst meinen Vornamen zu mir sagen!'
                                : 'Du kannst $vorname zu mir sagen!',
                            selected: _selectedStyle ==
                                RelationshipStyle.vorname,
                            onTap: () => _selectStyle(
                                RelationshipStyle.vorname),
                          ),
                          const SizedBox(height: 10),
                          RelationshipOptionCard(
                            skin: skin,
                            icon: Icons.workspace_premium_outlined,
                            text: nachname.isEmpty
                                ? 'Für Dich gehöre ich zur Familie!'
                                : 'Für Dich gehöre ich zur Familie, $nachname!',
                            selected: _selectedStyle ==
                                RelationshipStyle.familie,
                            onTap: () => _selectStyle(
                                RelationshipStyle.familie),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),
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
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.dark_mode_outlined,
                              label: 'Nachtschicht-Modus'),
                          const SizedBox(height: 12),
                          Text(
                            'Erkennt automatisch Nachtschichten und legt zwei Einträge an:\n• Kommen bis 23:59 (selber Tag)\n• 00:00 bis Gehen (nächster Tag)',
                            style: TextStyle(
                                fontSize: 13,
                                color: skin.textMuted,
                                height: 1.55),
                          ),
                          const SizedBox(height: 16),
                          _TiToggleRow(
                            skin: skin,
                            label: _nachtschichtModus
                                ? 'Aktiviert'
                                : 'Deaktiviert',
                            value: _nachtschichtModus,
                            activeColor: const Color(0xFF2E7D32),
                            onChanged: _setNachtschichtModus,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ── Reisemodus (Platzhalter) ───────────────────────
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _TiCardHeader(
                                skin: skin,
                                icon: Icons.flight_takeoff_rounded,
                                label: 'Reisemodus'),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6D7ADF)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFF6D7ADF)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: const Text('BALD VERFÜGBAR',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF6D7ADF),
                                      letterSpacing: 0.6)),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Text(
                            'Passt Zeiterfassung und Zeitzonen automatisch an, wenn du auf Reisen bist. Diese Funktion ist in Entwicklung und hat aktuell noch keine Auswirkung.',
                            style: TextStyle(
                                fontSize: 13,
                                color: skin.textMuted,
                                height: 1.55),
                          ),
                          const SizedBox(height: 16),
                          _TiToggleRow(
                            skin: skin,
                            label: _reisemodus
                                ? 'Aktiviert'
                                : 'Deaktiviert',
                            value: _reisemodus,
                            activeColor: const Color(0xFF6D7ADF),
                            onChanged: _setReisemodus,
                          ),
                        ],
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
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _TiCardHeader(
                                skin: skin,
                                icon:
                                    Icons.calendar_month_outlined,
                                label: 'Dienstplan'),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFB347)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(6),
                                border: Border.all(
                                    color: const Color(0xFFFFB347)
                                        .withValues(alpha: 0.35)),
                              ),
                              child: const Text('BETA',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFFFB347),
                                      letterSpacing: 0.8)),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB347)
                                  .withValues(alpha: 0.07),
                              borderRadius:
                                  BorderRadius.circular(12),
                              border: Border.all(
                                  color: const Color(0xFFFFB347)
                                      .withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                const Text('⚠️',
                                    style:
                                        TextStyle(fontSize: 14)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Diese Funktion befindet sich noch in der Beta-Phase.',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: const Color(
                                                0xFFFFB347)
                                            .withValues(
                                                alpha: 0.85),
                                        height: 1.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(
                                          alpha: 0.45)
                                      : Colors.white.withValues(
                                          alpha: 0.05),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.glassBorder),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                          decoration:
                                              BoxDecoration(
                                            color: const Color(
                                                    0xFFEF5B5B)
                                                .withValues(
                                                    alpha: 0.12),
                                            borderRadius:
                                                BorderRadius
                                                    .circular(6),
                                            border: Border.all(
                                                color: const Color(
                                                        0xFFEF5B5B)
                                                    .withValues(
                                                        alpha:
                                                            0.3)),
                                          ),
                                          child: const Text(
                                              'DEV',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight
                                                          .w700,
                                                  color: Color(
                                                      0xFFEF5B5B),
                                                  letterSpacing:
                                                      0.8)),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                              'Entwickler-Modus',
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight
                                                          .w600,
                                                  color: skin
                                                      .textPrimary)),
                                        ),
                                        Switch(
                                          value: _dienstplanDevMode,
                                          onChanged: _toggleDevMode,
                                          activeThumbColor:
                                              const Color(
                                                  0xFFEF5B5B),
                                          activeTrackColor:
                                              const Color(0xFFEF5B5B)
                                                  .withValues(
                                                      alpha: 0.25),
                                          inactiveThumbColor:
                                              skin.textMuted,
                                          inactiveTrackColor:
                                              skin.surface(0.08),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        'Erweiterte Fehlermeldungen beim PDF-Import.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: skin.textMuted,
                                            height: 1.45)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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

// ─────────────────────────────────────────────────────────────────────────────
// UNTERMENÜ: DATENVERWALTUNG
// ─────────────────────────────────────────────────────────────────────────────

class _DataManagementSettingsScreen extends StatefulWidget {
  const _DataManagementSettingsScreen();

  @override
  State<_DataManagementSettingsScreen> createState() =>
      _DataManagementSettingsScreenState();
}

class _DataManagementSettingsScreenState
    extends State<_DataManagementSettingsScreen> {
  int _deleteAfterMonths = 3;
  String _taskAutoDelete = 'never';

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _deleteAfterMonths =
        box.get('deleteAfterMonths', defaultValue: 3);
    _taskAutoDelete =
        box.get('task_auto_delete', defaultValue: 'never') as String;
  }

  String _taskAutoDeleteLabel(String key) {
    switch (key) {
      case '1d':
        return '1 Tag';
      case '2d':
        return '2 Tagen';
      case '1w':
        return '1 Woche';
      case '1m':
        return '1 Monat';
      default:
        return '';
    }
  }

  void _autoDeleteOldEntries() {
    final now = DateTime.now();
    final cutoffMonth =
        DateTime(now.year, now.month - _deleteAfterMonths);

    final zeitBox = Hive.box('arbeitszeiten');
    final zeitKeysToDelete = zeitBox.keys.where((key) {
      try {
        final date = DateTime.parse(key.toString());
        final entryMonth = DateTime(date.year, date.month);
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in zeitKeysToDelete) {
      zeitBox.delete(key);
    }

    final settingsBox = Hive.box('einstellungen');
    final scheduleKeysToDelete = settingsBox.keys.where((key) {
      final k = key.toString();
      if (!k.startsWith('schedule_')) return false;
      try {
        final monthStr = k.substring('schedule_'.length);
        final parts = monthStr.split('-');
        if (parts.length < 2) return false;
        final entryMonth = DateTime(
            int.parse(parts[0]), int.parse(parts[1]));
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in scheduleKeysToDelete) {
      settingsBox.delete(key);
    }

    final noteKeysToDelete = settingsBox.keys.where((key) {
      final k = key.toString();
      if (!k.startsWith('schedule_note_')) return false;
      try {
        final dateStr =
            k.substring('schedule_note_'.length);
        final date = DateTime.parse(dateStr);
        final entryMonth = DateTime(date.year, date.month);
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in noteKeysToDelete) {
      settingsBox.delete(key);
    }

    final fahrtKeys = settingsBox.keys.where((key) {
      final k = key.toString();
      if (!k.startsWith('fahrten_')) return false;
      try {
        final monthStr = k.substring('fahrten_'.length);
        final parts = monthStr.split('-');
        if (parts.length < 2) return false;
        final entryMonth = DateTime(
            int.parse(parts[0]), int.parse(parts[1]));
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in fahrtKeys) {
      settingsBox.delete(key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final monthLabel =
        '$_deleteAfterMonths Monat${_deleteAfterMonths > 1 ? 'en' : ''}';

    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Datenverwaltung',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Zeiten / Dienstplan / Fahrtenbuch ─────────────
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.delete_outline_rounded,
                              label: 'Zeiten & Dienstplan'),
                          const SizedBox(height: 12),
                          Text(
                              'Alte Daten nach diesem Zeitraum automatisch löschen:',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: skin.textMuted)),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(
                                          alpha: 0.45)
                                      : Colors.white.withValues(
                                          alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.glassBorder),
                                ),
                                child: Row(
                                  children: [1, 3, 6, 12]
                                      .map((months) {
                                    final isSelected =
                                        _deleteAfterMonths ==
                                            months;
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() =>
                                              _deleteAfterMonths =
                                                  months);
                                          Hive.box('einstellungen')
                                              .put(
                                                  'deleteAfterMonths',
                                                  months);
                                          _autoDeleteOldEntries();
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          padding: const EdgeInsets
                                              .symmetric(
                                              vertical: 10),
                                          decoration:
                                              BoxDecoration(
                                            color: isSelected
                                                ? (skin.isLight
                                                    ? Colors.white
                                                        .withValues(
                                                            alpha:
                                                                0.80)
                                                    : Colors.white
                                                        .withValues(
                                                            alpha:
                                                                0.14))
                                                : Colors
                                                    .transparent,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(10),
                                            border: isSelected
                                                ? Border.all(
                                                    color: skin
                                                        .glassBorder,
                                                    width: 1.0)
                                                : null,
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                        color: skin
                                                            .glassShadow,
                                                        blurRadius:
                                                            8,
                                                        offset:
                                                            const Offset(
                                                                0,
                                                                2))
                                                  ]
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                                '$months M',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isSelected
                                                        ? FontWeight
                                                            .w700
                                                        : FontWeight
                                                            .w400,
                                                    color: isSelected
                                                        ? skin.primary
                                                        : skin.surface(
                                                            0.45))),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(
                                          alpha: 0.50)
                                      : skin.primary.withValues(
                                          alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                      color: skin.glassBorder),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        Icons
                                            .info_outline_rounded,
                                        color: skin.primary
                                            .withValues(alpha: 0.6),
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Zeiterfassungs-Einträge, sowie Dienstplan- und Fahrtenbuch-Daten werden gelöscht, sobald sie mehr als $monthLabel zurückliegen.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: skin.textMuted,
                                            height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Erledigte Aufgaben ─────────────────────────────
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.task_alt_outlined,
                              label: 'Erledigte Aufgaben'),
                          const SizedBox(height: 12),
                          Text(
                              'Erledigte Aufgaben automatisch löschen nach:',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: skin.textMuted)),
                          const SizedBox(height: 14),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(
                                          alpha: 0.45)
                                      : Colors.white.withValues(
                                          alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                  border: Border.all(
                                      color: skin.glassBorder),
                                ),
                                child: Row(
                                  children: [
                                    {
                                      'key': 'never',
                                      'label': 'Nie'
                                    },
                                    {'key': '1d', 'label': '1T'},
                                    {'key': '2d', 'label': '2T'},
                                    {'key': '1w', 'label': '1W'},
                                    {'key': '1m', 'label': '1M'},
                                  ].map((opt) {
                                    final isSelected =
                                        _taskAutoDelete ==
                                            opt['key'];
                                    return Expanded(
                                      child: GestureDetector(
                                        onTap: () {
                                          setState(() =>
                                              _taskAutoDelete =
                                                  opt['key']!);
                                          Hive.box('einstellungen')
                                              .put(
                                                  'task_auto_delete',
                                                  opt['key']);
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                              milliseconds: 200),
                                          padding: const EdgeInsets
                                              .symmetric(
                                              vertical: 10),
                                          decoration:
                                              BoxDecoration(
                                            color: isSelected
                                                ? (skin.isLight
                                                    ? Colors.white
                                                        .withValues(
                                                            alpha:
                                                                0.80)
                                                    : Colors.white
                                                        .withValues(
                                                            alpha:
                                                                0.14))
                                                : Colors
                                                    .transparent,
                                            borderRadius:
                                                BorderRadius
                                                    .circular(10),
                                            border: isSelected
                                                ? Border.all(
                                                    color: skin
                                                        .glassBorder)
                                                : null,
                                            boxShadow: isSelected
                                                ? [
                                                    BoxShadow(
                                                        color: skin
                                                            .glassShadow,
                                                        blurRadius:
                                                            8,
                                                        offset:
                                                            const Offset(
                                                                0,
                                                                2))
                                                  ]
                                                : null,
                                          ),
                                          child: Center(
                                            child: Text(
                                                opt['label']!,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isSelected
                                                        ? FontWeight
                                                            .w700
                                                        : FontWeight
                                                            .w400,
                                                    color: isSelected
                                                        ? skin.primary
                                                        : skin.surface(
                                                            0.45))),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius:
                                BorderRadius.circular(12),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
                                  sigmaX: 8, sigmaY: 8),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(
                                          alpha: 0.50)
                                      : skin.primary.withValues(
                                          alpha: 0.06),
                                  borderRadius:
                                      BorderRadius.circular(12),
                                  border: Border.all(
                                      color: skin.glassBorder),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                        Icons
                                            .info_outline_rounded,
                                        color: skin.primary
                                            .withValues(alpha: 0.6),
                                        size: 16),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _taskAutoDelete == 'never'
                                            ? 'Erledigte Aufgaben bleiben dauerhaft erhalten.'
                                            : 'Erledigte Aufgaben werden ${_taskAutoDeleteLabel(_taskAutoDelete)} nach dem Abhaken automatisch gelöscht.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: skin.textMuted,
                                            height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: SafeArea(
        child: Column(
          children: [
            _SettingsHeader(
                title: 'Design',
                onBack: () => Navigator.pop(context)),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TiCard(
                      skin: skin,
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          _TiCardHeader(
                              skin: skin,
                              icon: Icons.palette_outlined,
                              label: 'Design'),
                          const SizedBox(height: 12),
                          Text(
                              'Aussehen der App. Änderung wird sofort übernommen.',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: skin.textMuted,
                                  height: 1.5)),
                          const SizedBox(height: 16),
                          _TiSkinPicker(
                              activeSkin: _activeSkin,
                              onSelect: _setSkin),
                        ],
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