import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

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

  @override
  Widget build(BuildContext context) {
    final entries = _getEntriesForMonth();
    final monthName = DateFormat('MMMM yyyy', 'de').format(_selectedMonth);
    final complete = entries.where((e) => (e['gehen'] ?? '').isNotEmpty).length;
    final open = entries.length - complete;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
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
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Center(child: Text('🇩🇪', style: TextStyle(fontSize: 24))),
                      ),
                      const SizedBox(width: 10),
                      const Text('OperationTimer',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const Text('Monatsübersicht',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                  const SizedBox(height: 16),

                  // Monats-Navigation
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141420),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFF1E1E35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          onPressed: () => setState(() =>
                              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1)),
                          icon: const Icon(Icons.chevron_left, color: Color(0xFF6C63FF)),
                        ),
                        Text(monthName,
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                        IconButton(
                          onPressed: () => setState(() =>
                              _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1)),
                          icon: const Icon(Icons.chevron_right, color: Color(0xFF6C63FF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Stats Row
                  Row(
                    children: [
                      _StatCard(label: 'Einträge', value: '${entries.length}', color: const Color(0xFF6C63FF)),
                      const SizedBox(width: 10),
                      _StatCard(label: 'Vollständig', value: '$complete', color: const Color(0xFF4ECDC4)),
                      const SizedBox(width: 10),
                      _StatCard(label: 'Offen', value: '$open', color: const Color(0xFFFF6B6B)),
                    ],
                  ),
                ],
              ),
            ),

            // Liste
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('📭', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          const Text('Keine Einträge',
                              style: TextStyle(color: Color(0xFF555570), fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final datum = DateTime.parse(entry['datum']);
                        final dayName = DateFormat('EEE', 'de').format(datum);
                        final dayNum = DateFormat('dd').format(datum);
                        final kommen = entry['kommen'] ?? '';
                        final gehen = entry['gehen'] ?? '';
                        final teamchef = entry['teamchef'] ?? '';
                        final duration = _calcDuration(kommen, gehen);
                        final isComplete = gehen.isNotEmpty;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141420),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isComplete
                                  ? const Color(0xFF4ECDC4).withValues(alpha: 0.2)
                                  : const Color(0xFFFF6B6B).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              // Datum Badge
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
                                        style: const TextStyle(
                                            fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
                                    Text(dayNum,
                                        style: const TextStyle(
                                            fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 14),

                              // Zeiten
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
                                    if (teamchef.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('👤 $teamchef',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF555570))),
                                    ],
                                  ],
                                ),
                              ),

                              // Dauer & Status
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(duration,
                                      style: const TextStyle(
                                          fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isComplete
                                          ? const Color(0xFF4ECDC4).withValues(alpha: 0.12)
                                          : const Color(0xFFFF6B6B).withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isComplete ? '✓ Ok' : '⏳ Offen',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: isComplete ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
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
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF141420),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF555570), fontWeight: FontWeight.w500)),
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