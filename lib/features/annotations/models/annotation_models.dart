import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

enum ScriptumTool {
  pan,
  pen,
  highlighter,
  eraser,
  image,
}

enum PageOperation {
  rotateClockwise,
  insertAfter,
  delete,
}

class NormalizedPoint {
  final double x;
  final double y;
  final double pressure;

  const NormalizedPoint({
    required this.x,
    required this.y,
    this.pressure = 0.5,
  });

  Map<String, dynamic> toJson() => {
    'x': double.parse(x.toStringAsFixed(5)),
    'y': double.parse(y.toStringAsFixed(5)),
    'p': double.parse(pressure.toStringAsFixed(3)),
  };

  factory NormalizedPoint.fromJson(Map<String, dynamic> json) =>
      NormalizedPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['p'] as num?)?.toDouble() ?? 0.5,
      );
}

class InkStroke {
  final List<NormalizedPoint> points;
  final Color color;
  final double size;
  final bool isHighlighter;

  InkStroke({
    required this.points,
    required this.color,
    required this.size,
    this.isHighlighter = false,
  });

  InkStroke rotatedClockwise() {
    return InkStroke(
      color: color,
      size: size,
      isHighlighter: isHighlighter,
      points: points
          .map(
            (pt) => NormalizedPoint(
          x: 1.0 - pt.y,
          y: pt.x,
          pressure: pt.pressure,
        ),
      )
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
    'c': color.toARGB32(),
    's': size,
    'h': isHighlighter,
    'pts': points.map((p) => p.toJson()).toList(),
  };

  factory InkStroke.fromJson(Map<String, dynamic> json) => InkStroke(
    color: Color(json['c'] as int),
    size: (json['s'] as num).toDouble(),
    isHighlighter: json['h'] as bool? ?? false,
    points: (json['pts'] as List)
        .map((e) => NormalizedPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}

class ImageAnnotation {
  final String id;
  final Uint8List bytes;
  double x;
  double y;
  double width;
  double height;

  ImageAnnotation({
    required this.id,
    required this.bytes,
    this.x = 0.25,
    this.y = 0.25,
    this.width = 0.35,
    this.height = 0.25,
  });

  void rotateClockwise() {
    final oldX = x;
    final oldY = y;
    final oldW = width;
    final oldH = height;
    x = (1.0 - oldY - oldH).clamp(0.0, 1.0);
    y = oldX.clamp(0.0, 1.0);
    width = oldH;
    height = oldW;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'b64': base64Encode(bytes),
    'x': x,
    'y': y,
    'w': width,
    'h': height,
  };

  factory ImageAnnotation.fromJson(Map<String, dynamic> json) =>
      ImageAnnotation(
        id: json['id'] as String,
        bytes: base64Decode(json['b64'] as String),
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        width: (json['w'] as num).toDouble(),
        height: (json['h'] as num).toDouble(),
      );
}

class PageAnnotations {
  final List<InkStroke> strokes;
  final List<InkStroke> redoStrokes;
  final List<ImageAnnotation> images;

  PageAnnotations({
    List<InkStroke>? strokes,
    List<InkStroke>? redoStrokes,
    List<ImageAnnotation>? images,
  })  : strokes = strokes ?? [],
        redoStrokes = redoStrokes ?? [],
        images = images ?? [];

  bool get isEmpty => strokes.isEmpty && images.isEmpty;

  void rotateClockwise() {
    for (int i = 0; i < strokes.length; i++) {
      strokes[i] = strokes[i].rotatedClockwise();
    }
    for (int i = 0; i < redoStrokes.length; i++) {
      redoStrokes[i] = redoStrokes[i].rotatedClockwise();
    }
    for (final img in images) {
      img.rotateClockwise();
    }
  }

  Map<String, dynamic> toJson() => {
    'strokes': strokes.map((s) => s.toJson()).toList(),
    'images': images.map((img) => img.toJson()).toList(),
  };

  factory PageAnnotations.fromJson(Map<String, dynamic> json) =>
      PageAnnotations(
        strokes: (json['strokes'] as List? ?? [])
            .map((e) => InkStroke.fromJson(e as Map<String, dynamic>))
            .toList(),
        images: (json['images'] as List? ?? [])
            .map((e) => ImageAnnotation.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class VirtualPage {
  final int? sourcePageNumber;
  int rotationQuarterTurns;
  final Size pageSize;

  VirtualPage({
    this.sourcePageNumber,
    this.rotationQuarterTurns = 0,
    this.pageSize = const Size(595, 842),
  });

  bool get isBlankPage => sourcePageNumber == null;

  Map<String, dynamic> toJson() => {
    'src': sourcePageNumber,
    'rot': rotationQuarterTurns,
    'w': pageSize.width,
    'h': pageSize.height,
  };

  factory VirtualPage.fromJson(Map<String, dynamic> json) => VirtualPage(
    sourcePageNumber: json['src'] as int?,
    rotationQuarterTurns: json['rot'] as int? ?? 0,
    pageSize: Size(
      (json['w'] as num?)?.toDouble() ?? 595,
      (json['h'] as num?)?.toDouble() ?? 842,
    ),
  );
}