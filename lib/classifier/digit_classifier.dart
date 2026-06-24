import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class DigitPrediction {
  const DigitPrediction({
    required this.digit,
    required this.confidence,
    required this.probabilities,
    required this.box,
    required this.modelInput28,
  });

  final int digit;
  final double confidence;
  final List<double> probabilities;
  final DigitBox box;
  final List<List<double>> modelInput28;
}

class MultiDigitPrediction {
  const MultiDigitPrediction({
    required this.text,
    required this.digits,
    required this.imageWidth,
    required this.imageHeight,
  });

  final String text;
  final List<DigitPrediction> digits;
  final int imageWidth;
  final int imageHeight;
}

class DigitBox {
  const DigitBox(this.x, this.y, this.width, this.height);

  final int x;
  final int y;
  final int width;
  final int height;

  int get area => width * height;
}

class ArabicDigitClassifier {
  ArabicDigitClassifier._(this._interpreter);

  final Interpreter _interpreter;

  static const int inputSize = 28;
  static const int digitSize = 20;
  static const bool trainingBackgroundIsWhite = false;

  static Future<ArabicDigitClassifier> create({
    String assetPath = 'assets/model/arabic_digit_mlp_model.tflite',
  }) async {
    final interpreter = await Interpreter.fromAsset(assetPath);
    return ArabicDigitClassifier._(interpreter);
  }

  void close() => _interpreter.close();

  Future<MultiDigitPrediction> predictFile(File file) async {
    final bytes = await file.readAsBytes();
    return predictBytes(bytes);
  }

  MultiDigitPrediction predictBytes(Uint8List bytes) {
    final source = img.decodeImage(bytes);
    if (source == null) {
      throw ArgumentError('Could not decode image bytes.');
    }

    return predictImage(source);
  }

  MultiDigitPrediction predictImage(img.Image source) {
    final mask = _createDigitMask(source);
    final boxes = _detectDigitBoxes(mask);

    if (boxes.isEmpty) {
      return MultiDigitPrediction(
        text: '',
        digits: [],
        imageWidth: source.width,
        imageHeight: source.height,
      );
    }

    final predictions = <DigitPrediction>[];

    for (final box in boxes) {
      final finalImage = _preprocessDigitFromBox(mask, box);
      if (finalImage == null) {
        continue;
      }

      final output = List.generate(1, (_) => List<double>.filled(10, 0));
      final input = _toTfliteInput(finalImage);

      _interpreter.run(input, output);

      final probabilities = output[0];
      var bestDigit = 0;
      var bestConfidence = probabilities[0];

      for (var i = 1; i < probabilities.length; i++) {
        if (probabilities[i] > bestConfidence) {
          bestConfidence = probabilities[i];
          bestDigit = i;
        }
      }

      predictions.add(
        DigitPrediction(
          digit: bestDigit,
          confidence: bestConfidence,
          probabilities: List<double>.from(probabilities),
          box: box,
          modelInput28: finalImage,
        ),
      );
    }

    final text = predictions.map((p) => p.digit.toString()).join();
    return MultiDigitPrediction(
      text: text,
      digits: predictions,
      imageWidth: source.width,
      imageHeight: source.height,
    );
  }

  List<List<List<List<double>>>> _toTfliteInput(List<List<double>> image28) {
    return [
      List.generate(inputSize, (y) {
        return List.generate(inputSize, (x) {
          return [image28[y][x]];
        });
      }),
    ];
  }

  List<List<int>> _createDigitMask(img.Image source, {bool useBlueFirst = true}) {
    final width = source.width;
    final height = source.height;
    List<List<int>>? mask;

    if (useBlueFirst) {
      final blueMask = List.generate(height, (_) => List<int>.filled(width, 0));
      var bluePixels = 0;

      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final pixel = source.getPixel(x, y);
          final hsv = _rgbToHsv(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt());
          final isBlue = hsv.h >= 85 &&
              hsv.h <= 145 &&
              hsv.s >= 35 / 255 &&
              hsv.v >= 30 / 255;

          if (isBlue) {
            blueMask[y][x] = 255;
            bluePixels++;
          }
        }
      }

