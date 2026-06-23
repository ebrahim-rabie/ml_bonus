import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;

/// Service for TensorFlow Lite model inference
///
/// Model specs:
/// - Input:  [1, 28, 28, 1] float32
/// - Output: [1, 10] float32 (digits 0-9 probabilities)
class TFLiteService {
  static final TFLiteService _instance = TFLiteService._internal();
  factory TFLiteService() => _instance;
  TFLiteService._internal();

  Interpreter? _interpreter;
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;

  /// Model input/output shapes
  static const int inputSize = 28;
  static const int numChannels = 1;
  static const int numClasses = 10;

  /// Load the TFLite model from assets
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/arabic_digit_ann.tflite',
        options: InterpreterOptions()..threads = 4,
      );
      _isLoaded = true;

      // Verify input/output shapes
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final outputShape = _interpreter!.getOutputTensor(0).shape;

      print('TFLite Model Loaded Successfully');
      print('Input shape: $inputShape');
      print('Output shape: $outputShape');

      // Validate shapes
      assert(inputShape[0] == 1, 'Batch size must be 1');
      assert(inputShape[1] == 28, 'Height must be 28');
      assert(inputShape[2] == 28, 'Width must be 28');
      assert(inputShape[3] == 1, 'Channels must be 1');
      assert(outputShape[0] == 1, 'Output batch must be 1');
      assert(outputShape[1] == 10, 'Output classes must be 10');

    } catch (e) {
      print('Error loading TFLite model: $e');
      _isLoaded = false;
      rethrow;
    }
  }

  /// Run inference on a preprocessed image buffer
  ///
  /// [imageBuffer] should be a Float32List of size 28*28*1 = 784
  /// with values normalized to [0.0, 1.0]
  Future<PredictionResult> predict(Float32List imageBuffer) async {
    if (!_isLoaded || _interpreter == null) {
      throw Exception('Model not loaded. Call loadModel() first.');
    }

    // Reshape input: [1, 28, 28, 1]
    final input = imageBuffer.reshape([1, 28, 28, 1]);

    // Output buffer: [1, 10]
    final output = List.generate(1, (_) => List.filled(10, 0.0));

    // Run inference
    _interpreter!.run(input, output);

    // Parse results
    final probabilities = output[0];
    final predictedDigit = _argMax(probabilities);
    final confidence = probabilities[predictedDigit];

    return PredictionResult(
      digit: predictedDigit,
      confidence: confidence,
      probabilities: List<double>.from(probabilities),
    );
  }

  /// Run inference from a file path (image file)
  Future<PredictionResult> predictFromFile(String imagePath) async {
    final bytes = await File(imagePath).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    final processed = ImagePreprocessingService.preprocessImage(image);
    return predict(processed);
  }

  /// Run inference from raw image bytes
  Future<PredictionResult> predictFromBytes(Uint8List bytes) async {
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Failed to decode image');

    final processed = ImagePreprocessingService.preprocessImage(image);
    return predict(processed);
  }

  /// Find index of maximum value
  int _argMax(List<double> list) {
    int maxIndex = 0;
    double maxValue = list[0];
    for (int i = 1; i < list.length; i++) {
      if (list[i] > maxValue) {
        maxValue = list[i];
        maxIndex = i;
      }
    }
    return maxIndex;
  }

  /// Release resources
  void dispose() {
    _interpreter?.close();
    _isLoaded = false;
  }
}

/// Result of a prediction
class PredictionResult {
  final int digit;
  final double confidence;
  final List<double> probabilities;

  PredictionResult({
    required this.digit,
    required this.confidence,
    required this.probabilities,
  });

  String get confidencePercent => '${(confidence * 100).toStringAsFixed(1)}%';

  @override
  String toString() {
    return 'PredictionResult(digit: $digit, confidence: $confidencePercent)';
  }
}

/// Image preprocessing utilities
class ImagePreprocessingService {

  /// Preprocess image for model input
  ///
  /// Steps:
  /// 1. Convert to grayscale
  /// 2. Resize to 28x28
  /// 3. Normalize pixels to [0.0, 1.0]
  /// 4. Flatten to Float32List of size 784
  static Float32List preprocessImage(img.Image sourceImage) {
    // Step 1: Convert to grayscale
    img.Image grayImage = img.grayscale(sourceImage);

    // Step 2: Resize to 28x28
    img.Image resized = img.copyResize(
      grayImage,
      width: 28,
      height: 28,
      interpolation: img.Interpolation.cubic,
    );

    // Step 3 & 4: Extract pixels, normalize, and create Float32List
    final buffer = Float32List(28 * 28);
    int index = 0;

    for (int y = 0; y < 28; y++) {
      for (int x = 0; x < 28; x++) {
        final pixel = resized.getPixel(x, y);
        // Get luminance (grayscale value 0-255)
        final luminance = pixel.r.toInt(); // In grayscale, R=G=B
        // Normalize to [0, 1]
        buffer[index++] = luminance / 255.0;
      }
    }

    return buffer;
  }

  /// Preprocess with inversion (for white-background images)
  static Float32List preprocessImageInverted(img.Image sourceImage) {
    final buffer = preprocessImage(sourceImage);
    // Invert: white background becomes black (0), black digits become white (1)
    for (int i = 0; i < buffer.length; i++) {
      buffer[i] = 1.0 - buffer[i];
    }
    return buffer;
  }

  /// Preprocess drawing canvas data (Uint8List from flutter_drawing_board)
  static Float32List preprocessDrawing(Uint8List pngBytes, {bool invert = true}) {
    final image = img.decodePng(pngBytes);
    if (image == null) throw Exception('Failed to decode drawing');

    if (invert) {
      return preprocessImageInverted(image);
    }
    return preprocessImage(image);
  }
}