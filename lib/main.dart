import 'dart:ui';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:workmanager/workmanager.dart'; // NEU
import 'services/travel_mode_service.dart';
import 'services/apple_calendar_sync_service.dart';
import 'widgets/glass_dialogs.dart';
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
import 'services/pdf_service.dart';
import 'screens/dictation_help_screen.dart';
import 'screens/bva_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/glass_kit.dart';
import 'widgets/glass_snackbar.dart';
import 'widgets/glass_dialogs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'dart:convert';
import 'utils/cleanup.dart';
import 'package:intl/intl.dart';
import 'screens/tasks_screen.dart';
import 'services/notification_service.dart';
import 'services/auth_service.dart';
import 'services/rule_engine.dart';
import 'services/sync_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/notification_center.dart';
import 'models/calendar_event.dart'; // NEU

// ─────────────────────────────────────────────────────────────────────────────
// TAB-DEFINITION — steuert Reihenfolge & Sichtbarkeit der Haupt-Tabs.
// Im Lesemodus fallen Monat & Fahrtenbuch weg, alle Indizes werden daraus
// dynamisch berechnet statt hartcodiert zu sein.
// ─────────────────────────────────────────────────────────────────────────────

enum _Tab { home, month, schedule, fahrtenbuch, tasks }

List<_Tab> _computeActiveTabs({required bool readOnly}) => [
      _Tab.home,
      if (!readOnly) _Tab.month,
      _Tab.schedule,
      if (!readOnly) _Tab.fahrtenbuch,
      _Tab.tasks,
    ];

// ─────────────────────────────────────────────────────────────────────────
// HINTERGRUND-SYNC (Apple Kalender → Firestore) — NEU
//
// Läuft in einem EIGENEN, komplett neuen Isolate, den iOS irgendwann nach
// eigenem Ermessen startet (BGAppRefreshTask via workmanager-Plugin). Alle
// Anthropic-typischen Annahmen ("App läuft schon") gelten hier NICHT — der
// Isolate hat keinerlei Zustand aus main(), deshalb wird hier die komplette
// Mindest-Init-Kette nochmal durchlaufen, exakt wie beim normalen App-Start,
// nur ohne UI-bezogene Teile (RuleEngine/NotificationService nicht nötig).
// ─────────────────────────────────────────────────────────────────────────

const String kAppleCalendarBgTaskName = 'appleCalendarSync';
const String kAppleCalendarBgTaskId = 'de.marcel.optimes.appleCalendarSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🕐 BG-Task gestartet: $task');
    try {
      WidgetsFlutterBinding.ensureInitialized();

      await Hive.initFlutter();
      if (!Hive.isBoxOpen('arbeitszeiten')) await Hive.openBox('arbeitszeiten');
      if (!Hive.isBoxOpen('einstellungen')) await Hive.openBox('einstellungen');
      tzdata.initializeTimeZones();

      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );

      await AuthService.instance.init();
      // WICHTIG: SyncService._token ist privat und wird ausschließlich in
      // _startSync() gesetzt, das nur über init()/onTokenSet() erreichbar
      // ist. Ohne diesen Aufruf würde AppleCalendarSyncService.pullAllLinkedGroups()
      // zwar lokal pullen, aber der neue pushCalendarEvent()-Aufruf danach
      // würde wegen "if (_token == null) return;" stillschweigend nichts tun.
      await SyncService.instance.init();

      await AppleCalendarSyncService.instance.requestPermission();
      await AppleCalendarSyncService.instance.pullAllLinkedGroups();

      debugPrint('✅ BG-Task fertig: $task');
    } catch (e) {
      debugPrint('⚠️ BG-Task Fehler ($task): $e');
    }
    return Future.value(true);
  });
}

