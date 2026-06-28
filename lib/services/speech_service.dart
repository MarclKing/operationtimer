import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false;
  bool _initialized = false;
  bool _initializing = false;

  stt.SpeechToText get speech => _speech;
  bool get isAvailable => _available;

  Future<bool> ensureInitialized({
    required Function(String) onStatus,
    required Function(dynamic) onError,
  }) async {
    if (_initialized) return _available;
    if (_initializing) {
      // Warten bis laufende Initialisierung fertig
      while (_initializing) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _available;
    }
    _initializing = true;
    try {
      _available = await _speech.initialize(
        onStatus: onStatus,
        onError: onError,
      );
    } catch (_) {
      _available = false;
    }
    _initialized = true;
    _initializing = false;
    return _available;
  }
}