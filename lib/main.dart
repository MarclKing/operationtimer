import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'dart:io' as dartio;
import 'screens/home_screen.dart';
import 'screens/month_screen.dart';
import 'screens/schedule_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/support_screen.dart';
import 'services/pdf_service.dart';
import 'theme/app_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

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
  if (changed) debugPrint('✅ Migration abgeschlossen');
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _mainScreenKey = GlobalKey<_MainScreenState>();

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
            // NEU:
onGenerateRoute: (settings) {
  final name = settings.name ?? '';
  if (name.startsWith('optimes://dienstplan/note/')) {
    final dateKey = name.replaceFirst('optimes://dienstplan/note/', '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyApp._mainScreenKey.currentState?._navigateToScheduleNote(dateKey);
    });
  } else if (name == 'optimes://dienstplan' || name == '/dienstplan') {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyApp._mainScreenKey.currentState?._goToPage(2);
    });
  } else if (name.isNotEmpty && name != '/' && !name.startsWith('http')) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      MyApp._mainScreenKey.currentState?.handleSharedPdf(name);
    });
  }
  return null;
},
            onUnknownRoute: (settings) =>
                MaterialPageRoute(builder: (_) => const MainScreen()),
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
            home: MainScreen(key: MyApp._mainScreenKey),
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
  int _currentPage = 0;

  late AnimationController _slideCtrl;
  bool _isDragging = false;
  double _dragStartValue = 0;

  late AnimationController _menuAnimController;
  bool _menuOpen = false;

  DateTime _sharedDate = DateTime.now();
  DateTime _sharedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime _scheduleViewMonth =
      DateTime(DateTime.now().year, DateTime.now().month);

  StreamSubscription? _intentSub;
final _scheduleKey = GlobalKey<ScheduleScreenState>();
final _monthKey = GlobalKey<MonthScreenState>();
final ValueNotifier<bool> _dayCardDragging = ValueNotifier(false);
static const _navChannel = MethodChannel('de.marcel.optimes/navigation');

  bool get _dienstplanEnabled => true;

  int get _pageCount => _dienstplanEnabled ? 3 : 2;

  @override
void initState() {
  super.initState();

  _slideCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    lowerBound: 0.0,
    upperBound: 2.0,
    value: 0.0,
  );
  _slideCtrl.addListener(() => setState(() {}));

  _menuAnimController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  if (!kIsWeb) {
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

  _navChannel.setMethodCallHandler((call) async {
    if (call.method == 'openFromWidget') {
      final args = Map<String, dynamic>.from(call.arguments as Map);
      final url = args['url'] as String;
      if (url.contains('/note/')) {
        final dateKey = url.split('/').last;
        _navigateToScheduleNote(dateKey);
      } else {
        _animateToPage(2);
      }
    }
  });
}

  @override
// RICHTIG:
@override
void dispose() {
  _intentSub?.cancel();
  _slideCtrl.dispose();
  _menuAnimController.dispose();
  _dayCardDragging.dispose();
  super.dispose();
}  // ← diese Klammer einfügen

