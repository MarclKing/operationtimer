import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

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

  void _loadEntry() {
    final box = Hive.box('arbeitszeiten');
    final entry = box.get(_dateKey);
    setState(() {
      if (entry != null) {
        _kommenController.text = entry['kommen'] ?? '';
        _gehenController.text = entry['gehen'] ?? '';
        _teamchefController.text = entry['TKF'] ?? '';
        _notizController.text = entry['notiz'] ?? '';
      } else {
        _kommenController.clear();
        _gehenController.clear();
        _teamchefController.clear();
        _notizController.clear();
      }
    });
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadEntry();
  }

  // Zeit aus String parsen
  TimeOfDay? _parseTime(String text) {
    if (text.isEmpty || text == '--:--') return null;
    try {
      final parts = text.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  // Zeit um Minuten ändern per Swipe
  void _adjustTime(TextEditingController controller, int minutesDelta) {
    TimeOfDay current = _parseTime(controller.text) ?? TimeOfDay.now();
    final totalMinutes = current.hour * 60 + current.minute + minutesDelta;
    final clampedMinutes = totalMinutes.clamp(0, 23 * 60 + 59);
    final newHour = clampedMinutes ~/ 60;
    final newMinute = clampedMinutes % 60;
    setState(() {
      controller.text =
          '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  void _saveEntry() async {
    await _saveAnimController.forward();
    await _saveAnimController.reverse();
    final box = Hive.box('arbeitszeiten');
    box.put(_dateKey, {
      'kommen': _kommenController.text,
      'gehen': _gehenController.text,
      'TKF': _teamchefController.text,
      'notiz': _notizController.text,
      'datum': _dateKey,
    });
    setState(() {
      _kommenController.clear();
      _gehenController.clear();
      _teamchefController.clear();
      _notizController.clear();
      _selectedDate = DateTime.now();
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Eintrag gespeichert ✓'),
          backgroundColor: const Color(0xFF6C63FF),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6C63FF),
              surface: Color(0xFF141420),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadEntry();
    }
  }

  Future<void> _selectTime(TextEditingController controller) async {
    final current = _parseTime(controller.text);
    final picked = await showTimePicker(
      context: context,
      initialTime: current ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF6C63FF),
              surface: Color(0xFF141420),
            ),
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
      },
    );
    if (picked != null) {
      setState(() {
        controller.text =
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -300) {
          _changeDate(1);
        } else if (details.primaryVelocity! > 300) {
          _changeDate(-1);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0F),
        body: SafeArea(
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                // Begrüßung
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      children: [
                        TextSpan(text: _greeting),
                        if (_firstName.isNotEmpty) ...[
                          const TextSpan(text: ', '),
                          TextSpan(
                            text: _firstName,
                            style: const TextStyle(color: Color(0xFF6C63FF)),
                          ),
                        ],
                        const TextSpan(text: ' 👋'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Datum Navigation
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _changeDate(-1),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Icon(Icons.chevron_left, color: Colors.white54, size: 20),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: _selectDate,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF141420),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isToday
                                    ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                                    : Colors.white.withValues(alpha: 0.1),
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text('📅', style: TextStyle(fontSize: 16)),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isToday ? 'HEUTE' : 'DATUM',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: isToday ? const Color(0xFF6C63FF) : Colors.white38,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    Text(
                                      DateFormat('EEEE, d. MMMM yyyy', 'de').format(_selectedDate),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Icon(Icons.calendar_today_outlined,
                                    color: Colors.white.withValues(alpha: 0.3), size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      GestureDetector(
                        onTap: () => _changeDate(1),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: const Icon(Icons.chevron_right, color: Colors.white54, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Kommen & Gehen
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SwipeTimeCard(
                          label: 'KOMMEN',
                          color: const Color(0xFF4ECDC4),
                          controller: _kommenController,
                          onTap: () => _selectTime(_kommenController),
                          onSwipeUp: () => _adjustTime(_kommenController, 1),
                          onSwipeDown: () => _adjustTime(_kommenController, -1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SwipeTimeCard(
                          label: 'GEHEN',
                          color: const Color(0xFFFF6B6B),
                          controller: _gehenController,
                          onTap: () => _selectTime(_gehenController),
                          onSwipeUp: () => _adjustTime(_gehenController, 1),
                          onSwipeDown: () => _adjustTime(_gehenController, -1),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '↕ Auf Kachel wischen = Minute anpassen  ·  Tippen = Uhrzeit wählen',
                    style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.25)),
                  ),
                ),
                const SizedBox(height: 12),

                // TKF
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _GlassInputCard(
                    label: 'TAGESKOMMANDOFÜHRER',
                    emoji: '👤',
                    controller: _teamchefController,
                    hint: 'Name des Tageskommandoführers',
                  ),
                ),
                const SizedBox(height: 12),

                // Notiz
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _GlassInputCard(
                    label: 'NOTIZ',
                    emoji: '📝',
                    controller: _notizController,
                    hint: 'Optionale Notiz zum Tag...',
                    maxLines: 3,
                  ),
                ),
                const SizedBox(height: 24),

                // Speichern Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 0.95).animate(
                      CurvedAnimation(parent: _saveAnimController, curve: Curves.easeInOut),
                    ),
                    child: GestureDetector(
                      onTap: _saveEntry,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Text(
                            '✓  Eintrag speichern',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Kachel mit Swipe-Funktion für Zeitanpassung
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onVerticalDragStart: (details) {
        _dragStart = details.localPosition.dy;
        _accumulated = 0;
      },
      onVerticalDragUpdate: (details) {
        _accumulated += _dragStart - details.localPosition.dy;
        _dragStart = details.localPosition.dy;
        // Pro 8 Pixel = 1 Minute
        if (_accumulated >= 8) {
          _accumulated -= 8;
          widget.onSwipeUp();
        } else if (_accumulated <= -8) {
          _accumulated += 8;
          widget.onSwipeDown();
        }
      },
      child: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Container(
          padding: const EdgeInsets.all(18),
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
                  Icon(Icons.unfold_more, color: widget.color.withValues(alpha: 0.5), size: 16),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.controller.text.isEmpty ? '--:--' : widget.controller.text,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.controller.text.isEmpty ? 'Tippen zum Eintragen' : 'Wischen zum Anpassen',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassInputCard extends StatelessWidget {
  final String label;
  final String emoji;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _GlassInputCard({
    required this.label,
    required this.emoji,
    required this.controller,
    required this.hint,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
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