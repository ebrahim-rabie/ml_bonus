import 'package:flutter/material.dart';
import 'package:flutter_drawing_board/flutter_drawing_board.dart';

/// Custom drawing canvas for handwritten digit input
///
/// Provides a white canvas where users can draw digits
/// with adjustable stroke width and clear functionality.
class DrawingCanvas extends StatefulWidget {
  final Function(Uint8List)? onDrawingChanged;
  final double width;
  final double height;

  const DrawingCanvas({
    super.key,
    this.onDrawingChanged,
    this.width = 280,
    this.height = 280,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  final DrawingController _controller = DrawingController();
  double _strokeWidth = 8.0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void clearCanvas() {
    _controller.clear();
  }

  Future<Uint8List?> getImageData() async {
    final data = await _controller.getImageData();
    return data?.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Canvas Container
        Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: DrawingBoard(
              controller: _controller,
              background: Container(
                width: widget.width,
                height: widget.height,
                color: Colors.white,
              ),
              showDefaultActions: false,
              showDefaultTools: false,
              panAxis: PanAxis.free,
              boardClipBehavior: Clip.hardEdge,
              boardConstrained: false,
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Controls
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Stroke width slider
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Stroke Width: ${_strokeWidth.toInt()}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Slider(
                    value: _strokeWidth,
                    min: 2,
                    max: 20,
                    divisions: 9,
                    label: _strokeWidth.toInt().toString(),
                    onChanged: (value) {
                      setState(() {
                        _strokeWidth = value;
                        _controller.setStyle(
                          strokeWidth: _strokeWidth,
                          color: Colors.black,
                        );
                      });
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(width: 16),

            // Clear button
            ElevatedButton.icon(
              onPressed: clearCanvas,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade100,
                foregroundColor: Colors.red.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}