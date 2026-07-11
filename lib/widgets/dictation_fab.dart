import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../theme/app_theme.dart';
import '../services/spoken_task_parser.dart';
import '../services/speech_normalizer.dart';
import '../services/speech_log.dart';
import '../services/rule_engine.dart';
import '../services/speech_service.dart';
import 'glass_snackbar.dart';
import '../main.dart' show MyApp;

// ─────────────────────────────────────────────────────────────────────────────
// TOP-LEVEL KONSTANTEN — für alle Klassen im File
// ─────────────────────────────────────────────────────────────────────────────

const _kRadius20 = BorderRadius.all(Radius.circular(20));
final _kBlur20 = ImageFilter.blur(sigmaX: 20, sigmaY: 20);
final _kBlur22 = ImageFilter.blur(sigmaX: 22, sigmaY: 22);

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION FAB — wiederverwendbarer Diktier-Button mit Live-Bubble
// ─────────────────────────────────────────────────────────────────────────────

enum DictationPhase { idle, preparing, listening, processing, revealing, done }

class DictationFab extends StatefulWidget {
  final AppSkin skin;
  final void Function(ParsedSpokenTask parsed, String logRef) onResult;
  final void Function(ParsedSpokenTask parsed, String logRef) onNeedsReview;
  final VoidCallback? onListeningStart;
  final VoidCallback? onListeningEnd;

  /// Blendet den FAB-Button aus, aber lässt die Bubbles sichtbar
  final bool hideButton;

  /// Wenn gesetzt, rendert DictationFab KEINE eigenen Bubbles intern.
  /// Stattdessen ruft er [onBubbleStateChanged] auf, damit der Aufrufer
  /// die Bubbles selbst per [buildExternalBubbles] positionieren kann.
  final bool useExternalBubbles;
  final VoidCallback? onBubbleStateChanged;

  const DictationFab({
    super.key,
    required this.skin,
    required this.onResult,
    required this.onNeedsReview,
    this.onListeningStart,
    this.onListeningEnd,
    this.hideButton = false,
    this.useExternalBubbles = false,
    this.onBubbleStateChanged,
  });

  @override
  State<DictationFab> createState() => DictationFabState();
}