Future<void> _initializeAppServicesInBackground() async {
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    debugPrint('✅ Firebase + Firestore Offline-Cache initialisiert');
  } catch (e) {
    debugPrint('⚠️ Firebase init fehlgeschlagen (offline?): $e');
  }

  try {
    await AuthService.instance.init();
  } catch (e) {
    debugPrint('⚠️ AuthService init fehlgeschlagen: $e');
  }

  try {
    await SyncService.instance.init();
  } catch (e) {
    debugPrint('⚠️ SyncService init fehlgeschlagen: $e');
  }

  try {
    await RuleEngine.instance.init();
  } catch (e) {
    debugPrint('⚠️ RuleEngine init fehlgeschlagen: $e');
  }

  try {
    await NotificationService.instance.init();
  } catch (e) {
    debugPrint('⚠️ NotificationService init fehlgeschlagen: $e');
  }

  _migrateOldEntries();
  await runAutoCleanup();

  // NEU: Widgets direkt nach dem initialen Sync mit aktuellen Daten
  // befüllen, statt auf die erste manuelle Änderung zu warten.
  try {
    await ScheduleScreenState.pushScheduleToWidget();
  } catch (e) {
    debugPrint('⚠️ Initial Schedule-Widget-Push fehlgeschlagen: $e');
  }
  try {
    await CalendarEventStore.pushUpcomingEventsToWidget();
  } catch (e) {
    debugPrint('⚠️ Initial Kalender-Widget-Push fehlgeschlagen: $e');
  }
}

void main() async {
  WidgetsBinding binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: binding);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();
  await Hive.openBox('arbeitszeiten');
  await Hive.openBox('einstellungen');

  await initializeDateFormatting('de', null);

  tzdata.initializeTimeZones();

  // NEU: Hintergrund-Sync registrieren — läuft nach iOS' eigenem Zeitplan
  // (keine Garantie, aber i.d.R. mehrmals täglich bei normaler Nutzung).
  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    await Workmanager().registerPeriodicTask(
      kAppleCalendarBgTaskId,
      kAppleCalendarBgTaskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } catch (e) {
    debugPrint('⚠️ Workmanager-Registrierung fehlgeschlagen: $e');
  }

  try {
    FlutterNativeSplash.remove();
  } catch (_) {
    // Web kann den Splash-Remove-Channel nicht sofort bereitstellen.
  }

  runApp(const MyApp());
  unawaited(_initializeAppServicesInBackground());
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
  static final navigatorKey = GlobalKey<NavigatorState>();

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
            navigatorKey: MyApp.navigatorKey,
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
                  MyApp.mainScreenKey.currentState?.goToScheduleTab();
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
            home: MainScreen(key: MyApp.mainScreenKey),
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

