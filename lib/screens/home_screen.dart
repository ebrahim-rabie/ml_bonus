import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:ml_bonus/services/tflite_service.dart';
import 'package:ml_bonus/widgets/drawing_canvas.dart';
import 'package:ml_bonus/widgets/prediction_card.dart';


/// Main screen of the Arabic Digit Recognition app
///
/// Features:
/// - Drawing canvas for handwritten input
/// - Gallery image upload
/// - Real-time prediction display
/// - Confidence visualization
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TFLiteService _tfliteService = TFLiteService();
  final ImagePicker _imagePicker = ImagePicker();
  final GlobalKey<DrawingCanvasState> _canvasKey = GlobalKey<DrawingCanvasState>();

  bool _isModelLoading = true;
  bool _isPredicting = false;
  PredictionResult? _predictionResult;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  @override
  void dispose() {
    _tfliteService.dispose();
    super.dispose();
  }

  /// Load TFLite model on startup
  Future<void> _loadModel() async {
    try {
      await _tfliteService.loadModel();
      setState(() {
        _isModelLoading = false;
      });
    } catch (e) {
      setState(() {
        _isModelLoading = false;
        _errorMessage = 'Failed to load model: $e\n\n'
            'Please ensure arabic_digit_ann.tflite is in assets/model/';
      });
    }
  }

  /// Predict from drawing canvas
  Future<void> _predictFromDrawing() async {
    if (!_tfliteService.isLoaded) {
      Fluttertoast.showToast(msg: 'Model not loaded yet');
      return;
    }

    setState(() {
      _isPredicting = true;
      _predictionResult = null;
    });

    try {
      final imageData = await _canvasKey.currentState?.getImageData();
      if (imageData == null) {
        Fluttertoast.showToast(msg: 'Canvas is empty');
        setState(() => _isPredicting = false);
        return;
      }

      // Preprocess drawing (invert colors: white bg -> black bg)
      final processed = ImagePreprocessingService.preprocessDrawing(imageData, invert: true);

      // Run prediction
      final result = await _tfliteService.predict(processed);

      setState(() {
        _predictionResult = result;
        _isPredicting = false;
      });

      Fluttertoast.showToast(
        msg: 'Predicted: ${result.digit} (${result.confidencePercent})',
        toastLength: Toast.LENGTH_SHORT,
      );

    } catch (e) {
      setState(() => _isPredicting = false);
      Fluttertoast.showToast(msg: 'Prediction error: $e');
    }
  }

  /// Predict from gallery image
  Future<void> _predictFromGallery() async {
    if (!_tfliteService.isLoaded) {
      Fluttertoast.showToast(msg: 'Model not loaded yet');
      return;
    }

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      setState(() {
        _isPredicting = true;
        _predictionResult = null;
      });

      final bytes = await pickedFile.readAsBytes();
      final result = await _tfliteService.predictFromBytes(bytes);

      setState(() {
        _predictionResult = result;
        _isPredicting = false;
      });

      Fluttertoast.showToast(
        msg: 'Predicted: ${result.digit} (${result.confidencePercent})',
        toastLength: Toast.LENGTH_SHORT,
      );

    } catch (e) {
      setState(() => _isPredicting = false);
      Fluttertoast.showToast(msg: 'Image prediction error: $e');
    }
  }

  /// Predict from camera
  Future<void> _predictFromCamera() async {
    if (!_tfliteService.isLoaded) {
      Fluttertoast.showToast(msg: 'Model not loaded yet');
      return;
    }

    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 90,
      );

      if (pickedFile == null) return;

      setState(() {
        _isPredicting = true;
        _predictionResult = null;
      });

      final bytes = await pickedFile.readAsBytes();
      final result = await _tfliteService.predictFromBytes(bytes);

      setState(() {
        _predictionResult = result;
        _isPredicting = false;
      });

    } catch (e) {
      setState(() => _isPredicting = false);
      Fluttertoast.showToast(msg: 'Camera prediction error: $e');
    }
  }

  /// Clear all inputs and results
  void _clearAll() {
    _canvasKey.currentState?.clearCanvas();
    setState(() {
      _predictionResult = null;
      _errorMessage = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Show loading screen while model loads
    if (_isModelLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Text(
                'Loading AI Model...',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Arabic Digit Recognition',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Show error screen if model failed to load
    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: theme.textTheme.headlineSmall?.copyWith(color: Colors.red),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _loadModel,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main app screen
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome),
            SizedBox(width: 8),
            Text('Arabic Digit AI'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Title section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Handwritten Arabic Digit Recognition',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Draw a digit (٠-٩) or upload an image',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Drawing Canvas
            DrawingCanvas(
              key: _canvasKey,
              width: 280,
              height: 280,
            ),

            const SizedBox(height: 20),

            // Action Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Predict from drawing
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isPredicting ? null : _predictFromDrawing,
                    icon: _isPredicting
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.psychology),
                    label: Text(_isPredicting ? 'Analyzing...' : 'Predict'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                // Upload from gallery
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isPredicting ? null : _predictFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Secondary actions
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Camera button
                TextButton.icon(
                  onPressed: _isPredicting ? null : _predictFromCamera,
                  icon: const Icon(Icons.camera_alt, size: 20),
                  label: const Text('Camera'),
                ),

                const SizedBox(width: 16),

                // Clear button
                TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.clear_all, size: 20),
                  label: const Text('Clear All'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade400,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Prediction Result Card
            PredictionCard(
              result: _predictionResult,
              isLoading: _isPredicting,
            ),

            const SizedBox(height: 32),

            // Footer
            Text(
              'Powered by TensorFlow Lite | ANN Model',
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.grey.shade500,
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Show app info dialog
  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info),
            SizedBox(width: 8),
            Text('About'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Arabic Handwritten Digit Recognition',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'This app uses a Fully Connected Neural Network (ANN) '
                  'to recognize handwritten Arabic digits (0-9).',
            ),
            SizedBox(height: 12),
            Text('Model Details:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Input: 28×28 grayscale image'),
            Text('• Architecture: Flatten → Dense(256) → Dense(128) → Dense(64) → Dense(10)'),
            Text('• Output: 10 class probabilities'),
            SizedBox(height: 12),
            Text('Tips:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('• Draw digits clearly in the center'),
            Text('• Use thick strokes for better recognition'),
            Text('• Ensure good contrast'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}