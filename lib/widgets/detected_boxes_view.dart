import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../classifier/digit_classifier.dart';

class DetectedBoxesView extends StatelessWidget {
  const DetectedBoxesView({
    super.key,
    required this.imageFile,
    required this.prediction,
  });

  final File imageFile;
  final MultiDigitPrediction prediction;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Detected Boxes',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Final Prediction: ${prediction.text}',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: const Color(0xFF00E5FF),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Flexible(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final imageSize = Size(
                  prediction.imageWidth.toDouble(),
                  prediction.imageHeight.toDouble(),
                );
                final fitted = _containSize(
                  imageSize,
                  Size(constraints.maxWidth, constraints.maxHeight),
                );

                return Center(
                  child: SizedBox(
                    width: fitted.width,
                    height: fitted.height,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          imageFile,
                          fit: BoxFit.fill,
                        ),
                        CustomPaint(
                          painter: DetectedBoxesPainter(
                            prediction: prediction,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Size _containSize(Size source, Size bounds) {
    if (source.width <= 0 ||
        source.height <= 0 ||
        bounds.width <= 0 ||
        bounds.height <= 0) {
      return Size.zero;
    }

    final scale = math.min(
      bounds.width / source.width,
      bounds.height / source.height,
    );

    return Size(source.width * scale, source.height * scale);
  }
}

class DetectedBoxesPainter extends CustomPainter {
  const DetectedBoxesPainter({
    required this.prediction,
  });

  final MultiDigitPrediction prediction;

  @override
  void paint(Canvas canvas, Size size) {
    if (prediction.imageWidth <= 0 || prediction.imageHeight <= 0) {
      return;
    }

    final scaleX = size.width / prediction.imageWidth;
    final scaleY = size.height / prediction.imageHeight;

    final boxPaint = Paint()
      ..color = const Color(0xFF39FF14)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (final digit in prediction.digits) {
      final box = digit.box;
      final rect = Rect.fromLTWH(
        box.x * scaleX,
        box.y * scaleY,
        box.width * scaleX,
        box.height * scaleY,
      );

      canvas.drawRect(rect, boxPaint);
      _drawLabel(
        canvas,
        '${digit.digit}:${(digit.confidence * 100).toStringAsFixed(0)}%',
        Offset(rect.left, math.max(0, rect.top - 18)),
      );
    }
  }

  void _drawLabel(Canvas canvas, String text, Offset offset) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF39FF14),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          backgroundColor: Colors.black45, // Add background to text to make it readable
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    textPainter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant DetectedBoxesPainter oldDelegate) {
    return oldDelegate.prediction != prediction;
  }
}
