import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import '../../../core/theme/scriptum_theme.dart';
import '../models/annotation_models.dart';

class PageAnnotationOverlay extends StatefulWidget {
  final Size pageSize;
  final PageAnnotations annotations;
  final ScriptumTool activeTool;
  final Color activeColor;
  final double activeStrokeSize;
  final VoidCallback onAnnotationsChanged;

  const PageAnnotationOverlay({
    super.key,
    required this.pageSize,
    required this.annotations,
    required this.activeTool,
    required this.activeColor,
    required this.activeStrokeSize,
    required this.onAnnotationsChanged,
  });

  @override
  State<PageAnnotationOverlay> createState() => _PageAnnotationOverlayState();
}

class _PageAnnotationOverlayState extends State<PageAnnotationOverlay> {
  InkStroke? _currentStroke;

  bool get _isDrawingMode =>
      widget.activeTool == ScriptumTool.pen ||
          widget.activeTool == ScriptumTool.highlighter ||
          widget.activeTool == ScriptumTool.eraser;

  void _handlePointerDown(PointerDownEvent event) {
    if (!_isDrawingMode) return;

    final normX = (event.localPosition.dx / widget.pageSize.width).clamp(0.0, 1.0);
    final normY = (event.localPosition.dy / widget.pageSize.height).clamp(0.0, 1.0);

    if (widget.activeTool == ScriptumTool.eraser) {
      _eraseNear(normX, normY);
      return;
    }

    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final pressure = isStylus ? event.pressure.clamp(0.1, 1.0) : 0.5;

    setState(() {
      _currentStroke = InkStroke(
        points: [NormalizedPoint(x: normX, y: normY, pressure: pressure)],
        color: widget.activeColor,
        size: widget.activeTool == ScriptumTool.highlighter
            ? widget.activeStrokeSize * 3.2
            : widget.activeStrokeSize,
        isHighlighter: widget.activeTool == ScriptumTool.highlighter,
      );
    });
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isDrawingMode) return;

    final normX = (event.localPosition.dx / widget.pageSize.width).clamp(0.0, 1.0);
    final normY = (event.localPosition.dy / widget.pageSize.height).clamp(0.0, 1.0);

    if (widget.activeTool == ScriptumTool.eraser) {
      _eraseNear(normX, normY);
      return;
    }

    final stroke = _currentStroke;
    if (stroke == null) return;

    final isStylus = event.kind == PointerDeviceKind.stylus ||
        event.kind == PointerDeviceKind.invertedStylus;
    final pressure = isStylus ? event.pressure.clamp(0.1, 1.0) : 0.5;

