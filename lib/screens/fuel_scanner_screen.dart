import 'dart:async';
import 'dart:io' as dartio;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import '../theme/app_theme.dart';

class FuelScannerScreen extends StatefulWidget {
  final String label; // 'KRAFTSTOFF LITER'
  final Color color;

  const FuelScannerScreen({
    super.key,
    required this.label,
    required this.color,
  });

  @override
  State<FuelScannerScreen> createState() => _FuelScannerScreenState();
}

class _FuelScannerScreenState extends State<FuelScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isDisposed = false;

  // OCR
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  Timer? _scanTimer;
  String? _lastDetected;
  bool _showConfirm = false;
  String? _pendingLiter;

  // Ergebnis
  String? _resultLiter;
  String? _resultImagePath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) return;
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await _controller!.initialize();
      if (_isDisposed) return;
      setState(() => _isInitialized = true);
      _startScanning();
    } catch (e) {
      debugPrint('Kamera Init Fehler: $e');
    }
  }

  void _startScanning() {
    _scanTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (!_isProcessing && !_showConfirm) {
        _scanFrame();
      }
    });
  }

  Future<void> _scanFrame() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isProcessing || _isDisposed) return;
    _isProcessing = true;

    try {
      final xFile = await _controller!.takePicture();
      final inputImage = InputImage.fromFilePath(xFile.path);
      final result = await _recognizer.processImage(inputImage);

      final liter = _extractLiter(result);
      if (liter != null && liter != _lastDetected) {
        _lastDetected = liter;
        if (mounted && !_showConfirm) {
          HapticFeedback.mediumImpact();
          setState(() {
            _pendingLiter = liter;
            _showConfirm = true;
            _resultImagePath = xFile.path;
          });
          _scanTimer?.cancel();
        }
      } else {
        // Temp-Datei löschen wenn kein Treffer
        try { dartio.File(xFile.path).deleteSync(); } catch (_) {}
      }
    } catch (e) {
      debugPrint('Scan Fehler: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// 🔥 ANGEPASSTE Methode für Liter-Erkennung
  String? _extractLiter(RecognizedText result) {
    for (final block in result.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();

        // Suche nach Muster: Zahl mit 1-2 Nachkommastellen + "l" oder "L" oder "Liter"
        // Unterstützt: "45.6l", "45,6L", "50.00 Liter", "12,5 l", "7.5L"
        final match = RegExp(
          r'(\d{1,3}[.,]\d{1,2})\s*[lL](?:iter)?',
          caseSensitive: false,
        ).firstMatch(text);

        if (match != null) {
          final raw = match.group(1)!.replaceAll(',', '.');
          final val = double.tryParse(raw);
          if (val != null && val > 1.0 && val < 300.0) {
            // Format: deutsche Komma-Darstellung (z.B. "45,6")
            final formatted = raw.replaceAll('.', ',');
            // Wenn nur eine Nachkommastelle, eine Null anhängen (z.B. "45,6" → "45,60")
            if (formatted.contains(',') && formatted.split(',').last.length == 1) {
              return '$formatted' '0';
            }
            return formatted;
          }
        }

        // Fallback: Zahl + "L" ohne Leerzeichen (z.B. "45,6L")
        final matchNoSpace = RegExp(
          r'(\d{1,3}[.,]\d{1,2})[lL]',
          caseSensitive: false,
        ).firstMatch(text.replaceAll(' ', ''));

        if (matchNoSpace != null) {
          final raw = matchNoSpace.group(1)!.replaceAll(',', '.');
          final val = double.tryParse(raw);
          if (val != null && val > 1.0 && val < 300.0) {
            final formatted = raw.replaceAll('.', ',');
            if (formatted.contains(',') && formatted.split(',').last.length == 1) {
              return '$formatted' '0';
            }
            return formatted;
          }
        }
      }
    }
    return null;
  }

  void _acceptLiter() {
    HapticFeedback.heavyImpact();
    setState(() => _resultLiter = _pendingLiter);
    Navigator.of(context).pop({
      'liter': _resultLiter,
      'imagePath': _resultImagePath,
    });
  }

  void _rejectLiter() {
    HapticFeedback.selectionClick();
    // Temp-Bild löschen
    if (_resultImagePath != null) {
      try { dartio.File(_resultImagePath!).deleteSync(); } catch (_) {}
    }
    setState(() {
      _showConfirm = false;
      _pendingLiter = null;
      _lastDetected = null;
      _resultImagePath = null;
    });
    _startScanning();
  }

  Future<void> _openGallery() async {
    _scanTimer?.cancel();
    final picker = ImagePicker();
    try {
      final xFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1920,
      );
      if (xFile == null || !mounted) {
        _startScanning();
        return;
      }

      // OCR auf Galerie-Bild
      final inputImage = InputImage.fromFilePath(xFile.path);
      final result = await _recognizer.processImage(inputImage);
      final liter = _extractLiter(result);

      if (liter != null && mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _pendingLiter = liter;
          _showConfirm = true;
          _resultImagePath = xFile.path;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Kein Liter-Wert im Bild erkannt'),
            duration: Duration(seconds: 2),
          ));
          _startScanning();
        }
      }
    } catch (e) {
      debugPrint('Galerie Fehler: $e');
      _startScanning();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;
    if (state == AppLifecycleState.inactive) {
      _scanTimer?.cancel();
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _scanTimer?.cancel();
    _recognizer.close();
    _controller?.dispose();
    super.dispose();
  }

  String _formatLiterDisplay(String liter) {
    // Wenn bereits mit Komma, einfach anzeigen
    if (liter.contains(',')) {
      // Stelle sicher, dass es 2 Nachkommastellen hat
      final parts = liter.split(',');
      if (parts.length == 2) {
        final decimals = parts[1].padRight(2, '0');
        return '${parts[0]},$decimals L';
      }
      return '$liter L';
    }
    // Fallback: Punkt durch Komma ersetzen
    final withComma = liter.replaceAll('.', ',');
    final parts = withComma.split(',');
    if (parts.length == 2) {
      final decimals = parts[1].padRight(2, '0');
      return '${parts[0]},$decimals L';
    }
    return '$withComma L';
  }

  @override
  Widget build(BuildContext context) {
    final skin = AppTheme.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Kamera-Preview
            if (_isInitialized && _controller != null)
              CameraPreview(_controller!)
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // Dunkles Overlay oben
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                height: MediaQuery.of(context).padding.top + 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Header
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(null),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.label,
                          style: TextStyle(
                            color: widget.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Text(
                          'Tank-Anzeige auf den Liter-Wert richten',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Suchanzeige (pulsierender Ring wenn keine Bestätigung)
            if (!_showConfirm)
              Center(
                child: _ScanOverlay(color: widget.color),
              ),

            // Bestätigungs-Overlay
            if (_showConfirm && _pendingLiter != null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _ConfirmOverlay(
                  liter: _formatLiterDisplay(_pendingLiter!),
                  color: widget.color,
                  skin: skin,
                  onAccept: _acceptLiter,
                  onReject: _rejectLiter,
                ),
              ),

            // Galerie-Button unten (nur wenn kein Confirm)
            if (!_showConfirm)
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 40,
                left: 0,
                right: 0,
                child: Column(
                  children: [
                    Text(
                      'Wird automatisch erkannt…',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _openGallery,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined,
                                color: Colors.white.withOpacity(0.9), size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Aus Galerie auswählen',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Scan-Overlay (pulsierender Rahmen) ───────────────────────────────────────

class _ScanOverlay extends StatefulWidget {
  final Color color;
  const _ScanOverlay({required this.color});

  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: Container(
          width: 260,
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.color.withOpacity(0.8),
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              ..._corners(widget.color),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _corners(Color color) {
    const size = 20.0;
    const thickness = 3.0;
    return [
      _Corner(top: 0, left: 0, color: color, size: size, thickness: thickness),
      _Corner(top: 0, right: 0, color: color, size: size, thickness: thickness),
      _Corner(bottom: 0, left: 0, color: color, size: size, thickness: thickness),
      _Corner(bottom: 0, right: 0, color: color, size: size, thickness: thickness),
    ];
  }
}

class _Corner extends StatelessWidget {
  final double? top, left, right, bottom;
  final Color color;
  final double size, thickness;

  const _Corner({
    this.top,
    this.left,
    this.right,
    this.bottom,
    required this.color,
    required this.size,
    required this.thickness,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: CustomPaint(
        size: Size(size, size),
        painter: _CornerPainter(
          color: color,
          thickness: thickness,
          isTopLeft: top == 0 && left == 0,
          isTopRight: top == 0 && right == 0,
          isBottomLeft: bottom == 0 && left == 0,
          isBottomRight: bottom == 0 && right == 0,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double thickness;
  final bool isTopLeft, isTopRight, isBottomLeft, isBottomRight;

  _CornerPainter({
    required this.color,
    required this.thickness,
    required this.isTopLeft,
    required this.isTopRight,
    required this.isBottomLeft,
    required this.isBottomRight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final path = Path();
    if (isTopLeft) {
      path.moveTo(0, size.height);
      path.lineTo(0, 0);
      path.lineTo(size.width, 0);
    } else if (isTopRight) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
    } else if (isBottomLeft) {
      path.moveTo(0, 0);
      path.lineTo(0, size.height);
      path.lineTo(size.width, size.height);
    } else if (isBottomRight) {
      path.moveTo(0, size.height);
      path.lineTo(size.width, size.height);
      path.lineTo(size.width, 0);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ─── Bestätigungs-Overlay ────────────────────────────────────────────────────

class _ConfirmOverlay extends StatelessWidget {
  final String liter;
  final Color color;
  final AppSkin skin;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _ConfirmOverlay({
    required this.liter,
    required this.color,
    required this.skin,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          24, 28, 24, MediaQuery.of(context).padding.bottom + 32),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Icon(Icons.local_gas_station_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liter erkannt',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      liter,
                      style: TextStyle(
                        color: color,
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onReject,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border:
                          Border.all(color: Colors.white.withOpacity(0.15)),
                    ),
                    child: Center(
                      child: Text(
                        'Weiter suchen',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'Übernehmen',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}