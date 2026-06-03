import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _selectedDate = DateTime.now();
  final _kommenController = TextEditingController();
  final _gehenController = TextEditingController();
  final _teamchefController = TextEditingController();
  final _notizController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadEntry();
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
    if (entry != null) {
      _kommenController.text = entry['kommen'] ?? '';
      _gehenController.text = entry['gehen'] ?? '';
      _teamchefController.text = entry['teamchef'] ?? '';
      _notizController.text = entry['notiz'] ?? '';
    } else {
      _kommenController.clear();
      _gehenController.clear();
      _teamchefController.clear();
      _notizController.clear();
    }
  }

  void _saveEntry() {
    final box = Hive.box('arbeitszeiten');
    box.put(_dateKey, {
      'kommen': _kommenController.text,
      'gehen': _gehenController.text,
      'teamchef': _teamchefController.text,
      'notiz': _notizController.text,
      'datum': _dateKey,
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Eintrag gespeichert ✓'),
        backgroundColor: const Color(0xFF6C63FF),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
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
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
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
    final isToday =
        DateFormat('yyyy-MM-dd').format(DateTime.now()) == _dateKey;
    final dateLabel = isToday
        ? 'Heute'
        : DateFormat('EEEE, d. MMMM yyyy', 'de').format(_selectedDate);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero Header
              Container(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A0A0F), Color(0xFF111128)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo Row
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: const Center(
                            child: Text('🇩🇪', style: TextStyle(fontSize: 24)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'OperationTimer',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Greeting
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        children: [
                          TextSpan(text: '$_greeting'),
                          if (_firstName.isNotEmpty) ...[
                            const TextSpan(text: ', '),
                            TextSpan(
                              text: _firstName,
                              style:
                                  const TextStyle(color: Color(0xFF6C63FF)),
                            ),
                          ],
                          const TextSpan(text: ' 👋'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Datum Chip – größer, direkt über Kommen/Gehen
                    GestureDetector(
                      onTap: _selectDate,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141420),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF6C63FF).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6C63FF)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text('📅',
                                  style: TextStyle(fontSize: 18)),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Datum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF6C63FF),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                Text(
                                  DateFormat('EEEE, d. MMMM yyyy', 'de')
                                      .format(_selectedDate),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            const Icon(Icons.chevron_right,
                                color: Color(0xFF6C63FF), size: 20),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Kommen & Gehen
                    Row(
                      children: [
                        Expanded(
                          child: _TimeCard(
                            label: 'KOMMEN',
                            color: const Color(0xFF4ECDC4),
                            controller: _kommenController,
                            onTap: () => _selectTime(_kommenController),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TimeCard(
                            label: 'GEHEN',
                            color: const Color(0xFFFF6B6B),
                            controller: _gehenController,
                            onTap: () => _selectTime(_gehenController),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Teamchef
                    _DarkInputCard(
                      label: 'TEAMCHEF',
                      emoji: '👤',
                      controller: _teamchefController,
                      hint: 'Name des Teamchefs',
                    ),
                    const SizedBox(height: 12),

                    // Notiz
                    _DarkInputCard(
                      label: 'NOTIZ',
                      emoji: '📝',
                      controller: _notizController,
                      hint: 'Optionale Notiz zum Tag...',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    // Save Button
                    GestureDetector(
                      onTap: _saveEntry,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)],
                          ),
                          borderRadius: BorderRadius.circular(18),
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
                    const SizedBox(height: 32),
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

class _TimeCard extends StatelessWidget {
  final String label;
  final Color color;
  final TextEditingController controller;
  final VoidCallback onTap;

  const _TimeCard({
    required this.label,
    required this.color,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              controller.text.isEmpty ? '--:--' : controller.text,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              controller.text.isEmpty ? 'Tippen zum Eintragen' : 'Tippen zum Ändern',
              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkInputCard extends StatelessWidget {
  final String label;
  final String emoji;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _DarkInputCard({
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
        color: const Color(0xFF141420),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF1E1E35)),
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
                    hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.25), fontSize: 15),
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