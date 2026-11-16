import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:path_provider/path_provider.dart';
import '../../annotations/models/annotation_models.dart';

class SavedWorkspaceState {
  final Map<int, PageAnnotations> pageAnnotations;
  final List<VirtualPage> virtualPages;
  final int lastPage;

  SavedWorkspaceState({
    required this.pageAnnotations,
    required this.virtualPages,
    this.lastPage = 1,
  });
}

class AutoSaveService {
  static Future<File> _getSidecarFile(String pdfPath) async {
    final docsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory('${docsDir.path}/scriptum_vault');
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    // Generate a deterministic, filesystem-safe key based on file name + size
    final file = File(pdfPath);
    final fileName = pdfPath.split(RegExp(r'[/\\]')).last;
    final fileSize = await file.exists() ? await file.length() : 0;
    final safeKey = '${fileName}_$fileSize'
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

    return File('${vaultDir.path}/$safeKey.scriptum.json');
  }

  /// Serializes and writes annotations to disk inside a background Isolate (0ms UI lag)
  static Future<void> saveWorkspace({
    required String pdfPath,
    required Map<int, PageAnnotations> pageAnnotations,
    required List<VirtualPage> virtualPages,
    required int currentPage,
  }) async {
    final sidecarFile = await _getSidecarFile(pdfPath);
    final targetPath = sidecarFile.path;

    // Snapshot data structures cleanly before passing to Isolate
    final serializedPages = <String, dynamic>{};
    for (final entry in pageAnnotations.entries) {
      if (!entry.value.isEmpty) {
        serializedPages[entry.key.toString()] = entry.value.toJson();
      }
    }
    final serializedVirtual = virtualPages.map((v) => v.toJson()).toList();

    await Isolate.run(() {
      final payload = jsonEncode({
        'version': 1,
        'lastPage': currentPage,
        'virtualPages': serializedVirtual,
        'annotations': serializedPages,
      });
      File(targetPath).writeAsStringSync(payload, flush: true);
    });
  }

  /// Restores saved annotations and page rotations when reopening a PDF
  static Future<SavedWorkspaceState?> loadWorkspace(String pdfPath) async {
    try {
      final sidecarFile = await _getSidecarFile(pdfPath);
      if (!await sidecarFile.exists()) return null;

      final targetPath = sidecarFile.path;
      final decoded = await Isolate.run(() {
        final raw = File(targetPath).readAsStringSync();
        return jsonDecode(raw) as Map<String, dynamic>;
      });

      final annotationsMap = <int, PageAnnotations>{};
      final rawAnnots = decoded['annotations'] as Map<String, dynamic>? ?? {};
      for (final entry in rawAnnots.entries) {
        final pageNum = int.tryParse(entry.key);
        if (pageNum != null) {
          annotationsMap[pageNum] = PageAnnotations.fromJson(
            entry.value as Map<String, dynamic>,
          );
        }
      }

      final virtualList = (decoded['virtualPages'] as List? ?? [])
          .map((e) => VirtualPage.fromJson(e as Map<String, dynamic>))
          .toList();

      return SavedWorkspaceState(
        pageAnnotations: annotationsMap,
        virtualPages: virtualList,
        lastPage: decoded['lastPage'] as int? ?? 1,
      );
    } catch (_) {
      return null;
    }
  }
}