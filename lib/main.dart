import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'screens/home_screen.dart';
import 'screens/month_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';
import 'services/pdf_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('arbeitszeiten');
  await Hive.openBox('einstellungen');
  await initializeDateFormatting('de', null);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpTime',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
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
  late AnimationController _tabAnimController;
  late AnimationController _menuAnimController;
  bool _menuOpen = false;

  @override
  void initState() {
    super.initState();
    _tabAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _menuAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _tabAnimController.dispose();
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
    setState(() {
      _selectedIndex = index;
      _tabAnimController.forward(from: 0);
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _goToPage(int index) {
    setState(() => _selectedIndex = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [
          // ── PageView ersetzt AnimatedSwitcher ────────────────────────────
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(), // Wischen wird von den Screens selbst gesteuert
            onPageChanged: (index) {
              setState(() => _selectedIndex = index);
            },
            children: [
              HomeScreen(
                key: const ValueKey('home'),
                onNavigateToMonth: () => _goToPage(1),
              ),
              MonthScreen(
                key: const ValueKey('month'),
                onNavigateToHome: () => _goToPage(0),
              ),
            ],
          ),

          // ── Blur overlay when menu open ──────────────────────────────────
          if (_menuOpen)
            GestureDetector(
              onTap: _closeMenu,
              child: Container(
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),

          // ── Dropdown Menu ────────────────────────────────────────────────
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
                    child: _DropdownMenu(
                      onClose: _closeMenu,
                      onSettings: () {
                        _closeMenu();
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const SettingsScreen(),
                          ),
                        );
                      },
                      onSupport: () {
                        _closeMenu();
                        Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => const SupportScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          ),

          // ── Top Bar with Hamburger ───────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
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
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15)),
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                        child: const Center(
                          child: Text('🇩🇪', style: TextStyle(fontSize: 20)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'OpTime',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: _toggleMenu,
                    child: AnimatedBuilder(
                      animation: _menuAnimController,
                      builder: (context, _) => Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: _menuOpen
                              ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                              : Colors.white.withValues(alpha: 0.08),
                          border: Border.all(
                            color: _menuOpen
                                ? const Color(0xFF6C63FF).withValues(alpha: 0.5)
                                : Colors.white.withValues(alpha: 0.1),
                          ),
                        ),
                        child: AnimatedRotation(
                          turns: _menuOpen ? 0.125 : 0,
                          duration: const Duration(milliseconds: 250),
                          child: Icon(
                            _menuOpen ? Icons.close : Icons.menu,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom Navigation ────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _BottomNav(
              selectedIndex: _selectedIndex,
              onTap: _selectTab,
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownMenu extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onSettings;
  final VoidCallback onSupport;

  const _DropdownMenu({
    required this.onClose,
    required this.onSettings,
    required this.onSupport,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuItem(
            emoji: '📤',
            label: 'Zeiten exportieren',
            onTap: () {
              onClose();
              PdfService.showMonthPickerAndExport(context);
            },
          ),
          _MenuDivider(),
          _MenuItem(
            emoji: '⚙️',
            label: 'Einstellungen',
            onTap: onSettings,
          ),
          _MenuDivider(),
          _MenuItem(
            emoji: '🆘',
            label: 'Support',
            onTap: onSupport,
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final String emoji;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: Colors.white.withValues(alpha: 0.08),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onTap;

  const _BottomNav({required this.selectedIndex, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 8,
        top: 12,
        left: 40,
        right: 40,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A0F).withValues(alpha: 0.9),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _NavItem(
            icon: Icons.access_time_outlined,
            activeIcon: Icons.access_time_filled,
            label: 'Zeiterfassung',
            isSelected: selectedIndex == 0,
            onTap: () => onTap(0),
          ),
          _NavItem(
            icon: Icons.calendar_month_outlined,
            activeIcon: Icons.calendar_month,
            label: 'Monatsübersicht',
            isSelected: selectedIndex == 1,
            onTap: () => onTap(1),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C63FF).withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6C63FF).withValues(alpha: 0.3)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isSelected ? activeIcon : icon,
                key: ValueKey(isSelected),
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : Colors.white.withValues(alpha: 0.4),
                size: 24,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 250),
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? const Color(0xFF6C63FF)
                    : Colors.white.withValues(alpha: 0.4),
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}