class DictationFabState extends State<DictationFab>
    with TickerProviderStateMixin {
  stt.SpeechToText get _speech => SpeechService.instance.speech;
  bool get _speechAvailable => SpeechService.instance.isAvailable;

  DictationPhase _phase = DictationPhase.idle;
  bool _isFinishing = false; // Guard gegen doppelten Aufruf von _finishListeningAndReveal
  String _liveTranscript = '';
  String _finalTranscript = '';
  List<String> _revealedWords = [];
  int _revealIndex = 0;
  Timer? _revealTimer;

  final ValueNotifier<double> rawLevelNotifier = ValueNotifier(0.0);

  bool _aborted = false;
  bool _isCancelling = false;
  double _cancelDragX = 0.0;
  DateTime? _listenStartedAt;

  late AnimationController _fabPulseCtrl;
  late AnimationController _idlePulseCtrl;
  late AnimationController _bubbleCtrl;
  late Animation<double> _bubbleScale;
  late Animation<double> _bubbleOpacity;

  late AnimationController _cancelAnimCtrl;
  late Animation<double> _spectrumShrink;
  late Animation<double> _spectrumFade;
  late Animation<double> _trashPulse;
  late Animation<double> _exitFade;

  // ── Public getters für externen Bubble-Aufbau ──────────────────────────────
  DictationPhase get phase => _phase;
  bool get isCancelling => _isCancelling;
  double get cancelDragX => _cancelDragX;
  double get cancelProgress => (_cancelDragX.abs() / 80.0).clamp(0.0, 1.0);
  List<String> get revealedWords => _revealedWords;
  int get revealIndex => _revealIndex;
  Animation<double> get bubbleScale => _bubbleScale;
  Animation<double> get bubbleOpacity => _bubbleOpacity;
  AnimationController get bubbleCtrl => _bubbleCtrl;
  AnimationController get cancelAnimCtrl => _cancelAnimCtrl;
  Animation<double> get spectrumShrink => _spectrumShrink;
  Animation<double> get spectrumFade => _spectrumFade;
  Animation<double> get trashPulse => _trashPulse;
  Animation<double> get exitFade => _exitFade;
  AnimationController get fabPulseCtrl => _fabPulseCtrl;
  DateTime? get listenStartedAt => _listenStartedAt;

  @override
  void initState() {
    super.initState();
    _fabPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _idlePulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _bubbleCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    _bubbleScale = CurvedAnimation(
        parent: _bubbleCtrl,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInBack);
    _bubbleOpacity = CurvedAnimation(
        parent: _bubbleCtrl,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn);

    _cancelAnimCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 480));
    _spectrumShrink = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _cancelAnimCtrl,
            curve: const Interval(0.0, 0.55, curve: Curves.easeInCubic)));
    _spectrumFade = Tween<double>(begin: 1.0, end: 0.0).animate(
        CurvedAnimation(
            parent: _cancelAnimCtrl,
            curve: const Interval(0.25, 0.55, curve: Curves.easeIn)));
    _trashPulse = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.35), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.35, end: 0.0), weight: 60),
    ]).animate(CurvedAnimation(
        parent: _cancelAnimCtrl,
        curve: const Interval(0.30, 0.80, curve: Curves.easeInOut)));
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
        parent: _cancelAnimCtrl,
        curve: const Interval(0.60, 1.0, curve: Curves.easeOut)));

    _cancelAnimCtrl.addListener(() {
      if (mounted) {
        widget.onBubbleStateChanged?.call();
      }
    });

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    await SpeechService.instance.ensureInitialized(
      onStatus: _onSpeechStatus,
      onError: (err) {
        if (_aborted) return;
        if (mounted) {
          setState(() => _phase = DictationPhase.idle);
          _bubbleCtrl.reverse();
          widget.onListeningEnd?.call();
          widget.onBubbleStateChanged?.call();
        }
      },
    );
    if (mounted) setState(() {});
  }

  void _onSpeechStatus(String status) {
    if (_aborted) return;
    if (status == 'done' || status == 'notListening') {
      if (_phase == DictationPhase.listening) {
        _finishListeningAndReveal();
      }
    }
  }

  void startListening() => _startListening();

  void stopListening() {
    if (_phase != DictationPhase.listening &&
        _phase != DictationPhase.preparing) return;
    if (_aborted) return;
    _aborted = true;
    try {
      _speech.stop();
    } catch (_) {}
    if (mounted) {
      _fabPulseCtrl.stop();
      _cancelAnimCtrl.reset();
      _bubbleCtrl.reset();
      setState(() {
        _phase = DictationPhase.idle;
        _liveTranscript = '';
        _finalTranscript = '';
        _revealedWords = [];
        _revealIndex = 0;
        rawLevelNotifier.value = 0.0;
        _cancelDragX = 0.0;
        _isCancelling = false;
        _aborted = false;
        _isFinishing = false; // NEU
      });
      widget.onListeningEnd?.call();
      widget.onBubbleStateChanged?.call();
    }
  }

  void finishListening() {
    if (_phase == DictationPhase.preparing) {
      // Zu kurz gehalten, noch keine echte Aufnahme — sauber abbrechen
      stopListening();
      return;
    }
    if (_phase != DictationPhase.listening) return;
    _finishListeningAndReveal();
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _fabPulseCtrl.dispose();
    _idlePulseCtrl.dispose();
    _bubbleCtrl.dispose();
    _cancelAnimCtrl.dispose();
    rawLevelNotifier.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      // Nochmal versuchen — vielleicht war initialize() noch nicht fertig
      await _initSpeech();
      if (!_speechAvailable) {
        HapticFeedback.heavyImpact();
        final overlayContext = MyApp.navigatorKey.currentContext;
        if (overlayContext != null && mounted) {
          showGlassSnackBar(
            overlayContext,
            'Mikrofon nicht verfügbar — Berechtigung prüfen',
            type: GlassSnackBarType.error,
            duration: const Duration(seconds: 3),
          );
        }
        return;
      }
    }

    HapticFeedback.mediumImpact();
    _aborted = false;
    _isCancelling = false;
    _isFinishing = false; // NEU
    _cancelDragX = 0.0;
    _listenStartedAt = DateTime.now();
    setState(() {
      _phase = DictationPhase.preparing;
      _liveTranscript = '';
      _finalTranscript = '';
      rawLevelNotifier.value = 0.0;
      _revealedWords = [];
      _revealIndex = 0;
    });
    widget.onListeningStart?.call();
    widget.onBubbleStateChanged?.call();
    _cancelAnimCtrl.reset();
    _bubbleCtrl.forward();

    Future.delayed(const Duration(milliseconds: 450), () {
      if (_aborted || !mounted) return;
      if (_phase == DictationPhase.preparing) {
        setState(() => _phase = DictationPhase.listening);
        _fabPulseCtrl.repeat(reverse: true);
        widget.onBubbleStateChanged?.call();
      }
    });

    await _speech.listen(
      localeId: 'de_DE',
      onResult: (result) {
        if (_aborted || !mounted) return;
        setState(() {
          _liveTranscript = result.recognizedWords;
          if (result.finalResult) _finalTranscript = result.recognizedWords;
        });
        widget.onBubbleStateChanged?.call();
      },
      onSoundLevelChange: (level) {
        if (_aborted || !mounted) return;
        rawLevelNotifier.value = level;
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  Future<void> _finishListeningAndReveal() async {
    if (_aborted || _isFinishing) return;
    if (_phase != DictationPhase.listening) return;
    _isFinishing = true;
    await _speech.stop();
    if (_aborted) {
      _isFinishing = false;
      return;
    }
    setState(() => _cancelDragX = 0.0);
    widget.onBubbleStateChanged?.call();

    final text =
        (_finalTranscript.isNotEmpty ? _finalTranscript : _liveTranscript)
            .trim();
    if (text.isEmpty) {
      setState(() => _phase = DictationPhase.idle);
      _bubbleCtrl.reverse();
      widget.onListeningEnd?.call();
      widget.onBubbleStateChanged?.call();
      return;
    }

    _fabPulseCtrl.stop();
    setState(() => _phase = DictationPhase.processing);
    widget.onBubbleStateChanged?.call();
    await Future.delayed(const Duration(milliseconds: 350));
    if (_aborted || !mounted) return;

    final words =
        text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _phase = DictationPhase.revealing;
      _revealedWords = words;
      _revealIndex = 0;
    });
    widget.onBubbleStateChanged?.call();

    _revealTimer?.cancel();
    _revealTimer =
        Timer.periodic(const Duration(milliseconds: 90), (timer) {
      if (_aborted || !mounted) {
        timer.cancel();
        return;
      }
      setState(() => _revealIndex++);
      widget.onBubbleStateChanged?.call();
      if (_revealIndex >= _revealedWords.length) {
        timer.cancel();
        _onRevealComplete(text);
      }
    });
  }

  Future<void> _cancelListening() async {
    if (_isCancelling) return;
    if (_phase != DictationPhase.listening &&
        _phase != DictationPhase.preparing) return;
    _aborted = true;
    _isCancelling = true;
    HapticFeedback.heavyImpact();

    _revealTimer?.cancel();
    try {
      await _speech.cancel();
    } catch (_) {}

    if (!mounted) return;
    await _cancelAnimCtrl.forward();

    if (!mounted) return;
    _fabPulseCtrl.stop();
    _cancelAnimCtrl.reset();
    _bubbleCtrl.reset();
    setState(() {
      _phase = DictationPhase.idle;
      _liveTranscript = '';
      _finalTranscript = '';
      _revealedWords = [];
      _revealIndex = 0;
      rawLevelNotifier.value = 0.0;
      _cancelDragX = 0.0;
      _isCancelling = false;
      _aborted = false;
      _isFinishing = false; // NEU
    });
    widget.onListeningEnd?.call();
    widget.onBubbleStateChanged?.call();
  }

  void _onRevealComplete(String text) {
    if (_aborted) return;
    setState(() => _phase = DictationPhase.done);
    widget.onBubbleStateChanged?.call();

    final ruleMatch = RuleEngine.instance.match(text);
    if (ruleMatch != null) {
      final logRef = SpeechLog.record(
        raw: text,
        normalized: text,
        parsedTitle: ruleMatch.title,
        hasDate: ruleMatch.date != null,
      );
      Future.delayed(const Duration(milliseconds: 900), () {
        if (_aborted || !mounted) return;
        widget.onResult(ruleMatch, logRef);
        _bubbleCtrl.reverse().then((_) {
          if (!_aborted && mounted) {
            setState(() {
              _phase = DictationPhase.idle;
              _liveTranscript = '';
              _finalTranscript = '';
              _revealedWords = [];
              _revealIndex = 0;
            });
          }
          widget.onListeningEnd?.call();
          widget.onBubbleStateChanged?.call();
        });
      });
      return;
    }

    final normalized = SpeechNormalizer.normalize(text);
    final parsed = SpokenTaskParser.parse(normalized);

    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final normalizerMissed = normalized == text;
    final hasNoDateTime = parsed.date == null && !parsed.hasTime;
    final titleTooShort = parsed.title.trim().length < 3;

    final needsReview = titleTooShort ||
        (normalizerMissed && wordCount > 4);

    final logRef = SpeechLog.record(
      raw: text,
      normalized: normalized,
      parsedTitle: parsed.title,
      hasDate: parsed.date != null,
      wentToReview: needsReview,
    );

    Future.delayed(const Duration(milliseconds: 900), () {
      if (_aborted || !mounted) return;
      if (needsReview) {
        widget.onNeedsReview(parsed, logRef);
      } else {
        widget.onResult(parsed, logRef);
      }
      _bubbleCtrl.reverse().then((_) {
        if (!_aborted && mounted) {
          setState(() {
            _phase = DictationPhase.idle;
            _liveTranscript = '';
            _finalTranscript = '';
            _revealedWords = [];
            _revealIndex = 0;
          });
        }
        widget.onListeningEnd?.call();
        widget.onBubbleStateChanged?.call();
      });
    });
  }

  bool get _isActive => _phase != DictationPhase.idle;

  // ── Externe Bubbles bauen ──────────────────────────────────────────────────
  /// Gibt die Bubble-Widgets zurück, die der Aufrufer selbst positionieren kann.
  /// [anchorBottomRight] = die Pixel-Position der unteren rechten Ecke des Anchors
  /// (z.B. der Kachel), in globalen Screen-Koordinaten.
  List<Widget> buildExternalBubbles({
    required AppSkin skin,
    required Offset anchorTopRight,   // obere rechte Ecke der Kachel
    required double kachelWidth,
    double kachelHeight = 100.0,
  }) {
    final showBubbles =
        (_isActive && !_isCancelling) || _cancelAnimCtrl.value > 0;

    final widgets = <Widget>[];

    // ── Spektrum-Bubble (während Listening) ───────────────────────────────
    if (showBubbles &&
        (_phase == DictationPhase.listening ||
            _phase == DictationPhase.preparing)) {
      widgets.add(
        _ExternalSpectrumBubble(
          skin: skin,
          fabState: this,
          anchorTopRight: anchorTopRight,
          kachelWidth: kachelWidth,
        ),
      );
    }

    // ── Trash-Button (links, erscheint beim Drag) ─────────────────────────
    if (_isActive || _cancelAnimCtrl.value > 0) {
      widgets.add(
        _ExternalTrashButton(
          skin: skin,
          fabState: this,
          anchorTopRight: anchorTopRight,
          kachelWidth: kachelWidth,
          kachelHeight: kachelHeight,
        ),
      );
    }

    // ── Reveal / Processing Bubble ────────────────────────────────────────
    if (_phase == DictationPhase.revealing ||
        _phase == DictationPhase.done ||
        _phase == DictationPhase.processing) {
      widgets.add(
        _ExternalRevealBubble(
          skin: skin,
          fabState: this,
          anchorTopRight: anchorTopRight,
          kachelWidth: kachelWidth,
        ),
      );
    }

    return widgets;
  }

  // ── Drag-Handling für externen Einsatz ────────────────────────────────────
  void onExternalDragUpdate(double dx) {
    if ((_phase != DictationPhase.listening &&
            _phase != DictationPhase.preparing) ||
        _isCancelling) return;
    final newVal = (dx < 0 ? dx : 0.0);
    setState(() => _cancelDragX = newVal);
    widget.onBubbleStateChanged?.call();
    if (newVal < -80.0) _cancelListening();
  }

  void onExternalDragEnd() {
    if (_cancelDragX > -80.0) {
      setState(() => _cancelDragX = 0.0);
      widget.onBubbleStateChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Im External-Bubble-Modus nur den FAB selbst rendern (oder nichts)
    if (widget.useExternalBubbles) {
      if (widget.hideButton) return const SizedBox.shrink();
      return _buildFabButton(widget.skin);
    }

    // ── Original-Verhalten: Bubbles intern im Stack ───────────────────────
    final skin = widget.skin;
    final bool showBubbles =
        _isActive && !_isCancelling || _cancelAnimCtrl.value > 0;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        if (showBubbles &&
            (_phase == DictationPhase.listening ||
                _phase == DictationPhase.preparing))
          Positioned(
            bottom: 68,
            right: 0,
            child: AnimatedBuilder(
              animation:
                  Listenable.merge([_bubbleCtrl, _cancelAnimCtrl]),
              builder: (context, child) {
                final exitOpacity = _exitFade.value;
                final bubbleOp =
                    (_bubbleOpacity.value * exitOpacity).clamp(0.0, 1.0);
                final dragProgress = cancelProgress;
                final slideX = -dragProgress * 40.0;
                final shrink =
                    _spectrumShrink.value * (1.0 - dragProgress * 0.2);
                final fadeOp =
                    _spectrumFade.value * (1.0 - dragProgress * 0.3);

                return Transform.translate(
                  offset: Offset(slideX, 0),
                  child: Transform.scale(
                    scale: (0.85 + _bubbleScale.value * 0.15) * shrink,
                    alignment: Alignment.bottomRight,
                    child: Opacity(
                      opacity: (bubbleOp * fadeOp).clamp(0.0, 1.0),
                      child: child,
                    ),
                  ),
                );
              },
              child: _buildSpectrumBubble(skin),
            ),
          ),

        if (_isActive || _cancelAnimCtrl.value > 0)
          Positioned(
            bottom: 0,
            right: 68,
            child: _buildTrashButton(skin),
          ),

        if (_phase == DictationPhase.revealing ||
            _phase == DictationPhase.done ||
            _phase == DictationPhase.processing)
          Positioned(
            bottom: 68,
            right: 0,
            child: AnimatedBuilder(
              animation: _bubbleCtrl,
              builder: (context, child) {
                return Transform.scale(
                  alignment: Alignment.bottomRight,
                  scale: 0.85 + _bubbleScale.value * 0.15,
                  child: Opacity(
                    opacity: _bubbleOpacity.value.clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: _buildRevealBubble(skin),
            ),
          ),

        if (!widget.hideButton) _buildFabButton(skin),
      ],
    );
  }

  // ── FAB Button Widget ──────────────────────────────────────────────────────
  Widget _buildFabButton(AppSkin skin) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) => _startListening(),
      onLongPressEnd: (_) {
        if (!_isCancelling) _finishListeningAndReveal();
      },
      onLongPressCancel: () {
        if (!_isCancelling) _finishListeningAndReveal();
      },
      onLongPressMoveUpdate: (details) {
        if ((_phase != DictationPhase.listening &&
                _phase != DictationPhase.preparing) ||
            _isCancelling) return;
        final dx = details.offsetFromOrigin.dx;
        setState(() => _cancelDragX = dx < 0 ? dx : 0.0);
        if (dx < -80.0) _cancelListening();
      },
      child: AnimatedBuilder(
        animation: Listenable.merge([_fabPulseCtrl, _cancelAnimCtrl]),
        builder: (context, _) {
          final pulse =
              _phase == DictationPhase.listening ? _fabPulseCtrl.value : 0.0;
          final cp = cancelProgress;
          final fabColor = _isActive
              ? Color.lerp(
                  skin.primary.withValues(alpha: 0.85 + pulse * 0.15),
                  const Color(0xFFEF5B5B).withValues(alpha: 0.9),
                  cp,
                )!
              : (skin.isLight
                  ? Colors.white.withValues(alpha: 0.72)
                  : Colors.black.withValues(alpha: 0.55));

          final fabContent = Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: fabColor,
              borderRadius: _kRadius20,
              border: Border.all(
                color: _isActive
                    ? Colors.white.withValues(alpha: 0.35)
                    : (skin.isLight
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.white.withValues(alpha: 0.12)),
                width: _isActive ? 1.2 : 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: _isActive
                      ? Color.lerp(
                          skin.primaryWithAlpha(0.45 + pulse * 0.2),
                          const Color(0xFFEF5B5B)
                              .withValues(alpha: 0.5),
                          cp,
                        )!
                      : Colors.black.withValues(
                          alpha: skin.isLight ? 0.08 : 0.35),
                  blurRadius: _isActive ? 20 + pulse * 10 : 24,
                  spreadRadius: _isActive ? pulse * 2 : 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                cp > 0.35
                    ? Icons.close_rounded
                    : (_isActive
                        ? Icons.mic_rounded
                        : Icons.mic_none_rounded),
                key: ValueKey(cp > 0.35
                    ? 'cancel'
                    : (_isActive ? 'active' : 'idle')),
                color: cp > 0.35
                    ? Colors.white
                    : (_isActive ? skin.onGradient : skin.textPrimary),
                size: 24,
              ),
            ),
          );

          return Opacity(
            opacity: _exitFade.value,
            child: ClipRRect(
              borderRadius: _kRadius20,
              child: _isActive
                  ? BackdropFilter(
                      filter: _kBlur20,
                      child: fabContent,
                    )
                  : fabContent,
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpectrumBubble(AppSkin skin) {
    return ClipRRect(
      borderRadius: _kRadius20,
      child: BackdropFilter(
        filter: _kBlur22,
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: skin.isLight
                ? Colors.white.withValues(alpha: 0.85)
                : skin.bgCard.withValues(alpha: 0.85),
            borderRadius: _kRadius20,
            border: Border.all(
                color: skin.primary.withValues(alpha: 0.30), width: 1.0),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.20),
                  blurRadius: 24,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: _phase == DictationPhase.preparing
              ? PreparingDots(skin: skin)
              : SpectrumIndicator(
                  skin: skin,
                  rawLevelNotifier: rawLevelNotifier,
                  listenStartedAt: _listenStartedAt,
                ),
        ),
      ),
    );
  }

  Widget _buildTrashButton(AppSkin skin) {
    return AnimatedBuilder(
      animation: _cancelAnimCtrl,
      builder: (context, _) {
        final dragProgress = cancelProgress;
        final trashScale = _isCancelling
            ? _trashPulse.value
            : (0.75 + dragProgress * 0.25);
        final trashOpacity = _isCancelling
            ? _trashPulse.value.clamp(0.0, 1.0)
            : (0.28 + dragProgress * 0.72).clamp(0.0, 1.0);
        final exitOp = _exitFade.value;

        return Opacity(
          opacity: (trashOpacity * exitOp).clamp(0.0, 1.0),
          child: Transform.scale(
            scale: trashScale,
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: _kRadius20,
              child: BackdropFilter(
                filter: _kBlur20,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      skin.isLight
                          ? Colors.white.withValues(alpha: 0.55)
                          : Colors.black.withValues(alpha: 0.40),
                      const Color(0xFFEF5B5B).withValues(alpha: 0.20),
                      dragProgress,
                    ),
                    borderRadius: _kRadius20,
                    border: Border.all(
                      color: Color.lerp(
                        skin.isLight
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.10),
                        const Color(0xFFEF5B5B).withValues(alpha: 0.60),
                        dragProgress,
                      )!,
                      width: 0.8 + dragProgress * 0.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF5B5B)
                            .withValues(alpha: dragProgress * 0.30),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Color.lerp(skin.surface(0.25),
                        const Color(0xFFEF5B5B), dragProgress),
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRevealBubble(AppSkin skin) {
    final isProcessing = _phase == DictationPhase.processing;
    final isRevealing =
        _phase == DictationPhase.revealing || _phase == DictationPhase.done;
    const double minWidth = 88;
    const double maxWidth = 240;
    final double targetWidth = isRevealing
        ? math.min(
            maxWidth,
            minWidth +
                (_revealedWords.take(_revealIndex).join(' ').length * 6.2))
        : minWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      constraints:
          const BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      width: targetWidth.clamp(minWidth, maxWidth),
      child: ClipRRect(
        borderRadius: _kRadius20,
        child: BackdropFilter(
          filter: _kBlur22,
          child: Container(
            decoration: BoxDecoration(
              color: skin.isLight
                  ? Colors.white.withValues(alpha: 0.85)
                  : skin.bgCard.withValues(alpha: 0.85),
              borderRadius: _kRadius20,
              border: Border.all(
                  color: skin.primary.withValues(alpha: 0.30), width: 1.0),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.20),
                    blurRadius: 24,
                    offset: const Offset(0, 8)),
              ],
            ),
            child: isProcessing
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: ProcessingIndicator(skin: skin),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    child: RevealingText(
                      skin: skin,
                      words: _revealedWords,
                      revealIndex: _revealIndex,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EXTERNE BUBBLE-WIDGETS — werden vom Homescreen im Overlay gerendert
// Identisches Design und Verhalten wie die internen Bubbles in Tasks
// ─────────────────────────────────────────────────────────────────────────────

/// Spektrum-Bubble, positioniert über der Kachel (rechts ausgerichtet)
class _ExternalSpectrumBubble extends StatelessWidget {
  final AppSkin skin;
  final DictationFabState fabState;
  final Offset anchorTopRight;
  final double kachelWidth;

  const _ExternalSpectrumBubble({
    required this.skin,
    required this.fabState,
    required this.anchorTopRight,
    required this.kachelWidth,
  });

  @override
  Widget build(BuildContext context) {
    const bubbleH = 56.0;
    const gap = 8.0;
    final bubbleW = kachelWidth;

    // Rechts an der Kachel ausgerichtet, direkt drüber
    final left = anchorTopRight.dx - bubbleW;
    final top = anchorTopRight.dy - bubbleH - gap;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation:
            Listenable.merge([fabState.bubbleCtrl, fabState.cancelAnimCtrl]),
        builder: (context, child) {
          final exitOpacity = fabState.exitFade.value;
          final bubbleOp =
              (fabState.bubbleOpacity.value * exitOpacity).clamp(0.0, 1.0);
          final dragProgress = fabState.cancelProgress;
          final slideX = -dragProgress * 40.0;
          final shrink =
              fabState.spectrumShrink.value * (1.0 - dragProgress * 0.2);
          final fadeOp =
              fabState.spectrumFade.value * (1.0 - dragProgress * 0.3);

          return Transform.translate(
            offset: Offset(slideX, 0),
            child: Transform.scale(
              scale: (0.85 + fabState.bubbleScale.value * 0.15) * shrink,
              alignment: Alignment.bottomRight,
              child: Opacity(
                opacity: (bubbleOp * fadeOp).clamp(0.0, 1.0),
                child: child,
              ),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: _kRadius20,
          child: BackdropFilter(
            filter: _kBlur22,
            child: Container(
              width: bubbleW,
              height: bubbleH,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: skin.isLight
                    ? Colors.white.withValues(alpha: 0.85)
                    : skin.bgCard.withValues(alpha: 0.85),
                borderRadius: _kRadius20,
                border: Border.all(
                    color: skin.primary.withValues(alpha: 0.30), width: 1.0),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 24,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: Center(
                child: fabState.phase == DictationPhase.preparing
                    ? PreparingDots(skin: skin)
                    : SpectrumIndicator(
                        skin: skin,
                        rawLevelNotifier: fabState.rawLevelNotifier,
                        listenStartedAt: fabState.listenStartedAt,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trash-Button, positioniert links neben der Spektrum-Bubble
class _ExternalTrashButton extends StatelessWidget {
  final AppSkin skin;
  final DictationFabState fabState;
  final Offset anchorTopRight;
  final double kachelWidth;
  final double kachelHeight;

  const _ExternalTrashButton({
    required this.skin,
    required this.fabState,
    required this.anchorTopRight,
    required this.kachelWidth,
    this.kachelHeight = 100.0,
  });

  @override
  Widget build(BuildContext context) {
    const trashW = 56.0;
    const trashGap = 10.0;

    final trashLeft = anchorTopRight.dx - kachelWidth - trashW - trashGap;
    final trashTop = anchorTopRight.dy;

    return Positioned(
      left: trashLeft,
      top: trashTop,
      child: AnimatedBuilder(
        animation: fabState.cancelAnimCtrl,
        builder: (context, _) {
          final dragProgress = fabState.cancelProgress;
          final trashScale = fabState.isCancelling
              ? fabState.trashPulse.value
              : (0.75 + dragProgress * 0.25);
          final trashOpacity = fabState.isCancelling
              ? fabState.trashPulse.value.clamp(0.0, 1.0)
              : (0.28 + dragProgress * 0.72).clamp(0.0, 1.0);
          final exitOp = fabState.exitFade.value;

          return Opacity(
            opacity: (trashOpacity * exitOp).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: trashScale,
              alignment: Alignment.center,
              child: ClipRRect(
                borderRadius: _kRadius20,
                child: BackdropFilter(
                  filter: _kBlur20,
                  child: Container(
                    width: trashW,
                    height: kachelHeight,
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        skin.isLight
                            ? Colors.white.withValues(alpha: 0.55)
                            : Colors.black.withValues(alpha: 0.40),
                        const Color(0xFFEF5B5B).withValues(alpha: 0.20),
                        dragProgress,
                      ),
                      borderRadius: _kRadius20,
                      border: Border.all(
                        color: Color.lerp(
                          skin.isLight
                              ? Colors.white.withValues(alpha: 0.45)
                              : Colors.white.withValues(alpha: 0.10),
                          const Color(0xFFEF5B5B).withValues(alpha: 0.60),
                          dragProgress,
                        )!,
                        width: 0.8 + dragProgress * 0.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFEF5B5B)
                              .withValues(alpha: dragProgress * 0.30),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.delete_outline_rounded,
                      color: Color.lerp(skin.surface(0.25),
                          const Color(0xFFEF5B5B), dragProgress),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Reveal/Processing-Bubble, positioniert über der Kachel (rechts ausgerichtet)
class _ExternalRevealBubble extends StatelessWidget {
  final AppSkin skin;
  final DictationFabState fabState;
  final Offset anchorTopRight;
  final double kachelWidth;

  const _ExternalRevealBubble({
    required this.skin,
    required this.fabState,
    required this.anchorTopRight,
    required this.kachelWidth,
  });

  @override
  Widget build(BuildContext context) {
    const double minWidth = 88;
    const double maxWidth = 240;
    const double bubbleH = 56.0;
    const gap = 8.0;

    final isRevealing = fabState.phase == DictationPhase.revealing ||
        fabState.phase == DictationPhase.done;
    final targetWidth = isRevealing
        ? math.min(
            maxWidth,
            minWidth +
                (fabState.revealedWords
                        .take(fabState.revealIndex)
                        .join(' ')
                        .length *
                    6.2))
        : minWidth;
    final clampedW = targetWidth.clamp(minWidth, maxWidth);

    // Rechts ausgerichtet an der Kachel
    final left = anchorTopRight.dx - clampedW;
    final top = anchorTopRight.dy - bubbleH - gap;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation: fabState.bubbleCtrl,
        builder: (context, child) {
          return Transform.scale(
            alignment: Alignment.bottomRight,
            scale: 0.85 + fabState.bubbleScale.value * 0.15,
            child: Opacity(
              opacity: fabState.bubbleOpacity.value.clamp(0.0, 1.0),
              child: child,
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          constraints:
              const BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
          width: clampedW,
          child: ClipRRect(
            borderRadius: _kRadius20,
            child: BackdropFilter(
              filter: _kBlur22,
              child: Container(
                decoration: BoxDecoration(
                  color: skin.isLight
                      ? Colors.white.withValues(alpha: 0.85)
                      : skin.bgCard.withValues(alpha: 0.85),
                  borderRadius: _kRadius20,
                  border: Border.all(
                      color: skin.primary.withValues(alpha: 0.30), width: 1.0),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.20),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: fabState.phase == DictationPhase.processing
                    ? Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        child: ProcessingIndicator(skin: skin),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: RevealingText(
                          skin: skin,
                          words: fabState.revealedWords,
                          revealIndex: fabState.revealIndex,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SPECTRUM INDICATOR
// ─────────────────────────────────────────────────────────────────────────────

class SpectrumIndicator extends StatefulWidget {
  final AppSkin skin;
  final ValueNotifier<double> rawLevelNotifier;
  final DateTime? listenStartedAt;

  const SpectrumIndicator({
    super.key,
    required this.skin,
    required this.rawLevelNotifier,
    this.listenStartedAt,
  });

  @override
  State<SpectrumIndicator> createState() => _SpectrumIndicatorState();
}

class _SpectrumIndicatorState extends State<SpectrumIndicator>
    with SingleTickerProviderStateMixin {
  final List<double> _smoothed = List.generate(5, (_) => 0.08);
  final List<double> _phaseOffset = [0.0, 0.72, 1.44, 0.36, 1.08];
  final List<double> _sensitivityFactor = [0.85, 1.10, 1.25, 1.05, 0.90];

  double _idleTick = 0.0;
  double _levelFloor = -2.0;
  double _levelCeil = 3.0;

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration _) {
    if (!mounted) return;
    _idleTick += 0.055;

    final raw = widget.rawLevelNotifier.value;

    if (raw > _levelCeil) _levelCeil = raw * 1.05;
    _levelCeil = math.max(_levelCeil - 0.008, 2.0);

    if (raw > _levelFloor + 0.5) {
      _levelFloor = _levelFloor * 0.95 + raw * 0.05;
    }
    _levelFloor = math.max(_levelFloor - 0.002, -2.5);

    final range = (_levelCeil - _levelFloor).clamp(1.5, double.infinity);
    final normalized = ((raw - _levelFloor) / range).clamp(0.0, 1.0);

    final warmingUp = widget.listenStartedAt != null &&
        DateTime.now().difference(widget.listenStartedAt!) <
            const Duration(milliseconds: 500);

    setState(() {
      for (var i = 0; i < 5; i++) {
        final sim = 0.18 +
            (math.sin(_idleTick * (1.6 + i * 0.35) + _phaseOffset[i]) * 0.5 + 0.5) * 0.35;

        final boosted = (normalized * _sensitivityFactor[i]).clamp(0.0, 1.0);
        final target = (sim * 0.55 + boosted * 0.75).clamp(0.04, 1.0);

        final smooth = target > _smoothed[i] ? 0.65 : 0.18;
        _smoothed[i] += (target - _smoothed[i]) * smooth;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    return SizedBox(
      height: 28,
      width: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(5, (i) {
          final v = _smoothed[i].clamp(0.04, 1.0);
          final h = 4.0 + v * 24.0;
          return Container(
            width: 4,
            height: h,
            decoration: BoxDecoration(
              color: skin.primary.withValues(alpha: 0.45 + v * 0.55),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

class ProcessingIndicator extends StatelessWidget {
  final AppSkin skin;
  const ProcessingIndicator({super.key, required this.skin});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      width: 56,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
            valueColor: AlwaysStoppedAnimation(skin.primary),
          ),
        ),
      ),
    );
  }
}

class PreparingDots extends StatefulWidget {
  final AppSkin skin;
  const PreparingDots({super.key, required this.skin});

  @override
  State<PreparingDots> createState() => _PreparingDotsState();
}

class _PreparingDotsState extends State<PreparingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _dotOpacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
    _dotOpacity = List.generate(3, (i) {
      final start = i * 0.2;
      return TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.3, end: 1.0), weight: 30),
        TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.3), weight: 30),
        TweenSequenceItem(tween: ConstantTween(0.3), weight: 40),
      ]).animate(CurvedAnimation(
        parent: _ctrl,
        curve: Interval(start, (start + 0.6).clamp(0.0, 1.0),
            curve: Curves.easeInOut),
      ));
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      width: 56,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            3,
            (i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Opacity(
                opacity: _dotOpacity[i].value,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: widget.skin.primary, shape: BoxShape.circle),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RevealingText extends StatelessWidget {
  final AppSkin skin;
  final List<String> words;
  final int revealIndex;

  const RevealingText({
    super.key,
    required this.skin,
    required this.words,
    required this.revealIndex,
  });

  @override
  Widget build(BuildContext context) {
    final visibleWords = words.take(revealIndex).toList();
    final isEmpty = visibleWords.isEmpty;

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 120),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.15),
                end: Offset.zero,
              ).animate(
                  CurvedAnimation(parent: anim, curve: Curves.easeOut)),
              child: child,
            ),
          ),
          child: Text(
            isEmpty ? '…' : visibleWords.join(' '),
            key: ValueKey(visibleWords.length),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: isEmpty ? skin.surface(0.35) : skin.textPrimary,
              height: 1.38,
            ),
            textAlign: TextAlign.center,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}