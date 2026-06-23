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

// ─────────────────────────────────────────────────────────────────────────────
// DICTATION FAB — wiederverwendbarer Diktier-Button mit Live-Bubble
// Ursprünglich aus tasks_screen.dart extrahiert, damit er auch auf dem
// Homescreen genutzt werden kann (gleiches Aussehen & Verhalten).
// ─────────────────────────────────────────────────────────────────────────────

enum DictationPhase { idle, listening, processing, revealing, done }

class DictationFab extends StatefulWidget {
  final AppSkin skin;
  final void Function(ParsedSpokenTask parsed, String logRef) onResult;
  final void Function(ParsedSpokenTask parsed, String logRef) onNeedsReview;

  /// Optionaler Callback, der ausgelöst wird, sobald das Zuhören beginnt
  /// bzw. endet — z.B. um auf dem Homescreen andere UI auszublenden.
  final VoidCallback? onListeningStart;
  final VoidCallback? onListeningEnd;

  /// Blendet den FAB-Button aus, aber lässt die Bubbles sichtbar
  final bool hideButton;

  const DictationFab({
    super.key,
    required this.skin,
    required this.onResult,
    required this.onNeedsReview,
    this.onListeningStart,
    this.onListeningEnd,
    this.hideButton = false,
  });

  @override
  State<DictationFab> createState() => DictationFabState();
}