    setState(() {
      stroke.points.add(
        NormalizedPoint(x: normX, y: normY, pressure: pressure),
      );
    });
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_currentStroke != null) {
      setState(() {
        widget.annotations.strokes.add(_currentStroke!);
        _currentStroke = null;
      });
      widget.onAnnotationsChanged();
    }
  }

  void _eraseNear(double normX, double normY) {
    const eraseThreshold = 0.03; // 3% of page dimension
    final beforeCount = widget.annotations.strokes.length;

    widget.annotations.strokes.removeWhere((stroke) {
      return stroke.points.any((pt) {
        final dx = pt.x - normX;
        final dy = pt.y - normY;
        return (dx * dx + dy * dy) < (eraseThreshold * eraseThreshold);
      });
    });

    if (widget.annotations.strokes.length != beforeCount) {
      setState(() {});
      widget.onAnnotationsChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.pageSize.width,
      height: widget.pageSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 1. Inserted Draggable & Resizable Images
          ...widget.annotations.images.map((img) {
            final left = img.x * widget.pageSize.width;
            final top = img.y * widget.pageSize.height;
            final width = img.width * widget.pageSize.width;
            final height = img.height * widget.pageSize.height;

            return Positioned(
              left: left,
              top: top,
              width: width,
              height: height,
              child: GestureDetector(
                onPanUpdate: (details) {
                  setState(() {
                    img.x = (img.x + details.delta.dx / widget.pageSize.width)
                        .clamp(0.0, 1.0 - img.width);
                    img.y = (img.y + details.delta.dy / widget.pageSize.height)
                        .clamp(0.0, 1.0 - img.height);
                  });
                  widget.onAnnotationsChanged();
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: ScriptumTheme.cyanGlow.withValues(alpha: 0.7),
                          width: 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: Image.memory(
                          img.bytes,
                          width: width,
                          height: height,
                          fit: BoxFit.fill,
                        ),
                      ),
                    ),
                    // Delete Image Button
                    Positioned(
                      top: -10,
                      right: -10,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            widget.annotations.images.removeWhere(
                                  (e) => e.id == img.id,
                            );
                          });
                          widget.onAnnotationsChanged();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: ScriptumTheme.dangerRed,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Bottom-Right Resize Handle
                    Positioned(
                      bottom: -10,
                      right: -10,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            img.width = (img.width +
                                details.delta.dx / widget.pageSize.width)
                                .clamp(0.08, 0.95);
                            img.height = (img.height +
                                details.delta.dy / widget.pageSize.height)
                                .clamp(0.08, 0.95);
                          });
                          widget.onAnnotationsChanged();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: const BoxDecoration(
                            color: ScriptumTheme.cyanGlow,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.open_in_full_rounded,
                            size: 12,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          // 2. Freehand Stylus & Highlighter Vector Canvas
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_isDrawingMode,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _handlePointerDown,
                onPointerMove: _handlePointerMove,
                onPointerUp: _handlePointerUp,
                child: CustomPaint(
                  painter: _FreehandCalligraphyPainter(
                    strokes: widget.annotations.strokes,
                    currentStroke: _currentStroke,
                    pageSize: widget.pageSize,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FreehandCalligraphyPainter extends CustomPainter {
  final List<InkStroke> strokes;
  final InkStroke? currentStroke;
  final Size pageSize;

  _FreehandCalligraphyPainter({
    required this.strokes,
    required this.currentStroke,
    required this.pageSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      _drawStroke(canvas, stroke);
    }
    if (currentStroke != null) {
      _drawStroke(canvas, currentStroke!);
    }
  }

  void _drawStroke(Canvas canvas, InkStroke stroke) {
    if (stroke.points.isEmpty) return;

    final scaleFactor = pageSize.width / 1000.0;
    final pointVectors = stroke.points
        .map(
          (p) => PointVector(
        p.x * pageSize.width,
        p.y * pageSize.height,
        p.pressure,
      ),
    )
        .toList();

    final outlinePoints = getStroke(
      pointVectors,
      options: StrokeOptions(
        size: stroke.size * scaleFactor,
        thinning: stroke.isHighlighter ? 0.0 : 0.65,
        smoothing: 0.55,
        streamline: 0.5,
        simulatePressure: false,
      ),
    );

    if (outlinePoints.isEmpty) return;

    final path = Path();
    if (outlinePoints.length == 1) {
      path.addOval(
        Rect.fromCircle(
          center: outlinePoints.first,
          radius: (stroke.size * scaleFactor) / 2,
        ),
      );
    } else {
      path.moveTo(outlinePoints.first.dx, outlinePoints.first.dy);
      for (int i = 0; i < outlinePoints.length - 1; i++) {
        final p0 = outlinePoints[i];
        final p1 = outlinePoints[i + 1];
        path.quadraticBezierTo(
          p0.dx,
          p0.dy,
          (p0.dx + p1.dx) / 2,
          (p0.dy + p1.dy) / 2,
        );
      }
    }

    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = stroke.isHighlighter
          ? stroke.color.withValues(alpha: 0.35)
          : stroke.color
      ..blendMode =
      stroke.isHighlighter ? BlendMode.multiply : BlendMode.srcOver;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _FreehandCalligraphyPainter oldDelegate) => true;
}