import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../classifier/digit_classifier.dart';
import '../widgets/detected_boxes_view.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ArabicDigitClassifier? _classifier;
  final ImagePicker _picker = ImagePicker();

  bool _isModelLoaded = false;
  bool _isProcessing = false;

  File? _selectedImage;
  int? _predictedDigit;
  String _arabicDigit = '';
  String _latinDigit = '';
  double _confidence = 0.0;
  List<double> _probabilities = [];
  MultiDigitPrediction? _lastPrediction;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      _classifier = await ArabicDigitClassifier.create();
      if (mounted) setState(() => _isModelLoaded = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading model: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
      );

      if (pickedFile == null) return;

      setState(() {
        _selectedImage = File(pickedFile.path);
        _isProcessing = true;
        _predictedDigit = null;
      });

      await _runInference();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _runInference() async {
    if (_selectedImage == null || !_isModelLoaded) {
      setState(() => _isProcessing = false);
      return;
    }

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final rawImage = img.decodeImage(bytes);

      if (rawImage == null) {
        setState(() => _isProcessing = false);
        return;
      }

      final result = _classifier?.predictImage(rawImage);

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
          _lastPrediction = result;
          _isProcessing = false;
        });
      } else {
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Inference error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _classifier?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildImageSection(),
              const SizedBox(height: 20),
              _buildButtons(),
              const SizedBox(height: 20),
              _buildResultSection(),
              const SizedBox(height: 16),
              _buildProbabilitiesBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color.fromRGBO(0, 229, 255, 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color.fromRGBO(0, 229, 255, 0.4),
            ),
          ),
          child: const Icon(
            Icons.translate_rounded,
            color: Color(0xFF00E5FF),
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Arabic Digit Recognizer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isModelLoaded
                          ? const Color(0xFF00E5FF)
                          : Colors.orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isModelLoaded ? 'Model ready' : 'Loading model...',
                    style: const TextStyle(
                      color: Color.fromRGBO(255, 255, 255, 0.5),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImageSection() {
    return Container(
      width: double.infinity,
      height: 280,
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _selectedImage != null
              ? const Color.fromRGBO(0, 229, 255, 0.3)
              : const Color.fromRGBO(255, 255, 255, 0.08),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: _isProcessing
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF00E5FF)),
                    SizedBox(height: 16),
                    Text(
                      'Analyzing...',
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  ],
                ),
              )
            : _selectedImage != null
                ? (_lastPrediction != null && _lastPrediction!.digits.isNotEmpty)
                    ? DetectedBoxesView(
                        imageFile: _selectedImage!,
                        prediction: _lastPrediction!,
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            _selectedImage!,
                            fit: BoxFit.contain,
                          ),
                        ],
                      )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_outlined,
                          size: 56,
                          color: Color.fromRGBO(255, 255, 255, 0.15),
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Take a photo or upload an image\nof a handwritten Arabic digit',
                          style: TextStyle(
                            color: Color.fromRGBO(255, 255, 255, 0.3),
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildButtons() {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            icon: Icons.camera_alt_rounded,
            label: 'Take Photo',
            onTap: _isModelLoaded
                ? () => _pickImage(ImageSource.camera)
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _buildActionButton(
            icon: Icons.photo_library_rounded,
            label: 'Upload Image',
            onTap: _isModelLoaded
                ? () => _pickImage(ImageSource.gallery)
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isEnabled
              ? const Color.fromRGBO(0, 229, 255, 0.1)
              : const Color(0xFF12121A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isEnabled
                ? const Color.fromRGBO(0, 229, 255, 0.4)
                : const Color.fromRGBO(255, 255, 255, 0.05),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isEnabled
                  ? const Color(0xFF00E5FF)
                  : Colors.white24,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? Colors.white : Colors.white24,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF12121A),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _predictedDigit != null
              ? const Color.fromRGBO(0, 229, 255, 0.3)
              : const Color.fromRGBO(255, 255, 255, 0.08),
        ),
      ),
      child: _predictedDigit == null
          ? const Center(
              child: Text(
                'No prediction yet',
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
                const SizedBox(width: 24),
                Container(width: 1, height: 60, color: Colors.white12),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Digit $_latinDigit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
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
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildProbabilitiesBar() {
    if (_probabilities.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 12),
          Row(
            children: List.generate(10, (i) {
              final prob =
                  _probabilities.length > i ? _probabilities[i] : 0.0;
              final isMax = i == _predictedDigit;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      // Bar
                      Container(
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: const Color.fromRGBO(255, 255, 255, 0.05),
                        ),
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: prob.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              color: isMax
                                  ? const Color(0xFF00E5FF)
                                  : const Color.fromRGBO(124, 77, 255, 0.5),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'][i],
                        style: TextStyle(
                          color: isMax
                              ? const Color(0xFF00E5FF)
                              : Colors.white38,
                          fontSize: 13,
                          fontWeight:
                              isMax ? FontWeight.bold : FontWeight.normal,
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
