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
    debugPrint('✅ Migration abgeschlossen: Alte Einträge konvertiert');
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

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  final PageController _pageController = PageController(initialPage: 0);
  late AnimationController _menuAnimController;
  bool _menuOpen = false;
  bool _prevDienstplanEnabled = false;

  DateTime _sharedDate = DateTime.now();
  DateTime _sharedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _scheduleViewMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  // Share Intent
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
    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    // App war geschlossen und wurde über "Teilen" geöffnet
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      if (files.isNotEmpty) {
        final path = files.first.path;
        if (path != null && path.toLowerCase().endsWith('.pdf')) {
          // Kurz warten bis Widget aufgebaut ist
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleSharedPdf(path);
          });
        }
      }
    });

    // App war im Hintergrund
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
    // Dienstplan-Tab aktivieren falls vorhanden, sonst trotzdem Sheet zeigen
    if (_dienstplanEnabled) {
      _goToPage(2);
    }

    final skin = AppTheme.of(context);
    final fileName = path.split('/').last;

    // Sheet öffnen mit vorgeladener Datei
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
    _pageController.dispose();
    _menuAnimController.dispose();
    super.dispose();
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

  void _selectTab(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final safeIndex = index.clamp(0, _pageCount - 1);
    if (_selectedIndex == safeIndex) return;
    setState(() => _selectedIndex = safeIndex);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        safeIndex,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPage(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    final safeIndex = index.clamp(0, _pageCount - 1);
    setState(() => _selectedIndex = safeIndex);
    if (_pageController.hasClients) {
      _pageController.jumpToPage(safeIndex);
    }
  }

  bool get _isOnSchedulePage => _dienstplanEnabled && _selectedIndex == 2;

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

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
              PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) =>
                    setState(() => _selectedIndex = index),
                children: [
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
                  if (currentDienstplanEnabled)
                    ScheduleScreen(
                      key: const ValueKey('schedule'),
                      onNavigateToHome: () => _goToPage(0),
                      onNavigateToMonth: () => _goToPage(1),
                      onMonthChanged: (m) =>
                          setState(() => _scheduleViewMonth = m),
                    ),
                ],
              ),

              if (_menuOpen)
                GestureDetector(
                  onTap: _closeMenu,
                  child: Container(color: Colors.black.withValues(alpha: 0.5)),
                ),

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
                              border: Border.all(color: skin.borderMedium),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
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
                              _menuOpen ? Icons.close : Icons.menu_rounded,
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
// Dropdown Menu helpers
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
// Bottom Navigation
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
  late AnimationController _slideController;
  int _fromIndex = 0;
  int _toIndex = 0;

  @override
  void initState() {
    super.initState();
    _fromIndex = widget.selectedIndex;
    _toIndex = widget.selectedIndex;
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _slideController.value = 1.0;
  }

  @override
void didUpdateWidget(_BottomNav oldWidget) {
  super.didUpdateWidget(oldWidget);

  if (oldWidget.selectedIndex != widget.selectedIndex) {
    if (_toIndex != widget.selectedIndex) {
      final itemCount = widget.dienstplanEnabled ? 3 : 2;
      // Aktuelle Position als neuen Startpunkt berechnen
      final t = CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeInOutCubic,
      ).value;
      final fromPos = _fromIndex.clamp(0, itemCount - 1).toDouble();
      final toPos = _toIndex.clamp(0, itemCount - 1).toDouble();
      final currentPos = fromPos + (toPos - fromPos) * t;

      _fromIndex = currentPos.round().clamp(0, itemCount - 1);
      _toIndex = widget.selectedIndex;

      // Controller von aktueller Position neu starten
      _slideController.stop();
      _slideController.duration = const Duration(milliseconds: 300);
      _slideController.forward(from: 0.0);
    }
  } else if (oldWidget.dienstplanEnabled != widget.dienstplanEnabled) {
    _fromIndex = widget.selectedIndex;
    _toIndex = widget.selectedIndex;
    _slideController.value = 1.0;
  }
}

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final itemCount = widget.dienstplanEnabled ? 3 : 2;

    final items = [
      _NavItemData(
        itemKey: 'home',
        icon: Icons.access_time_outlined,
        activeIcon: Icons.access_time_filled,
        label: 'Zeiterfassung',
        index: 0,
      ),
      _NavItemData(
        itemKey: 'month',
        icon: Icons.calendar_month_outlined,
        activeIcon: Icons.calendar_month,
        label: 'Monatsübersicht',
        index: 1,
      ),
      if (widget.dienstplanEnabled)
        _NavItemData(
          itemKey: 'schedule',
          icon: Icons.event_note_outlined,
          activeIcon: Icons.event_note,
          label: 'Dienstplan',
          index: 2,
        ),
    ];

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 12,
        left: widget.dienstplanEnabled ? 20 : 40,
        right: widget.dienstplanEnabled ? 20 : 40,
      ),
      decoration: BoxDecoration(
        color: skin.bgBase,
        border: Border(top: BorderSide(color: skin.borderSubtle)),
      ),
      child: AnimatedBuilder(
        animation: _slideController,
        builder: (context, _) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final totalWidth = constraints.maxWidth;
              final itemWidth = totalWidth / itemCount;

              final fromX =
                  _fromIndex.clamp(0, itemCount - 1) * itemWidth + itemWidth / 2;
              final toX =
                  _toIndex.clamp(0, itemCount - 1) * itemWidth + itemWidth / 2;

              final t = CurvedAnimation(
                parent: _slideController,
                curve: Curves.easeInOutCubic,
              ).value;
              final currentX = fromX + (toX - fromX) * t;

              final stretchT = (t < 0.5 ? t * 2 : (1 - t) * 2);
              final distance = (toX - fromX).abs();
              final extraWidth =
                  (distance * 0.25 * stretchT).clamp(0.0, 40.0);
              const baseWidth = 90.0;
              final highlightWidth = baseWidth + extraWidth;

              return Stack(
  clipBehavior: Clip.none,
  children: [
    Positioned(
      left: currentX - highlightWidth / 2,
                    top: 0,
                    child: Container(
                      width: highlightWidth,
                      height: 56,
                      decoration: BoxDecoration(
                        color: skin.primaryWithAlpha(0.15),
                        borderRadius: BorderRadius.circular(14),
                        border:
                            Border.all(color: skin.primaryWithAlpha(0.3)),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: items.map((item) {
                      final isSelected = widget.selectedIndex == item.index;
                      return GestureDetector(
                        onTap: () => widget.onTap(item.index),
                        child: SizedBox(
                          width: itemWidth,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isSelected ? item.activeIcon : item.icon,
                                color: isSelected
                                    ? skin.primary
                                    : skin.surface(0.4),
                                size: 24,
                              ),
                              const SizedBox(height: 4),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? skin.primary
                                      : skin.surface(0.4),
                                ),
                                child: Text(item.label),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _NavItemData {
  final String itemKey;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;

  const _NavItemData({
    required this.itemKey,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
  });
}