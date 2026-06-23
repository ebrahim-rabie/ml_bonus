# Arabic Digit Recognizer

A Flutter mobile application for **recognizing handwritten Arabic digits (0-9)** using on-device machine learning with TensorFlow Lite (TFLite).

## Overview

This app uses a pre-trained MLP neural network model to classify handwritten Arabic numerals in real-time. Users can capture or select images from their device, and the app displays the predicted digit along with confidence scores.

### Key Features
- 🎥 Real-time camera capture for digit input
- 🖼️ Image picker integration (gallery/camera roll)
- 🚀 Fast on-device inference using TFLite
- 🎯 Multi-digit detection and bounding box visualization
- 🎨 Dark theme optimized UI with modern design
- ✅ Permissioned camera and storage access

---

## Project Structure

```
lib/
├── main.dart                    # App entry point and theme config
├── screens/
│   ├── home_screen.dart        # Main interface (image selection/upload)
│   └── camera_screen.dart      # Camera capture and live preview
├── classifier/
│   └── digit_classifier.dart   # TFLite model interface and inference logic
└── widgets/
    └── detected_boxes_view.dart # Visualization of detection results

assets/
└── model/
    └── arabic_digit_mlp_model.tflite  # Pre-trained MLP model
```

### Model Details

- **Model Name**: `arabic_digit_mlp_model.tflite`
- **Architecture**: Multi-layer Perceptron (MLP)
- **Input Shape**: 28×28 grayscale image
- **Output Classes**: 10 (digits 0-9)
- **Quantization**: [Check TFLite model properties]
- **Size**: [Typically < 1 MB for digit classification]

---

## Setup Instructions

### Prerequisites
- Flutter SDK 3.0+ (check with `flutter --version`)
- Dart 3.0+
- Android SDK (for Android development) or Xcode (for iOS)
- Device/emulator with camera access

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd ml_bonus
   ```

2. **Get dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### Android-Specific Setup
   - Ensure camera permissions are granted in `android/app/src/main/AndroidManifest.xml`
   - SDK version compatibility may require Gradle adjustments

### iOS-Specific Setup
   - Ensure camera permissions are added to `ios/Runner/Info.plist`
   - Build settings may require ARM64 architecture configuration

---

## Usage

### Capturing a Digit

1. **Launch the app** → Main home screen appears
2. **Choose input method**:
   - Tap camera button → Open camera for live capture
   - Tap gallery button → Select image from device storage
3. **Position digit** clearly in frame (for best results: well-lit, centered, 28×28 pixel equivalent)
4. **Capture/Select** → Image is sent to classifier
5. **View results** → Predicted digit and bounding boxes appear

### Understanding Results

- **Predicted Digit**: Top detection (highest confidence)
- **Confidence Score**: 0.0–1.0 (1.0 = 100% confidence)
- **Bounding Boxes**: Green boxes around detected digits
- **Multiple Detections**: If multi-digit mode enabled, see all detected digits

---

## Architecture

### Data Flow

```
User Input (Camera/Gallery)
    ↓
Image Preprocessing (Resize → Grayscale → Normalize)
    ↓
TFLite Model Inference
    ↓
Output Tensor (10 class probabilities)
    ↓
Post-processing (argmax → confidence)
    ↓