class _MainScreenState extends State<MainScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
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
  Timer? _cleanupTimer;
  final _homeKey = GlobalKey<HomeScreenState>();
  final _scheduleKey = GlobalKey<ScheduleScreenState>();
  final _monthKey = GlobalKey<MonthScreenState>();
  final _fahrtenbuchKey = GlobalKey<FahrtenbuchScreenState>();
  final _tasksKey = GlobalKey<TasksScreenState>();
  final _bellKey = GlobalKey<NotificationBellButtonState>();
  final ValueNotifier<bool> _dayCardDragging = ValueNotifier(false);
  final ValueNotifier<bool> _homeOverlayActive = ValueNotifier(false);
  final ValueNotifier<bool> _navCompact = ValueNotifier(false);
  final ValueNotifier<bool> _scheduleForeignView = ValueNotifier(false);
  // NEU: true, während der Tasks-Tab die Kalender-Jahresübersicht zeigt —
  // steuert das Ausblenden der Bottom-Navbar.
  final ValueNotifier<bool> _tasksShowingYear = ValueNotifier(false);
  static const _navChannel = MethodChannel('de.marcel.optimes/navigation');

  // ── NEU: View-Mode für Tasks-Tab (Liste ⇄ Kalender) ──
  final ValueNotifier<bool> _tasksCalendarMode = ValueNotifier(false);
  late AnimationController _calToggleCtrl; // für die Icon-Morph-Animation

  // ── Lesemodus ────────────────────────────────────────────────────────────
  bool get _readOnlyMode =>
      Hive.box('einstellungen').get('read_only_mode', defaultValue: false) as bool;

  List<_Tab> get _activeTabs => _computeActiveTabs(readOnly: _readOnlyMode);
  int _indexOfTab(_Tab t) => _activeTabs.indexOf(t);

  int get _pageCount => _activeTabs.length;
  bool get _isOnSchedulePage => _currentPage == _indexOfTab(_Tab.schedule);
  bool get _isOnFahrtenbuchPage =>
      !_readOnlyMode && _currentPage == _indexOfTab(_Tab.fahrtenbuch);

  /// Öffentlicher Helfer, damit externe Aufrufer (z.B. Deep-Links in MyApp)
  /// nicht selbst mit Indizes hantieren müssen.
  void goToScheduleTab() => _goToPage(_indexOfTab(_Tab.schedule));
  void goToHomeTab() => _goToPage(0);

  // NEU: Nur im Lesemodus gibt es ein eigenes Kalender-Icon in der Navbar,
  // das nativ umschaltet, statt über den Umschalter oben rechts zu gehen
  // (der bleibt im Normalmodus unverändert). Beide Methoden zeigen auf
  // denselben physischen Tasks-Screen, schalten nur dessen internen Modus.
  void _selectTasksListView() {
    _goToPage(_indexOfTab(_Tab.tasks));
    _tasksCalendarMode.value = false;
    _tasksKey.currentState?.setCalendarMode(false);
  }

  void _selectCalendarView() {
    _goToPage(_indexOfTab(_Tab.tasks));
    _tasksCalendarMode.value = true;
    _tasksKey.currentState?.setCalendarMode(true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTravelModeTz());

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

    // ── NEU: Calendar Toggle Animation Controller ──
    _calToggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
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
        if (path == 'kalender') {
          await _navigateToCalendarToday();
          return;
        }
        if (path == 'fahrtenbuch_neue_fahrt_scan') {
          if (_readOnlyMode) return;
          await _animateToPage(_indexOfTab(_Tab.fahrtenbuch));
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _fahrtenbuchKey.currentState?.triggerKmStartScan();
          return;
        }
        if (url.contains('/note/')) {
          final dateKey = url.split('/').last;
          await _navigateToScheduleNote(dateKey);
        } else if (path == 'dienstplan') {
          await _animateToPage(_indexOfTab(_Tab.schedule));
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowWelcomeDialog(context);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.requestPermissions();
    });

     // NEU: periodischer Cleanup-Check, damit erledigte Aufgaben auch
    // gelöscht werden, ohne dass die App komplett neu gestartet wird.
    _cleanupTimer = Timer.periodic(const Duration(hours: 1), (_) {
      runAutoCleanup();
    });

    // NEU: Periodischer Apple-Kalender-Abgleich alle 15 Minuten, damit
    // Änderungen aus Apple auch bei durchgehend geöffneter App zeitnah
    // ankommen, nicht nur beim Resume/Neustart.
    Timer.periodic(const Duration(minutes: 15), (_) {
      AppleCalendarSyncService.instance.pullAllLinkedGroups();
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

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) _scrollListenerActive = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkTravelModeTz();
      // NEU: Apple-Kalender bei jedem App-Wiedereinstieg neu abgleichen,
      // damit im Apple-Kalender erstellte/geänderte/gelöschte Termine
      // zeitnah in der App ankommen, nicht erst beim nächsten App-Start.
      AppleCalendarSyncService.instance.pullAllLinkedGroups();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _flushHiveBoxes();
    }
  }

  void _flushHiveBoxes() {
    if (Hive.isBoxOpen('arbeitszeiten')) {
      Hive.box('arbeitszeiten').flush();
    }
    if (Hive.isBoxOpen('einstellungen')) {
      Hive.box('einstellungen').flush();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cleanupTimer?.cancel();
    _intentSub?.cancel();
    _slideCtrl.dispose();
    _menuAnimController.dispose();
    _calToggleCtrl.dispose(); // NEU
    _tasksCalendarMode.dispose(); // NEU
    _dayCardDragging.dispose();
    _navCompact.dispose();
    _scheduleForeignView.dispose();
    _tasksShowingYear.dispose();
    super.dispose();
  }

  Future<void> _checkTravelModeTz() async {
    final detectedTz = await TravelModeService.checkForTimeZoneChange();
    if (detectedTz == null || !mounted) return;

    // Nur zeigen, wenn diese Zone nicht schon beim letzten Mal gemeldet wurde.
    if (!TravelModeService.shouldNotifyZoneChange(detectedTz)) return;
    await TravelModeService.markZoneChangeNotified(detectedTz);
    if (!mounted) return;

    final label = TravelModeService.offsetLabelFor(detectedTz);
    showGlassSnackBar(
      context,
      'Neue Zeitzone erkannt: $detectedTz${label.isNotEmpty ? ' ($label)' : ''}',
      type: GlassSnackBarType.info,
      duration: const Duration(seconds: 6),
      actionLabel: 'Übernehmen',
      onAction: () async {
        await TravelModeService.setActiveTz(detectedTz);
        _monthKey.currentState?.syncActiveTravelZone();
      },
    );
  }

  Future<void> _navigateToScheduleNote(String dateKey) async {
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _animateToPage(_indexOfTab(_Tab.schedule));
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    if (!_readOnlyMode) _scheduleKey.currentState?.openNoteOverlay(dateKey);
  }

  Future<void> _navigateToCalendarToday() async {
    _closeMenu();
    _homeKey.currentState?.closeOverlays();
    _scheduleKey.currentState?.closeOverlays();
    await Future.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await _animateToPage(_indexOfTab(_Tab.tasks));
    if (!mounted) return;
    // Kalenderansicht aktivieren — dieselbe Umschaltung wie beim
    // oberen Icon (Normalmodus) bzw. eigenen Navbar-Tab (Lesemodus).
    _tasksCalendarMode.value = true;
    _tasksKey.currentState?.setCalendarMode(true);
    // Kurze Wartezeit, bis CalendarView tatsächlich gebaut/gemounted ist,
    // bevor jumpToToday() darauf aufgerufen wird.
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    _tasksKey.currentState?.jumpCalendarToToday();
  }

  void _handleSharedPdfWithBytesAndName(String path, List<int> bytes, String fileName) async {
    if (_readOnlyMode) return; // Import im Lesemodus nicht erlaubt
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
    await _animateToPage(_indexOfTab(_Tab.schedule));
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin, preloadedBytes: bytes);
  }

  Future<bool?> _showImportConfirmDialog(String displayName, AppSkin skin) {
    return confirmActionDialog(
      context: context,
      skin: skin,
      title: 'Dienstplan importieren',
      message: 'Soll diese PDF als Dienstplan importiert werden?',
      icon: Icons.upload_file_outlined,
      confirmLabel: 'Importieren',
      extraContent: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: skin.surface(0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.glassBorder),
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
        ),
      ),
    );
  }

  void handleSharedPdf(String path) => _handleSharedPdfWithBytes(path, []);

  void _handleSharedPdf(String path) async {
    if (_readOnlyMode) return; // Import im Lesemodus nicht erlaubt
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
    await _animateToPage(_indexOfTab(_Tab.schedule));
    if (!mounted) return;
    _autoImportPdf(path, fileName, skin);
  }

  void _handleSharedPdfWithBytes(String path, List<int> bytes) async {
    if (_readOnlyMode) return; // Import im Lesemodus nicht erlaubt
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
    await _animateToPage(_indexOfTab(_Tab.schedule));
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
    showGlassSnackBar(
      context,
      snackText,
      type: wasOverwritten ? GlassSnackBarType.warning : GlassSnackBarType.success,
      duration: const Duration(seconds: 3),
    );
  }

  String _monthName(int m) {
    const names = ['', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];
    return names[m.clamp(1, 12)];
  }

  void _openUploadSheet(String path, String fileName, AppSkin skin, {List<int>? preloadedBytes, String? autoImportError}) {
    if (_readOnlyMode) return;
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
    _tasksKey.currentState?.closeOverlays();

    if (index == 0) _navCompact.value = false;

    final tabs = _activeTabs;
    if (index >= 0 && index < tabs.length && tabs[index] == _Tab.schedule) {
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
      final tabs = _activeTabs;
      if (index >= 0 && index < tabs.length) {
        switch (tabs[index]) {
          case _Tab.month:
            _monthKey.currentState?.scrollToTop();
            break;
          case _Tab.schedule:
            _scheduleKey.currentState?.scrollToTop();
            break;
          case _Tab.fahrtenbuch:
            _fahrtenbuchKey.currentState?.scrollToTop();
            break;
          case _Tab.tasks:
            if (_tasksCalendarMode.value) {
              _tasksCalendarMode.value = false;
              _tasksKey.currentState?.setCalendarMode(false);
            }
            _tasksKey.currentState?.scrollToTop();
            break;
          case _Tab.home:
            break;
        }
      }
      return;
    }

    // NEU: Wenn wir zum Schedule-Tab wechseln, Task-Marker aktualisieren
    final tabs = _activeTabs;
    if (index >= 0 && index < tabs.length && tabs[index] == _Tab.schedule) {
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
    _navCompact.value = false;

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
      _tasksKey.currentState?.closeOverlays();

      final tabs = _activeTabs;
      if (targetPage >= 0 && targetPage < tabs.length && tabs[targetPage] == _Tab.schedule) {
        _scheduleKey.currentState?.refreshTaskMarkers();
      }
    }

    if (targetPage == 0) _navCompact.value = false;

    setState(() => _currentPage = targetPage);
    _slideCtrl.animateTo(
      targetPage.toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _wrapWithScrollListener(Widget child) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _onScrollNotification(notification);
        return false;
      },
      child: child,
    );
  }

  List<Widget> _buildPages() {
    final readOnly = _readOnlyMode;
    return [
      HomeScreen(
        key: _homeKey,
        selectedDate: _sharedDate,
        onDateChanged: (d) => setState(() => _sharedDate = d),
        onNavigateToMonth: () {
          if (readOnly) return;
          _goToPage(_indexOfTab(_Tab.month));
        },
        onNavigateToFahrtenbuch: () {
          if (readOnly) return;
          _goToPage(_indexOfTab(_Tab.fahrtenbuch));
        },
        onNavigateToFahrtenbuchNeueFahrt: () async {
          if (readOnly) return;
          await _animateToPage(_indexOfTab(_Tab.fahrtenbuch));
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
          _fahrtenbuchKey.currentState?.triggerKmStartScan();
        },
        onNavigateToTasks: () => _goToPage(_indexOfTab(_Tab.tasks)),
        onNavigateToTasksQuickAdd: () => _tasksKey.currentState?.openQuickAdd(),
        onNavigateToTasksQuickAddEvent: () => _tasksKey.currentState?.openQuickAddEvent(),
        onNavigateToSchedule: () => _goToPage(_indexOfTab(_Tab.schedule)),
        onNavigateToScheduleAndImport: () async {
          if (readOnly) return;
          await _animateToPage(_indexOfTab(_Tab.schedule));
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
          _showUploadSheet(context, AppTheme.of(context));
        },
      ),
      if (!readOnly)
        _wrapWithScrollListener(MonthScreen(
          key: _monthKey,
          selectedMonth: _sharedMonth,
          onMonthChanged: (m) => setState(() => _sharedMonth = m),
          onNavigateToHome: () => _goToPage(0),
        )),
      _wrapWithScrollListener(ScheduleScreen(
        key: _scheduleKey,
        onNavigateToHome: () => _goToPage(0),
        onNavigateToMonth: () {
          if (readOnly) return;
          _goToPage(_indexOfTab(_Tab.month));
        },
        onMonthChanged: (m) => setState(() => _scheduleViewMonth = m),
        dayCardDragging: _dayCardDragging,
        onForeignViewChanged: (v) => _scheduleForeignView.value = v,
        readOnly: readOnly,
      )),
      if (!readOnly)
        _wrapWithScrollListener(FahrtenbuchScreen(
          key: _fahrtenbuchKey,
          onDraftChanged: () => setState(() {}),
        )),
      _wrapWithScrollListener(TasksScreen(
        key: _tasksKey,
        onCalendarShowingYearChanged: (v) => _tasksShowingYear.value = v,
      )),
    ];
  }

  void _toggleMenu() {
    if (!_menuOpen) {
      _bellKey.currentState?.closeOverlay();
    }
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

  bool _scrollListenerActive = false;

  void _onScrollNotification(ScrollNotification notification) {
    if (!_scrollListenerActive) return;
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 4 && !_navCompact.value) {
        _navCompact.value = true;
      } else if (delta < -4 && _navCompact.value) {
        _navCompact.value = false;
      }
    }
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
    final readOnly = _readOnlyMode;

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
                child: ValueListenableBuilder<bool>(
                  // NEU: in der Kalender-Jahresübersicht bleibt nur der
                  // "Heute"-Button (aus tasks_screen.dart) sichtbar —
                  // die Haupt-Navbar wird komplett ausgeblendet.
                  valueListenable: _tasksShowingYear,
                  builder: (context, showingYear, _) {
                    if (showingYear) return const SizedBox.shrink();
                    return Center(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _navCompact,
                        builder: (context, compact, _) => ValueListenableBuilder<bool>(
                          valueListenable: _tasksCalendarMode,
                          builder: (context, calendarActive, __) => _GlassBottomNav(
                            selectedIndex: _currentPage,
                            readOnlyMode: readOnly,
                            onTap: (index) {
                              // Tap expandiert die Navbar sofort wieder
                              _navCompact.value = false;
                              _selectTab(index);
                            },
                            compact: compact,
                            showCalendarSplit: readOnly,
                            calendarActive: calendarActive,
                            tasksTabIndex: _indexOfTab(_Tab.tasks),
                            onSelectTasksList: () {
                              _navCompact.value = false;
                              _selectTasksListView();
                            },
                            onSelectCalendar: () {
                              _navCompact.value = false;
                              _selectCalendarView();
                            },
                          ),
                        ),
                      ),
                    );
                  },
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
                                  if (_isOnFahrtenbuchPage && _currentPage != _indexOfTab(_Tab.tasks)) ...[
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
                                  if (_isOnSchedulePage && !_isOnFahrtenbuchPage && !readOnly) ...[
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
                                  if (_currentPage == _indexOfTab(_Tab.month)) ...[
                                    _DropdownItem(
                                      icon: Icons.picture_as_pdf_outlined,
                                      label: 'Zeiten exportieren',
                                      onTap: () {
                                        _closeMenu();
                                        PdfService.showMonthPickerAndExport(context);
                                      },
                                    ),
                                    _Divider(),
                                    _DropdownItem(
                                      icon: Icons.description_outlined,
                                      label: 'BVA-Dienstreise',
                                      onTap: () {
                                        _closeMenu();
                                        Navigator.push(
                                          context,
                                          CupertinoPageRoute(builder: (_) => const BvaScreen()),
                                        );
                                      },
                                    ),
                                    _Divider(),
                                  ],

                                  if (_currentPage == _indexOfTab(_Tab.tasks)) ...[
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
                    children: [
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
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
                            if (!readOnly && _currentPage == _indexOfTab(_Tab.tasks))
                              ValueListenableBuilder<bool>(
                                valueListenable: _tasksCalendarMode,
                                builder: (context, isCalendar, _) => GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    final newValue = !isCalendar;
                                    _tasksCalendarMode.value = newValue;
                                    _tasksKey.currentState?.setCalendarMode(newValue);
                                    _calToggleCtrl.forward(from: 0);
                                  },
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 280),
                                        transitionBuilder: (child, anim) => RotationTransition(
                                          turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                                          child: ScaleTransition(
                                            scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                                            child: FadeTransition(opacity: anim, child: child),
                                          ),
                                        ),
                                        child: Icon(
                                          isCalendar ? Icons.view_list_rounded : Icons.calendar_month_outlined,
                                          key: ValueKey(isCalendar),
                                          color: skin.textPrimary,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_currentPage == _indexOfTab(_Tab.tasks))
                              ValueListenableBuilder<bool>(
                                valueListenable: _tasksCalendarMode,
                                builder: (context, isCalendar, _) => GestureDetector(
                                  onTap: () => isCalendar
                                      ? _tasksKey.currentState?.openQuickAddEvent()
                                      : _tasksKey.currentState?.openQuickAdd(),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: Icon(
                                        Icons.add,
                                        color: skin.textPrimary,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            if (_isOnSchedulePage && !readOnly)
                              ValueListenableBuilder<bool>(
                                valueListenable: _scheduleForeignView,
                                builder: (context, isForeign, _) => GestureDetector(
                                  onTap: isForeign
                                      ? null
                                      : () => _scheduleKey.currentState?.openColleagueSearch(),
                                  child: SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(milliseconds: 200),
                                        child: isForeign
                                            ? Icon(
                                                Icons.person_rounded,
                                                key: const ValueKey('foreign'),
                                                color: skin.primary,
                                                size: 22,
                                              )
                                            : Icon(
                                                Icons.search_rounded,
                                                key: const ValueKey('search'),
                                                color: skin.textPrimary,
                                                size: 22,
                                              ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      NotificationBellButton(
                        key: _bellKey,
                        onBeforeOpen: _closeMenu,
                        onNavigateToTasksList: _selectTasksListView,
                        onNavigateToCalendar: _selectCalendarView,
                        onOpenSyncConflicts: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => const SyncConflictsScreen()),
                        ),
                        onOpenCalendarSyncSettings: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => const TasksDictationSettingsScreen()),
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
    if (_readOnlyMode) return;
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
      context: context,
      skin: skin,
      title: '$kennzeichen löschen?',
      message: 'Das Fahrzeug wird aus dem KM-Gedächtnis entfernt.',
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
        child: GlassSheet(
          skin: skin,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: SheetHandle(skin: skin)),
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
                GlassPrimaryButton(
                  skin: skin,
                  label: 'Übernehmen',
                  onTap: () {
                    final km = int.tryParse(ctrl.text);
                    if (km != null && km > 0) {
                      KmMemory.save(kz, km);
                      Navigator.pop(context);
                      _load();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      child: GlassSheet(
        skin: skin,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHandle(skin: skin),
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
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GlassSwipeCard(
                        height: 72,
                        cardKey: kz,
                        onTap: () => _editKm(e),
                        onDelete: () => _deleteEntry(kz),
                        animateDelete: false,
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
  final bool readOnlyMode;
  final Function(int) onTap;
  final bool compact;
  // NEU: Im Lesemodus wird das Aufgaben-Icon durch zwei eigenständige Icons
  // (Aufgaben / Kalender) ersetzt — beide zeigen auf denselben physischen
  // Tasks-Screen, schalten nur dessen internen Anzeigemodus um.
  final bool showCalendarSplit;
  final bool calendarActive;
  final int tasksTabIndex;
  final VoidCallback? onSelectTasksList;
  final VoidCallback? onSelectCalendar;

  const _GlassBottomNav({
    required this.selectedIndex,
    required this.readOnlyMode,
    required this.onTap,
    this.compact = false,
    this.showCalendarSplit = false,
    this.calendarActive = false,
    this.tasksTabIndex = -1,
    this.onSelectTasksList,
    this.onSelectCalendar,
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

  // NEU: ausgelagertes Icon-Rendering (Pill bei Auswahl, sonst schlicht),
  // damit sowohl normale Tab-Icons als auch die im Lesemodus aufgeteilten
  // Aufgaben-/Kalender-Icons dieselbe Optik nutzen.
  Widget _navIconWidget({
    required AppSkin skin,
    required IconData icon,
    required IconData activeIcon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
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
                          color: Colors.black.withValues(alpha: skin.isLight ? 0.04 : 0.20),
                          blurRadius: 6,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Icon(activeIcon, color: skin.primary, size: 24),
                  ),
                ),
              )
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Icon(icon, color: skin.surface(0.35), size: 21),
              ),
      ),
    );
  }

  _NavItem _navItemFor(_Tab tab, int index) {
    switch (tab) {
      case _Tab.home:
        return _NavItem(Icons.home_outlined, Icons.home_filled, 'Zeiterfassung', index);
      case _Tab.month:
        return _NavItem(Icons.access_time_outlined, Icons.access_time_filled, 'Monatsübersicht', index);
      case _Tab.schedule:
        return _NavItem(Icons.event_note_outlined, Icons.event_note, 'Dienstplan', index);
      case _Tab.fahrtenbuch:
        return _NavItem(Icons.directions_car_outlined, Icons.directions_car, 'Fahrtenbuch', index);
      case _Tab.tasks:
        return _NavItem(Icons.check_rounded, Icons.check_rounded, 'Aufgaben', index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    final tabs = _computeActiveTabs(readOnly: widget.readOnlyMode);
    final items = [for (int i = 0; i < tabs.length; i++) _navItemFor(tabs[i], i)];

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
              children: () {
                // NEU: Im Lesemodus wird der Aufgaben-Eintrag durch zwei
                // eigenständige Icons ersetzt (Aufgaben / Kalender) — beide
                // zeigen auf denselben physischen Tasks-Screen und schalten
                // nur dessen internen Anzeigemodus um.
                final children = <Widget>[];
                for (final item in items) {
                  if (widget.showCalendarSplit && item.index == widget.tasksTabIndex) {
                    final onTasksPage = widget.selectedIndex == widget.tasksTabIndex;
                    children.add(_navIconWidget(
                      skin: skin,
                      icon: Icons.check_rounded,
                      activeIcon: Icons.check_rounded,
                      isSelected: onTasksPage && !widget.calendarActive,
                      onTap: () => widget.onSelectTasksList?.call(),
                    ));
                    children.add(_navIconWidget(
                      skin: skin,
                      icon: Icons.calendar_month_outlined,
                      activeIcon: Icons.calendar_month_rounded,
                      isSelected: onTasksPage && widget.calendarActive,
                      onTap: () => widget.onSelectCalendar?.call(),
                    ));
                  } else {
                    children.add(_navIconWidget(
                      skin: skin,
                      icon: item.icon,
                      activeIcon: item.activeIcon,
                      isSelected: widget.selectedIndex == item.index,
                      onTap: () => _handleTap(item.index),
                    ));
                  }
                }
                return children;
              }(),
            ),
          ),
        ),
      ),
    );

    return AnimatedScale(
      scale: widget.compact ? 0.82 : 1.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.bottomCenter,
      child: AnimatedOpacity(
        opacity: widget.compact ? 0.72 : 1.0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        child: RawGestureDetector(
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
                    final itemCount = tabs.length;
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
        ),
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