void _navigateToScheduleNote(String dateKey) async {
  await _animateToPage(2);
  if (!mounted) return;
  await Future.delayed(const Duration(milliseconds: 350));
  if (!mounted) return;
  _scheduleKey.currentState?.openNoteOverlay(dateKey);
}

  // ── Share Intent ───────────────────────────────────────────────────────────

  void _handleSharedPdf(String path) async {
    if (!mounted) return;
    final skin = AppTheme.of(context);
    final fileName = path.split('/').last;

    // Kürze Dateinamen für Anzeige
    String displayName = fileName;
    if (displayName.length > 40) {
      displayName = '${displayName.substring(0, 37)}...';
    }

    // ── Bestätigungs-Alert ─────────────────────────────────────────────────
    final confirmed = await _showImportConfirmDialog(displayName, skin);
    if (!mounted) return;
    if (confirmed != true) return;

    if (_dienstplanEnabled) {
      await _animateToPage(2);
    }
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin);
  }

  Future<bool?> _showImportConfirmDialog(
      String displayName, AppSkin skin) async {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInBack,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
          child: FadeTransition(
            opacity: anim,
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: skin.bgCard,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: skin.borderMedium),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.35),
                  blurRadius: 32,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon + Titel
                Row(children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: skin.primaryWithAlpha(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.upload_file_outlined,
                        color: skin.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Dienstplan importieren',
                      style: TextStyle(
                        color: skin.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 16),
                // Datei-Vorschau
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: skin.surface(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: skin.borderSubtle),
                  ),
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_outlined,
                        color: skin.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        displayName,
                        style: TextStyle(
                          color: skin.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Text(
                  'Soll diese PDF als Dienstplan importiert werden?',
                  style: TextStyle(
                      color: skin.textMuted, fontSize: 13, height: 1.45),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.borderSubtle),
                        ),
                        child: Center(
                          child: Text('Abbrechen',
                              style: TextStyle(
                                  color: skin.textMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: skin.gradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: skin.primaryWithAlpha(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text('Importieren',
                              style: TextStyle(
                                  color: skin.onGradient,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void handleSharedPdf(String path) => _handleSharedPdf(path);

  void _autoImportPdf(
      String path, String fileName, AppSkin skin) async {
    final settingsBox = Hive.box('einstellungen');
    final scheduleName =
        settingsBox.get('dienstplan_name', defaultValue: '') as String;
    final mainName =
        settingsBox.get('name', defaultValue: '') as String;
    final userName =
        scheduleName.isNotEmpty ? scheduleName : mainName;
    final devMode = settingsBox
        .get('dienstplan_dev_placeholder', defaultValue: false) as bool;

    List<int>? bytes;
    try {
      bytes = await dartio.File(path).readAsBytes();
    } catch (_) {
      bytes = null;
    }

    if (!mounted) return;

    if (bytes == null || bytes.isEmpty) {
      _openUploadSheet(path, fileName, skin);
      return;
    }

    final result = await DienstplanParser.parse(
      fileBytes: bytes,
      userName: userName,
      fileName: fileName,
      devMode: devMode,
    );

    if (!mounted) return;

    final error = result['error'] as String?;
    final data =
        Map<String, String>.from(result['data'] as Map? ?? {});
    final DateTime? month = result['month'] as DateTime?;

    if ((error != null && error.isNotEmpty) ||
        data.isEmpty ||
        month == null) {
      _openUploadSheet(
        path,
        fileName,
        skin,
        preloadedBytes: bytes,
        autoImportError: devMode ? (error ?? 'Unbekannter Fehler') : null,
      );
      return;
    }

    final monthKey =
        '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';

    // ── Diff gegen vorhandenen Dienstplan ──────────────────────────────────
    final existingRaw = settingsBox.get('schedule_$monthKey');
    final Map<String, String> oldData = {};
    if (existingRaw is Map) {
      for (final e in existingRaw.entries) {
        oldData[e.key.toString()] = e.value.toString();
      }
    }

    if (oldData.isNotEmpty) {
      final allKeys = {...oldData.keys, ...data.keys};
      final changed = <String>{};
      for (final k in allKeys) {
        if ((oldData[k] ?? '').trim().toUpperCase() !=
            (data[k] ?? '').trim().toUpperCase()) {
          changed.add(k);
        }
      }
      if (changed.isNotEmpty) {
        final changedKey = 'schedule_changed_$monthKey';
        final existingList = settingsBox.get(changedKey);
        final existing = existingList is List
            ? existingList.map((e) => e.toString()).toSet()
            : <String>{};
        settingsBox.put(changedKey, {...existing, ...changed}.toList());
      }
    }

    settingsBox.put('schedule_$monthKey', data);
    setState(() => _scheduleViewMonth = month);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          '✓ Dienstplan ${_monthName(month.month)} ${month.year} importiert (${data.length} Tage)'),
      backgroundColor: skin.statComplete,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(seconds: 3),
    ));
  }

  String _monthName(int m) {
    const names = [
      '',
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];
    return names[m.clamp(1, 12)];
  }

  void _openUploadSheet(
    String path,
    String fileName,
    AppSkin skin, {
    List<int>? preloadedBytes,
    String? autoImportError,
  }) {
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
        preloadedBytes: preloadedBytes,
        autoImportError: autoImportError,
        onImported: () => setState(() {}),
      ),
    );
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> _animateToPage(int target) async {
    final safeTarget = target.clamp(0, _pageCount - 1).toDouble();
    setState(() => _currentPage = target.clamp(0, _pageCount - 1));
    await _slideCtrl.animateTo(
      safeTarget,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _goToPage(int index) {
  FocusManager.instance.primaryFocus?.unfocus();
  _closeMenu();
  _scheduleKey.currentState?.closeOverlays();
  _monthKey.currentState?.closeAllRows();
  _animateToPage(index);
}

  void _selectTab(int index) => _goToPage(index);

  // ── Wischgesten ─────────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    if (_slideCtrl.isAnimating) _slideCtrl.stop();
    _dragStartValue = _slideCtrl.value;
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
  if (!_isDragging) return;
  if (_dayCardDragging.value) return;
  if (_currentPage == 2 && d.delta.dx < 0) return; // ← NEU
  final screenW = MediaQuery.of(context).size.width;
  final delta = -d.delta.dx / screenW;
  final newVal = (_slideCtrl.value + delta)
      .clamp(0.0, (_pageCount - 1).toDouble());
  _slideCtrl.value = newVal;
}

  void _onDragEnd(DragEndDetails d) {
  if (!_isDragging) return;
  _isDragging = false;
  _dayCardDragging.value = false; // ← NEU

  final velocity = d.primaryVelocity ?? 0;
  final current = _slideCtrl.value;

  int targetPage;
  if (velocity < -400) {
    targetPage = (current.ceil()).clamp(0, _pageCount - 1);
  } else if (velocity > 400) {
    targetPage = (current.floor()).clamp(0, _pageCount - 1);
  } else {
    targetPage = current.round().clamp(0, _pageCount - 1);
  }

  // ← NEU: Overlays/Slider schließen wenn Seite wechselt
  if (targetPage != _currentPage) {
    _scheduleKey.currentState?.closeOverlays();
    _monthKey.currentState?.closeAllRows();
  }

  setState(() => _currentPage = targetPage);
  _slideCtrl.animateTo(
    targetPage.toDouble(),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutCubic,
  );
}

  // ── Pages ──────────────────────────────────────────────────────────────────

  List<Widget> _buildPages() => [
        HomeScreen(
          key: const ValueKey('home'),
          selectedDate: _sharedDate,
          onDateChanged: (d) => setState(() => _sharedDate = d),
          onNavigateToMonth: () => _goToPage(1),
        ),
        MonthScreen(
  key: _monthKey,
  selectedMonth: _sharedMonth,
  onMonthChanged: (m) => setState(() => _sharedMonth = m),
  onNavigateToHome: () => _goToPage(0),
),
        if (_dienstplanEnabled)
  ScheduleScreen(
    key: _scheduleKey,
    onNavigateToHome: () => _goToPage(0),
    onNavigateToMonth: () => _goToPage(1),
    onMonthChanged: (m) =>
        setState(() => _scheduleViewMonth = m),
    dayCardDragging: _dayCardDragging, // ← NEU
  ),
      ];

  bool get _isOnSchedulePage =>
      _dienstplanEnabled && _currentPage == 2;

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
    if (!_menuOpen) return;
    setState(() => _menuOpen = false);
    _menuAnimController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        final pages = _buildPages();
        final pageCount = pages.length;

        return Scaffold(
          backgroundColor: skin.bgBase,
          body: Stack(
            children: [
              // ── Slides ────────────────────────────────────────────────────
              RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  HorizontalDragGestureRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                          HorizontalDragGestureRecognizer>(
                    () => HorizontalDragGestureRecognizer(),
                    (instance) {
                      instance
                        ..onStart = _onDragStart
                        ..onUpdate = _onDragUpdate
                        ..onEnd = _onDragEnd;
                    },
                  ),
                },
                behavior: HitTestBehavior.translucent,
                child: Stack(
                  children: List.generate(pageCount, (i) {
                    final offset =
                        (i.toDouble() - _slideCtrl.value) * screenWidth;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: SizedBox(
                        width: screenWidth,
                        height: double.infinity,
                        child: pages[i],
                      ),
                    );
                  }),
                ),
              ),

              // ── Menu Overlay ──────────────────────────────────────────────
              if (_menuOpen)
                GestureDetector(
                  onTap: _closeMenu,
                  child: Container(
                      color: Colors.black.withValues(alpha: 0.5)),
                ),

              // ── Dropdown ──────────────────────────────────────────────────
              AnimatedBuilder(
                animation: _menuAnimController,
                builder: (context, _) => Positioned(
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
                                color: Colors.black
                                    .withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isOnSchedulePage) ...[
                                _DropdownItem(
                                  icon: Icons.upload_file_outlined,
                                  label: 'Dienstplan importieren',
                                  onTap: () {
                                    _closeMenu();
                                    _showUploadSheet(context, skin);
                                  },
                                ),
                                _Divider(),
                              ],
                              if (!_isOnSchedulePage) ...[
                                _DropdownItem(
                                  icon: Icons.picture_as_pdf_outlined,
                                  label: 'Zeiten exportieren',
                                  onTap: () {
                                    _closeMenu();
                                    PdfService.showMonthPickerAndExport(
                                        context);
                                  },
                                ),
                                _Divider(),
                              ],
                              _DropdownItem(
                                icon: Icons.settings_outlined,
                                label: 'Einstellungen',
                                onTap: () {
                                  _closeMenu();
                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                        builder: (_) =>
                                            const SettingsScreen()),
                                  );
                                },
                              ),
                              _Divider(),
                              _DropdownItem(
                                icon: Icons.support_agent_outlined,
                                label: 'Support',
                                onTap: () {
                                  _closeMenu();
                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                        builder: (_) =>
                                            const SupportScreen()),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Top Bar ───────────────────────────────────────────────────
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
                      Row(children: [
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
                        Text('OpTimes',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: skin.textPrimary,
                            )),
                      ]),
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

              // ── Bottom Nav ────────────────────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _BottomNav(
                  pageValue: _slideCtrl.value,
                  selectedIndex: _currentPage,
                  dienstplanEnabled: true,
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

class _DropdownItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DropdownItem(
      {required this.icon, required this.label, required this.onTap});

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
        child: Row(children: [
          Icon(icon, size: 20, color: skin.textMuted),
          const SizedBox(width: 12),
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: skin.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500))),
        ]),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return Container(height: 0.5, color: skin.borderSubtle);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Navigation
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final double pageValue;
  final int selectedIndex;
  final bool dienstplanEnabled;
  final Function(int) onTap;

  const _BottomNav({
    required this.pageValue,
    required this.selectedIndex,
    required this.dienstplanEnabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final count = dienstplanEnabled ? 3 : 2;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    // Dimensionen
    const double iconSize = 24.0;
    const double labelFontSize = 10.5;
    const double iconLabelGap = 4.0;
    const double labelH = 14.0;
    const double contentH = iconSize + iconLabelGap + labelH; // 42
    const double pillVPad = 7.0; // mehr Luft oben/unten in der Pill
    const double pillH = contentH + pillVPad * 2; // 56

    // Gesamthöhe der NavBar: oben 12px Abstand, dann Pill, dann safe-area
    const double navTopPad = 12.0;
    // Nach der Pill noch etwas Luft + safe-area
    final double navH =
        navTopPad + pillH + (bottomPad > 0 ? bottomPad + 4.0 : 10.0);

    final items = [
      _NavItem(Icons.access_time_outlined, Icons.access_time_filled,
          'Zeiterfassung', 0),
      _NavItem(Icons.calendar_month_outlined, Icons.calendar_month,
          'Monatsübersicht', 1),
      if (dienstplanEnabled)
        _NavItem(Icons.event_note_outlined, Icons.event_note,
            'Dienstplan', 2),
    ];

    return Container(
      height: navH,
      decoration: BoxDecoration(
        color: skin.bgBase,
        border: Border(
            top: BorderSide(color: skin.borderSubtle, width: 0.5)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final totalW = constraints.maxWidth;
        final itemW = totalW / count;

        // Pill-Breite: etwas kleiner als itemW damit Ränder frei bleiben
        final pillW = (itemW - 16.0).clamp(64.0, itemW - 8.0);

        // Kontinuierliche Pill-X-Position
        final maxPages = (count - 1).toDouble().clamp(1.0, 99.0);
        final normPos = pageValue.clamp(0.0, maxPages) / maxPages;
        final pillCenterX = normPos * (totalW - itemW) + itemW / 2;

        // Stretch-Effekt
        final frac =
            (pageValue - pageValue.truncateToDouble()).abs();
        final stretch =
            frac < 0.5 ? frac * 2.0 : (1.0 - frac) * 2.0;
        final stretchExtra =
            (itemW * 0.07 * stretch).clamp(0.0, 10.0);
        final finalPillW =
            (pillW + stretchExtra).clamp(64.0, itemW - 4.0);

        // Vertikale Positionierung: Pill oben, dann Items
        final pillTop = navTopPad;
        // Icon soll vertikal in der Pill zentriert sein
        final iconTop = pillTop + pillVPad;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Pill ──────────────────────────────────────────────────
            Positioned(
              top: pillTop,
              left: pillCenterX - finalPillW / 2,
              child: Container(
                width: finalPillW,
                height: pillH,
                decoration: BoxDecoration(
                  color: skin.primaryWithAlpha(0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: skin.primaryWithAlpha(0.28), width: 1),
                ),
              ),
            ),

            // ── Items ─────────────────────────────────────────────────
            SizedBox(
              height: navH,
              child: Row(
                children: items.map((item) {
                  final isSelected = selectedIndex == item.index;
                  return GestureDetector(
                    onTap: () => onTap(item.index),
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox(
                      width: itemW,
                      height: navH,
                      child: Padding(
                        padding: EdgeInsets.only(top: iconTop),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment:
                              CrossAxisAlignment.center,
                          children: [
                            Icon(
                              isSelected
                                  ? item.activeIcon
                                  : item.icon,
                              color: isSelected
                                  ? skin.primary
                                  : skin.surface(0.38),
                              size: iconSize,
                            ),
                            const SizedBox(height: iconLabelGap),
                            Text(
                              item.label,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: labelFontSize,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isSelected
                                    ? skin.primary
                                    : skin.surface(0.38),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      }),
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