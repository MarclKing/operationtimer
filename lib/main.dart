import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'screens/home_screen.dart';
import 'screens/month_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';
import 'services/pdf_service.dart';
import 'services/night_shift_helper.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('arbeitszeiten');
  await Hive.openBox('einstellungen');
  _migrateOldEntries();
  await initializeDateFormatting('de', null);
  runApp(const MyApp());
}

void _migrateOldEntries() {
  final box = Hive.box('arbeitszeiten');
  final keys = box.keys.toList();
  bool changed = false;

  for (final key in keys) {
    final data = box.get(key);
    if (data != null && data is! List) {
      final entry = Map<String, dynamic>.from(data);
      if (!entry.containsKey('id')) {
        entry['id'] = DateTime.now().millisecondsSinceEpoch.toString();
      }
      if (!entry.containsKey('createdAt')) {
        entry['createdAt'] = DateTime.now().toIso8601String();
      }
      box.put(key, [entry]);
      changed = true;
    } else if (data is List) {
      bool needsUpdate = false;
      for (final entry in data) {
        if (!entry.containsKey('id')) {
          entry['id'] = DateTime.now().millisecondsSinceEpoch.toString();
          needsUpdate = true;
        }
        if (!entry.containsKey('createdAt')) {
          entry['createdAt'] = DateTime.now().toIso8601String();
          needsUpdate = true;
        }
      }
      if (needsUpdate) {
        box.put(key, data);
        changed = true;
      }
    }
  }

  if (changed) {
    debugPrint('✅ Migration abgeschlossen');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        final skinKey =
            box.get(AppTheme.hiveKey, defaultValue: 'chrome') as String;
        final skin = AppTheme.fromKey(skinKey);

        return SkinProvider(
          skin: skin,
          child: MaterialApp(
            title: 'OpTimes',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              brightness: skin.isLight ? Brightness.light : Brightness.dark,
              scaffoldBackgroundColor: skin.bgBase,
              colorScheme: ColorScheme(
                brightness: skin.isLight ? Brightness.light : Brightness.dark,
                primary: skin.primary,
                onPrimary: skin.onGradient,
                secondary: skin.secondary,
                onSecondary: skin.onGradient,
                error: skin.deleteColor,
                onError: Colors.white,
                surface: skin.bgCard,
                onSurface: skin.textPrimary,
              ),
              appBarTheme: AppBarTheme(
                backgroundColor: skin.bgCard,
                foregroundColor: skin.textPrimary,
              ),
              useMaterial3: true,
            ),
            home: const MainScreen(),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MainScreen
// ─────────────────────────────────────────────────────────────────────────────

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;

  // Wir nutzen einen eigenen AnimationController für den Page-Slide,
  // damit wir ihn auch von Wischgesten aus triggern können.
  late AnimationController _pageAnimController;
  late Animation<double> _pageAnim;

  int _fromPage = 0;
  int _toPage = 0;

  // Für Wischgesten: Drag-Offset
  double _dragOffset = 0;
  bool _isDragging = false;

  late AnimationController _menuAnimController;
  bool _menuOpen = false;
  bool _prevDienstplanEnabled = false;

  DateTime _sharedDate = DateTime.now();
  DateTime _sharedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _scheduleViewMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  StreamSubscription? _intentSub;

  bool get _dienstplanEnabled {
    final box = Hive.box('einstellungen');
    return box.get('dienstplan_enabled', defaultValue: false) as bool;
  }

  int get _pageCount => _dienstplanEnabled ? 3 : 2;

  @override
  void initState() {
    super.initState();
    _prevDienstplanEnabled = _dienstplanEnabled;

    _pageAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _pageAnim = _pageAnimController.drive(CurveTween(curve: Curves.easeInOutCubic));

    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        final path = files.first.path;
        if (path != null && path.toLowerCase().endsWith('.pdf')) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleSharedPdf(path);
          });
        }
      }
    });

    _intentSub =
        ReceiveSharingIntent.instance.getMediaStream().listen((files) {
      if (files.isNotEmpty) {
        final path = files.first.path;
        if (path != null && path.toLowerCase().endsWith('.pdf')) {
          _handleSharedPdf(path);
        }
      }
    });
  }

  void _handleSharedPdf(String path) {
    if (_dienstplanEnabled) {
      _goToPage(2);
    }
    final skin = AppTheme.of(context);
    final fileName = path.split('/').last;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DienstplanUploadSheet(
        skin: skin,
        initialMonth: _scheduleViewMonth,
        selectedMonth: _scheduleViewMonth,
        preloadedFilePath: path,
        preloadedFileName: fileName,
        onImported: () => setState(() {}),
      ),
    );
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _pageAnimController.dispose();
    _menuAnimController.dispose();
    super.dispose();
  }

  // ── Navigation mit Animation ───────────────────────────────────────────────

  void _animateToPage(int target) {
    FocusManager.instance.primaryFocus?.unfocus();
    final count = _pageCount;
    final safeTarget = target.clamp(0, count - 1);
    if (safeTarget == _selectedIndex && !_isDragging) return;

    _fromPage = _selectedIndex;
    _toPage = safeTarget;

    _pageAnimController.value = 0.0;
    _pageAnimController.forward().then((_) {
      setState(() {
        _selectedIndex = _toPage;
        _fromPage = _toPage;
      });
    });

    // selectedIndex schon vorab setzen für NavBar-Highlight
    setState(() => _selectedIndex = safeTarget);
  }

  void _goToPage(int index) => _animateToPage(index);
  void _selectTab(int index) => _animateToPage(index);

  bool get _isOnSchedulePage => _dienstplanEnabled && _selectedIndex == 2;

  // ── Wischgesten ────────────────────────────────────────────────────────────

  void _onHorizontalDragStart(DragStartDetails d) {
    if (_pageAnimController.isAnimating) {
      _pageAnimController.stop();
    }
    _isDragging = true;
    _dragOffset = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset += d.delta.dx;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails d) {
    if (!_isDragging) return;
    _isDragging = false;
    final velocity = d.primaryVelocity ?? 0;
    final screenW = MediaQuery.of(context).size.width;

    bool shouldNavigate = false;
    int targetPage = _selectedIndex;

    if (velocity < -300 || _dragOffset < -screenW * 0.3) {
      // Wischen nach links → nächste Seite
      if (_selectedIndex < _pageCount - 1) {
        targetPage = _selectedIndex + 1;
        shouldNavigate = true;
      }
    } else if (velocity > 300 || _dragOffset > screenW * 0.3) {
      // Wischen nach rechts → vorherige Seite
      if (_selectedIndex > 0) {
        targetPage = _selectedIndex - 1;
        shouldNavigate = true;
      }
    }

    setState(() => _dragOffset = 0);

    if (shouldNavigate) {
      _fromPage = _selectedIndex;
      _toPage = targetPage;
      _pageAnimController.value = 0.0;
      _pageAnimController.forward().then((_) {
        setState(() {
          _selectedIndex = _toPage;
          _fromPage = _toPage;
        });
      });
      setState(() => _selectedIndex = targetPage);
    }
  }

  // ── Pages bauen ────────────────────────────────────────────────────────────

  List<Widget> get _pages {
    final pages = <Widget>[
      HomeScreen(
        key: const ValueKey('home'),
        selectedDate: _sharedDate,
        onDateChanged: (d) => setState(() => _sharedDate = d),
        onNavigateToMonth: () => _goToPage(1),
      ),
      MonthScreen(
        key: const ValueKey('month'),
        selectedMonth: _sharedMonth,
        onMonthChanged: (m) => setState(() => _sharedMonth = m),
        onNavigateToHome: () => _goToPage(0),
      ),
      if (_dienstplanEnabled)
        ScheduleScreen(
          key: const ValueKey('schedule'),
          onNavigateToHome: () => _goToPage(0),
          onNavigateToMonth: () => _goToPage(1),
          onMonthChanged: (m) => setState(() => _scheduleViewMonth = m),
        ),
    ];
    return pages;
  }

  Widget _buildAnimatedPages(double screenWidth) {
    final pages = _pages;
    final count = pages.length;

    return AnimatedBuilder(
      animation: _pageAnimController,
      builder: (context, _) {
        final t = _pageAnim.value;

        // Drag-basierter Offset (während Geste)
        double dragT = 0;
        if (_isDragging) {
          dragT = -_dragOffset / screenWidth;
        }

        return Stack(
          children: List.generate(count, (i) {
            double offset;
            if (_isDragging) {
              // Während Drag: linear verschieben
              offset = (i - _selectedIndex).toDouble() + dragT;
            } else {
              // Animierter Übergang
              final fromOffset = (i - _fromPage).toDouble();
              final toOffset = (i - _toPage).toDouble();
              offset = fromOffset + (toOffset - fromOffset) * t;
            }

            final isVisible = offset.abs() < 1.5;
            if (!isVisible) return const SizedBox.shrink();

            return Transform.translate(
              offset: Offset(offset * screenWidth, 0),
              child: SizedBox(
                width: screenWidth,
                height: double.infinity,
                child: pages[i],
              ),
            );
          }),
        );
      },
    );
  }

  void _toggleMenu() {
    setState(() {
      _menuOpen = !_menuOpen;
      if (_menuOpen) {
        _menuAnimController.forward();
      } else {
        _menuAnimController.reverse();
      }
    });
  }

  void _closeMenu() {
    setState(() {
      _menuOpen = false;
      _menuAnimController.reverse();
    });
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        final currentDienstplanEnabled = _dienstplanEnabled;

        if (!currentDienstplanEnabled && _selectedIndex >= 2) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _goToPage(0);
          });
        }

        if (currentDienstplanEnabled != _prevDienstplanEnabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _prevDienstplanEnabled = currentDienstplanEnabled);
            }
          });
        }

        return Scaffold(
          backgroundColor: skin.bgBase,
          body: Stack(
            children: [
              // ── Animierter Seitenbereich mit Wischgesten ──────────────────
              GestureDetector(
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                behavior: HitTestBehavior.translucent,
                child: _buildAnimatedPages(screenWidth),
              ),

              // ── Menü-Overlay ───────────────────────────────────────────────
              if (_menuOpen)
                GestureDetector(
                  onTap: _closeMenu,
                  child:
                      Container(color: Colors.black.withValues(alpha: 0.5)),
                ),

              // ── Dropdown-Menü ──────────────────────────────────────────────
              AnimatedBuilder(
                animation: _menuAnimController,
                builder: (context, child) {
                  return Positioned(
                    top: MediaQuery.of(context).padding.top + 60,
                    right: 16,
                    child: Transform.scale(
                      scale: _menuAnimController.value,
                      alignment: Alignment.topRight,
                      child: Opacity(
                        opacity: _menuAnimController.value,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            width: 220,
                            decoration: BoxDecoration(
                              color: skin.bgCard,
                              borderRadius: BorderRadius.circular(18),
                              border:
                                  Border.all(color: skin.borderMedium),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_isOnSchedulePage) ...[
                                  _DropdownMenuItem(
                                    icon: Icons.upload_file_outlined,
                                    label: 'Dienstplan importieren',
                                    onTap: () {
                                      _closeMenu();
                                      _showUploadSheet(context, skin);
                                    },
                                  ),
                                  _DropdownDivider(),
                                ],
                                if (!_isOnSchedulePage) ...[
                                  _DropdownMenuItem(
                                    icon: Icons.picture_as_pdf_outlined,
                                    label: 'Zeiten exportieren',
                                    onTap: () {
                                      _closeMenu();
                                      PdfService.showMonthPickerAndExport(
                                          context);
                                    },
                                  ),
                                  _DropdownDivider(),
                                ],
                                _DropdownMenuItem(
                                  icon: Icons.settings_outlined,
                                  label: 'Einstellungen',
                                  onTap: () {
                                    _closeMenu();
                                    Navigator.push(
                                      context,
                                      CupertinoPageRoute(
                                        builder: (_) =>
                                            const SettingsScreen(),
                                      ),
                                    );
                                  },
                                ),
                                _DropdownDivider(),
                                _DropdownMenuItem(
                                  icon: Icons.support_agent_outlined,
                                  label: 'Support',
                                  onTap: () {
                                    _closeMenu();
                                    Navigator.push(
                                      context,
                                      CupertinoPageRoute(
                                        builder: (_) =>
                                            const SupportScreen(),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              // ── Top-Bar ────────────────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  color: skin.bgBase,
                  padding: EdgeInsets.only(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 20,
                    right: 16,
                    bottom: 8,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: skin.primary.withAlpha(26),
                              border: Border.all(
                                  color: skin.primary.withAlpha(51)),
                            ),
                            child: Icon(Icons.access_time_filled,
                                size: 20, color: skin.primary),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'OpTimes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: skin.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _toggleMenu,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            color: _menuOpen
                                ? skin.primary.withAlpha(77)
                                : skin.surface(0.08),
                            border: Border.all(
                              color: _menuOpen
                                  ? skin.primary.withAlpha(128)
                                  : skin.surface(0.1),
                            ),
                          ),
                          child: AnimatedRotation(
                            turns: _menuOpen ? 0.125 : 0,
                            duration: const Duration(milliseconds: 250),
                            child: Icon(
                              _menuOpen
                                  ? Icons.close
                                  : Icons.menu_rounded,
                              color: skin.textPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Bottom Navigation ──────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _BottomNav(
                  selectedIndex: _selectedIndex,
                  dienstplanEnabled: currentDienstplanEnabled,
                  onTap: _selectTab,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showUploadSheet(BuildContext context, AppSkin skin) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DienstplanUploadSheet(
        skin: skin,
        initialMonth: _scheduleViewMonth,
        selectedMonth: _scheduleViewMonth,
        onImported: () => setState(() {}),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DropdownMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: skin.textMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: skin.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DropdownDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(height: 0.5, color: skin.borderSubtle);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation – komplett überarbeitet
// Fixes: Highlight mittig, kein Springen, größere Tippfläche
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatefulWidget {
  final int selectedIndex;
  final bool dienstplanEnabled;
  final Function(int) onTap;

  const _BottomNav({
    required this.selectedIndex,
    required this.dienstplanEnabled,
    required this.onTap,
  });

  @override
  State<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<_BottomNav>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  double _fromPos = 0; // 0..1 normalisiert
  double _toPos = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _anim = _ctrl.drive(CurveTween(curve: Curves.easeInOutCubic));
    final count = widget.dienstplanEnabled ? 3 : 2;
    _fromPos = widget.selectedIndex / (count - 1);
    _toPos = _fromPos;
  }

  @override
  void didUpdateWidget(_BottomNav old) {
    super.didUpdateWidget(old);

    final count = widget.dienstplanEnabled ? 3 : 2;

    if (old.selectedIndex != widget.selectedIndex) {
      // Aktuelle interpolierte Position als neuen Startpunkt
      final currentPos = _fromPos + (_toPos - _fromPos) * _anim.value;
      _fromPos = currentPos;
      _toPos = widget.selectedIndex / (count - 1).clamp(1, 100);

      _ctrl.stop();
      _ctrl.forward(from: 0);
    }

    if (old.dienstplanEnabled != widget.dienstplanEnabled) {
      // Tabs haben sich geändert – neu berechnen ohne Animation
      _fromPos = widget.selectedIndex / (count - 1).clamp(1, 100);
      _toPos = _fromPos;
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final count = widget.dienstplanEnabled ? 3 : 2;

    final items = [
      _NavItem(Icons.access_time_outlined, Icons.access_time_filled, 'Zeiterfassung', 0),
      _NavItem(Icons.calendar_month_outlined, Icons.calendar_month, 'Monatsübersicht', 1),
      if (widget.dienstplanEnabled)
        _NavItem(Icons.event_note_outlined, Icons.event_note, 'Dienstplan', 2),
    ];

    return Container(
      decoration: BoxDecoration(
        color: skin.bgBase,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom,
        top: 0,
      ),
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final totalW = constraints.maxWidth;
              final itemW = totalW / count;

              // Glatte interpolierte Position
              final normPos =
                  _fromPos + (_toPos - _fromPos) * _anim.value;
              final centerX = normPos * (totalW - itemW) + itemW / 2;

              // Stretch-Effekt: in der Mitte der Animation breiter
              final stretchT = (_anim.value < 0.5
                  ? _anim.value * 2
                  : (1 - _anim.value) * 2);
              final dist = (_toPos - _fromPos).abs() * totalW;
              final extra = (dist * 0.22 * stretchT).clamp(0.0, 36.0);
              const baseW = 72.0;
              const pillH = 52.0;
              final pillW = baseW + extra;

              return SizedBox(
                height: pillH + 8 + 42.0, // Pill + Padding + Text+Icon
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Highlight-Pill ────────────────────────────────────
                    Positioned(
                      // Vertikal mittig über den Icons
                      top: 8,
                      left: centerX - pillW / 2,
                      child: Container(
                        width: pillW,
                        height: pillH,
                        decoration: BoxDecoration(
                          color: skin.primaryWithAlpha(0.14),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: skin.primaryWithAlpha(0.28)),
                        ),
                      ),
                    ),

                    // ── Items ─────────────────────────────────────────────
                    Row(
                      children: items.map((item) {
                        final isSelected =
                            widget.selectedIndex == item.index;
                        return GestureDetector(
                          onTap: () => widget.onTap(item.index),
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox(
                            width: itemW,
                            height: pillH + 8 + 42.0,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(height: 10),
                                AnimatedSwitcher(
                                  duration:
                                      const Duration(milliseconds: 220),
                                  child: Icon(
                                    isSelected
                                        ? item.activeIcon
                                        : item.icon,
                                    key: ValueKey(isSelected),
                                    color: isSelected
                                        ? skin.primary
                                        : skin.surface(0.38),
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                AnimatedDefaultTextStyle(
                                  duration:
                                      const Duration(milliseconds: 220),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSelected
                                        ? skin.primary
                                        : skin.surface(0.38),
                                  ),
                                  child: Text(item.label),
                                ),
                                SizedBox(
                                    height: MediaQuery.of(context)
                                            .padding
                                            .bottom >
                                        0
                                        ? 0
                                        : 8),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
  const _NavItem(this.icon, this.activeIcon, this.label, this.index);
}