import 'dart:io';
import 'dart:ui';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../annotations/models/annotation_models.dart';

class PdfExportService {
  static Future<String> exportFlattenedPdf({
    required String sourceFilePath,
    required Map<int, PageAnnotations> pageAnnotations,
  }) async {
    final sourceBytes = await File(sourceFilePath).readAsBytes();
    final document = PdfDocument(inputBytes: sourceBytes);

    for (final entry in pageAnnotations.entries) {
      final pageNumber = entry.key; // 1-indexed from pdfrx
      final annotations = entry.value;

      if (annotations.isEmpty ||
          pageNumber < 1 ||
          pageNumber > document.pages.count) {
        continue;
      }

      final page = document.pages[pageNumber - 1];
      final pageWidth = page.getClientSize().width;
      final pageHeight = page.getClientSize().height;
      final graphics = page.graphics;

      // 1. Embed Inserted Images
      for (final img in annotations.images) {
        final pdfBitmap = PdfBitmap(img.bytes);
        graphics.drawImage(
          pdfBitmap,
          Rect.fromLTWH(
            img.x * pageWidth,
            img.y * pageHeight,
            img.width * pageWidth,
            img.height * pageHeight,
          ),
        );
      }

      // 2. Flatten Stylus Strokes & Highlights
      for (final stroke in annotations.strokes) {
        if (stroke.points.length < 2) continue;

        graphics.save();
        if (stroke.isHighlighter) {
          graphics.setTransparency(0.35, alphaBrush: 0.35, mode: PdfBlendMode.multiply);
        }

        final pdfColor = PdfColor(
          (stroke.color.r * 255).round(),
          (stroke.color.g * 255).round(),
          (stroke.color.b * 255).round(),
        );

        final penWidth = stroke.size * (pageWidth / 1000.0);
        final pdfPen = PdfPen(
          pdfColor,
          width: penWidth,
        )
          ..lineCap = PdfLineCap.round
          ..lineJoin = PdfLineJoin.round;

        for (int i = 0; i < stroke.points.length - 1; i++) {
          final p1 = stroke.points[i];
          final p2 = stroke.points[i + 1];
          graphics.drawLine(
            pdfPen,
            Offset(p1.x * pageWidth, p1.y * pageHeight),
            Offset(p2.x * pageWidth, p2.y * pageHeight),
          );
        }
        graphics.restore();
      }
    }

    final savedBytes = await document.save();
    document.dispose();

    final tempDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final outputPath = '${tempDir.path}/Scriptum_Annotated_$timestamp.pdf';
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(savedBytes, flush: true);

    return outputPath;
  }
}