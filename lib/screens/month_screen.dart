import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';
import '../services/pdf_service.dart';

class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  DateTime _selectedMonth = DateTime.now();

  List<Map<String, dynamic>> _getEntriesForMonth() {
    final box = Hive.box('arbeitszeiten');
    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final List<Map<String, dynamic>> entries = [];
    for (final key in box.keys) {
      if (key.toString().startsWith(monthKey)) {
        final entry = box.get(key);
        if (entry != null) entries.add(Map<String, dynamic>.from(entry));
      }
    }
    entries.sort((a, b) => a['datum'].compareTo(b['datum']));
    return entries;
  }

  String _calcDuration(String kommen, String gehen) {
    if (kommen.isEmpty || gehen.isEmpty) return '--';
    try {
      final k = kommen.split(':');
      final g = gehen.split(':');
      final start = Duration(hours: int.parse(k[0]), minutes: int.parse(k[1]));
      final end = Duration(hours: int.parse(g[0]), minutes: int.parse(g[1]));
      final diff = end - start;
      if (diff.isNegative) return '--';
      return '${diff.inHours}h ${(diff.inMinutes % 60).toString().padLeft(2, '0')}m';
    } catch (_) {
      return '--';
    }
  }

  void _deleteEntry(String datum) {
    final box = Hive.box('arbeitszeiten');
    box.delete(datum);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Eintrag gelöscht'),
        backgroundColor: const Color(0xFFFF6B6B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      ),
    );
  }

  void _copyEntry(Map<String, dynamic> entry) async {
    final targetDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Tag auswählen zum Kopieren',
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
    if (targetDate == null) return;
    final newKey = DateFormat('yyyy-MM-dd').format(targetDate);
    final box = Hive.box('arbeitszeiten');
    box.put(newKey, {
      'kommen': entry['kommen'] ?? '',
      'gehen': entry['gehen'] ?? '',
      'TKF': entry['TKF'] ?? '',
      'notiz': entry['notiz'] ?? '',
      'datum': newKey,
    });
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Kopiert auf ${DateFormat('dd.MM.yyyy').format(targetDate)}'),
          backgroundColor: const Color(0xFF4ECDC4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ),
      );
    }
  }

  void _editEntry(Map<String, dynamic> entry) {
    final kommenCtrl = TextEditingController(text: entry['kommen'] ?? '');
    final gehenCtrl = TextEditingController(text: entry['gehen'] ?? '');
    final tkfCtrl = TextEditingController(text: entry['TKF'] ?? '');
    final notizCtrl = TextEditingController(text: entry['notiz'] ?? '');
    final datum = DateTime.parse(entry['datum']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
          left: 24,
          right: 24,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Eintrag bearbeiten – ${DateFormat('dd.MM.yyyy').format(datum)}',
              style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            _EditField(label: 'Kommen', controller: kommenCtrl),
            const SizedBox(height: 12),
            _EditField(label: 'Gehen', controller: gehenCtrl),
            const SizedBox(height: 12),
            _EditField(label: 'TKF', controller: tkfCtrl),
            const SizedBox(height: 12),
            _EditField(label: 'Notiz', controller: notizCtrl, maxLines: 2),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                final box = Hive.box('arbeitszeiten');
                box.put(entry['datum'], {
                  'kommen': kommenCtrl.text,
                  'gehen': gehenCtrl.text,
                  'TKF': tkfCtrl.text,
                  'notiz': notizCtrl.text,
                  'datum': entry['datum'],
                });
                setState(() {});
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Eintrag aktualisiert ✓'),
                    backgroundColor: const Color(0xFF6C63FF),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                  ),
                );
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Center(
                  child: Text('Speichern', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEntryOptions(Map<String, dynamic> entry) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _OptionButton(
              emoji: '✏️',
              label: 'Bearbeiten',
              color: const Color(0xFF6C63FF),
              onTap: () {
                Navigator.pop(context);
                _editEntry(entry);
              },
            ),
            const SizedBox(height: 10),
            _OptionButton(
              emoji: '📋',
              label: 'Tag kopieren',
              color: const Color(0xFF4ECDC4),
              onTap: () {
                Navigator.pop(context);
                _copyEntry(entry);
              },
            ),
            const SizedBox(height: 10),
            _OptionButton(
              emoji: '🗑',
              label: 'Löschen',
              color: const Color(0xFFFF6B6B),
              onTap: () {
                Navigator.pop(context);
                _deleteEntry(entry['datum']);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _changeMonth(int months) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + months);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final complete = entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length;
    final open = entries.length - complete;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity == null) return;
            if (details.primaryVelocity! < -300) {
              _changeMonth(1);
            } else if (details.primaryVelocity! > 300) {
              _changeMonth(-1);
            }
          },
          child: Column(
            children: [
              const SizedBox(height: 60),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Monatsübersicht',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF141420),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            onPressed: () => _changeMonth(-1),
                            icon: const Icon(Icons.chevron_left, color: Color(0xFF6C63FF)),
                          ),
                          Text(monthName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                          IconButton(
                            onPressed: () => _changeMonth(1),
                            icon: const Icon(Icons.chevron_right, color: Color(0xFF6C63FF)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _StatCard(label: 'Einträge', value: '${entries.length}', color: const Color(0xFF6C63FF)),
                        const SizedBox(width: 10),
                        _StatCard(label: 'Vollständig', value: '$complete', color: const Color(0xFF4ECDC4)),
                        const SizedBox(width: 10),
                        _StatCard(label: 'Offen', value: '$open', color: const Color(0xFFFF6B6B)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rechts swipen: Bearbeiten/PDF  ·  Links swipen: Löschen',
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('📭', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text(
                              'Keine Einträge für diesen Monat',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 15),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final datum = DateTime.parse(entry['datum']);
                          final dayName = DateFormat('EEE', 'de').format(datum);
                          final dayNum = DateFormat('dd').format(datum);
                          final kommen = entry['kommen'] ?? '';
                          final gehen = entry['gehen'] ?? '';
                          final tkf = entry['TKF'] ?? '';
                          final notiz = entry['notiz'] ?? '';
                          final duration = _calcDuration(kommen, gehen);
                          final isComplete = gehen.isNotEmpty;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Slidable(
                                key: Key(entry['datum']),
                                closeOnScroll: true,
                                startActionPane: ActionPane(
                                  motion: const DrawerMotion(),
                                  extentRatio: 0.5,
                                  children: [
                                    CustomSlidableAction(
                                      onPressed: (_) {
                                        _editEntry(entry);
                                        Slidable.of(context)?.close();
                                      },
                                      backgroundColor: const Color(0xFF6C63FF),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.edit_outlined, color: Colors.white, size: 26),
                                          SizedBox(height: 4),
                                          Text('Bearbeiten',
                                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                    CustomSlidableAction(
                                      onPressed: (_) {
                                        PdfService.exportSingleEntry(entry);
                                        Slidable.of(context)?.close();
                                      },
                                      backgroundColor: const Color(0xFF4ECDC4),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.picture_as_pdf_outlined, color: Colors.white, size: 26),
                                          SizedBox(height: 4),
                                          Text('Tag teilen',
                                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                endActionPane: ActionPane(
                                  motion: const DrawerMotion(),
                                  extentRatio: 0.25,
                                  children: [
                                    CustomSlidableAction(
                                      onPressed: (_) {
                                        _deleteEntry(entry['datum']);
                                        Slidable.of(context)?.close();
                                      },
                                      backgroundColor: const Color(0xFFFF6B6B),
                                      child: const Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.delete_outline, color: Colors.white, size: 26),
                                          SizedBox(height: 4),
                                          Text('Löschen',
                                              style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                child: GestureDetector(
                                  onLongPress: () => _showEntryOptions(entry),
                                  // 🔥 Tippen auf die Kachel schließt das Slidable
                                  onTap: () {
                                    Slidable.of(context)?.close();
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF141420),
                                      border: Border.all(
                                        color: isComplete
                                            ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                                            : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              width: 52,
                                              padding: const EdgeInsets.symmetric(vertical: 10),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                children: [
                                                  Text(dayName.toUpperCase(),
                                                      style: const TextStyle(fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
                                                  Text(dayNum,
                                                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      _TimeChip(time: kommen.isEmpty ? '--:--' : kommen, color: const Color(0xFF4ECDC4)),
                                                      const Padding(
                                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                                        child: Icon(Icons.arrow_forward, size: 14, color: Color(0xFF555570)),
                                                      ),
                                                      _TimeChip(time: gehen.isEmpty ? '--:--' : gehen, color: const Color(0xFFFF6B6B)),
                                                    ],
                                                  ),
                                                  if (tkf.isNotEmpty) ...[
                                                    const SizedBox(height: 6),
                                                    Text('👤 $tkf', style: const TextStyle(fontSize: 12, color: Color(0xFF555570))),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            Column(
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Text(duration, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                                const SizedBox(height: 4),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: isComplete ? const Color(0xFF4ECDC4).withValues(alpha: 0.12) : const Color(0xFFFF6B6B).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    isComplete ? '✓ Ok' : '⏳ Offen',
                                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isComplete ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B)),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                        if (notiz.isNotEmpty) ...[
                                          const SizedBox(height: 10),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.04),
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            child: Row(
                                              children: [
                                                const Text('📝', style: TextStyle(fontSize: 12)),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(notiz, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF555570))),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String time;
  final Color color;

  const _TimeChip({required this.time, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(time, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _EditField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;

  const _EditField({required this.label, required this.controller, this.maxLines = 1});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600, letterSpacing: 0.8)),
          TextField(
            controller: controller,
            maxLines: maxLines,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
          ),
        ],
      ),
    );
  }
}

class _OptionButton extends StatelessWidget {
  final String emoji;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _OptionButton({required this.emoji, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}