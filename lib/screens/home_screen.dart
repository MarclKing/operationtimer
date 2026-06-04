import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/night_shift_helper.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onNavigateToMonth;
  const HomeScreen({super.key, required this.onNavigateToMonth});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  DateTime _selectedDate = DateTime.now();
  final _kommenController = TextEditingController();
  final _gehenController = TextEditingController();
  final _teamchefController = TextEditingController();
  final _notizController = TextEditingController();
  late AnimationController _saveAnimController;
  bool _initialTimeSet = false;
  
  double _horizontalDragStart = 0;
  bool _isHorizontalSwipe = false;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _saveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _loadEntry();
  }

  @override
  void dispose() {
    _saveAnimController.dispose();
    _kommenController.dispose();
    _gehenController.dispose();
    _teamchefController.dispose();
    _notizController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Guten Morgen';
    if (hour < 18) return 'Guten Tag';
    return 'Guten Abend';
  }

  String get _firstName {
    final box = Hive.box('einstellungen');
    final fullName = box.get('name', defaultValue: '') as String;
    if (fullName.trim().isEmpty) return '';
    return fullName.trim().split(' ').first;
  }

  String _getCurrentTimeFormatted() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  void _resetToCurrentTime() {
    _kommenController.text = _getCurrentTimeFormatted();
  }

  void _resetAllFields() {
    _kommenController.text = _getCurrentTimeFormatted();
    _gehenController.clear();
    _teamchefController.clear();
    _notizController.clear();
  }

  void _loadEntry() {
    final isToday = _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    setState(() {
      if (!isToday) {
        _resetAllFields();
      } else {
        _resetAllFields();
      }
      _initialTimeSet = true;
    });
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
      _initialTimeSet = false;
    });
    _loadEntry();
  }

  TimeOfDay? _parseTime(String text) {
    if (text.isEmpty || text == '--:--') return null;
    try {
      final parts = text.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  void _adjustTime(TextEditingController controller, int minutesDelta) {
    final isKommen = controller == _kommenController;
    final isGehen = controller == _gehenController;
    
    final current = _parseTime(controller.text) ?? TimeOfDay.now();
    final total =
        (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    
    final newHour = total ~/ 60;
    final newMinute = total % 60;
    
    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
      final gehenTime = _parseTime(_gehenController.text);
      if (gehenTime != null) {
        final gehenMinutes = gehenTime.hour * 60 + gehenTime.minute;
        if (total > gehenMinutes) return;
      }
    }
    
    if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
      final kommenTime = _parseTime(_kommenController.text);
      if (kommenTime != null) {
        final kommenMinutes = kommenTime.hour * 60 + kommenTime.minute;
        if (total < kommenMinutes) return;
      }
    }
    
    setState(() {
      controller.text =
          '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  void _saveEntry(BuildContext context) async {
    final kommen = _kommenController.text.trim();
    final gehen = _gehenController.text.trim();
    final tkf = _teamchefController.text.trim();
    final notiz = _notizController.text.trim();
    
    final result = await NightShiftHelper.save(
      context: context,
      datum: _selectedDate,
      kommen: kommen,
      gehen: gehen,
      tkf: tkf,
      notiz: notiz,
    );
    
    if (result == SaveResult.saved || result == SaveResult.splitSaved) {
      await _saveAnimController.forward();
      await _saveAnimController.reverse();
      
      final isToday = _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now());
      if (isToday) {
        _resetAllFields();
      }
      
      if (mounted) {
        final skin = AppTheme.of(context);
        String message;
        if (result == SaveResult.splitSaved) {
          message = '✓ Nachtschicht gespeichert (2 Einträge)';
        } else {
          message = '✓ Eintrag gespeichert';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(message),
          backgroundColor: skin.primary == Colors.white
              ? const Color(0xFF3DD6C8)
              : skin.primary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
      }
    }
  }

  // 🔥 KORRIGIERT: iOS-ähnlicher Date Picker mit "Heute" Button
  Future<void> _selectDateWithPicker() async {
    final skin = AppTheme.of(context);
    DateTime tempDate = _selectedDate;
    
    // Erstelle einen Unique Key für den Picker, um ihn neu zu erstellen
    UniqueKey pickerKey = UniqueKey();
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Container(
              decoration: BoxDecoration(
                color: skin.bgSheet,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border.all(color: skin.borderMedium),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: skin.surface(0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Datum auswählen',
                    style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 🔥 Verwende einen Key, um den Picker neu zu erstellen
                  SizedBox(
                    height: 200,
                    child: CupertinoDatePicker(
                      key: pickerKey,
                      mode: CupertinoDatePickerMode.date,
                      initialDateTime: tempDate,
                      minimumDate: DateTime(2020),
                      maximumDate: DateTime(2030),
                      backgroundColor: Colors.transparent,
                      onDateTimeChanged: (DateTime newDate) {
                        tempDate = newDate;
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // 🔥 "Heute" Button - erstellt Picker komplett neu
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            tempDate = DateTime.now();
                            // 🔥 Neuen Key generieren, um Picker neu zu erstellen
                            pickerKey = UniqueKey();
                            setDialogState(() {});
                          },
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(16, 0, 4, 0),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              color: skin.surface(0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: skin.borderSubtle),
                            ),
                            child: Center(
                              child: Text(
                                'Heute',
                                style: TextStyle(
                                  color: skin.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // 🔥 "Übernehmen" Button
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedDate = tempDate;
                              _initialTimeSet = false;
                            });
                            _loadEntry();
                            Navigator.pop(context);
                          },
                          child: Container(
                            margin: const EdgeInsets.fromLTRB(4, 0, 16, 0),
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            decoration: BoxDecoration(
                              gradient: skin.gradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Text(
                                'Übernehmen',
                                style: TextStyle(
                                  color: skin.onGradient,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _selectTimeWithPicker(TextEditingController controller) async {
    final isKommen = controller == _kommenController;
    final isGehen = controller == _gehenController;
    final nightShiftEnabled = NightShiftHelper.isNightShiftEnabled();
    final skin = AppTheme.of(context);
    
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _IOSTimePicker(
        initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
        skin: skin,
        onTimeSelected: (t) {
          final newMinutes = t.hour * 60 + t.minute;
          
          if (!nightShiftEnabled && isKommen && _gehenController.text.isNotEmpty) {
            final gehenTime = _parseTime(_gehenController.text);
            if (gehenTime != null) {
              final gehenMinutes = gehenTime.hour * 60 + gehenTime.minute;
              if (newMinutes > gehenMinutes) return;
            }
          }
          
          if (!nightShiftEnabled && isGehen && _kommenController.text.isNotEmpty) {
            final kommenTime = _parseTime(_kommenController.text);
            if (kommenTime != null) {
              final kommenMinutes = kommenTime.hour * 60 + kommenTime.minute;
              if (newMinutes < kommenMinutes) return;
            }
          }
          
          setState(() {
            controller.text =
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;
    final isChromeSkin = skin.key == 'chrome';

    return Scaffold(
      backgroundColor: skin.bgBase,
      resizeToAvoidBottomInset: true,
      body: NotificationListener<ScrollNotification>(
        onNotification: (scrollInfo) {
          return false;
        },
        child: GestureDetector(
          onHorizontalDragStart: (details) {
            _horizontalDragStart = details.globalPosition.dx;
            _isHorizontalSwipe = false;
          },
          onHorizontalDragUpdate: (details) {
            final delta = details.globalPosition.dx - _horizontalDragStart;
            if (delta.abs() > 20 && !_isHorizontalSwipe) {
              _isHorizontalSwipe = true;
            }
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -400) {
              widget.onNavigateToMonth();
            }
            _isHorizontalSwipe = false;
          },
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: ListView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 80),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _greeting,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: skin.white(0.7),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('👋', style: TextStyle(fontSize: 20)),
                        ],
                      ),
                      if (_firstName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _firstName,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: skin.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      _NavBtn(icon: Icons.chevron_left, onTap: () => _changeDate(-1)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectDateWithPicker,
                          onHorizontalDragEnd: (d) {
                            final v = d.primaryVelocity ?? 0;
                            if (v < -300) _changeDate(1);
                            if (v > 300) _changeDate(-1);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                            decoration: BoxDecoration(
                              color: skin.bgCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isToday
                                    ? skin.primaryWithAlpha(0.5)
                                    : skin.white(0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('📅',
                                    style: TextStyle(fontSize: 14)),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        isToday ? 'HEUTE' : 'DATUM',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: isToday
                                              ? skin.primary
                                              : skin.white(0.38),
                                          letterSpacing: 1.0,
                                        ),
                                      ),
                                      Text(
                                        DateFormat('EEEE, d. MMMM yyyy', 'de')
                                            .format(_selectedDate),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: skin.textPrimary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(Icons.chevron_right,
                                    color: skin.white(0.3), size: 14),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      _NavBtn(
                          icon: Icons.chevron_right,
                          onTap: () => _changeDate(1)),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SwipeTimeCard(
                          label: 'KOMMEN',
                          color: skin.kommenColor,
                          controller: _kommenController,
                          onTap: () => _selectTimeWithPicker(_kommenController),
                          onSwipeUp: () => _adjustTime(_kommenController, 1),
                          onSwipeDown: () => _adjustTime(_kommenController, -1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SwipeTimeCard(
                          label: 'GEHEN',
                          color: skin.gehenColor,
                          controller: _gehenController,
                          onTap: () => _selectTimeWithPicker(_gehenController),
                          onSwipeUp: () => _adjustTime(_gehenController, 1),
                          onSwipeDown: () => _adjustTime(_gehenController, -1),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '↕ Wischen = Minute  ·  Tippen = Uhrzeit wählen',
                    style: TextStyle(
                        fontSize: 11, color: skin.white(0.3)),
                  ),
                ),

                const SizedBox(height: 20),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _GlassInput(
                    label: 'TAGESKOMMANDOFÜHRER',
                    emoji: '👤',
                    controller: _teamchefController,
                    hint: 'Name des TKF',
                  ),
                ),

                const SizedBox(height: 12),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _GlassInput(
                    label: 'NOTIZ',
                    emoji: '📝',
                    controller: _notizController,
                    hint: 'Optionale Notiz...',
                  ),
                ),

                const SizedBox(height: 28),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 0.95).animate(
                      CurvedAnimation(
                          parent: _saveAnimController,
                          curve: Curves.easeInOut),
                    ),
                    child: GestureDetector(
                      onTap: () => _saveEntry(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          gradient: isChromeSkin
                              ? const LinearGradient(
                                  colors: [Color(0xFF333333), Color(0xFF555555)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                )
                              : const LinearGradient(
                                  colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: isChromeSkin
                                  ? Colors.black.withValues(alpha: 0.3)
                                  : const Color(0xFF6C63FF).withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.save_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Eintrag speichern',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: skin.white(0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: skin.white(0.1)),
        ),
        child: Icon(icon, color: skin.white(0.54), size: 22),
      ),
    );
  }
}

class _GlassInput extends StatelessWidget {
  final String label;
  final String emoji;
  final TextEditingController controller;
  final String hint;

  const _GlassInput({
    required this.label,
    required this.emoji,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: skin.white(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.white(0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: skin.primaryWithAlpha(0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child:
                Center(child: Text(emoji, style: const TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: skin.primary,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  style: TextStyle(color: skin.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: skin.white(0.25), fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IOSTimePicker extends StatefulWidget {
  final TimeOfDay initialTime;
  final AppSkin skin;
  final Function(TimeOfDay) onTimeSelected;

  const _IOSTimePicker({
    required this.initialTime,
    required this.skin,
    required this.onTimeSelected,
  });

  @override
  State<_IOSTimePicker> createState() => _IOSTimePickerState();
}

class _IOSTimePickerState extends State<_IOSTimePicker> {
  late int _selectedHour;
  late int _selectedMinute;
  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    _selectedHour = widget.initialTime.hour;
    _selectedMinute = widget.initialTime.minute;
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(initialItem: _selectedMinute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _setCurrentTime() {
    final now = DateTime.now();
    final nowHour = now.hour;
    final nowMinute = now.minute;
    
    _hourController.animateToItem(
      nowHour,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    _minuteController.animateToItem(
      nowMinute,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    
    setState(() {
      _selectedHour = nowHour;
      _selectedMinute = nowMinute;
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;

    return Container(
      decoration: BoxDecoration(
        color: skin.bgSheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: skin.white(0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: skin.white(0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Uhrzeit auswählen',
            style: TextStyle(
                color: skin.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _hourController,
                    magnification: 1.2,
                    backgroundColor: Colors.transparent,
                    itemExtent: 40,
                    looping: false,
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedHour = index;
                      });
                    },
                    children: List.generate(
                      24,
                      (hour) => Center(
                        child: Text(
                          hour.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: _selectedHour == hour
                                ? skin.primary
                                : skin.white(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Text(
                  ':',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: skin.primary,
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _minuteController,
                    magnification: 1.2,
                    backgroundColor: Colors.transparent,
                    itemExtent: 40,
                    looping: false,
                    onSelectedItemChanged: (index) {
                      setState(() {
                        _selectedMinute = index;
                      });
                    },
                    children: List.generate(
                      60,
                      (minute) => Center(
                        child: Text(
                          minute.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: _selectedMinute == minute
                                ? skin.primary
                                : skin.white(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _setCurrentTime,
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: skin.white(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.primary.withValues(alpha: 0.3)),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.access_time, color: skin.primary, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            'Jetzt',
                            style: TextStyle(
                              color: skin.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    widget.onTimeSelected(
                      TimeOfDay(hour: _selectedHour, minute: _selectedMinute),
                    );
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: skin.gradient,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'Übernehmen',
                        style: TextStyle(
                          color: skin.onGradient,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }
}

class _SwipeTimeCard extends StatefulWidget {
  final String label;
  final Color color;
  final TextEditingController controller;
  final VoidCallback onTap;
  final VoidCallback onSwipeUp;
  final VoidCallback onSwipeDown;

  const _SwipeTimeCard({
    required this.label,
    required this.color,
    required this.controller,
    required this.onTap,
    required this.onSwipeUp,
    required this.onSwipeDown,
  });

  @override
  State<_SwipeTimeCard> createState() => _SwipeTimeCardState();
}

class _SwipeTimeCardState extends State<_SwipeTimeCard> {
  double _dragStart = 0;
  double _accumulated = 0;
  static const double _pxPerMin = 12;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onVerticalDragStart: (d) {
        _dragStart = d.localPosition.dy;
        _accumulated = 0;
      },
      onVerticalDragUpdate: (d) {
        _accumulated += _dragStart - d.localPosition.dy;
        _dragStart = d.localPosition.dy;
        while (_accumulated >= _pxPerMin) {
          _accumulated -= _pxPerMin;
          widget.onSwipeUp();
        }
        while (_accumulated <= -_pxPerMin) {
          _accumulated += _pxPerMin;
          widget.onSwipeDown();
        }
      },
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (_, __) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: widget.color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: widget.color,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Icon(
                    Icons.unfold_more,
                    color: widget.color.withValues(alpha: 0.5),
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.controller.text.isEmpty
                      ? '--:--'
                      : widget.controller.text,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -1,
                  ),
                  maxLines: 1,
                ),
              ),
              const SizedBox(height: 4),
              
            ],
          ),
        ),
      ),
    );
  }
}