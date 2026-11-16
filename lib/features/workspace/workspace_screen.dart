import 'dart:async';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'widgets/page_navigator_sheet.dart';
import 'services/auto_save_service.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with TickerProviderStateMixin {
  PdfViewerController _pdfController = PdfViewerController();
  StreamSubscription<List<SharedMediaFile>>? _intentSub;

  late final AnimationController _ambientController;
  late final AnimationController _floatController;

  String? _currentPdfPath;
  String _documentTitle = 'No Document Loaded';
  int _currentPage = 1;
  int _totalPages = 0;
  PdfDocument? _loadedDocument;

  ScriptumTool _selectedTool = ScriptumTool.pen;
  Color _selectedColor = ScriptumTheme.cyanGlow;
  double _strokeSize = 3.5;
  bool _stylusOnlyMode = false; // False = Hand + Stylus, True = Stylus Only
  bool _isHudVisible = true;
  bool _isExporting = false;

  ExportCancelToken? _exportCancelToken;
  int _exportCurrentPage = 0;
  int _exportTotalPages = 0;

  final Map<int, PageAnnotations> _pageAnnotations = {};
  final List<VirtualPage> _virtualPages = [];

  bool get _hasDocument => _currentPdfPath != null;

  Timer? _autoSaveDebounce;
  bool _isSavingIndicator = false;

  void _scheduleAutoSave() {
    if (_currentPdfPath == null) return;
    _autoSaveDebounce?.cancel();
    _autoSaveDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (_currentPdfPath == null || !mounted) return;
      setState(() => _isSavingIndicator = true);
      await AutoSaveService.saveWorkspace(
        pdfPath: _currentPdfPath!,
        pageAnnotations: _pageAnnotations,
        virtualPages: _virtualPages,
        currentPage: _currentPage,
      );
      if (mounted) {
        setState(() => _isSavingIndicator = false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _initOpenWithIntentListener();

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat(reverse: true);

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  void _initOpenWithIntentListener() {
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> files) {
        if (files.isNotEmpty) {
          _loadPdfFromPath(files.first.path);
        }
      },
      onError: (err) => debugPrint('Intent stream error: $err'),
    );

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
    _ambientController.dispose();
    _floatController.dispose();
    _autoSaveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadPdfFromPath(String path) async {
    final fileName = path.split(RegExp(r'[/\\]')).last;
    final savedState = await AutoSaveService.loadWorkspace(path);

    // Pause background aurora/float tickers while reading so 100% GPU goes to PDF scrolling
    _ambientController.stop();
    _floatController.stop();

    if (!mounted) return;
    setState(() {
      _currentPdfPath = path;
      _documentTitle = fileName;
      _loadedDocument = null;
      _pdfController = PdfViewerController();
      _pageAnnotations
        ..clear()
        ..addAll(savedState?.pageAnnotations ?? {});
      _virtualPages
        ..clear()
        ..addAll(savedState?.virtualPages ?? []);
      _currentPage = savedState?.lastPage ?? 1;
      _isHudVisible = true;
    });
  }

  void _closeDocument() {
    _ambientController.repeat(reverse: true);
    _floatController.repeat(reverse: true);
    setState(() {
      _currentPdfPath = null;
      _loadedDocument = null;
      _documentTitle = 'No Document Loaded';
      _pageAnnotations.clear();
      _virtualPages.clear();
      _totalPages = 0;
      _currentPage = 1;
    });
  }

  Future<void> _pickPdfDocument() async {
    HapticFeedback.mediumImpact();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      _loadPdfFromPath(result.files.single.path!);
    }
  }

  /// Handles Rotate 90°, Insert Blank Page After, and Delete Page from the Thumbnail Grid
  void _handlePageOperation(int pageNumber, PageOperation operation) {
    if (pageNumber < 1 || pageNumber > _virtualPages.length) return;
    final idx = pageNumber - 1;

    setState(() {
      switch (operation) {
        case PageOperation.rotateClockwise:
          _virtualPages[idx].rotationQuarterTurns =
              (_virtualPages[idx].rotationQuarterTurns + 1) % 4;
          _pageAnnotations[pageNumber]?.rotateClockwise();
          break;

        case PageOperation.insertAfter:
          final currentSize = _virtualPages[idx].pageSize;
          _virtualPages.insert(idx + 1, VirtualPage(pageSize: currentSize));
          final shifted = <int, PageAnnotations>{};
          for (final entry in _pageAnnotations.entries) {
            shifted[entry.key <= pageNumber ? entry.key : entry.key + 1] =
                entry.value;
          }
          _pageAnnotations
            ..clear()
            ..addAll(shifted);
          _totalPages = _virtualPages.length;
          break;

        case PageOperation.delete:
          if (_virtualPages.length <= 1) return;
          _virtualPages.removeAt(idx);
          final shifted = <int, PageAnnotations>{};
          for (final entry in _pageAnnotations.entries) {
            if (entry.key < pageNumber) {
              shifted[entry.key] = entry.value;
            } else if (entry.key > pageNumber) {
              shifted[entry.key - 1] = entry.value;
            }
          }
          _pageAnnotations
            ..clear()
            ..addAll(shifted);
          _totalPages = _virtualPages.length;
          _currentPage = _currentPage.clamp(1, _totalPages);
          break;
      }
      _scheduleAutoSave();
    });

    if ((operation == PageOperation.rotateClockwise || operation == PageOperation.delete) && _loadedDocument != null) {
      _pdfController.goToPage(pageNumber: _currentPage);
    }

  }

  void _openPageNavigator() {
    if (_loadedDocument == null) return;
    HapticFeedback.mediumImpact();
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Page Navigator',
      barrierColor: Colors.black.withValues(alpha: 0.65),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, anim1, anim2) {
        return PageNavigatorSheet(
          document: _loadedDocument!,
          currentPage: _currentPage,
          virtualPages: _virtualPages,
          pageAnnotations: _pageAnnotations,
          onPageSelected: (targetPage) {
            _pdfController.goToPage(pageNumber: targetPage);
          },
          onPageOperation: _handlePageOperation,
        );
      },
      transitionBuilder: (context, anim, _, child) {
        return FadeTransition(
          opacity: anim,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  Future<void> _insertPictureOnCurrentPage() async {
    if (!_hasDocument) return;

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
    _scheduleAutoSave();
  }

  void _undoLastStroke() {
    final annots = _pageAnnotations[_currentPage];
    if (annots != null && annots.strokes.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        final removed = annots.strokes.removeLast();
        annots.redoStrokes.add(removed);
      });
    }
    _scheduleAutoSave();
  }

  void _redoLastStroke() {
    final annots = _pageAnnotations[_currentPage];
    if (annots != null && annots.redoStrokes.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        final restored = annots.redoStrokes.removeLast();
        annots.strokes.add(restored);
      });
    }
    _scheduleAutoSave();
  }

  Future<void> _exportAndSharePdf() async {
    if (!_hasDocument || _isExporting) return;

    final token = ExportCancelToken();
    setState(() {
      _isExporting = true;
      _exportCancelToken = token;
      _exportCurrentPage = 1;
      _exportTotalPages = _virtualPages.length;
    });

    try {
      final exportedPath = await PdfExportService.exportFlattenedPdf(
        sourceFilePath: _currentPdfPath!,
        pageAnnotations: _pageAnnotations,
        virtualPages: _virtualPages,
        cancelToken: token,
        onProgress: (current, total) {
          if (mounted) {
            setState(() {
              _exportCurrentPage = current;
              _exportTotalPages = total;
            });
          }
        },
      );

      if (!mounted || token.isCancelled) return;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(exportedPath)],
          text: 'Annotated in Scriptum',
        ),
      );
    } on ExportCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF export stopped.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportCancelToken = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAnnots = _pageAnnotations[_currentPage];
    final canUndo = currentAnnots != null && currentAnnots.strokes.isNotEmpty;
    final canRedo =
        currentAnnots != null && currentAnnots.redoStrokes.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Subtle Architectural Dot-Matrix Grid Background
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _DotMatrixGridPainter(),
              ),
            ),
          ),

          // 2. Animated Drifting Aurora Orbs
          AnimatedBuilder(
            animation: _ambientController,
            builder: (context, _) {
              final t = _ambientController.value;
              return Stack(
                children: [
                  Positioned(
                    top: -120 + (math.sin(t * math.pi) * 60),
                    left: -80 + (math.cos(t * math.pi) * 80),
                    child: AmbientGlowOrb(
                      color: ScriptumTheme.cyanGlow.withValues(alpha: 0.16),
                      size: 520,
                    ),
                  ),
                  Positioned(
                    bottom: -140 + (math.cos(t * math.pi) * 60),
                    right: -60 + (math.sin(t * math.pi) * 90),
                    child: AmbientGlowOrb(
                      color: ScriptumTheme.goldAccent.withValues(alpha: 0.12),
                      size: 540,
                    ),
                  ),
                ],
              );
            },
          ),

          // 3. Main PDF Canvas or Animated Home Studio
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 450),
              switchInCurve: Curves.easeOutCubic,
              child: _hasDocument
                  ? _buildPdfReaderCanvas()
                  : _buildAnimatedHomeStudio(),
            ),
          ),

          // 4. Top Floating Glass Header Bar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutQuart,
            top: _isHudVisible ? 22 : -100,
            left: 28,
            right: 28,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Left Brand Pill + Clickable Page Counter Badge
                GlassContainer(
                  borderRadius: 20,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ScriptumTheme.cyanGlow.withValues(alpha: 0.15),
                        ),
                        child: const Icon(
                          Icons.auto_stories_rounded,
                          color: ScriptumTheme.cyanGlow,
                          size: 18,
                        ),
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
                      if (_hasDocument) ...[
                        Container(
                          height: 14,
                          width: 1,
                          margin: const EdgeInsets.symmetric(horizontal: 14),
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            _documentTitle,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                        if (_totalPages > 0) ...[
                          const SizedBox(width: 12),
                          Tooltip(
                            message: 'Tap to view Page Grid, Outline & Go To Page',
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: _openPageNavigator,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: ScriptumTheme.cyanGlow
                                      .withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: ScriptumTheme.cyanGlow
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '$_currentPage / $_totalPages',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: ScriptumTheme.cyanGlow,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.unfold_more_rounded,
                                      size: 13,
                                      color: ScriptumTheme.cyanGlow,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                // Right Action Bar — ONLY VISIBLE WHEN A PDF IS LOADED
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: anim, child: child),
                  ),
                  child: _hasDocument
                      ? GlassContainer(
                    key: const ValueKey('pdf_actions'),
                    borderRadius: 20,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Page Grid, Outline & Go To Page',
                          onPressed: _openPageNavigator,
                          icon: const Icon(
                            Icons.grid_view_rounded,
                            size: 20,
                            color: ScriptumTheme.cyanGlow,
                          ),
                        ),
                        Container(
                          height: 18,
                          width: 1,
                          margin:
                          const EdgeInsets.symmetric(horizontal: 4),
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                        IconButton(
                          tooltip: 'Open Another PDF',
                          onPressed: _pickPdfDocument,
                          icon: const Icon(
                            Icons.folder_open_rounded,
                            size: 20,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Undo Stroke',
                          onPressed: canUndo ? _undoLastStroke : null,
                          icon: Icon(
                            Icons.undo_rounded,
                            size: 20,
                            color: canUndo
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Redo Stroke',
                          onPressed: canRedo ? _redoLastStroke : null,
                          icon: Icon(
                            Icons.redo_rounded,
                            size: 20,
                            color: canRedo
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Distraction-Free Zen Mode',
                          onPressed: () => setState(
                                  () => _isHudVisible = !_isHudVisible),
                          icon: const Icon(
                            Icons.fullscreen_rounded,
                            size: 20,
                          ),
                        ),
                        _isExporting
                            ? const Padding(
                          padding:
                          EdgeInsets.symmetric(horizontal: 12),
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
                          tooltip: 'Export Flattened PDF',
                          onPressed: _exportAndSharePdf,
                          icon: const Icon(
                            Icons.ios_share_rounded,
                            size: 20,
                            color: ScriptumTheme.goldAccent,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close Document',
                          onPressed: _closeDocument,
                          icon: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),

          // 5. Zen Mode Restore Button
          if (_hasDocument && !_isHudVisible)
            Positioned(
              top: 24,
              right: 28,
              child: GlassContainer(
                borderRadius: 14,
                child: IconButton(
                  tooltip: 'Restore Toolbars',
                  onPressed: () => setState(() => _isHudVisible = true),
                  icon: const Icon(
                    Icons.fullscreen_exit_rounded,
                    color: ScriptumTheme.cyanGlow,
                  ),
                ),
              ),
            ),

          // 6. Bottom Floating Stylus Dock — ONLY VISIBLE WHEN A PDF IS LOADED
          AnimatedPositioned(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            bottom: (_hasDocument && _isHudVisible) ? 24 : -180,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingDock(
                selectedTool: _selectedTool,
                selectedColor: _selectedColor,
                strokeSize: _strokeSize,
                stylusOnlyMode: _stylusOnlyMode,
                onToolSelected: (tool) => setState(() => _selectedTool = tool),
                onColorSelected: (color) =>
                    setState(() => _selectedColor = color),
                onStrokeSizeChanged: (size) =>
                    setState(() => _strokeSize = size),
                onStylusOnlyChanged: (val) =>
                    setState(() => _stylusOnlyMode = val),
                onInsertImageTap: _insertPictureOnCurrentPage,
              ),
            ),
          ),

          // 7. Blocking Live Export Progress Overlay with Cancel Button
          if (_isExporting)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true, // Blocks all drawing, scrolling, and taps on the PDF
                child: Container(
                  color: Colors.black.withValues(alpha: 0.68),
                  child: Center(
                    child: GlassContainer(
                      width: 400,
                      borderRadius: 28,
                      padding: const EdgeInsets.all(28),
                      borderColor:
                      ScriptumTheme.cyanGlow.withValues(alpha: 0.4),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: ScriptumTheme.goldAccent
                                  .withValues(alpha: 0.16),
                            ),
                            child: const Icon(
                              Icons.picture_as_pdf_rounded,
                              size: 32,
                              color: ScriptumTheme.goldAccent,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Flattening & Exporting PDF',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Rendering page $_exportCurrentPage of $_exportTotalPages...',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 22),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: LinearProgressIndicator(
                              minHeight: 8,
                              value: _exportTotalPages > 0
                                  ? (_exportCurrentPage / _exportTotalPages)
                                  .clamp(0.0, 1.0)
                                  : null,
                              backgroundColor:
                              Colors.white.withValues(alpha: 0.10),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                ScriptumTheme.cyanGlow,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: () {
                              HapticFeedback.heavyImpact();
                              _exportCancelToken?.cancel();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: ScriptumTheme.dangerRed,
                              side: BorderSide(
                                color: ScriptumTheme.dangerRed
                                    .withValues(alpha: 0.6),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 22,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            icon: const Icon(Icons.stop_circle_rounded, size: 18),
                            label: const Text(
                              'Stop Export',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPdfReaderCanvas() {
    final allowSingleFingerPan =
        _selectedTool == ScriptumTool.pan || _stylusOnlyMode;

    return RepaintBoundary(
      key: ValueKey('pdf_canvas_$_currentPdfPath'),
      child: PdfViewer.file(
        _currentPdfPath!,
        controller: _pdfController,
        params: PdfViewerParams(
          backgroundColor: const Color(0xFF090B10), // Solid dark canvas prevents expensive alpha blending during scroll
          margin: 20,
          panEnabled: allowSingleFingerPan,
          scaleEnabled: true,
          maxScale: 8.0,
          minScale: 0.1,
          // Limit offscreen page cache to keep RAM minimal on 500+ page textbooks
          maxImageBytesCachedOnMemory: 60 * 1024 * 1024, // 60 MB strict tile cache
          useAlternativeFitScaleAsMinScale: false,
          errorBannerBuilder: (context, error, stackTrace, documentRef) {
            return Center(
              child: Text(
                'Failed to render PDF: $error',
                style: const TextStyle(color: Colors.white70),
              ),
            );
          },
          onViewerReady: (document, controller) {
            if (!mounted) return;
            setState(() {
              _loadedDocument = document;
              if (_virtualPages.isEmpty) {
                _virtualPages.addAll(
                  List.generate(
                    document.pages.length,
                        (i) => VirtualPage(
                      sourcePageNumber: i + 1,
                      pageSize: Size(
                        document.pages[i].width,
                        document.pages[i].height,
                      ),
                    ),
                  ),
                );
              }
              _totalPages = _virtualPages.length;
            });
          },
          onPageChanged: (pageNumber) {
            if (pageNumber != null && mounted && _currentPage != pageNumber) {
              setState(() => _currentPage = pageNumber);
              _scheduleAutoSave();
            }
          },
          pageOverlaysBuilder: (context, pageRect, page) {
            if (!pageRect.size.isFinite ||
                pageRect.size.width <= 0 ||
                pageRect.size.height <= 0) {
              return const [];
            }

            final vPageIndex = _virtualPages.indexWhere(
                  (v) => v.sourcePageNumber == page.pageNumber,
            );
            final displayPageNum =
            vPageIndex != -1 ? vPageIndex + 1 : page.pageNumber;
            final pageAnnots = _pageAnnotations.putIfAbsent(
              displayPageNum,
                  () => PageAnnotations(),
            );

            return [
              PageAnnotationOverlay(
                pageSize: pageRect.size,
                annotations: pageAnnots,
                activeTool: _selectedTool,
                activeColor: _selectedColor,
                activeStrokeSize: _strokeSize,
                stylusOnlyMode: _stylusOnlyMode,
                onAnnotationsChanged: () {
                  setState(() {});
                  _scheduleAutoSave();
                },
              ),
            ];
          },
        ),
      ),
    );
  }

  Widget _buildAnimatedHomeStudio() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 80),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        color: ScriptumTheme.cyanGlow.withValues(alpha: 0.12),
                        border: Border.all(
                          color: ScriptumTheme.cyanGlow.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            size: 14,
                            color: ScriptumTheme.cyanGlow,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '120Hz Stylus Calligraphic Engine',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: ScriptumTheme.cyanGlow,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Your fluid canvas for\ndeep reading & ink.',
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.8,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Import any textbook, paper, or handout to annotate with zero-latency pressure curves, layered images, and instant flattened PDF export.',
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.55,
                        color: Colors.white.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 30),
                    GestureDetector(
                      onTap: _pickPdfDocument,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF38BDF8),
                              Color(0xFF0284C7),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:
                              ScriptumTheme.cyanGlow.withValues(alpha: 0.35),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_open_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            SizedBox(width: 12),
                            Text(
                              'Open PDF Document',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    GlassContainer(
                      borderRadius: 22,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: (_stylusOnlyMode
                                  ? ScriptumTheme.cyanGlow
                                  : ScriptumTheme.goldAccent)
                                  .withValues(alpha: 0.15),
                            ),
                            child: Icon(
                              _stylusOnlyMode
                                  ? Icons.draw_rounded
                                  : Icons.pan_tool_rounded,
                              color: _stylusOnlyMode
                                  ? ScriptumTheme.cyanGlow
                                  : ScriptumTheme.goldAccent,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _stylusOnlyMode
                                      ? 'Stylus-Only Mode (Palm Rejection)'
                                      : 'Hand + Stylus Drawing Mode',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _stylusOnlyMode
                                      ? 'Pen draws; 1 finger scrolls; 2 fingers zoom'
                                      : '1 finger draws; 2 fingers pinch-to-zoom',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          CupertinoSwitch(
                            value: _stylusOnlyMode,
                            activeTrackColor: ScriptumTheme.cyanGlow,
                            onChanged: (value) {
                              HapticFeedback.lightImpact();
                              setState(() => _stylusOnlyMode = value);
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 48),
              Expanded(
                flex: 5,
                child: AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) {
                    final offset =
                        math.sin(_floatController.value * math.pi) * 12.0;
                    return Transform.translate(
                      offset: Offset(0, -offset),
                      child: child,
                    );
                  },
                  child: GestureDetector(
                    onTap: _pickPdfDocument,
                    child: SizedBox(
                      height: 380,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Transform.rotate(
                            angle: -0.08,
                            child: GlassContainer(
                              width: 270,
                              height: 330,
                              borderRadius: 28,
                              child: const SizedBox.expand(),
                            ),
                          ),
                          Transform.rotate(
                            angle: 0.03,
                            child: GlassContainer(
                              width: 285,
                              height: 340,
                              borderRadius: 28,
                              borderColor:
                              ScriptumTheme.cyanGlow.withValues(alpha: 0.35),
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: ScriptumTheme.goldAccent
                                              .withValues(alpha: 0.18),
                                          borderRadius:
                                          BorderRadius.circular(8),
                                        ),
                                        child: const Text(
                                          'PDF • ANNOTATE',
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: ScriptumTheme.goldAccent,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.edit_note_rounded,
                                        color:
                                        Colors.white.withValues(alpha: 0.5),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  _mockLine(widthFactor: 0.85),
                                  const SizedBox(height: 12),
                                  _mockLine(widthFactor: 0.95),
                                  const SizedBox(height: 12),
                                  _mockLine(
                                    widthFactor: 0.70,
                                    highlight: ScriptumTheme.cyanGlow
                                        .withValues(alpha: 0.25),
                                  ),
                                  const SizedBox(height: 24),
                                  Expanded(
                                    child: Container(
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(18),
                                        color:
                                        Colors.white.withValues(alpha: 0.04),
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.08),
                                        ),
                                      ),
                                      child: CustomPaint(
                                        painter: _SignaturePreviewPainter(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.touch_app_rounded,
                                        size: 14,
                                        color: ScriptumTheme.cyanGlow
                                            .withValues(alpha: 0.8),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Tap card to browse tablet files',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white
                                              .withValues(alpha: 0.55),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mockLine({required double widthFactor, Color? highlight}) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 10,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: highlight ?? Colors.white.withValues(alpha: 0.12),
        ),
      ),
    );
  }
}

class _DotMatrixGridPainter extends CustomPainter {
  const _DotMatrixGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.045)
      ..style = PaintingStyle.fill;

    const spacing = 32.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.1, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _SignaturePreviewPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.72)
      ..cubicTo(
        size.width * 0.35,
        size.height * 0.10,
        size.width * 0.65,
        size.height * 0.90,
        size.width * 0.84,
        size.height * 0.28,
      );

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(
        colors: [ScriptumTheme.cyanGlow, ScriptumTheme.goldAccent],
      ).createShader(Offset.zero & size);

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}