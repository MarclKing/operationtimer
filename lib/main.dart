import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
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
import 'screens/fahrtenbuch_screen.dart';
import 'screens/export_hinweise_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/splash_screen.dart';
import 'services/pdf_service.dart';
import 'screens/dictation_help_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:convert';
import 'utils/cleanup.dart';
import 'package:intl/intl.dart';
import 'screens/tasks_screen.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'screens/admin_rules_screen.dart';
import 'services/rule_engine.dart';
import 'services/sync_service.dart';

void main() async {
  WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  // Querformat sperren
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Hive MUSS vor Services initialisiert werden, die darauf zugreifen
  await Hive.initFlutter();
  await Hive.openBox('arbeitszeiten');
  await Hive.openBox('einstellungen');

  // Erst danach Services initialisieren
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await AuthService.instance.init();
  await SyncService.instance.init();
  await RuleEngine.instance.init();

  await NotificationService.instance.init();

  _migrateOldEntries();
  await runAutoCleanup();
  await initializeDateFormatting('de', null);

  try {
    FlutterNativeSplash.remove();
  } catch (e) {
    debugPrint('⚠️  FlutterNativeSplash.remove() fehlgeschlagen (im Web normal): $e');
  }

  runApp(const MyApp());
}

Future<bool?> confirmDeleteDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Löschen',
}) {
  final skin = AppTheme.of(context);
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: skin.bgCard,
      title: Text(title, style: TextStyle(color: skin.textPrimary)),
      content: Text(body, style: TextStyle(color: skin.textMuted)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Abbrechen', style: TextStyle(color: skin.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel, style: TextStyle(color: skin.deleteColor)),
        ),
      ],
    ),
  );
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

  static final mainScreenKey = GlobalKey<_MainScreenState>();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        final skinKey = box.get(AppTheme.hiveKey, defaultValue: 'shield') as String;
        final skin = AppTheme.fromKey(skinKey);
        return SkinProvider(
          skin: skin,
          child: MaterialApp(
            title: 'OpTimes',
            debugShowCheckedModeBanner: false,
            onGenerateRoute: (settings) {
              final name = settings.name ?? '';
              if (name.startsWith('optimes://dienstplan/note/')) {
                final dateKey = name.replaceFirst('optimes://dienstplan/note/', '');
                Future.delayed(const Duration(milliseconds: 200), () {
                  MyApp.mainScreenKey.currentState?._navigateToScheduleNote(dateKey);
                });
              } else if (name == 'optimes://dienstplan' || name == '/dienstplan') {
                Future.delayed(const Duration(milliseconds: 200), () {
                  MyApp.mainScreenKey.currentState?._goToPage(2);
                });
              } else if (name.isNotEmpty &&
                  name != '/' &&
                  !name.startsWith('http') &&
                  name.toLowerCase().endsWith('.pdf')) {
                Future.delayed(const Duration(milliseconds: 200), () {
                  MyApp.mainScreenKey.currentState?.handleSharedPdf(name);
                });
              }
              return null;
            },
            onUnknownRoute: (settings) => MaterialPageRoute(builder: (_) => MainScreen(key: MyApp.mainScreenKey)),
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
            home: const SplashScreen(),
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
  DateTime _scheduleViewMonth = DateTime(DateTime.now().year, DateTime.now().month);

  StreamSubscription? _intentSub;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _scheduleKey = GlobalKey<ScheduleScreenState>();
  final _monthKey = GlobalKey<MonthScreenState>();
  final _fahrtenbuchKey = GlobalKey<FahrtenbuchScreenState>();
  final _tasksKey = GlobalKey<TasksScreenState>();
  final ValueNotifier<bool> _dayCardDragging = ValueNotifier(false);
  final ValueNotifier<bool> _homeOverlayActive = ValueNotifier(false);
  static const _navChannel = MethodChannel('de.marcel.optimes/navigation');

  bool get _dienstplanEnabled => true;
  int get _pageCount => _dienstplanEnabled ? 5 : 4;
  bool get _isOnSchedulePage => _dienstplanEnabled && _currentPage == 2;
  bool get _isOnFahrtenbuchPage => _currentPage == (_dienstplanEnabled ? 3 : 2);

  @override
  void initState() {
    super.initState();

    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      lowerBound: 0.0,
      upperBound: 4.0,
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
            dartio.File(path).readAsBytes().then((bytes) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (bytes.isNotEmpty) {
                  _handleSharedPdfWithBytes(path, bytes);
                } else {
                  _handleSharedPdf(path);
                }
              });
            }).catchError((e) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _handleSharedPdf(path);
              });
            });
          }
        }
      });

      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((files) {
        if (files.isNotEmpty) {
          final path = files.first.path;
          if (path != null && path.toLowerCase().endsWith('.pdf')) {
            dartio.File(path).readAsBytes().then((bytes) {
              if (bytes.isNotEmpty) {
                _handleSharedPdfWithBytes(path, bytes);
              } else {
                _handleSharedPdf(path);
              }
            }).catchError((e) {
              _handleSharedPdf(path);
            });
          }
        }
      }, onError: (e) {
        debugPrint('❌ Stream onError: $e');
      });
    }

    _navChannel.setMethodCallHandler((call) async {
      if (call.method == 'openFromWidget') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final url = args['url'] as String;
        final path = args['path'] as String;
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        if (path == 'fahrtenbuch_neue_fahrt_scan') {
          await _animateToPage(_dienstplanEnabled ? 3 : 2);
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _fahrtenbuchKey.currentState?.triggerKmStartScan();
          return;
        }
        if (url.contains('/note/')) {
          final dateKey = url.split('/').last;
          await _navigateToScheduleNote(dateKey);
        } else if (path == 'dienstplan') {
          await _animateToPage(2);
        }
      } else if (call.method == 'openSharedPdf') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final path = args['path'] as String;
        final fileName = (args['fileName'] as String?) ?? 'dienstplan.pdf';
        if (path.isEmpty) return;
        await Future.delayed(const Duration(milliseconds: 150));
        if (!mounted) return;
        try {
          final bytes = await dartio.File(path).readAsBytes();
          if (bytes.isNotEmpty && mounted) {
            _handleSharedPdfWithBytesAndName(path, bytes, fileName);
          }
        } catch (e) {
          debugPrint('❌ openSharedPdf Fehler: $e');
        }
      }
    });

    // onOverlayStateChanged wurde entfernt - nicht mehr benötigt

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWelcomeDialog(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermissions();
    });

    // ── NEU: Review-Callback für Homescreen ──
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeKey.currentState?.onReviewFromHomescreen = (parsed, logRef) {
        _tasksKey.currentState?.openQuickAdd(
          initialTitle: parsed.title,
          initialDate: parsed.combinedDateTime,
        );
      };
    });
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _slideCtrl.dispose();
    _menuAnimController.dispose();
    _dayCardDragging.dispose();
    super.dispose();
  }

  Future<void> _navigateToScheduleNote(String dateKey) async {
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _animateToPage(2);
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _scheduleKey.currentState?.openNoteOverlay(dateKey);
  }

  void _handleSharedPdfWithBytesAndName(String path, List<int> bytes, String fileName) async {
    if (!mounted) return;
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final skin = AppTheme.of(context);
    String displayName = fileName;
    if (displayName.length > 40) displayName = '${displayName.substring(0, 37)}...';
    final confirmed = await _showImportConfirmDialog(displayName, skin);
    if (!mounted || confirmed != true) return;
    if (_dienstplanEnabled) await _animateToPage(2);
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin, preloadedBytes: bytes);
  }

  Future<bool?> _showImportConfirmDialog(String displayName, AppSkin skin) async {
    return showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Schließen',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 280),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeInBack);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.82, end: 1.0).animate(curved),
          child: FadeTransition(opacity: anim, child: child),
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
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 32, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: skin.primaryWithAlpha(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.upload_file_outlined, color: skin.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('Dienstplan importieren',
                        style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: skin.surface(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: skin.borderSubtle),
                  ),
                  child: Row(children: [
                    Icon(Icons.picture_as_pdf_outlined, color: skin.primary, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(displayName,
                          style: TextStyle(color: skin.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('Soll diese PDF als Dienstplan importiert werden?',
                    style: TextStyle(color: skin.textMuted, fontSize: 13, height: 1.45)),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          color: skin.surface(0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: skin.borderSubtle),
                        ),
                        child: Center(
                          child: Text('Abbrechen',
                              style: TextStyle(color: skin.textMuted, fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(ctx, true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        decoration: BoxDecoration(
                          gradient: skin.gradient,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [BoxShadow(color: skin.primaryWithAlpha(0.3), blurRadius: 8, offset: const Offset(0, 3))],
                        ),
                        child: Center(
                          child: Text('Importieren',
                              style: TextStyle(color: skin.onGradient, fontSize: 15, fontWeight: FontWeight.w700)),
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

  void handleSharedPdf(String path) => _handleSharedPdfWithBytes(path, []);

  void _handleSharedPdf(String path) async {
    if (!mounted) return;
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final skin = AppTheme.of(context);
    final fileName = path.split('/').last;
    String displayName = fileName;
    if (displayName.length > 40) displayName = '${displayName.substring(0, 37)}...';
    final confirmed = await _showImportConfirmDialog(displayName, skin);
    if (!mounted || confirmed != true) return;
    if (_dienstplanEnabled) await _animateToPage(2);
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin);
  }

  void _handleSharedPdfWithBytes(String path, List<int> bytes) async {
    if (!mounted) return;
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    final skin = AppTheme.of(context);
    final fileName = path.split('/').last;
    String displayName = fileName;
    if (displayName.length > 40) displayName = '${displayName.substring(0, 37)}...';
    final confirmed = await _showImportConfirmDialog(displayName, skin);
    if (!mounted || confirmed != true) return;
    if (_dienstplanEnabled) await _animateToPage(2);
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin, preloadedBytes: bytes);
  }

  void _autoImportPdf(String path, String fileName, AppSkin skin, {List<int>? preloadedBytes}) async {
    final settingsBox = Hive.box('einstellungen');
    final scheduleName = settingsBox.get('dienstplan_name', defaultValue: '') as String;
    final mainName = settingsBox.get('name', defaultValue: '') as String;
    final userName = scheduleName.isNotEmpty ? scheduleName : mainName;
    final devMode = settingsBox.get('dienstplan_dev_placeholder', defaultValue: false) as bool;

    List<int>? bytes = preloadedBytes;
    if (bytes == null || bytes.isEmpty) {
      try {
        bytes = await dartio.File(path).readAsBytes();
      } catch (_) {
        bytes = null;
      }
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
    final data = Map<String, String>.from(result['data'] as Map? ?? {});
    final DateTime? month = result['month'] as DateTime?;

    if ((error != null && error.isNotEmpty) || data.isEmpty || month == null) {
      _openUploadSheet(path, fileName, skin,
          preloadedBytes: bytes, autoImportError: devMode ? (error ?? 'Unbekannter Fehler') : null);
      return;
    }

    final monthKey = '${month.year.toString().padLeft(4, '0')}-${month.month.toString().padLeft(2, '0')}';
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
        if ((oldData[k] ?? '').trim().toUpperCase() != (data[k] ?? '').trim().toUpperCase()) {
          changed.add(k);
        }
      }
      if (changed.isNotEmpty) {
        final changedKey = 'schedule_changed_$monthKey';
        final existingList = settingsBox.get(changedKey);
        final existing = existingList is List ? existingList.map((e) => e.toString()).toSet() : <String>{};
        settingsBox.put(changedKey, {...existing, ...changed}.toList());
      }
    }

    settingsBox.put('schedule_$monthKey', data);

    try {
      if (bytes.isNotEmpty) {
        final colleagues = DienstplanParser.parseAllColleagues(
          bytes: bytes,
          fileName: fileName,
          ownUserName: userName,
        );
        if (colleagues.isNotEmpty) {
          final encoded = jsonEncode(colleagues.map((k, v) => MapEntry(k, v)));
          settingsBox.put('colleagues_$monthKey', encoded);
        }

        final events = DienstplanParser.parseEvents(
          bytes: bytes,
          fileName: fileName,
          devMode: devMode,
        );
        if (events.isNotEmpty) {
          final encodedEvents = jsonEncode(events);
          settingsBox.put('events_$monthKey', encodedEvents);
        }
      }
    } catch (e) {
      debugPrint('[DEV] Events-Import Fehler: $e');
    }

    setState(() => _scheduleViewMonth = month);
    await ScheduleScreenState.pushScheduleToWidget();

    final wasOverwritten = oldData.isNotEmpty;
    final changedCount = wasOverwritten
        ? (() {
            final allKeys = {...oldData.keys, ...data.keys};
            return allKeys
                .where((k) => (oldData[k] ?? '').trim().toUpperCase() != (data[k] ?? '').trim().toUpperCase())
                .length;
          })()
        : 0;

    final snackText = wasOverwritten
        ? '⚠️ Dienstplan ${_monthName(month.month)} ${month.year} überschrieben ($changedCount Änderungen)'
        : '✓ Dienstplan ${_monthName(month.month)} ${month.year} importiert (${data.length} Tage)';

    _scheduleKey.currentState?.loadScheduleData();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(snackText),
      backgroundColor: skin.statComplete,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      duration: const Duration(seconds: 3),
    ));
  }

  String _monthName(int m) {
    const names = ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return names[m.clamp(1, 12)];
  }

  void _openUploadSheet(String path, String fileName, AppSkin skin, {List<int>? preloadedBytes, String? autoImportError}) {
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
        onImported: () {
          setState(() {});
          _scheduleKey.currentState?.loadScheduleData();
        },
      ),
    );
  }

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
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    _monthKey.currentState?.closeAllRows();
    _fahrtenbuchKey.currentState?.closeOverlays();

    // NEU: Wenn wir zum Schedule-Tab (Index 2) wechseln, Task-Marker aktualisieren
    if (index == 2 && _dienstplanEnabled) {
      _scheduleKey.currentState?.refreshTaskMarkers();
    }

    _animateToPage(index);
  }

  void _onPlusPressed() {
    final hasDraft = _fahrtenbuchKey.currentState?.hasDraft ?? false;
    _fahrtenbuchKey.currentState?.closeOverlays();
    if (hasDraft) {
      _fahrtenbuchKey.currentState?.reopenDraft();
    } else {
      _fahrtenbuchKey.currentState?.showAddFahrtOverlay();
    }
  }

  void _selectTab(int index) {
    if (index == _currentPage) {
      switch (index) {
        case 1:
          _monthKey.currentState?.scrollToTop();
          break;
        case 2:
          if (_dienstplanEnabled) _scheduleKey.currentState?.scrollToTop();
          break;
        case 3:
          _fahrtenbuchKey.currentState?.scrollToTop();
          break;
        case 4:
          if (_dienstplanEnabled) _tasksKey.currentState?.scrollToTop();
          break;
      }
      return;
    }

    // NEU: Wenn wir zum Schedule-Tab (Index 2) wechseln, Task-Marker aktualisieren
    if (index == 2 && _dienstplanEnabled) {
      _scheduleKey.currentState?.refreshTaskMarkers();
    }

    _goToPage(index);
  }

  void _onDragStart(DragStartDetails d) {
    if (_slideCtrl.isAnimating) _slideCtrl.stop();
    _dragStartValue = _slideCtrl.value;
    _isDragging = true;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (!_isDragging) return;
    if (_dayCardDragging.value) return;
    if (_currentPage == (_pageCount - 1) && d.delta.dx < 0) return;
    final screenW = MediaQuery.of(context).size.width;
    final delta = -d.delta.dx / screenW;
    final newVal = (_slideCtrl.value + delta).clamp(0.0, (_pageCount - 1).toDouble());
    _slideCtrl.value = newVal;
  }

  void _onDragEnd(DragEndDetails d) {
    if (!_isDragging) return;
    _isDragging = false;
    _dayCardDragging.value = false;

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

    if (targetPage != _currentPage) {
      _homeKey.currentState?.closeOverlays();
      _scheduleKey.currentState?.closeOverlays();
      _monthKey.currentState?.closeAllRows();
      _fahrtenbuchKey.currentState?.closeOverlays();

      // NEU: Wenn wir zum Schedule-Tab (Index 2) wechseln, Task-Marker aktualisieren
      if (targetPage == 2 && _dienstplanEnabled) {
        _scheduleKey.currentState?.refreshTaskMarkers();
      }
    }

    setState(() => _currentPage = targetPage);
    _slideCtrl.animateTo(
      targetPage.toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  List<Widget> _buildPages() => [
    HomeScreen(
      key: _homeKey,
      selectedDate: _sharedDate,
      onDateChanged: (d) => setState(() => _sharedDate = d),
      onNavigateToMonth: () => _goToPage(1),
      onNavigateToFahrtenbuch: () => _goToPage(_dienstplanEnabled ? 3 : 2),
      onNavigateToFahrtenbuchNeueFahrt: () async {        // NEU
        await _animateToPage(_dienstplanEnabled ? 3 : 2);
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        _fahrtenbuchKey.currentState?.triggerKmStartScan();
      },
      onNavigateToTasks: () => _goToPage(_dienstplanEnabled ? 4 : 3),
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
        onMonthChanged: (m) => setState(() => _scheduleViewMonth = m),
        dayCardDragging: _dayCardDragging,
      ),
    FahrtenbuchScreen(
      key: _fahrtenbuchKey,
      onDraftChanged: () => setState(() {}),
    ),
    TasksScreen(key: _tasksKey),
  ];

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

  void _showKfzVerwaltung(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _KfzVerwaltungSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return ValueListenableBuilder(
      valueListenable: Hive.box('einstellungen').listenable(),
      builder: (context, box, _) {
        final pages = _buildPages();
        final pageCount = pages.length;
        final hasDraft = _fahrtenbuchKey.currentState?.hasDraft ?? false;

        return Scaffold(
          backgroundColor: skin.bgBase,
          resizeToAvoidBottomInset: false,
          body: Stack(
            children: [
              RawGestureDetector(
                gestures: <Type, GestureRecognizerFactory>{
                  HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
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
                    final offset = (i.toDouble() - _slideCtrl.value) * screenWidth;
                    return Transform.translate(
                      offset: Offset(offset, 0),
                      child: SizedBox(width: screenWidth, height: double.infinity, child: pages[i]),
                    );
                  }),
                ),
              ),

              Positioned(
                bottom: bottomPad > 0 ? bottomPad + 8 : 16,
                left: 0,
                right: 0,
                child: Center(
                  child: _GlassBottomNav(
                    selectedIndex: _currentPage,
                    dienstplanEnabled: _dienstplanEnabled,
                    onTap: _selectTab,
                  ),
                ),
              ),

              if (_menuOpen)
                GestureDetector(
                  onTap: _closeMenu,
                  child: Container(color: Colors.black.withValues(alpha: 0.5)),
                ),

              AnimatedBuilder(
                animation: _menuAnimController,
                builder: (context, _) => Positioned(
                  top: topPad + 60,
                  right: 16,
                  child: Transform.scale(
                    scale: _menuAnimController.value,
                    alignment: Alignment.topRight,
                    child: Opacity(
                      opacity: _menuAnimController.value,
                      child: Material(
                        color: Colors.transparent,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                            child: Container(
                              width: 220,
                              decoration: BoxDecoration(
                                color: skin.isLight ? Colors.white.withValues(alpha: 0.82) : skin.bgCard.withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.16)),
                                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 8))],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // IMMER OBEN: Einstellungen
                                  _DropdownItem(
                                    icon: Icons.settings_outlined,
                                    label: 'Einstellungen',
                                    onTap: () {
                                      _closeMenu();
                                      Navigator.push(context, CupertinoPageRoute(builder: (_) => const SettingsScreen()));
                                    },
                                  ),
                                  _Divider(),

                                  // DYNAMISCHE EINTRÄGE je nach aktiver Seite
                                  if (_isOnFahrtenbuchPage && _currentPage != (_dienstplanEnabled ? 4 : 3)) ...[
                                    _DropdownItem(
                                      icon: Icons.directions_car_outlined,
                                      label: 'Fahrzeuge verwalten',
                                      onTap: () {
                                        _closeMenu();
                                        _showKfzVerwaltung(context);
                                      },
                                    ),
                                    _Divider(),
                                    _DropdownItem(
                                      icon: Icons.upload_outlined,
                                      label: 'Exportanleitung',
                                      onTap: () {
                                        _closeMenu();
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(
                                            builder: (_) => const ExportHinweiseScreen(),
                                          ),
                                        );
                                      },
                                    ),
                                    _Divider(),
                                  ],
                                  if (_isOnSchedulePage && !_isOnFahrtenbuchPage) ...[
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
                                  if (_currentPage == 1) ...[
                                    _DropdownItem(
                                      icon: Icons.picture_as_pdf_outlined,
                                      label: 'Zeiten exportieren',
                                      onTap: () {
                                        _closeMenu();
                                        PdfService.showMonthPickerAndExport(context);
                                      },
                                    ),
                                    _Divider(),
                                  ],

                                  if (_currentPage == (_dienstplanEnabled ? 4 : 3)) ...[
                                    _DropdownItem(
                                      icon: Icons.mic_outlined,
                                      label: 'Sprachbefehle & Hilfe',
                                      onTap: () {
                                        _closeMenu();
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(builder: (_) => const DictationHelpScreen()),
                                        );
                                      },
                                    ),
                                    _Divider(),
                                  ],

                                  // IMMER UNTEN: Support
                                  _DropdownItem(
                                    icon: Icons.support_agent_outlined,
                                    label: 'Support',
                                    onTap: () {
                                      _closeMenu();
                                      Navigator.push(context, CupertinoPageRoute(builder: (_) => const SupportScreen()));
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
                ),
              ),

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: EdgeInsets.only(top: topPad + 8, left: 20, right: 16, bottom: 8),
                  color: Colors.transparent,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      const Spacer(),
                      if (_isOnFahrtenbuchPage)
                        GestureDetector(
                          onTap: _onPlusPressed,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                hasDraft ? Icons.edit_note_rounded : Icons.add,
                                color: skin.textPrimary,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      GestureDetector(
                        onTap: _toggleMenu,
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) =>
                                  ScaleTransition(
                                    scale: CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeInOutBack),
                                    child: FadeTransition(
                                        opacity: animation, child: child),
                                  ),
                              child: Icon(
                                _menuOpen ? Icons.close_rounded : Icons.menu_rounded,
                                key: ValueKey(_menuOpen),
                                color: skin.textPrimary,
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
        onImported: () {
          setState(() {});
          _scheduleKey.currentState?.loadScheduleData();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KFZ-Verwaltung Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _KfzVerwaltungSheet extends StatefulWidget {
  const _KfzVerwaltungSheet();

  @override
  State<_KfzVerwaltungSheet> createState() => _KfzVerwaltungSheetState();
}

class _KfzVerwaltungSheetState extends State<_KfzVerwaltungSheet> {
  List<Map<String, dynamic>> _entries = [];
  final Map<String, double> _swipeOffsets = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() => _entries = KmMemory.getAll());
  }

  String _formatKm(int km) {
    if (km >= 1000) return '${km ~/ 1000}.${(km % 1000).toString().padLeft(3, '0')}';
    return km.toString();
  }

  Future<void> _deleteEntry(String kennzeichen) async {
    final skin = AppTheme.of(context);
    final confirmed = await confirmDeleteDialog(
      context,
      title: '$kennzeichen löschen?',
      body: 'Das Fahrzeug wird aus dem KM-Gedächtnis entfernt.',
      confirmLabel: 'Löschen',
    );
    if (confirmed == true) {
      KmMemory.delete(kennzeichen);
      _load();
    }
  }

  void _editKm(Map<String, dynamic> entry) {
    final skin = AppTheme.of(context);
    final kz = entry['kennzeichen'] as String;
    final ctrl = TextEditingController(text: (entry['kmEnd'] as int).toString());
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              decoration: BoxDecoration(
                color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgSheet.withValues(alpha: 0.92),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                border: Border.all(color: skin.glassBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4,
                      decoration: BoxDecoration(color: skin.surface(0.2), borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  Text('KM-Stand bearbeiten – $kz',
                      style: TextStyle(color: skin.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(color: skin.textPrimary, fontSize: 28, fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: '0',
                      hintStyle: TextStyle(color: skin.surface(0.2), fontSize: 28),
                      border: InputBorder.none,
                      suffix: Text(' km', style: TextStyle(color: skin.surface(0.4), fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () {
                      final km = int.tryParse(ctrl.text);
                      if (km != null && km > 0) {
                        KmMemory.save(kz, km);
                        Navigator.pop(context);
                        _load();
                      }
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: skin.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: skin.primary.withValues(alpha: 0.35)),
                      ),
                      child: Center(child: Text('Übernehmen',
                          style: TextStyle(color: skin.primary, fontSize: 15, fontWeight: FontWeight.w700))),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.92) : skin.bgSheet.withValues(alpha: 0.92),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: skin.glassBorder),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4,
                  decoration: BoxDecoration(color: skin.surface(0.18), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Icon(Icons.directions_car_outlined, color: skin.primary, size: 20),
                  const SizedBox(width: 10),
                  Text('Fahrzeuge & KM-Stand', style: TextStyle(color: skin.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 12),
              if (_entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Noch keine Fahrzeuge gespeichert.',
                      style: TextStyle(color: skin.textMuted, fontSize: 14), textAlign: TextAlign.center),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: _entries.length,
                    itemBuilder: (context, i) {
                      final e = _entries[i];
                      final kz = e['kennzeichen'] as String? ?? '';
                      final km = e['kmEnd'] as int? ?? 0;
                      final datum = e['datum'] as String?;
                      final dateStr = datum != null
                          ? DateFormat('dd.MM.yy').format(DateTime.tryParse(datum) ?? DateTime.now())
                          : '';
                      final swipe = _swipeOffsets[kz] ?? 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) {
                            setState(() {
                              _swipeOffsets[kz] = ((_swipeOffsets[kz] ?? 0) + d.delta.dx).clamp(-80.0, 0.0);
                            });
                          },
                          onHorizontalDragEnd: (d) {
                            if ((_swipeOffsets[kz] ?? 0) < -40) {
                              setState(() => _swipeOffsets[kz] = -80.0);
                            } else {
                              setState(() => _swipeOffsets[kz] = 0.0);
                            }
                          },
                          child: SizedBox(
                            height: 72,
                            child: ClipRect(
                              child: Stack(
                                children: [
                                  Positioned(
                                    right: 0, top: 4, bottom: 4, width: 75,
                                    child: GestureDetector(
                                      onTap: () => _deleteEntry(kz),
                                      child: Opacity(
                                        opacity: ((-(_swipeOffsets[kz] ?? 0)) / 80).clamp(0.0, 1.0),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(14),
                                          child: BackdropFilter(
                                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                                            child: Container(
                                              margin: const EdgeInsets.only(left: 5),
                                              decoration: BoxDecoration(
                                                color: skin.deleteColor.withValues(alpha: 0.10),
                                                borderRadius: BorderRadius.circular(14),
                                                border: Border.all(color: skin.deleteColor.withValues(alpha: 0.22)),
                                              ),
                                              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                                Icon(Icons.delete_outline, color: skin.deleteColor, size: 20),
                                                const SizedBox(height: 3),
                                                Text('Löschen', style: TextStyle(color: skin.deleteColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                              ]),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Transform.translate(
                                    offset: Offset(swipe, 0),
                                    child: GestureDetector(
                                      onTap: () => _editKm(e),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(14),
                                        child: BackdropFilter(
                                          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                          child: Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: skin.isLight ? Colors.white.withValues(alpha: 0.72) : skin.bgCard.withValues(alpha: 0.65),
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: skin.glassBorder),
                                            ),
                                            child: Row(children: [
                                              Container(
                                                width: 36, height: 36,
                                                decoration: BoxDecoration(
                                                  color: skin.primary.withValues(alpha: 0.10),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(Icons.directions_car_outlined, color: skin.primary, size: 18),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                  Text(kz, style: TextStyle(color: skin.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                                                  Text('${_formatKm(km)} km  ·  $dateStr',
                                                      style: TextStyle(color: skin.textMuted, fontSize: 11)),
                                                ]),
                                              ),
                                              Icon(Icons.edit_outlined, color: skin.surface(0.3), size: 16),
                                            ]),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
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

// ─────────────────────────────────────────────────────────────────────────────
// Dropdown Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _DropdownItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DropdownItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, size: 20, color: skin.textMuted),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: skin.textPrimary, fontSize: 14, fontWeight: FontWeight.w500))),
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

class _GlassBottomNav extends StatefulWidget {
  final int selectedIndex;
  final bool dienstplanEnabled;
  final Function(int) onTap;

  const _GlassBottomNav({
    required this.selectedIndex,
    required this.dienstplanEnabled,
    required this.onTap,
  });

  @override
  State<_GlassBottomNav> createState() => _GlassBottomNavState();
}

class _GlassBottomNavState extends State<_GlassBottomNav>
    with SingleTickerProviderStateMixin {
  late AnimationController _bounceCtrl;
  late Animation<double> _stretchAnim;
  int _lastIndex = 0;
  double _stretchDirection = 0;

  bool _isDraggingNav = false;
  double _dragStartX = 0;
  int _dragStartIndex = 0;
  static const double _scrubItemWidth = 58.0;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.selectedIndex;
    _bounceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _stretchAnim = CurvedAnimation(
      parent: _bounceCtrl,
      curve: Curves.elasticOut,
    );
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    super.dispose();
  }

  void _handleTap(int index) {
    if (index == widget.selectedIndex) {
      widget.onTap(index);
      return;
    }
    _stretchDirection = index > _lastIndex ? 1.0 : -1.0;
    _lastIndex = index;
    _bounceCtrl.forward(from: 0);
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    final items = [
      _NavItem(Icons.home_outlined, Icons.home_filled, 'Zeiterfassung', 0),
      _NavItem(Icons.access_time_outlined, Icons.access_time_filled, 'Monatsübersicht', 1),
      if (widget.dienstplanEnabled)
        _NavItem(Icons.event_note_outlined, Icons.event_note, 'Dienstplan', 2),
      _NavItem(Icons.directions_car_outlined, Icons.directions_car, 'Fahrtenbuch', widget.dienstplanEnabled ? 3 : 2),
      _NavItem(Icons.check_rounded, Icons.check_rounded, 'Aufgaben', widget.dienstplanEnabled ? 4 : 3),
    ];

    final navContent = AnimatedBuilder(
      animation: _stretchAnim,
      builder: (context, child) {
        final t = _stretchAnim.value;
        final stretch = 1.0 + (_stretchDirection * 0.035 * (1.0 - t));
        final squish = 1.0 - (0.018 * (1.0 - t));
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..scale(stretch, squish),
          child: child,
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: 0.72)
                  : Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.55)
                    : Colors.white.withValues(alpha: 0.12),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                      alpha: skin.isLight ? 0.08 : 0.35),
                  blurRadius: 24,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: items.map((item) {
                final isSelected = widget.selectedIndex == item.index;
                return GestureDetector(
                  onTap: () => _handleTap(item.index),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                    child: isSelected
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 8),
                                decoration: BoxDecoration(
                                  color: skin.isLight
                                      ? Colors.white.withValues(alpha: 0.75)
                                      : Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: skin.isLight
                                        ? Colors.white.withValues(alpha: 0.85)
                                        : Colors.white.withValues(alpha: 0.18),
                                    width: 0.8,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                          alpha: skin.isLight ? 0.04 : 0.20),
                                      blurRadius: 6,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  item.activeIcon,
                                  color: skin.primary,
                                  size: 24,
                                ),
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Icon(
                              item.icon,
                              color: skin.surface(0.35),
                              size: 21,
                            ),
                          ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );

    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        HorizontalDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(),
          (instance) {
            instance
              ..onStart = (details) {
                  _isDraggingNav = true;
                  _dragStartX = details.localPosition.dx;
                  _dragStartIndex = widget.selectedIndex;
                }
              ..onUpdate = (details) {
                  if (!_isDraggingNav) return;
                  final delta = details.localPosition.dx - _dragStartX;
                  final itemCount = widget.dienstplanEnabled ? 5 : 4;
                  final steps = (delta / _scrubItemWidth).round();
                  final newIndex =
                      (_dragStartIndex + steps).clamp(0, itemCount - 1);
                  if (newIndex != widget.selectedIndex) {
                    HapticFeedback.selectionClick();
                    _stretchDirection =
                        newIndex > widget.selectedIndex ? 1.0 : -1.0;
                    _lastIndex = newIndex;
                    _bounceCtrl.forward(from: 0);
                    widget.onTap(newIndex);
                  }
                }
              ..onEnd = (details) {
                  _isDraggingNav = false;
                };
          },
        ),
      },
      child: navContent,
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