      final minBluePixels = math.max(20, (0.00002 * width * height).round());
      if (bluePixels >= minBluePixels) {
        mask = blueMask;
      }
    }

    if (mask == null) {
      final gray = _grayscale(source);
      final blurred = _boxBlur(gray, width, height);
      final threshold = _otsuThreshold(blurred);

      mask = List.generate(height, (_) => List<int>.filled(width, 0));
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          mask[y][x] = blurred[y][x] < threshold ? 255 : 0;
        }
      }
    }

    mask = _erode(mask);
    mask = _dilate(mask);
    mask = _dilate(mask);

    return mask;
  }

  List<DigitBox> _detectDigitBoxes(List<List<int>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final area = height * width;
    final mask2 = _dilate(mask);
    final visited = List.generate(height, (_) => List<bool>.filled(width, false));
    final boxes = <DigitBox>[];

    final minArea = math.max(80, area * 0.00008);
    final minHeight = math.max(8, height * 0.018);
    final minWidth = math.max(3, width * 0.004);

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        if (visited[y][x] || mask2[y][x] == 0) {
          continue;
        }

        final component = _floodFill(mask2, visited, x, y);
        final box = component.box;

        if (component.pixelCount < minArea) {
          continue;
        }
        if (box.width < minWidth || box.height < minHeight) {
          continue;
        }
        if (box.width > width * 0.40 || box.height > height * 0.65) {
          continue;
        }
        if (box.x < 5 ||
            box.y < 5 ||
            box.x + box.width > width - 5 ||
            box.y + box.height > height - 5) {
          continue;
        }

        boxes.add(box);
      }
    }

    boxes.sort((a, b) => a.x.compareTo(b.x));
    return boxes;
  }

  List<List<double>>? _preprocessDigitFromBox(
    List<List<int>> mask,
    DigitBox box, {
    int padding = 8,
  }) {
    final imageHeight = mask.length;
    final imageWidth = mask[0].length;

    final x1 = math.max(box.x - padding, 0);
    final y1 = math.max(box.y - padding, 0);
    final x2 = math.min(box.x + box.width + padding, imageWidth);
    final y2 = math.min(box.y + box.height + padding, imageHeight);

    var minX = x2;
    var minY = y2;
    var maxX = x1;
    var maxY = y1;
    var found = false;

    for (var y = y1; y < y2; y++) {
      for (var x = x1; x < x2; x++) {
        if (mask[y][x] > 0) {
          found = true;
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
    }

    if (!found) {
      return null;
    }

    final digitWidth = maxX - minX + 1;
    final digitHeight = maxY - minY + 1;
    final squareSize = math.max(digitWidth, digitHeight);
    final square = List.generate(squareSize, (_) => List<int>.filled(squareSize, 0));
    final xOffset = (squareSize - digitWidth) ~/ 2;
    final yOffset = (squareSize - digitHeight) ~/ 2;

    for (var y = 0; y < digitHeight; y++) {
      for (var x = 0; x < digitWidth; x++) {
        square[y + yOffset][x + xOffset] = mask[minY + y][minX + x];
      }
    }

    final resized = _resizeMask(square, digitSize, digitSize);
    var finalImage = List.generate(inputSize, (_) => List<double>.filled(inputSize, 0));
    const start = (inputSize - digitSize) ~/ 2;

    for (var y = 0; y < digitSize; y++) {
      for (var x = 0; x < digitSize; x++) {
        finalImage[y + start][x + start] = resized[y][x] / 255.0;
      }
    }

    finalImage = _centerByMass(finalImage);
    return _matchTrainingPolarity(finalImage);
  }

  List<List<double>> _centerByMass(List<List<double>> image28) {
    var totalWeight = 0.0;
    var weightedX = 0.0;
    var weightedY = 0.0;

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final value = image28[y][x];
        if (value > 0.05) {
          totalWeight += value;
          weightedX += x * value;
          weightedY += y * value;
        }
      }
    }

    if (totalWeight == 0) {
      return image28;
    }

    final centerX = weightedX / totalWeight;
    final centerY = weightedY / totalWeight;
    final shiftX = (14 - centerX).round();
    final shiftY = (14 - centerY).round();
    final shifted = List.generate(inputSize, (_) => List<double>.filled(inputSize, 0));

    for (var y = 0; y < inputSize; y++) {
      for (var x = 0; x < inputSize; x++) {
        final nx = x + shiftX;
        final ny = y + shiftY;
        if (nx >= 0 && nx < inputSize && ny >= 0 && ny < inputSize) {
          shifted[ny][nx] = image28[y][x];
        }
      }
    }

    return shifted;
  }

  List<List<double>> _matchTrainingPolarity(List<List<double>> image28) {
    if (!trainingBackgroundIsWhite) {
      return image28;
    }

    return List.generate(inputSize, (y) {
      return List.generate(inputSize, (x) => 1.0 - image28[y][x]);
    });
  }

  List<List<int>> _grayscale(img.Image source) {
    return List.generate(source.height, (y) {
      return List.generate(source.width, (x) {
        final pixel = source.getPixel(x, y);
        return (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b).round();
      });
    });
  }

  List<List<int>> _boxBlur(List<List<int>> gray, int width, int height) {
    final blurred = List.generate(height, (_) => List<int>.filled(width, 0));

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var sum = 0;
        var count = 0;

        for (var ky = -2; ky <= 2; ky++) {
          for (var kx = -2; kx <= 2; kx++) {
            final nx = x + kx;
            final ny = y + ky;
            if (nx >= 0 && nx < width && ny >= 0 && ny < height) {
              sum += gray[ny][nx];
              count++;
            }
          }
        }

        blurred[y][x] = (sum / count).round();
      }
    }

    return blurred;
  }

  int _otsuThreshold(List<List<int>> gray) {
    final histogram = List<int>.filled(256, 0);
    final height = gray.length;
    final width = gray[0].length;
    final total = width * height;

    for (final row in gray) {
      for (final value in row) {
        histogram[value]++;
      }
    }

    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * histogram[i];
    }

    var sumBackground = 0.0;
    var weightBackground = 0;
    var maxVariance = -1.0;
    var threshold = 0;

    for (var i = 0; i < 256; i++) {
      weightBackground += histogram[i];
      if (weightBackground == 0) {
        continue;
      }

      final weightForeground = total - weightBackground;
      if (weightForeground == 0) {
        break;
      }

      sumBackground += i * histogram[i];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sum - sumBackground) / weightForeground;
      final variance = weightBackground *
          weightForeground *
          math.pow(meanBackground - meanForeground, 2);

      if (variance > maxVariance) {
        maxVariance = variance.toDouble();
        threshold = i;
      }
    }

    return threshold;
  }

  List<List<int>> _erode(List<List<int>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final output = List.generate(height, (_) => List<int>.filled(width, 0));

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var keep = true;
        for (var ky = 0; ky < 2; ky++) {
          for (var kx = 0; kx < 2; kx++) {
            final nx = x + kx;
            final ny = y + ky;
            if (nx >= width || ny >= height || mask[ny][nx] == 0) {
              keep = false;
            }
          }
        }
        output[y][x] = keep ? 255 : 0;
      }
    }

    return output;
  }

  List<List<int>> _dilate(List<List<int>> mask) {
    final height = mask.length;
    final width = mask[0].length;
    final output = List.generate(height, (_) => List<int>.filled(width, 0));

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var value = 0;
        for (var ky = 0; ky < 2; ky++) {
          for (var kx = 0; kx < 2; kx++) {
            final nx = x - kx;
            final ny = y - ky;
            if (nx >= 0 && ny >= 0 && mask[ny][nx] > 0) {
              value = 255;
            }
          }
        }
        output[y][x] = value;
      }
    }

    return output;
  }

  _Component _floodFill(
    List<List<int>> mask,
    List<List<bool>> visited,
    int startX,
    int startY,
  ) {
    final height = mask.length;
    final width = mask[0].length;
    final queueX = <int>[startX];
    final queueY = <int>[startY];
    visited[startY][startX] = true;

    var minX = startX;
    var minY = startY;
    var maxX = startX;
    var maxY = startY;
    var pixelCount = 0;
    var index = 0;

    while (index < queueX.length) {
      final x = queueX[index];
      final y = queueY[index];
      index++;
      pixelCount++;

      minX = math.min(minX, x);
      minY = math.min(minY, y);
      maxX = math.max(maxX, x);
      maxY = math.max(maxY, y);

      const offsets = [
        [-1, 0],
        [1, 0],
        [0, -1],
        [0, 1],
      ];

      for (final offset in offsets) {
        final nx = x + offset[0];
        final ny = y + offset[1];
        if (nx < 0 || nx >= width || ny < 0 || ny >= height) {
          continue;
        }
        if (visited[ny][nx] || mask[ny][nx] == 0) {
          continue;
        }

        visited[ny][nx] = true;
        queueX.add(nx);
        queueY.add(ny);
      }
    }

    return _Component(
      DigitBox(minX, minY, maxX - minX + 1, maxY - minY + 1),
      pixelCount,
    );
  }

  List<List<int>> _resizeMask(List<List<int>> source, int targetWidth, int targetHeight) {
    final sourceHeight = source.length;
    final sourceWidth = source[0].length;
    final result = List.generate(targetHeight, (_) => List<int>.filled(targetWidth, 0));

    for (var y = 0; y < targetHeight; y++) {
      for (var x = 0; x < targetWidth; x++) {
        final sx = ((x + 0.5) * sourceWidth / targetWidth - 0.5).round();
        final sy = ((y + 0.5) * sourceHeight / targetHeight - 0.5).round();
        final sourceY = sy.clamp(0, sourceHeight - 1).toInt();
        final sourceX = sx.clamp(0, sourceWidth - 1).toInt();
        result[y][x] = source[sourceY][sourceX];
      }
    }

    return result;
  }

  _Hsv _rgbToHsv(int r, int g, int b) {
    final rf = r / 255.0;
    final gf = g / 255.0;
    final bf = b / 255.0;
    final maxValue = math.max(rf, math.max(gf, bf));
    final minValue = math.min(rf, math.min(gf, bf));
    final delta = maxValue - minValue;

    var hue = 0.0;
    if (delta != 0) {
      if (maxValue == rf) {
        hue = 60 * (((gf - bf) / delta) % 6);
      } else if (maxValue == gf) {
        hue = 60 * (((bf - rf) / delta) + 2);
      } else {
        hue = 60 * (((rf - gf) / delta) + 4);
      }
    }

    if (hue < 0) {
      hue += 360;
    }

    final saturation = maxValue == 0 ? 0.0 : delta / maxValue;
    return _Hsv(hue / 2, saturation, maxValue);
  }
}

class _Component {
  const _Component(this.box, this.pixelCount);

  final DigitBox box;
  final int pixelCount;
}

class _Hsv {
  const _Hsv(this.h, this.s, this.v);

  final double h;
  final double s;
  final double v;
}
