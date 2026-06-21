import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _nameController = TextEditingController();
  final _scheduleNameController = TextEditingController();
  int _deleteAfterMonths = 3;
  String _activeSkin = 'chrome';
  bool _nachtschichtModus = false;
  bool _dienstplanDevMode = false;

  @override
  void initState() {
    super.initState();
    final box = Hive.box('einstellungen');
    _nameController.text = box.get('name', defaultValue: '');
    _scheduleNameController.text =
        box.get('dienstplan_name', defaultValue: '');
    _deleteAfterMonths = box.get('deleteAfterMonths', defaultValue: 3);
    _activeSkin = box.get(AppTheme.hiveKey, defaultValue: 'chrome') as String;
    _nachtschichtModus =
        box.get('nachtschicht_modus', defaultValue: false) as bool;
    _dienstplanDevMode =
        box.get('dienstplan_dev_placeholder', defaultValue: false) as bool;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scheduleNameController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() => FocusScope.of(context).unfocus();

  void _setSkin(String key) {
    setState(() => _activeSkin = key);
    Hive.box('einstellungen').put(AppTheme.hiveKey, key);
  }

  void _setNachtschichtModus(bool value) {
    setState(() => _nachtschichtModus = value);
    Hive.box('einstellungen').put('nachtschicht_modus', value);
  }

  Future<void> _toggleDevMode(bool desiredValue) async {
    if (!desiredValue) {
      setState(() => _dienstplanDevMode = false);
      Hive.box('einstellungen').put('dienstplan_dev_placeholder', false);
      return;
    }
    final granted = await _showPinDialog();
    if (granted) {
      setState(() => _dienstplanDevMode = true);
      Hive.box('einstellungen').put('dienstplan_dev_placeholder', true);
    }
  }

  static int _pinFailCount = 0;
  static DateTime? _pinCooldownUntil;

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
                _pinCooldownUntil =
                    DateTime.now().add(const Duration(minutes: 1));
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5B5B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFFEF5B5B).withValues(alpha: 0.3)),
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
                  Text(
                    'Bitte gib den Entwickler-Code ein:',
                    style: TextStyle(color: skin.textMuted, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: skin.surface(0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.borderSubtle),
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
                        hintStyle:
                            TextStyle(color: skin.textHint, letterSpacing: 8),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(children: [
          const Icon(Icons.lock_outline, color: Color(0xFFEF5B5B), size: 20),
          const SizedBox(width: 8),
          Text('Nicht zugelassen',
              style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700)),
        ]),
        content: Text(
          'PIN zu oft falsch eingegeben.',
          style: TextStyle(color: skin.textMuted, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: TextStyle(
                    color: skin.primary, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _capitalizeEachWord(String text) {
    if (text.isEmpty) return text;
    return text
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  void _onNameChanged(String value) {
    final cursor = _nameController.selection.baseOffset;
    final formatted = _capitalizeEachWord(value);
    if (formatted != value) {
      _nameController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(
          offset: cursor > formatted.length ? formatted.length : cursor,
        ),
      );
    }
  }

  void _saveSettings() {
    _dismissKeyboard();
    final box = Hive.box('einstellungen');
    final formatted = _capitalizeEachWord(_nameController.text);
    _nameController.text = formatted;
    box.put('name', formatted);
    box.put('dienstplan_name', _scheduleNameController.text.trim());
    box.put('deleteAfterMonths', _deleteAfterMonths);
    _autoDeleteOldEntries();
    final skin = AppTheme.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('Einstellungen gespeichert ✓'),
      backgroundColor: skin.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ));
  }

void _autoSaveName() {
  final box = Hive.box('einstellungen');
  final formatted = _capitalizeEachWord(_nameController.text);
  _nameController.text = formatted;
  final existingName = box.get('name', defaultValue: '') as String;
  final isNew = existingName.isEmpty;
  if (formatted == existingName) return; // nichts geändert
  box.put('name', formatted);
  final skin = AppTheme.of(context);
  final message = isNew ? 'Name gespeichert ✓' : 'Name geändert ✓';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: skin.primary == Colors.white
        ? const Color(0xFF3DD6C8)
        : skin.primary,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
    duration: const Duration(milliseconds: 1500),
  ));
}

  void _autoDeleteOldEntries() {
    final now = DateTime.now();
    final cutoffMonth = DateTime(now.year, now.month - _deleteAfterMonths);

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
        final entryMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
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
        final dateStr = k.substring('schedule_note_'.length);
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

    // NEU: Fahrtenbuch-Einträge löschen
    final fahrtKeys = settingsBox.keys.where((key) {
      final k = key.toString();
      if (!k.startsWith('fahrten_')) return false;
      try {
        final monthStr = k.substring('fahrten_'.length);
        final parts = monthStr.split('-');
        if (parts.length < 2) return false;
        final entryMonth = DateTime(int.parse(parts[0]), int.parse(parts[1]));
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
        child: GestureDetector(
          onTap: _dismissKeyboard,
          child: Column(
            children: [
              // ── Header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                child: Row(
                  children: [
                    // Zurück-Button — nur Hitbox, kein Container
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const SizedBox(
                        width: 42,
                        height: 42,
                        child: Center(
                          child: Icon(Icons.arrow_back_ios_new, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('Einstellungen',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary,
                            letterSpacing: -0.5)),
                  ],
                ),
              ),

              // ── Scrollbereich ───────────────────────────────────────────────
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _dismissKeyboard();
                    return false;
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Benutzername ──────────────────────────────────────
                        _TiCard(
                          skin: skin,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TiCardHeader(
                                  skin: skin, icon: Icons.person_outline_rounded, label: 'Benutzername'),
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
    if (!hasFocus) {
      _autoSaveName();
    }
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

                        // ── Nachtschicht ──────────────────────────────────────
                        _TiCard(
                          skin: skin,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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

                        // ── Datenverwaltung ───────────────────────────────────
                        _TiCard(
                          skin: skin,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _TiCardHeader(
                                  skin: skin,
                                  icon: Icons.delete_outline_rounded,
                                  label: 'Datenverwaltung'),
                              const SizedBox(height: 12),
                              Text(
                                'Alte Daten nach diesem Zeitraum automatisch löschen:',
                                style: TextStyle(
                                    fontSize: 13, color: skin.textMuted),
                              ),
                              const SizedBox(height: 14),
                              // Segmented-style Auswahl mit Glas
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: skin.isLight
                                          ? Colors.white.withValues(alpha: 0.45)
                                          : Colors.white.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: skin.glassBorder),
                                    ),
                                    child: Row(
                                      children: [1, 3, 6, 12].map((months) {
                                        final isSelected =
                                            _deleteAfterMonths == months;
                                        return Expanded(
                                          child: GestureDetector(
                                            onTap: () {
                                              setState(() => _deleteAfterMonths = months);
                                              Hive.box('einstellungen')
                                                  .put('deleteAfterMonths', months);
                                              _autoDeleteOldEntries();
                                            },
                                            child: AnimatedContainer(
                                              duration: const Duration(
                                                  milliseconds: 200),
                                              padding: const EdgeInsets.symmetric(
                                                  vertical: 10),
                                              decoration: BoxDecoration(
                                                color: isSelected
                                                    ? (skin.isLight
                                                        ? Colors.white.withValues(alpha: 0.80)
                                                        : Colors.white.withValues(alpha: 0.14))
                                                    : Colors.transparent,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: isSelected
                                                    ? Border.all(color: skin.glassBorder, width: 1.0)
                                                    : null,
                                                boxShadow: isSelected
                                                    ? [BoxShadow(color: skin.glassShadow,
                                                          blurRadius: 8, offset: const Offset(0, 2))]
                                                    : null,
                                              ),
                                              child: Center(
                                                child: Text(
                                                  '$months M',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: isSelected
                                                        ? FontWeight.w700
                                                        : FontWeight.w400,
                                                    color: isSelected
                                                        ? skin.primary
                                                        : skin.surface(0.45),
                                                  ),
                                                ),
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
                              // Info-Box mit Glas
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: skin.isLight
                                          ? Colors.white.withValues(alpha: 0.50)
                                          : skin.primary.withValues(alpha: 0.06),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: skin.glassBorder),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.info_outline_rounded,
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

                        // ── Design ────────────────────────────────────────────
                        _TiCard(
                          skin: skin,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
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
                                    height: 1.5),
                              ),
                              const SizedBox(height: 16),
                              _TiSkinPicker(
                                activeSkin: _activeSkin,
                                onSelect: _setSkin,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Dienstplan ────────────────────────────────────────
                        _TiCard(
                          skin: skin,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                _TiCardHeader(
                                    skin: skin,
                                    icon: Icons.calendar_month_outlined,
                                    label: 'Dienstplan'),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFB347)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
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
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFFFB347)
                                        .withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('⚠️',
                                        style: TextStyle(fontSize: 14)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Diese Funktion befindet sich noch in der Beta-Phase.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: const Color(0xFFFFB347)
                                              .withValues(alpha: 0.85),
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              // Dev-Modus mit Glas
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: BackdropFilter(
                                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: skin.isLight
                                          ? Colors.white.withValues(alpha: 0.45)
                                          : Colors.white.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: skin.glassBorder),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFEF5B5B)
                                                    .withValues(alpha: 0.12),
                                                borderRadius:
                                                    BorderRadius.circular(6),
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
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Entwickler-Modus',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: skin.textPrimary,
                                                ),
                                              ),
                                            ),
                                            Switch(
                                              value: _dienstplanDevMode,
                                              onChanged: _toggleDevMode,
                                              activeThumbColor:
                                                  const Color(0xFFEF5B5B),
                                              activeTrackColor:
                                                  const Color(0xFFEF5B5B)
                                                      .withValues(alpha: 0.25),
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
                                              height: 1.45),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 40),
                        Center(
                          child: Text('OpTimes v1.3.0',
                              style: TextStyle(
                                  fontSize: 12, color: skin.textHint)),
                        ),
                      ],
                    ),
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
// LIQUID GLASS TI CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TiCard extends StatelessWidget {
  final AppSkin skin;
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _TiCard({
    required this.skin,
    required this.child,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: skin.glassBlur, sigmaY: skin.glassBlur),
        child: Container(
          width: double.infinity,
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: skin.glassOpacity)
                : skin.bgCard.withValues(alpha: skin.glassOpacity),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.glassBorder, width: 1.0),
            boxShadow: [
              BoxShadow(color: skin.glassShadow, blurRadius: 24,
                  spreadRadius: 0, offset: const Offset(0, 6)),
              BoxShadow(color: skin.glassHighlight, blurRadius: 0,
                  spreadRadius: -1, offset: const Offset(0, 1)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Card-Header mit Icon ohne Container
class _TiCardHeader extends StatelessWidget {
  final AppSkin skin;
  final IconData icon;
  final String label;

  const _TiCardHeader({
    required this.skin,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: skin.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: skin.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// Textfeld im Glass-Stil
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.45)
                : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: skin.glassBorder),
          ),
          child: TextField(
            controller: controller,
            style: TextStyle(color: skin.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: skin.textHint),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: onChanged,
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    );
  }
}

/// Glass Primary Button (kein Gradient mehr)
class _TiButton extends StatelessWidget {
  final AppSkin skin;
  final String label;
  final VoidCallback onTap;

  const _TiButton({
    required this.skin,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.13)
        : skin.primary.withValues(alpha: 0.22);
    final borderColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.28)
        : skin.primary.withValues(alpha: 0.45);
    final textColor = skin.isLight
        ? skin.primary.withValues(alpha: 0.90)
        : skin.primary.withValues(alpha: 0.85);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.5),
          boxShadow: [
            BoxShadow(color: skin.glassShadow, blurRadius: 24,
                spreadRadius: 0, offset: const Offset(0, 6)),
            BoxShadow(color: skin.glassHighlight, blurRadius: 0,
                spreadRadius: -1, offset: const Offset(0, 1)),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        ),
      ),
    );
  }
}

/// Toggle-Zeile mit Beschriftung
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
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: value ? activeColor : skin.textMuted,
          ),
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

// ─────────────────────────────────────────────────────────────────────────────
// Skin-Picker — mit Glas und kleineren Abmessungen
// ─────────────────────────────────────────────────────────────────────────────

class _TiSkinPicker extends StatefulWidget {
  final String activeSkin;
  final void Function(String) onSelect;
  const _TiSkinPicker({required this.activeSkin, required this.onSelect});

  @override
  State<_TiSkinPicker> createState() => _TiSkinPickerState();
}

class _TiSkinPickerState extends State<_TiSkinPicker> {
  static const _skins = ['shield', 'chrome', 'crystal', 'titanium'];
  static const _labels = ['Shield', 'Chrome', 'Crystal', 'Titanium'];

  List<BoxShadow> _cardShadow(AppSkin skin) {
    if (skin.isLight) {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.07),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          spreadRadius: 0,
          offset: const Offset(0, 1),
        ),
      ];
    } else {
      return [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSkin = AppTheme.of(context);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.8,
      ),
      itemCount: _skins.length,
      itemBuilder: (context, index) {
        final key = _skins[index];
        final label = _labels[index];
        final isSelected = widget.activeSkin == key;
        final theme = AppTheme.fromKey(key);

        return GestureDetector(
          onTap: () => widget.onSelect(key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            decoration: BoxDecoration(
              color: isSelected ? theme.primary.withValues(alpha: 0.08) : currentSkin.surface(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? theme.primary.withValues(alpha: 0.5)
                    : currentSkin.borderSubtle,
                width: isSelected ? 1.5 : 0.5,
              ),
              boxShadow: isSelected ? _cardShadow(currentSkin) : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Farbvorschau — 3 gestapelte Kreise (kleiner)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: theme.bgCard,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.black.withValues(alpha: 0.08)),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 6,
                          top: 5,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: theme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        if (theme.gradientColors.length >= 2)
                          Positioned(
                            left: 12,
                            top: 11,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: theme.secondary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isSelected
                                ? theme.primary
                                : currentSkin.textPrimary,
                          ),
                        ),
                        Text(
                          theme.isLight ? 'Hell' : 'Dunkel',
                          style: TextStyle(
                            fontSize: 10,
                            color: currentSkin.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_circle_rounded,
                        color: theme.primary, size: 16),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}