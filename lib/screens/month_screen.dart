import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/intl.dart';

class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  DateTime _selectedMonth = DateTime.now();
  final _slidableKeys = <String, GlobalKey<_SlidableRowState>>{};

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

  void _closeAllSlidables() {
    for (final key in _slidableKeys.values) {
      key.currentState?.close();
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
      builder: (context) => _EditEntrySheet(
        datum: datum,
        kommenCtrl: kommenCtrl,
        gehenCtrl: gehenCtrl,
        tkfCtrl: tkfCtrl,
        notizCtrl: notizCtrl,
        onSave: () {
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
      ),
    );
  }

  void _showMonthYearPicker() {
    int pickedYear = _selectedMonth.year;
    int pickedMonth = _selectedMonth.month;

    final yearController = FixedExtentScrollController(
      initialItem: pickedYear - 2020 + 1000,
    );
    final monthController = FixedExtentScrollController(
      initialItem: pickedMonth - 1 + 1000,
    );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
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
            const Text(
              'Monat auswählen',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  // Monat Picker
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: monthController,
                      magnification: 1.2,
                      backgroundColor: Colors.transparent,
                      itemExtent: 44,
                      looping: true,
                      onSelectedItemChanged: (i) => pickedMonth = (i % 12) + 1,
                      children: List.generate(12, (i) {
                        final name = DateFormat('MMMM', 'de').format(DateTime(2024, i + 1));
                        return Center(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  // Jahr Picker
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: yearController,
                      magnification: 1.2,
                      backgroundColor: Colors.transparent,
                      itemExtent: 44,
                      looping: false,
                      onSelectedItemChanged: (i) => pickedYear = 2020 + (i % (DateTime.now().year - 2020 + 2)),
                      children: List.generate(
                        DateTime.now().year - 2020 + 2,
                        (i) => Center(
                          child: Text(
                            '${2020 + i}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('Abbrechen',
                            style: TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedMonth = DateTime(pickedYear, pickedMonth);
                      });
                      Navigator.pop(context);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Text('Auswählen',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
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
      body: GestureDetector(
        onTap: _closeAllSlidables,
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) _changeMonth(1);
          if (details.primaryVelocity! > 300) _changeMonth(-1);
        },
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Monatsübersicht',
                        style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 16),

                    // Monats-Navigation
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => _changeMonth(-1),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: const Icon(Icons.chevron_left, color: Color(0xFF6C63FF)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: _showMonthYearPicker,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF141420),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(monthName,
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.expand_more, color: Color(0xFF6C63FF), size: 18),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => _changeMonth(1),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            child: const Icon(Icons.chevron_right, color: Color(0xFF6C63FF)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Stats
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
                      '← Wischen: Optionen  ·  → Wischen: Löschen',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.3)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Liste
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('📭', style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('Keine Einträge für diesen Monat',
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 15)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(24, 4, 24, 100),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final entry = entries[index];
                          final key = entry['datum'] as String;
                          _slidableKeys[key] ??= GlobalKey<_SlidableRowState>();

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _SlidableRow(
                              key: _slidableKeys[key],
                              entry: entry,
                              duration: _calcDuration(
                                entry['kommen'] ?? '',
                                entry['gehen'] ?? '',
                              ),
                              onEdit: () => _editEntry(entry),
                              onDelete: () => _deleteEntry(key),
                              onTap: _closeAllSlidables,
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

// ─── Slidable Row ────────────────────────────────────────────────────────────

class _SlidableRow extends StatefulWidget {
  final Map<String, dynamic> entry;
  final String duration;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _SlidableRow({
    super.key,
    required this.entry,
    required this.duration,
    required this.onEdit,
    required this.onDelete,
    required this.onTap,
  });

  @override
  State<_SlidableRow> createState() => _SlidableRowState();
}

class _SlidableRowState extends State<_SlidableRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _offsetAnim;
  double _dragOffset = 0;
  static const double _threshold = 80;
  static const double _maxLeft = 160;
  static const double _maxRight = 80;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 250));
    _offsetAnim = Tween<double>(begin: 0, end: 0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void close() {
    _animateTo(0);
  }

  void _animateTo(double target) {
    _offsetAnim = Tween<double>(begin: _dragOffset, end: target)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward(from: 0).then((_) {
      setState(() => _dragOffset = target);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragOffset =
          (_dragOffset + d.delta.dx).clamp(-_maxLeft, _maxRight);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_dragOffset < -_threshold) {
      _animateTo(-_maxLeft);
    } else if (_dragOffset > _threshold) {
      _animateTo(_maxRight);
    } else {
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final datum = DateTime.parse(entry['datum']);
    final dayName = DateFormat('EEE', 'de').format(datum);
    final dayNum = DateFormat('dd').format(datum);
    final kommen = entry['kommen'] ?? '';
    final gehen = entry['gehen'] ?? '';
    final tkf = entry['TKF'] ?? '';
    final notiz = entry['notiz'] ?? '';
    final isComplete = gehen.isNotEmpty;
    final borderColor = isComplete
        ? const Color(0xFF4ECDC4).withValues(alpha: 0.3)
        : const Color(0xFFFF6B6B).withValues(alpha: 0.3);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onTap: () {
        if (_dragOffset != 0) {
          _animateTo(0);
        } else {
          widget.onTap();
        }
      },
      child: AnimatedBuilder(
        animation: _animCtrl,
        builder: (context, _) {
          final offset = _animCtrl.isAnimating ? _offsetAnim.value : _dragOffset;
          return Stack(
            children: [
              // Hintergrund Aktionen
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Row(
                    children: [
                      // Links: Bearbeiten
                      Expanded(
                        child: Container(
                          color: const Color(0xFF6C63FF),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit_outlined, color: Colors.white, size: 22),
                              SizedBox(height: 4),
                              Text('Bearbeiten',
                                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      // Rechts: Löschen
                      Container(
                        width: _maxRight,
                        color: const Color(0xFFFF6B6B),
                        child: const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline, color: Colors.white, size: 22),
                            SizedBox(height: 4),
                            Text('Löschen',
                                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Vordergrund Kachel
              Transform.translate(
                offset: Offset(offset, 0),
                child: GestureDetector(
                  onTap: () {
                    if (offset != 0) {
                      _animateTo(0);
                    } else {
                      // Aktion ausführen wenn voll geöffnet
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF141420),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: borderColor),
                    ),
                    padding: const EdgeInsets.all(16),
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
                                      style: const TextStyle(
                                          fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w700)),
                                  Text(dayNum,
                                      style: const TextStyle(
                                          fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
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
                                      _TimeChip(
                                          time: kommen.isEmpty ? '--:--' : kommen,
                                          color: const Color(0xFF4ECDC4)),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8),
                                        child: Icon(Icons.arrow_forward,
                                            size: 14, color: Color(0xFF555570)),
                                      ),
                                      _TimeChip(
                                          time: gehen.isEmpty ? '--:--' : gehen,
                                          color: const Color(0xFFFF6B6B)),
                                    ],
                                  ),
                                  if (tkf.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text('👤 $tkf',
                                        style: const TextStyle(
                                            fontSize: 12, color: Color(0xFF555570))),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(widget.duration,
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white)),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
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
                                      color: isComplete
                                          ? const Color(0xFF4ECDC4)
                                          : const Color(0xFFFF6B6B),
                                    ),
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
                                  child: Text(notiz,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.white.withValues(alpha: 0.6))),
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

              // Unsichtbarer Tap-Detektor für Aktionen wenn offen
              if (offset <= -_maxLeft + 10)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _maxLeft,
                  child: GestureDetector(
                    onTap: () {
                      _animateTo(0);
                      widget.onEdit();
                    },
                  ),
                ),
              if (offset >= _maxRight - 10)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: _maxRight,
                  child: GestureDetector(
                    onTap: () {
                      _animateTo(0);
                      widget.onDelete();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Edit Sheet ──────────────────────────────────────────────────────────────

class _EditEntrySheet extends StatefulWidget {
  final DateTime datum;
  final TextEditingController kommenCtrl;
  final TextEditingController gehenCtrl;
  final TextEditingController tkfCtrl;
  final TextEditingController notizCtrl;
  final VoidCallback onSave;

  const _EditEntrySheet({
    required this.datum,
    required this.kommenCtrl,
    required this.gehenCtrl,
    required this.tkfCtrl,
    required this.notizCtrl,
    required this.onSave,
  });

  @override
  State<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<_EditEntrySheet> {
  TimeOfDay? _parseTime(String text) {
    if (text.isEmpty || text == '--:--') return null;
    try {
      final parts = text.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final current = _parseTime(ctrl.text);
    final hourCtrl = FixedExtentScrollController(
      initialItem: (current?.hour ?? TimeOfDay.now().hour) + 1000,
    );
    final minCtrl = FixedExtentScrollController(
      initialItem: (current?.minute ?? TimeOfDay.now().minute) + 1000,
    );
    int selHour = current?.hour ?? TimeOfDay.now().hour;
    int selMin = current?.minute ?? TimeOfDay.now().minute;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            const Text('Uhrzeit auswählen',
                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: Row(
                children: [
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: hourCtrl,
                      magnification: 1.2,
                      backgroundColor: Colors.transparent,
                      itemExtent: 40,
                      looping: true,
                      onSelectedItemChanged: (i) => selHour = i % 24,
                      children: List.generate(24, (h) => Center(
                        child: Text(h.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
                      )),
                    ),
                  ),
                  const Text(':', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: Color(0xFF6C63FF))),
                  Expanded(
                    child: CupertinoPicker(
                      scrollController: minCtrl,
                      magnification: 1.2,
                      backgroundColor: Colors.transparent,
                      itemExtent: 40,
                      looping: true,
                      onSelectedItemChanged: (i) => selMin = i % 60,
                      children: List.generate(60, (m) => Center(
                        child: Text(m.toString().padLeft(2, '0'),
                            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: Colors.white)),
                      )),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: Text('Abbrechen',
                          style: TextStyle(color: Colors.white60, fontSize: 16, fontWeight: FontWeight.w600))),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        ctrl.text =
                            '${selHour.toString().padLeft(2, '0')}:${selMin.toString().padLeft(2, '0')}';
                      });
                      Navigator.pop(ctx);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(child: Text('Übernehmen',
                          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 24, left: 24, right: 24,
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
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Eintrag – ${DateFormat('dd.MM.yyyy').format(widget.datum)}',
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 20),

          // Kommen & Gehen nebeneinander mit Zeit-Picker
          Row(
            children: [
              Expanded(child: _TimePickerField(label: 'KOMMEN', ctrl: widget.kommenCtrl, onTap: () => _pickTime(widget.kommenCtrl))),
              const SizedBox(width: 12),
              Expanded(child: _TimePickerField(label: 'GEHEN', ctrl: widget.gehenCtrl, onTap: () => _pickTime(widget.gehenCtrl))),
            ],
          ),
          const SizedBox(height: 12),
          _EditField(label: 'TKF', controller: widget.tkfCtrl),
          const SizedBox(height: 12),
          _EditField(label: 'NOTIZ', controller: widget.notizCtrl, maxLines: 2),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: widget.onSave,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF4ECDC4)]),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text('Speichern',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Helper Widgets ───────────────────────────────────────────────────────────

class _TimePickerField extends StatelessWidget {
  final String label;
  final TextEditingController ctrl;
  final VoidCallback onTap;

  const _TimePickerField({required this.label, required this.ctrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = label == 'KOMMEN' ? const Color(0xFF4ECDC4) : const Color(0xFFFF6B6B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: ctrl,
        builder: (context, _) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 1.2)),
              const SizedBox(height: 6),
              Text(
                ctrl.text.isEmpty ? '--:--' : ctrl.text,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: -1),
              ),
              const SizedBox(height: 2),
              Text('Tippen zum Ändern', style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.3))),
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