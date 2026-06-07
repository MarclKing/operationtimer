import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

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
    _autoDeleteOldEntries();
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

  // ── Dev-Modus hinter PIN-Code ─────────────────────────────────────────────
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

  // ── PIN Dialog ────────────────────────────────────────────────────────────
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
                  borderRadius: BorderRadius.circular(20)),
              title: Row(children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF5B5B).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(
                        color:
                            const Color(0xFFEF5B5B).withValues(alpha: 0.35)),
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
                      borderRadius: BorderRadius.circular(12),
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
          'PIN zu oft falsch eingegeben, nicht zugelassen.',
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

  // ─────────────────────────────────────────────────────────────────────────

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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  /// Löscht alle Einträge (Zeiterfassung + Dienstplan), deren Monat
  /// kalendarisch älter als [_deleteAfterMonths] Monate ist.
  ///
  /// Beispiel: Heute = Juni, Einstellung = 3 Monate
  /// → Cutoff-Monat = März  → alles vor April wird gelöscht.
  void _autoDeleteOldEntries() {
    final now = DateTime.now();
    // Cutoff ist der erste Tag des Monats, der genau X Monate zurückliegt.
    // Alles DAVOR (also älter) wird gelöscht.
    final cutoffMonth = DateTime(now.year, now.month - _deleteAfterMonths);

    // ── Zeiterfassung (Box 'arbeitszeiten', Keys: 'yyyy-MM-dd') ──────────
    final zeitBox = Hive.box('arbeitszeiten');
    final zeitKeysToDelete = zeitBox.keys.where((key) {
      try {
        final date = DateTime.parse(key.toString());
        // Monatsbeginn des Eintrags
        final entryMonth = DateTime(date.year, date.month);
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in zeitKeysToDelete) {
      zeitBox.delete(key);
    }

    // ── Dienstplan (Box 'einstellungen', Keys: 'schedule_yyyy-MM') ───────
    final settingsBox = Hive.box('einstellungen');
    final scheduleKeysToDelete = settingsBox.keys.where((key) {
      final k = key.toString();
      if (!k.startsWith('schedule_')) return false;
      try {
        // Key-Format: 'schedule_yyyy-MM'
        final monthStr = k.substring('schedule_'.length); // → 'yyyy-MM'
        final parts = monthStr.split('-');
        if (parts.length < 2) return false;
        final entryMonth =
            DateTime(int.parse(parts[0]), int.parse(parts[1]));
        return entryMonth.isBefore(cutoffMonth);
      } catch (_) {
        return false;
      }
    }).toList();
    for (final key in scheduleKeysToDelete) {
      settingsBox.delete(key);
    }

    // ── Dienstplan-Notizen (Keys: 'schedule_note_yyyy-MM-dd') ────────────
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
                        child: Icon(Icons.arrow_back_ios_new,
                            color: skin.textPrimary, size: 16),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Text('Einstellungen',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: skin.textPrimary)),
                  ],
                ),
              ),
              Expanded(
                child: NotificationListener<ScrollNotification>(
                  onNotification: (_) {
                    _dismissKeyboard();
                    return false;
                  },
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 8),

                        // ── Benutzername ────────────────────────────────────
                        _SettingsCard(
                          emoji: '👤',
                          title: 'Benutzername',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vor- und Nachname. Der Vorname erscheint in der Begrüßung, der vollständige Name im PDF und wird für die Dienstplan-Erkennung verwendet.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: skin.textMuted,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                decoration: BoxDecoration(
                                  color: skin.surface(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                  border:
                                      Border.all(color: skin.borderSubtle),
                                ),
                                child: TextField(
                                  controller: _nameController,
                                  style: TextStyle(
                                      color: skin.textPrimary, fontSize: 15),
                                  decoration: InputDecoration(
                                    hintText: 'z.B. Max Mustermann',
                                    hintStyle:
                                        TextStyle(color: skin.textHint),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                  onChanged: _onNameChanged,
                                  onSubmitted: (_) => _dismissKeyboard(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              _GradientButton(
                                  label: 'Speichern', onTap: _saveSettings),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Nachtschicht ────────────────────────────────────
                        _SettingsCard(
                          emoji: '🌙',
                          title: 'Nachtschicht-Modus',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wenn aktiviert, erkennt die App automatisch Nachtschichten (z.B. Kommen 22:00 → Gehen 02:00) und legt zwei Einträge an:\n\n'
                                '• Eintrag 1: Kommen bis 23:59 (selber Tag)\n'
                                '• Eintrag 2: 00:00 bis Gehen (nächster Tag)',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: skin.textMuted,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _nachtschichtModus
                                        ? '✅ Aktiviert'
                                        : '⬜ Deaktiviert',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: _nachtschichtModus
                                          ? skin.statComplete
                                          : skin.textMuted,
                                    ),
                                  ),
                                  Switch(
                                    value: _nachtschichtModus,
                                    onChanged: _setNachtschichtModus,
                                    activeThumbColor: skin.statComplete,
                                    activeTrackColor: skin.statComplete
                                        .withValues(alpha: 0.3),
                                    inactiveThumbColor: skin.textMuted,
                                    inactiveTrackColor: skin.surface(0.1),
                                  ),
                                ],
                              ),
                              if (_nachtschichtModus) ...[
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: skin.statComplete
                                        .withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: skin.statComplete
                                            .withValues(alpha: 0.2)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text('🌙',
                                          style: TextStyle(fontSize: 16)),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Beim Speichern wird ein Bestätigungs-Dialog angezeigt, bevor die zwei Einträge angelegt werden.',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: skin.statComplete
                                                  .withValues(alpha: 0.8)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Datenverwaltung ─────────────────────────────────
                        _SettingsCard(
                          emoji: '🗑',
                          title: 'Datenverwaltung',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wähle, nach wie vielen Monaten alte Daten automatisch gelöscht werden sollen:',
                                style: TextStyle(
                                    fontSize: 13, color: skin.textMuted),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [1, 3, 6, 12].map((months) {
                                  final isSelected =
                                      _deleteAfterMonths == months;
                                  return GestureDetector(
                                    onTap: () => setState(
                                        () => _deleteAfterMonths = months),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 200),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        gradient:
                                            isSelected ? skin.gradient : null,
                                        color: isSelected
                                            ? null
                                            : skin.surface(0.05),
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.transparent
                                              : skin.borderSubtle,
                                        ),
                                      ),
                                      child: Text(
                                        '$months Monat${months > 1 ? 'e' : ''}',
                                        style: TextStyle(
                                          color: isSelected
                                              ? skin.onGradient
                                              : skin.textMuted,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: skin.surface(0.03),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: skin.borderSubtle),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: skin.textMuted, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Zeiterfassungs-Einträge und Dienstplan-Daten werden automatisch gelöscht, sobald ihr Monat kalendarisch mehr als $monthLabel zurückliegt – unabhängig davon, wann sie eingetragen wurden.',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: skin.textMuted,
                                            height: 1.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Design ──────────────────────────────────────────
                        _SettingsCard(
                          emoji: '🎨',
                          title: 'Design',
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Wähle das Aussehen der App. Die Änderung wird sofort übernommen.',
                                style: TextStyle(
                                    fontSize: 13,
                                    color: skin.textMuted,
                                    height: 1.5),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _SimpleSkinOption(
                                      label: 'Chrome',
                                      isSelected: _activeSkin == 'chrome',
                                      onTap: () => _setSkin('chrome'),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _SimpleSkinOption(
                                      label: 'Space',
                                      isSelected: _activeSkin == 'space',
                                      onTap: () => _setSkin('space'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // ── Dienstplan ──────────────────────────────────────
                        _SettingsCardWithBadge(
                          emoji: '📅',
                          title: 'Dienstplan',
                          badge: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFB347)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: const Color(0xFFFFB347)
                                      .withValues(alpha: 0.4)),
                            ),
                            child: const Text('BETA',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFB347),
                                    letterSpacing: 0.8)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Beta warning
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFB347)
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFFFB347)
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('⚠️',
                                        style: TextStyle(fontSize: 15)),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Diese Funktion befindet sich noch in der Beta-Phase. Es kann zu Fehlern bei der Erkennung und Darstellung des Dienstplans kommen.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: const Color(0xFFFFB347)
                                              .withValues(alpha: 0.9),
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 16),

                              // ── Entwickler-Modus ──────────────────────────
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: skin.surface(0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: skin.borderSubtle),
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
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            border: Border.all(
                                                color:
                                                    const Color(0xFFEF5B5B)
                                                        .withValues(
                                                            alpha: 0.35)),
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
                                                  .withValues(alpha: 0.3),
                                          inactiveThumbColor:
                                              skin.textMuted,
                                          inactiveTrackColor:
                                              skin.surface(0.1),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Aktiviert erweiterte Fehlermeldungen beim PDF-Import mit technischen Details. Erleichtert die Fehleranalyse bei Problemen mit dem Dienstplan-Import.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: skin.textMuted,
                                          height: 1.45),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),
                        Center(
                          child: Text('OpTimes v1.0',
                              style: TextStyle(
                                  fontSize: 12, color: skin.textHint)),
                        ),
                        const SizedBox(height: 8),
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
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SimpleSkinOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  const _SimpleSkinOption(
      {required this.label, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          gradient: isSelected ? skin.gradient : null,
          color: isSelected ? null : skin.surface(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? Colors.transparent : skin.borderSubtle),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? skin.onGradient : skin.textMuted)),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final String emoji;
  final String title;
  final Widget child;
  const _SettingsCard(
      {required this.emoji, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: skin.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _SettingsCardWithBadge extends StatelessWidget {
  final String emoji;
  final String title;
  final Widget badge;
  final Widget child;
  const _SettingsCardWithBadge(
      {required this.emoji,
      required this.title,
      required this.badge,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: skin.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: skin.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text(title,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: skin.textPrimary)),
              const SizedBox(width: 8),
              badge,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GradientButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: skin.gradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: skin.onGradient,
                  fontWeight: FontWeight.w700,
                  fontSize: 15)),
        ),
      ),
    );
  }
}