class DictationFabState extends State<DictationFab> with TickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechAvailable = false;

  DictationPhase _phase = DictationPhase.idle;
  String _liveTranscript = '';
  String _finalTranscript = '';
  List<String> _revealedWords = [];
  int _revealIndex = 0;
  Timer? _revealTimer;

  final ValueNotifier<double> _rawLevelNotifier = ValueNotifier(0.0);

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

  @override
  void initState() {
    super.initState();
    _fabPulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _idlePulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650))
      ..repeat(reverse: true);
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
      if (mounted) setState(() {});
    });

    _initSpeech();
  }

  Future<void> _initSpeech() async {
    final available = await _speech.initialize(
      onStatus: _onSpeechStatus,
      onError: (err) {
        if (_aborted) return;
        if (mounted) {
          setState(() => _phase = DictationPhase.idle);
          _bubbleCtrl.reverse();
          widget.onListeningEnd?.call();
        }
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
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

  @override
  void dispose() {
    _revealTimer?.cancel();
    _fabPulseCtrl.dispose();
    _idlePulseCtrl.dispose();
    _bubbleCtrl.dispose();
    _cancelAnimCtrl.dispose();
    _rawLevelNotifier.dispose();
    super.dispose();
  }

  Future<void> _startListening() async {
    if (!_speechAvailable) {
      HapticFeedback.heavyImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('🎙 Spracherkennung nicht verfügbar — Berechtigung prüfen.'),
          backgroundColor: widget.skin.bgCard,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        ));
      }
      return;
    }
    HapticFeedback.mediumImpact();
    _aborted = false;
    _isCancelling = false;
    _cancelDragX = 0.0;
    _listenStartedAt = DateTime.now();
    setState(() {
      _phase = DictationPhase.listening;
      _liveTranscript = '';
      _finalTranscript = '';
      _rawLevelNotifier.value = 0.0;
      _revealedWords = [];
      _revealIndex = 0;
    });
    widget.onListeningStart?.call();
    _cancelAnimCtrl.reset();
    _bubbleCtrl.forward();

    await _speech.listen(
      localeId: 'de_DE',
      onResult: (result) {
        if (_aborted || !mounted) return;
        setState(() {
          _liveTranscript = result.recognizedWords;
          if (result.finalResult) _finalTranscript = result.recognizedWords;
        });
      },
      onSoundLevelChange: (level) {
        if (_aborted || !mounted) return;
        _rawLevelNotifier.value = level;
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      partialResults: true,
      cancelOnError: true,
      listenMode: stt.ListenMode.confirmation,
    );
  }

  Future<void> _finishListeningAndReveal() async {
    if (_aborted) return;
    if (_phase != DictationPhase.listening) return;
    await _speech.stop();
    if (_aborted) return;
    setState(() {
      _cancelDragX = 0.0;
    });

    final text = (_finalTranscript.isNotEmpty ? _finalTranscript : _liveTranscript).trim();
    if (text.isEmpty) {
      setState(() => _phase = DictationPhase.idle);
      _bubbleCtrl.reverse();
      widget.onListeningEnd?.call();
      return;
    }

    setState(() => _phase = DictationPhase.processing);
    await Future.delayed(const Duration(milliseconds: 350));
    if (_aborted || !mounted) return;

    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _phase = DictationPhase.revealing;
      _revealedWords = words;
      _revealIndex = 0;
    });

    _revealTimer?.cancel();
    _revealTimer = Timer.periodic(const Duration(milliseconds: 90), (timer) {
      if (_aborted || !mounted) {
        timer.cancel();
        return;
      }
      setState(() => _revealIndex++);
      if (_revealIndex >= _revealedWords.length) {
        timer.cancel();
        _onRevealComplete(text);
      }
    });
  }

  Future<void> _cancelListening() async {
    if (_isCancelling) return;
    if (_phase != DictationPhase.listening) return;
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
    _cancelAnimCtrl.reset();
    _bubbleCtrl.reset();
    setState(() {
      _phase = DictationPhase.idle;
      _liveTranscript = '';
      _finalTranscript = '';
      _revealedWords = [];
      _revealIndex = 0;
      _rawLevelNotifier.value = 0.0;
      _cancelDragX = 0.0;
      _isCancelling = false;
      _aborted = false;
    });
    widget.onListeningEnd?.call();
  }

  void _onRevealComplete(String text) {
    if (_aborted) return;
    setState(() => _phase = DictationPhase.done);

    // ── RuleEngine: zuerst gelernte Regeln prüfen ──
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
        });
      });
      return;
    }

    // ── Normaler Pfad: kein Regel-Treffer ──
    final normalized = SpeechNormalizer.normalize(text);
    final parsed = SpokenTaskParser.parse(normalized);

    // ── Konfidenz-Check ──
    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    final normalizerMissed = normalized == text;
    final hasNoDateTime = parsed.date == null && !parsed.hasTime;
    final titleTooShort = parsed.title.trim().length < 3;

    final needsReview = titleTooShort ||
        (normalizerMissed && wordCount > 4) ||
        (hasNoDateTime && wordCount > 6);

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
      });
    });
  }

  bool get _isActive => _phase != DictationPhase.idle;

  double get _cancelProgress => (_cancelDragX.abs() / 80.0).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final skin = widget.skin;
    final bool showBubbles = _isActive && !_isCancelling || _cancelAnimCtrl.value > 0;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        if (showBubbles && _phase == DictationPhase.listening)
          Positioned(
            bottom: 68,
            right: 0,
            child: AnimatedBuilder(
              animation: Listenable.merge([_bubbleCtrl, _cancelAnimCtrl]),
              builder: (context, child) {
                final exitOpacity = _exitFade.value;
                final bubbleOp = (_bubbleOpacity.value * exitOpacity).clamp(0.0, 1.0);
                final dragProgress = _cancelProgress;
                final slideX = -dragProgress * 40.0;
                final shrink = _spectrumShrink.value * (1.0 - dragProgress * 0.2);
                final fadeOp = _spectrumFade.value * (1.0 - dragProgress * 0.3);

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
            child: AnimatedBuilder(
              animation: _cancelAnimCtrl,
              builder: (context, _) {
                final dragProgress = _cancelProgress;
                final trashScale = _isCancelling ? _trashPulse.value : (0.75 + dragProgress * 0.25);
                final trashOpacity = _isCancelling ? _trashPulse.value.clamp(0.0, 1.0) : (0.28 + dragProgress * 0.72).clamp(0.0, 1.0);
                final exitOp = _exitFade.value;

                return Opacity(
                  opacity: (trashOpacity * exitOp).clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: trashScale,
                    alignment: Alignment.center,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Color.lerp(
                              skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.40),
                              const Color(0xFFEF5B5B).withValues(alpha: 0.20),
                              dragProgress,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Color.lerp(
                                skin.isLight ? Colors.white.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.10),
                                const Color(0xFFEF5B5B).withValues(alpha: 0.60),
                                dragProgress,
                              )!,
                              width: 0.8 + dragProgress * 0.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFEF5B5B).withValues(alpha: dragProgress * 0.30),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            color: Color.lerp(skin.surface(0.25), const Color(0xFFEF5B5B), dragProgress),
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        if (_phase == DictationPhase.revealing || _phase == DictationPhase.done || _phase == DictationPhase.processing)
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

        // ── FAB-Button (kann ausgeblendet werden) ──
        if (!widget.hideButton)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPressStart: (_) => _startListening(),
            onLongPressEnd: (_) {
              if (!_isCancelling) _finishListeningAndReveal();
            },
            onLongPressCancel: () {
              if (!_isCancelling) _finishListeningAndReveal();
            },
            onLongPressMoveUpdate: (details) {
              if (_phase != DictationPhase.listening || _isCancelling) return;
              final dx = details.offsetFromOrigin.dx;
              setState(() => _cancelDragX = dx < 0 ? dx : 0.0);
              if (dx < -80.0) _cancelListening();
            },
            child: AnimatedBuilder(
              animation: Listenable.merge([_fabPulseCtrl, _cancelAnimCtrl]),
              builder: (context, _) {
                final pulse = _phase == DictationPhase.listening ? _fabPulseCtrl.value : 0.0;
                final cancelProgress = _cancelProgress;
                final fabColor = _isActive
                    ? Color.lerp(
                        skin.primary.withValues(alpha: 0.85 + pulse * 0.15),
                        const Color(0xFFEF5B5B).withValues(alpha: 0.9),
                        cancelProgress,
                      )!
                    : (skin.isLight ? Colors.white.withValues(alpha: 0.72) : Colors.black.withValues(alpha: 0.55));

                return Opacity(
                  opacity: _exitFade.value,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: fabColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isActive ? Colors.white.withValues(alpha: 0.35) : (skin.isLight ? Colors.white.withValues(alpha: 0.55) : Colors.white.withValues(alpha: 0.12)),
                            width: _isActive ? 1.2 : 0.8,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _isActive
                                  ? Color.lerp(
                                      skin.primaryWithAlpha(0.45 + pulse * 0.2),
                                      const Color(0xFFEF5B5B).withValues(alpha: 0.5),
                                      cancelProgress,
                                    )!
                                  : Colors.black.withValues(alpha: skin.isLight ? 0.08 : 0.35),
                              blurRadius: _isActive ? 20 + pulse * 10 : 24,
                              spreadRadius: _isActive ? pulse * 2 : 0,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: Icon(
                            cancelProgress > 0.35 ? Icons.close_rounded : (_isActive ? Icons.mic_rounded : Icons.mic_none_rounded),
                            key: ValueKey(cancelProgress > 0.35 ? 'cancel' : (_isActive ? 'active' : 'idle')),
                            color: cancelProgress > 0.35 ? Colors.white : (_isActive ? skin.onGradient : skin.textPrimary),
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        else
          const SizedBox(width: 56, height: 56), // Platzhalter damit Stack-Positionen stimmen
      ],
    );
  }

  Widget _buildSpectrumBubble(AppSkin skin) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          width: 88,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: skin.isLight ? Colors.white.withValues(alpha: 0.85) : skin.bgCard.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: skin.primary.withValues(alpha: 0.30), width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 8)),
            ],
          ),
          child: _SpectrumIndicator(skin: skin, rawLevelNotifier: _rawLevelNotifier, listenStartedAt: _listenStartedAt),
        ),
      ),
    );
  }

  Widget _buildRevealBubble(AppSkin skin) {
    final isProcessing = _phase == DictationPhase.processing;
    final isRevealing = _phase == DictationPhase.revealing || _phase == DictationPhase.done;
    final double minWidth = 88;
    final double maxWidth = 240;
    final double targetWidth = isRevealing
        ? math.min(maxWidth, minWidth + (_revealedWords.take(_revealIndex).join(' ').length * 6.2))
        : minWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: maxWidth),
      width: targetWidth.clamp(minWidth, maxWidth),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            decoration: BoxDecoration(
              color: skin.isLight ? Colors.white.withValues(alpha: 0.85) : skin.bgCard.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: skin.primary.withValues(alpha: 0.30), width: 1.0),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.20), blurRadius: 24, offset: const Offset(0, 8)),
              ],
            ),
            child: isProcessing
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: _ProcessingIndicator(skin: skin),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: _RevealingText(
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
// SPECTRUM INDICATOR
// ─────────────────────────────────────────────────────────────────────────────

class _SpectrumIndicator extends StatefulWidget {
  final AppSkin skin;
  final ValueNotifier<double> rawLevelNotifier;
  final DateTime? listenStartedAt;
  const _SpectrumIndicator({
    required this.skin,
    required this.rawLevelNotifier,
    this.listenStartedAt,
  });

  @override
  State<_SpectrumIndicator> createState() => _SpectrumIndicatorState();
}

class _SpectrumIndicatorState extends State<_SpectrumIndicator>
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

    if (raw > _levelFloor + 0.5) _levelFloor = _levelFloor * 0.95 + raw * 0.05;
    _levelFloor = math.max(_levelFloor - 0.002, -2.5);

    final range = (_levelCeil - _levelFloor).clamp(1.5, double.infinity);
    final normalized = ((raw - _levelFloor) / range).clamp(0.0, 1.0);

    final warmingUp = widget.listenStartedAt != null &&
        DateTime.now().difference(widget.listenStartedAt!) < const Duration(milliseconds: 500);

    setState(() {
      for (var i = 0; i < 5; i++) {
        final idle = warmingUp
            ? 0.20 + math.sin(_idleTick + _phaseOffset[i]) * 0.12
            : 0.05 + math.sin(_idleTick * 0.6 + _phaseOffset[i]) * 0.04;

        final boosted = (normalized * _sensitivityFactor[i]).clamp(0.0, 1.0);
        final target = math.max(boosted, idle).clamp(0.04, 1.0);

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

class _ProcessingIndicator extends StatelessWidget {
  final AppSkin skin;
  const _ProcessingIndicator({required this.skin});

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

class _RevealingText extends StatelessWidget {
  final AppSkin skin;
  final List<String> words;
  final int revealIndex;
  const _RevealingText({required this.skin, required this.words, required this.revealIndex});

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
              ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
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