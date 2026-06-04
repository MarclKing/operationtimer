import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

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
  bool _dragOnInteractive = false;

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
        _initialTimeSet = true;
      } else {
        _kommenController.clear();
        _gehenController.clear();
        _teamchefController.clear();
        _notizController.clear();
        if (!_initialTimeSet &&
            _dateKey == DateFormat('yyyy-MM-dd').format(DateTime.now())) {
          final now = DateTime.now();
          _kommenController.text =
              '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
          _initialTimeSet = true;
        }
      }
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
    final current = _parseTime(controller.text) ?? TimeOfDay.now();
    final total =
        (current.hour * 60 + current.minute + minutesDelta).clamp(0, 23 * 60 + 59);
    setState(() {
      controller.text =
          '${(total ~/ 60).toString().padLeft(2, '0')}:${(total % 60).toString().padLeft(2, '0')}';
    });
    HapticFeedback.selectionClick();
  }

  void _saveEntry() async {
    await _saveAnimController.forward();
    await _saveAnimController.reverse();
    Hive.box('arbeitszeiten').put(_dateKey, {
      'kommen': _kommenController.text,
      'gehen': _gehenController.text,
      'TKF': _teamchefController.text,
      'notiz': _notizController.text,
      'datum': _dateKey,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Eintrag gespeichert ✓'),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ));
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6C63FF),
            surface: Color(0xFF141420),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _initialTimeSet = false;
      });
      _loadEntry();
    }
  }

  Future<void> _selectTimeWithPicker(TextEditingController controller) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _IOSTimePicker(
        initialTime: _parseTime(controller.text) ?? TimeOfDay.now(),
        onTimeSelected: (t) => setState(() {
          controller.text =
              '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onHorizontalDragStart: (_) => _dragOnInteractive = false,
        onHorizontalDragEnd: (d) {
          if (_dragOnInteractive) return;
          if ((d.primaryVelocity ?? 0) < -400) widget.onNavigateToMonth();
        },
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),
                
                // ── HEADER ─────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      
                     
                      const SizedBox(height: 20),
                      
                      // Begrüßung
                      Row(
                        children: [
                          Text(
                            _greeting,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            '👋',
                            style: TextStyle(fontSize: 20),
                          ),
                        ],
                      ),
                      if (_firstName.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _firstName,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF6C63FF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),

                // ── Datum Navigation ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Listener(
                    onPointerDown: (_) => _dragOnInteractive = true,
                    child: Row(
                      children: [
                        _NavBtn(
                          icon: Icons.chevron_left,
                          onTap: () => _changeDate(-1),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: _selectDate,
                            onHorizontalDragEnd: (d) {
                              final v = d.primaryVelocity ?? 0;
                              if (v < -300) _changeDate(1);
                              if (v > 300) _changeDate(-1);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                                  const Text('📅', style: TextStyle(fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isToday ? 'HEUTE' : 'DATUM',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: isToday ? const Color(0xFF6C63FF) : Colors.white38,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                        Text(
                                          DateFormat('EEEE, d. MMMM yyyy', 'de').format(_selectedDate),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.calendar_today_outlined,
                                      color: Colors.white.withValues(alpha: 0.3), size: 14),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _NavBtn(
                          icon: Icons.chevron_right,
                          onTap: () => _changeDate(1),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── Kommen & Gehen ─────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Listener(
                    onPointerDown: (_) => _dragOnInteractive = true,
                    child: Row(
                      children: [
                        Expanded(
                          child: _SwipeTimeCard(
                            label: 'KOMMEN',
                            color: const Color(0xFF4ECDC4),
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
                            color: const Color(0xFFFF6B6B),
                            controller: _gehenController,
                            onTap: () => _selectTimeWithPicker(_gehenController),
                            onSwipeUp: () => _adjustTime(_gehenController, 1),
                            onSwipeDown: () => _adjustTime(_gehenController, -1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    '↕ Wischen = Minute  ·  Tippen = Uhrzeit wählen',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.3)),
                  ),
                ),

                const SizedBox(height: 20),

                // ── TKF ─────────────────────────────────────────────────────
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

                // ── Notiz ───────────────────────────────────────────────────
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

                // ── Speichern Button (mit overflow Fix) ─────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 1.0, end: 0.95).animate(
                      CurvedAnimation(
                          parent: _saveAnimController,
                          curve: Curves.easeInOut),
                    ),
                    child: GestureDetector(
                      onTap: _saveEntry,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
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
                        child: const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '✓  Eintrag speichern',
                            style: TextStyle(
                              fontSize: 15,
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

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: Icon(icon, color: Colors.white54, size: 22),
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
    return Container(
      constraints: const BoxConstraints(minHeight: 68),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFF6C63FF).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 14))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8)),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25),
                        fontSize: 14),
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
  final Function(TimeOfDay) onTimeSelected;

  const _IOSTimePicker(
      {required this.initialTime, required this.onTimeSelected});

  @override
  State<_IOSTimePicker> createState() => _IOSTimePickerState();
}

class _IOSTimePickerState extends State<_IOSTimePicker> {
  late int _selH;
  late int _selM;
  late FixedExtentScrollController _hCtrl;
  late FixedExtentScrollController _mCtrl;

  @override
  void initState() {
    super.initState();
    _selH = widget.initialTime.hour;
    _selM = widget.initialTime.minute;
    _hCtrl = FixedExtentScrollController(initialItem: _selH + 1000);
    _mCtrl = FixedExtentScrollController(initialItem: _selM + 1000);
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _mCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141420),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Uhrzeit auswählen',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: Row(
              children: [
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _hCtrl,
                    magnification: 1.2,
                    backgroundColor: Colors.transparent,
                    itemExtent: 40,
                    looping: true,
                    onSelectedItemChanged: (i) =>
                        setState(() => _selH = i % 24),
                    children: List.generate(
                        24,
                        (h) => Center(
                              child: Text(
                                h.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: (_selH % 24) == h
                                      ? const Color(0xFF6C63FF)
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            )),
                  ),
                ),
                const Text(':',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6C63FF))),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: _mCtrl,
                    magnification: 1.2,
                    backgroundColor: Colors.transparent,
                    itemExtent: 40,
                    looping: true,
                    onSelectedItemChanged: (i) =>
                        setState(() => _selM = i % 60),
                    children: List.generate(
                        60,
                        (m) => Center(
                              child: Text(
                                m.toString().padLeft(2, '0'),
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  color: (_selM % 60) == m
                                      ? const Color(0xFF6C63FF)
                                      : Colors.white.withValues(alpha: 0.6),
                                ),
                              ),
                            )),
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
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                        child: Text('Abbrechen',
                            style: TextStyle(
                                color: Colors.white60,
                                fontSize: 16,
                                fontWeight: FontWeight.w600))),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    widget.onTimeSelected(
                        TimeOfDay(hour: _selH % 24, minute: _selM % 60));
                    Navigator.pop(context);
                  },
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(8, 0, 16, 0),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                        child: Text('Übernehmen',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700))),
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

// ─────────────────────────────────────────────────────────────────────────────
// _SwipeTimeCard
// ─────────────────────────────────────────────────────────────────────────────

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
                  widget.controller.text.isEmpty ? '--:--' : widget.controller.text,
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