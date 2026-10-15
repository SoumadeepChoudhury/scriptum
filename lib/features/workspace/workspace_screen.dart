import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/scriptum_theme.dart';
import '../../core/widgets/glass_container.dart';
import '../annotations/models/annotation_models.dart';
import '../annotations/widgets/page_annotation_overlay.dart';
import 'services/pdf_export_service.dart';
import 'widgets/floating_dock.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  String? _currentPdfPath;
  String _documentTitle = 'No Document Loaded';
  int _currentPage = 1;
  int _totalPages = 0;

  ScriptumTool _selectedTool = ScriptumTool.pen;
  Color _selectedColor = ScriptumTheme.cyanGlow;
  double _strokeSize = 3.5;
  bool _isHudVisible = true;
  bool _isExporting = false;

  // Stores annotations per page number (1-indexed)
  final Map<int, PageAnnotations> _pageAnnotations = {};

  @override
  void initState() {
    super.initState();
    _initOpenWithIntentListener();
  }

  /// Listens for PDFs opened via Android File Manager ("Open with Scriptum")
  void _initOpenWithIntentListener() {
    // 1. Handle intent when app is already running in memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _loadPdfFromPath(files.first.path);
        }
      },
      onError: (err) => debugPrint('Intent stream error: $err'),
    );

    // 2. Handle intent that cold-launched the app
    ReceiveSharingIntent.instance.getInitialMedia().then(
          (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _loadPdfFromPath(files.first.path);
          ReceiveSharingIntent.instance.reset();
        }
      },
    );
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    super.dispose();
  }

  void _loadPdfFromPath(String path) {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    setState(() {
      _currentPdfPath = path;
      _documentTitle = fileName;
      _pageAnnotations.clear();
      _currentPage = 1;
    });
  }

  Future<void> _pickPdfDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      _loadPdfFromPath(result.files.single.path!);
    }
  }

  Future<void> _insertPictureOnCurrentPage() async {
    if (_currentPdfPath == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final pageAnnots = _pageAnnotations.putIfAbsent(
      _currentPage,
          () => PageAnnotations(),
    );

    setState(() {
      pageAnnots.images.add(
        ImageAnnotation(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          bytes: bytes,
        ),
      );
      _selectedTool = ScriptumTool.pan;
    });
  }

  void _undoLastStroke() {
    final annots = _pageAnnotations[_currentPage];
    if (annots != null && annots.strokes.isNotEmpty) {
      setState(() {
        annots.strokes.removeLast();
      });
    }
  }

  Future<void> _exportAndSharePdf() async {
    if (_currentPdfPath == null || _isExporting) return;

    setState(() => _isExporting = true);
    try {
      final exportedPath = await PdfExportService.exportFlattenedPdf(
        sourceFilePath: _currentPdfPath!,
        pageAnnotations: _pageAnnotations,
      );

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(exportedPath)],
          text: 'Annotated in Scriptum',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Ambient Background Glow Orbs
          Positioned(
            top: -120,
            left: -100,
            child: AmbientGlowOrb(
              color: ScriptumTheme.cyanGlow.withValues(alpha: 0.14),
              size: 420,
            ),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: AmbientGlowOrb(
              color: ScriptumTheme.goldAccent.withValues(alpha: 0.10),
              size: 460,
            ),
          ),

          // 2. Main PDF Canvas or Empty Welcome State
          Positioned.fill(
            child: _currentPdfPath == null
                ? _buildEmptyWorkspace()
                : _buildPdfReaderCanvas(),
          ),

          // 3. Top Floating Glass Header Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutQuart,
            top: _isHudVisible ? 20 : -100,
            left: 24,
            right: 24,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Brand & Active Filename Pill
                  GlassContainer(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.auto_stories_rounded,
                          color: ScriptumTheme.cyanGlow,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Scriptum',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: 0.6,
                          ),
                        ),
                        Container(
                          height: 14,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text(
                            _documentTitle,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (_totalPages > 0) ...[
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: ScriptumTheme.cyanGlow.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$_currentPage / $_totalPages',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: ScriptumTheme.cyanGlow,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Action Controls Pill
                  GlassContainer(
                    borderRadius: 18,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Open PDF',
                          onPressed: _pickPdfDocument,
                          icon: const Icon(Icons.folder_open_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Undo Last Stroke',
                          onPressed: _undoLastStroke,
                          icon: const Icon(Icons.undo_rounded, size: 20),
                        ),
                        IconButton(
                          tooltip: 'Toggle Zen Mode',
                          onPressed: () =>
                              setState(() => _isHudVisible = !_isHudVisible),
                          icon: const Icon(
                            Icons.fullscreen_rounded,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _isExporting
                            ? const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ScriptumTheme.goldAccent,
                            ),
                          ),
                        )
                            : IconButton(
                          tooltip: 'Export & Share Annotated PDF',
                          onPressed: _exportAndSharePdf,
                          icon: const Icon(
                            Icons.ios_share_rounded,
                            size: 20,
                            color: ScriptumTheme.goldAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 4. Zen Mode Restore Button (When HUD is hidden)
          if (!_isHudVisible)
            Positioned(
              top: 24,
              right: 24,
              child: SafeArea(
                child: GlassContainer(
                  borderRadius: 14,
                  child: IconButton(
                    tooltip: 'Show Toolbars',
                    onPressed: () => setState(() => _isHudVisible = true),
                    icon: const Icon(
                      Icons.fullscreen_exit_rounded,
                      color: ScriptumTheme.cyanGlow,
                    ),
                  ),
                ),
              ),
            ),

          // 5. Bottom Floating Stylus & Annotation Dock
          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            bottom: _isHudVisible ? 24 : -160,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingDock(
                selectedTool: _selectedTool,
                selectedColor: _selectedColor,
                strokeSize: _strokeSize,
                onToolSelected: (tool) => setState(() => _selectedTool = tool),
                onColorSelected: (color) =>
                    setState(() => _selectedColor = color),
                onStrokeSizeChanged: (size) =>
                    setState(() => _strokeSize = size),
                onInsertImageTap: _insertPictureOnCurrentPage,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfReaderCanvas() {
    return PdfViewer.file(
      _currentPdfPath!,
      controller: _pdfController,
      params: PdfViewerParams(
        backgroundColor: Colors.transparent,
        margin: 24,
        // Disable single-finger pan when stylus/pen is active so strokes don't scroll the page
        panEnabled: _selectedTool == ScriptumTool.pan,
        onViewerReady: (document, controller) {
          setState(() {
            _totalPages = document.pages.length;
          });
        },
        onPageChanged: (pageNumber) {
          if (pageNumber != null) {
            setState(() => _currentPage = pageNumber);
          }
        },
        pageOverlaysBuilder: (context, pageRect, page) {
          final pageAnnots = _pageAnnotations.putIfAbsent(
            page.pageNumber,
                () => PageAnnotations(),
          );
          return [
            PageAnnotationOverlay(
              pageSize: pageRect.size,
              annotations: pageAnnots,
              activeTool: _selectedTool,
              activeColor: _selectedColor,
              activeStrokeSize: _strokeSize,
              onAnnotationsChanged: () {},
            ),
          ];
        },
      ),
    );
  }

  Widget _buildEmptyWorkspace() {
    return Center(
      child: GlassContainer(
        width: 520,
        height: 330,
        borderRadius: 28,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [
                    ScriptumTheme.cyanGlow.withValues(alpha: 0.2),
                    ScriptumTheme.goldAccent.withValues(alpha: 0.15),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                ),
              ),
              child: const Icon(
                Icons.draw_rounded,
                size: 44,
                color: ScriptumTheme.cyanGlow,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scriptum Studio',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import a PDF or use "Open With Scriptum" from your file manager',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _pickPdfDocument,
              style: FilledButton.styleFrom(
                backgroundColor: ScriptumTheme.cyanGlow.withValues(alpha: 0.15),
                foregroundColor: ScriptumTheme.cyanGlow,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: ScriptumTheme.cyanGlow.withValues(alpha: 0.4),
                  ),
                ),
              ),
              icon: const Icon(Icons.file_open_rounded, size: 18),
              label: const Text('Import PDF Document'),
            ),
          ],
        ),
      ),
    );
  }
}