import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:perfect_freehand/perfect_freehand.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

import '../../annotations/models/annotation_models.dart';

class ExportCancelledException implements Exception {
  @override
  String toString() => 'Export cancelled by user';
}

class ExportCancelToken {
  bool _isCancelled = false;
  bool get isCancelled => _isCancelled;
  void cancel() => _isCancelled = true;
}

class PdfExportService {
  /// Streams page-by-page using valid PNG streams with low RAM footprint and instant cancellation
  static Future<String> exportFlattenedPdf({
    required String sourceFilePath,
    required Map<int, PageAnnotations> pageAnnotations,
    required List<VirtualPage> virtualPages,
    required void Function(int current, int total) onProgress,
    required ExportCancelToken cancelToken,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/Scriptum_Annotated_$timestamp.pdf';

    final pdfiumDoc = await PdfDocument.openFile(sourceFilePath);
    final outDoc = sf.PdfDocument();
    outDoc.pageSettings.margins.all = 0;
    outDoc.compressionLevel = sf.PdfCompressionLevel.best;

    final total = virtualPages.length;

    try {
      for (int i = 0; i < total; i++) {
        if (cancelToken.isCancelled) {
          throw ExportCancelledException();
        }

        final displayPageNum = i + 1;
        onProgress(displayPageNum, total);

        final vPage = virtualPages[i];
        final annotations = pageAnnotations[displayPageNum];
        final hasEdits = (annotations != null && !annotations.isEmpty) ||
            (vPage.rotationQuarterTurns % 4 != 0) ||
            vPage.isBlankPage;

        final pageWidth = vPage.pageSize.width;
        final pageHeight = vPage.pageSize.height;

        final isRotatedSideways = (vPage.rotationQuarterTurns % 2) == 1;
        final targetWidth = isRotatedSideways ? pageHeight : pageWidth;
        final targetHeight = isRotatedSideways ? pageWidth : pageHeight;

        outDoc.pageSettings.size = ui.Size(targetWidth, targetHeight);
        final outPage = outDoc.pages.add();

        // Memory-safe scale: 1.4x on annotated pages, 1.1x on untouched pages
        // Prevents Dart heap OOM while keeping handwriting razor-sharp
        final renderScale = hasEdits ? 1.4 : 1.1;

        if (!vPage.isBlankPage) {
          final srcPage = pdfiumDoc.pages[vPage.sourcePageNumber! - 1];
          final pageImage = await srcPage.render(
            fullWidth: srcPage.width * renderScale,
            fullHeight: srcPage.height * renderScale,
          );

          if (pageImage != null) {
            final uiImage = await pageImage.createImage();
            pageImage.dispose();

            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);

            canvas.drawRect(
              Rect.fromLTWH(0, 0, targetWidth, targetHeight),
              Paint()..color = Colors.white,
            );

            canvas.save();
            if (vPage.rotationQuarterTurns % 4 != 0) {
              canvas.translate(targetWidth / 2, targetHeight / 2);
              canvas.rotate(
                (vPage.rotationQuarterTurns % 4) * (3.1415926535 / 2),
              );
              canvas.translate(-pageWidth / 2, -pageHeight / 2);
            }

            // 1. Base PDF page
            paintImage(
              canvas: canvas,
              rect: Rect.fromLTWH(0, 0, pageWidth, pageHeight),
              image: uiImage,
              fit: BoxFit.fill,
              filterQuality: FilterQuality.medium,
            );
            uiImage.dispose();

            // 2. Inserted pictures (decoded via Flutter engine so WebP/HEIC/PNG/JPG all work)
            if (annotations != null) {
              for (final img in annotations.images) {
                final codec = await ui.instantiateImageCodec(img.bytes);
                final frame = await codec.getNextFrame();
                paintImage(
                  canvas: canvas,
                  rect: Rect.fromLTWH(
                    img.x * pageWidth,
                    img.y * pageHeight,
                    img.width * pageWidth,
                    img.height * pageHeight,
                  ),
                  image: frame.image,
                  fit: BoxFit.fill,
                );
                frame.image.dispose();
              }

              // 3. Stylus strokes & highlights
              for (final stroke in annotations.strokes) {
                _paintCalligraphicStroke(
                  canvas,
                  stroke,
                  ui.Size(pageWidth, pageHeight),
                );
              }
            }
            canvas.restore();

            final picture = recorder.endRecording();
            final compositedImage = await picture.toImage(
              (targetWidth * renderScale).round(),
              (targetHeight * renderScale).round(),
            );
            picture.dispose();

            // Valid PNG stream required by Syncfusion PdfBitmap
            final pngData = await compositedImage.toByteData(
              format: ui.ImageByteFormat.png,
            );
            compositedImage.dispose();

            if (pngData != null) {
              final pdfBitmap = sf.PdfBitmap(pngData.buffer.asUint8List());
              outPage.graphics.drawImage(
                pdfBitmap,
                Rect.fromLTWH(0, 0, targetWidth, targetHeight),
              );
            }
          }
        } else if (annotations != null && !annotations.isEmpty) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder);
          canvas.drawRect(
            Rect.fromLTWH(0, 0, targetWidth, targetHeight),
            Paint()..color = Colors.white,
          );
          for (final img in annotations.images) {
            final codec = await ui.instantiateImageCodec(img.bytes);
            final frame = await codec.getNextFrame();
            paintImage(
              canvas: canvas,
              rect: Rect.fromLTWH(
                img.x * targetWidth,
                img.y * targetHeight,
                img.width * targetWidth,
                img.height * targetHeight,
              ),
              image: frame.image,
              fit: BoxFit.fill,
            );
            frame.image.dispose();
          }
          for (final stroke in annotations.strokes) {
            _paintCalligraphicStroke(
              canvas,
              stroke,
              ui.Size(targetWidth, targetHeight),
            );
          }
          final picture = recorder.endRecording();
          final compositedImage = await picture.toImage(
            (targetWidth * renderScale).round(),
            (targetHeight * renderScale).round(),
          );
          picture.dispose();

          final pngData = await compositedImage.toByteData(
            format: ui.ImageByteFormat.png,
          );
          compositedImage.dispose();

          if (pngData != null) {
            final pdfBitmap = sf.PdfBitmap(pngData.buffer.asUint8List());
            outPage.graphics.drawImage(
              pdfBitmap,
              Rect.fromLTWH(0, 0, targetWidth, targetHeight),
            );
          }
        }

        // Yield to UI event loop so progress bar updates and Stop Export responds instantly
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }

      if (cancelToken.isCancelled) {
        throw ExportCancelledException();
      }

      final savedBytes = await outDoc.save();
      final sink = File(outputPath).openSync(mode: FileMode.write);
      try {
        sink.writeFromSync(savedBytes);
        sink.flushSync();
      } finally {
        sink.closeSync();
      }
    } finally {
      outDoc.dispose();
      await pdfiumDoc.dispose();
    }

    return outputPath;
  }

  static void _paintCalligraphicStroke(
      Canvas canvas,
      InkStroke stroke,
      ui.Size pageSize,
      ) {
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
}