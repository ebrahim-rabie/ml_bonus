import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import '../classifier/digit_classifier.dart';

class CameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraScreen({super.key, required this.cameras});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  ArabicDigitClassifier? _classifier;

  bool _isModelLoaded = false;
  bool _isProcessing = false;
  bool _isCameraReady = false;

  int? _predictedDigit;
  String _arabicDigit = '';
  String _latinDigit = '';
  double _confidence = 0.0;
  List<double> _probabilities = [];

  // Throttle: run inference every N ms
  static const int _inferenceIntervalMs = 400;
  DateTime _lastInference = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _classifier = await ArabicDigitClassifier.create();
      if (mounted) setState(() => _isModelLoaded = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading model: $e')),
        );
      }
    }
  }

  Future<void> _initCamera() async {
    // Request camera permission first
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera permission denied')),
        );
      }
      return;
    }

    if (widget.cameras.isEmpty) return;

    // Prefer back camera
    final camera = widget.cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    _controller = CameraController(
      camera,
      ResolutionPreset.medium, // medium is enough and faster
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    try {
      await _controller!.initialize();
      if (!mounted) return;

      setState(() => _isCameraReady = true);

      // Start image stream
      await _controller!.startImageStream(_onCameraImage);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera error: $e')),
        );
      }
    }
  }

  void _onCameraImage(CameraImage cameraImage) {
    if (!_isModelLoaded || _isProcessing) return;

    final now = DateTime.now();
    if (now.difference(_lastInference).inMilliseconds < _inferenceIntervalMs) return;
    _lastInference = now;

    _isProcessing = true;

    // Convert CameraImage (YUV420) to img.Image on a separate isolate would be ideal,
    // but for simplicity we do it here (it's fast enough for 28x28 target)
    try {
      final image = _convertYUV420toImage(cameraImage);
      if (image == null) {
        _isProcessing = false;
        return;
      }

      final result = _classifier?.predictImage(image);
      if (result != null && result.digits.isNotEmpty && mounted) {
        final firstDigit = result.digits.first;
        const arabicLabels = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        String arabicText = result.text.split('').map((c) => arabicLabels[int.parse(c)]).join();

        setState(() {
          _predictedDigit = firstDigit.digit;
          _arabicDigit = arabicText;
          _latinDigit = result.text;
          _confidence = firstDigit.confidence;
          _probabilities = firstDigit.probabilities;
        });
      }
    } catch (_) {
      // Silently ignore frame errors
    } finally {
      _isProcessing = false;
    }
  }

  /// Convert YUV420 CameraImage to img.Image (RGB)
  img.Image? _convertYUV420toImage(CameraImage cameraImage) {
    try {
      final width = cameraImage.width;
      final height = cameraImage.height;
      final yPlane = cameraImage.planes[0];
      final uPlane = cameraImage.planes[1];
      final vPlane = cameraImage.planes[2];

      final yBytes = yPlane.bytes;
      final uBytes = uPlane.bytes;
      final vBytes = vPlane.bytes;

      final yRowStride = yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;

      final uvRowStride = uPlane.bytesPerRow;
      final uvPixelStride = uPlane.bytesPerPixel ?? 1;

      final image = img.Image(width: width, height: height);

      for (int y = 0; y < height; y++) {
        int uvRow = y ~/ 2;
        for (int x = 0; x < width; x++) {
          int uvCol = x ~/ 2;

          int yIndex = (y * yRowStride) + (x * yPixelStride);
          int uvIndex = (uvRow * uvRowStride) + (uvCol * uvPixelStride);

          if (yIndex >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
            continue;
          }

          int yValue = yBytes[yIndex];
          int uValue = uBytes[uvIndex] - 128;
          int vValue = vBytes[uvIndex] - 128;

          int r = (yValue + 1.402 * vValue).toInt().clamp(0, 255);
          int g = (yValue - 0.344 * uValue - 0.714 * vValue).toInt().clamp(0, 255);
          int b = (yValue + 1.772 * uValue).toInt().clamp(0, 255);

          image.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      return image;
    } catch (_) {
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _controller!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _classifier?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCameraSection()),
            _buildResultSection(),
            _buildProbabilitiesBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF00E5FF).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.4)),
            ),
            child: const Icon(Icons.translate_rounded, color: Color(0xFF00E5FF), size: 18),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arabic Digit Recognizer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _isModelLoaded ? const Color(0xFF00E5FF) : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isModelLoaded ? 'Model ready' : 'Loading model...',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Camera preview
            if (_isCameraReady && _controller != null)
              CameraPreview(_controller!)
            else
              Container(
                color: const Color(0xFF12121A),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
                ),
              ),

            // Scan overlay
            _buildScanOverlay(),

            // Confidence badge (top right)
            if (_predictedDigit != null)
              Positioned(
                top: 14,
                right: 14,
                child: _buildConfidenceBadge(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    return CustomPaint(
      painter: _ScanOverlayPainter(
        color: _confidence > 0.8
            ? const Color(0xFF00E5FF)
            : _confidence > 0.5
            ? Colors.orange
            : Colors.white.withOpacity(0.3),
      ),
    );
  }

  Widget _buildConfidenceBadge() {
    final pct = (_confidence * 100).toStringAsFixed(0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _confidence > 0.8 ? const Color(0xFF00E5FF) : Colors.orange,
          width: 1,
        ),
      ),
      child: Text(
        '$pct%',
        style: TextStyle(
          color: _confidence > 0.8 ? const Color(0xFF00E5FF) : Colors.orange,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _predictedDigit != null
              ? const Color(0xFF00E5FF).withOpacity(0.3)
              : Colors.white.withOpacity(0.08),
        ),
      ),
      child: _predictedDigit == null
          ? const Center(
        child: Text(
          'Point camera at a handwritten Arabic digit',
          style: TextStyle(color: Colors.white38, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      )
          : Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Arabic digit (big)
          Text(
            _arabicDigit,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontSize: 64,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
          const SizedBox(width: 20),
          Container(width: 1, height: 60, color: Colors.white12),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Digit $_latinDigit',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Confidence: ${(_confidence * 100).toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _confidence > 0.8
                      ? const Color(0xFF00E5FF)
                      : Colors.orange,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProbabilitiesBar() {
    if (_probabilities.isEmpty) return const SizedBox(height: 16);

    return Container(
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'All probabilities',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
          const SizedBox(height: 10),
          Row(
            children: List.generate(10, (i) {
              final prob = _probabilities.length > i ? _probabilities[i] : 0.0;
              final isMax = i == _predictedDigit;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      // Bar
                      Container(
                        height: 40,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.white.withOpacity(0.05),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: prob.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isMax
                                  ? const Color(0xFF00E5FF)
                                  : const Color(0xFF7C4DFF).withOpacity(0.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ['٠','١','٢','٣','٤','٥','٦','٧','٨','٩'][i],
                        style: TextStyle(
                          color: isMax ? const Color(0xFF00E5FF) : Colors.white38,
                          fontSize: 12,
                          fontWeight: isMax ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the scan frame overlay
class _ScanOverlayPainter extends CustomPainter {
  final Color color;
  _ScanOverlayPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    // Center square guide
    final cx = size.width / 2;
    final cy = size.height / 2;
    const boxSize = 160.0;
    const cornerLen = 24.0;
    const r = 8.0;

    final left = cx - boxSize / 2;
    final top = cy - boxSize / 2;
    final right = cx + boxSize / 2;
    final bottom = cy + boxSize / 2;

    // Top-left corner
    canvas.drawLine(Offset(left + r, top), Offset(left + cornerLen, top), paint);
    canvas.drawLine(Offset(left, top + r), Offset(left, top + cornerLen), paint);
    // Top-right corner
    canvas.drawLine(Offset(right - cornerLen, top), Offset(right - r, top), paint);
    canvas.drawLine(Offset(right, top + r), Offset(right, top + cornerLen), paint);
    // Bottom-left corner
    canvas.drawLine(Offset(left, bottom - cornerLen), Offset(left, bottom - r), paint);
    canvas.drawLine(Offset(left + r, bottom), Offset(left + cornerLen, bottom), paint);
    // Bottom-right corner
    canvas.drawLine(Offset(right, bottom - cornerLen), Offset(right, bottom - r), paint);
    canvas.drawLine(Offset(right - cornerLen, bottom), Offset(right - r, bottom), paint);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) => old.color != color;
}