UI Rendering (Result display + bounding boxes)
```

### Key Components

**digit_classifier.dart** - Model Interface
- Loads the TFLite model on initialization
- Provides `classifyImage()` method for inference
- Handles input tensor normalization
- Returns predicted class and confidence

**home_screen.dart** - Image Selection UI
- Image picker integration
- Gallery/Camera selection options
- Displays classification results

**camera_screen.dart** - Live Camera Feed
- Real-time camera preview
- Capture button for snapshot
- Optional live inference mode

**detected_boxes_view.dart** - Result Visualization
- Renders bounding boxes for detected digits
- Overlays confidence labels
- Handles multi-digit display

---

## Troubleshooting

### Model Not Loading
- **Error**: "Model not found" or "Unable to load model"
- **Fix**: Verify `assets/model/arabic_digit_mlp_model.tflite` exists
- **Check**: Ensure pubspec.yaml declares the asset path

### Poor Accuracy on Predictions
- **Cause**: Image quality, lighting, or digit orientation
- **Fix**: Ensure digit is centered, well-lit, and similar to training data (standard Arabic numerals)
- **Tip**: Training data was likely 28×28 grayscale; improve preprocessing if needed

### Camera Permission Denied
- **Fix**: Grant camera permission in device settings under App Permissions
- **Android**: Settings → Apps → Arabic Digit Recognizer → Permissions → Camera
- **iOS**: Settings → Privacy → Camera → Arabic Digit Recognizer → Allow

### High Memory Usage
- **Cause**: Model kept in memory or multiple inference calls queued
- **Fix**: Dispose of classifier properly when screen changes
- **Optimization**: Consider model quantization further or inference batching

### Inference Too Slow
- **Check**: Are you running on a real device (not emulator)?
- **Emulator Performance**: Use a high-performance AVD or physical device for real-world testing
- **GPU Acceleration**: TFLite GPU delegate may be available (requires setup)

---

## Development

### Adding/Updating the Model

1. **Export new model** (from training pipeline) as `.tflite`
2. **Update path** in `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/model/arabic_digit_mlp_model.tflite
   ```
3. **Update model specs** in code comments if input/output shape changes
4. **Test** new model with diverse digit samples

### Customizing the UI Theme

Dark theme settings are defined in `main.dart`:
```dart
theme: ThemeData.dark().copyWith(
  scaffoldBackgroundColor: const Color(0xFF0A0A0F),
  colorScheme: const ColorScheme.dark(
    primary: Color(0xFF00E5FF),      // Cyan
    secondary: Color(0xFF7C4DFF),    // Purple
    surface: Color(0xFF12121A),      // Dark surface
  ),
)
```

Modify colors in the `ColorScheme.dark()` constructor.

### Extending to Multi-Class Recognition

To recognize handwritten text beyond digits:
1. Retrain model on expanded dataset (letters, punctuation, etc.)
2. Update output tensor size (e.g., 10 → 36+ classes)
3. Adjust label mapping in `digit_classifier.dart`
4. Update UI to display text instead of single digit

---

## Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `tflite_flutter` | ^0.11.0 | TensorFlow Lite inference |
| `image_picker` | ^1.0.7 | Camera and gallery access |
| `image` | ^4.1.7 | Image processing (resize, color conversion) |
| `permission_handler` | ^11.3.0 | Runtime permission requests |
| `flutter` | SDK | UI framework |

---

## Performance Notes

- **Model Size**: ~200–500 KB (typical for digit MLP)
- **Inference Time**: ~10–50 ms per image (on modern mobile devices)
- **Latency**: Depends on device GPU; can be improved with quantization or GPU delegates
- **Memory**: < 50 MB typical app size

---

## Known Limitations

- Single-digit classification per inference (can be extended for multi-digit)
- Input required to be 28×28 grayscale equivalent after preprocessing
- No support for cursive or connected digit writing
- No offline learning or model retraining on-device

---

## Future Enhancements

- [ ] Add multi-digit detection (segmentation then classification)
- [ ] GPU acceleration via TFLite GPU delegate
- [ ] Batch inference for image sequences
- [ ] Custom digit training/fine-tuning UI
- [ ] Export predictions to CSV/logs
- [ ] Support for other Arabic handwritten characters (letters, special symbols)

---

## Resources

- [TensorFlow Lite Documentation](https://www.tensorflow.org/lite)
- [Flutter Camera & Image Picker Guides](https://pub.dev/packages/image_picker)
- [TFLite Flutter Package](https://pub.dev/packages/tflite_flutter)
- [Arabic Numeral Recognition Research](https://scholar.google.com/scholar?q=arabic+digit+recognition)

---

## License

[Specify your license here - e.g., MIT, Apache 2.0]

## Contact & Support

For issues, questions, or contributions, please open an issue on the repository or contact the development team.
