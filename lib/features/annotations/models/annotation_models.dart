import 'dart:typed_data';
import 'package:flutter/material.dart';

enum ScriptumTool {
  pan,
  pen,
  highlighter,
  eraser,
  image,
}

class NormalizedPoint {
  final double x; // 0.0 to 1.0 relative to page width
  final double y; // 0.0 to 1.0 relative to page height
  final double pressure;

  const NormalizedPoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
  });
}

class InkStroke {
  final List<NormalizedPoint> points;
  final Color color;
  final double size; // Relative to a standard 1000px page width
  final bool isHighlighter;

  InkStroke({
    required this.points,
    required this.color,
    required this.size,
    this.isHighlighter = false,
  });
}

class ImageAnnotation {
  final String id;
  final Uint8List bytes;
  double x; // Normalized 0.0 to 1.0
  double y; // Normalized 0.0 to 1.0
  double width; // Normalized 0.0 to 1.0
  double height; // Normalized 0.0 to 1.0

  ImageAnnotation({
    required this.id,
    required this.bytes,
    this.x = 0.25,
    this.y = 0.25,
    this.width = 0.35,
    this.height = 0.25,
  });
}

class PageAnnotations {
  final List<InkStroke> strokes;
  final List<ImageAnnotation> images;

  PageAnnotations({
    List<InkStroke>? strokes,
    List<ImageAnnotation>? images,
  })  : strokes = strokes ?? [],
        images = images ?? [];

  bool get isEmpty => strokes.isEmpty && images.isEmpty;
}