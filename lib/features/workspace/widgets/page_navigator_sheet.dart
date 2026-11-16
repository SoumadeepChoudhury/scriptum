import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/theme/scriptum_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../annotations/models/annotation_models.dart';

class PageNavigatorSheet extends StatefulWidget {
  final PdfDocument document;
  final int currentPage;
  final List<VirtualPage> virtualPages;
  final Map<int, PageAnnotations> pageAnnotations;
  final ValueChanged<int> onPageSelected;
  final void Function(int pageNumber, PageOperation operation) onPageOperation;

  const PageNavigatorSheet({
    super.key,
    required this.document,
    required this.currentPage,
    required this.virtualPages,
    required this.pageAnnotations,
    required this.onPageSelected,
    required this.onPageOperation,
  });

  @override
  State<PageNavigatorSheet> createState() => _PageNavigatorSheetState();
}

class _PageNavigatorSheetState extends State<PageNavigatorSheet> {
  final TextEditingController _jumpController = TextEditingController();
  final ScrollController _gridScrollController = ScrollController();

  int _activeTab = 0;
  List<PdfOutlineNode> _outline = [];
  bool _loadingOutline = true;
  String? _jumpErrorText;

  int get _totalPages => widget.virtualPages.length;

  @override
  void initState() {
    super.initState();
    _loadDocumentOutline();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentPage();
    });
  }

  void _scrollToCurrentPage() {
    if (!_gridScrollController.hasClients || widget.currentPage <= 4) return;
    final rowIndex = (widget.currentPage - 1) ~/ 4;
    const estimatedRowHeight = 235.0;
    final targetOffset = (rowIndex * estimatedRowHeight).clamp(
      0.0,
      _gridScrollController.position.maxScrollExtent,
    );
    _gridScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _loadDocumentOutline() async {
    try {
      final outline = await widget.document.loadOutline();
      if (mounted) {
        setState(() {
          _outline = outline;
          _loadingOutline = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingOutline = false);
      }
    }
  }

  @override
  void dispose() {
    _jumpController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  void _triggerJump() {
    final rawText = _jumpController.text.trim();
    final target = int.tryParse(rawText);

    if (target != null && target >= 1 && target <= _totalPages) {
      HapticFeedback.mediumImpact();
      widget.onPageSelected(target);
      Navigator.of(context).pop();
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _jumpErrorText = 'Enter 1–$_totalPages';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: GlassContainer(
          width: (screenSize.width * 0.86).clamp(520.0, 920.0),
          height: (screenSize.height * 0.82).clamp(420.0, 640.0),
          borderRadius: 30,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Top Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildTabPill(
                          index: 0,
                          icon: Icons.grid_view_rounded,
                          label: 'Pages ($_totalPages)',
                        ),
                        _buildTabPill(
                          index: 1,
                          icon: Icons.toc_rounded,
                          label: 'Outline',
                          badgeCount: _outline.length,
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // "Go to Page" Input Box
                  Container(
                    width: 235,
                    height: 44,
                    padding: const EdgeInsets.only(left: 14, right: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _jumpErrorText != null
                            ? ScriptumTheme.dangerRed.withValues(alpha: 0.8)
                            : ScriptumTheme.cyanGlow.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.find_in_page_rounded,
                          size: 16,
                          color: _jumpErrorText != null
                              ? ScriptumTheme.dangerRed
                              : ScriptumTheme.cyanGlow,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _jumpController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            onChanged: (_) {
                              if (_jumpErrorText != null) {
                                setState(() => _jumpErrorText = null);
                              }
                            },
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                            decoration: InputDecoration(
                              hintText:
                              _jumpErrorText ?? 'Go to (1-$_totalPages)',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: _jumpErrorText != null
                                    ? ScriptumTheme.dangerRed
                                    : Colors.white.withValues(alpha: 0.45),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                            onSubmitted: (_) => _triggerJump(),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _triggerJump,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color:
                              ScriptumTheme.cyanGlow.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Text(
                              'Go',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: ScriptumTheme.cyanGlow,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),

              const SizedBox(height: 18),
              Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
              const SizedBox(height: 18),

              // 2. Main Body
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  child: _activeTab == 0
                      ? _buildThumbnailGrid()
                      : _buildOutlineList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabPill({
    required int index,
    required IconData icon,
    required String label,
    int badgeCount = 0,
  }) {
    final isSelected = _activeTab == index;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _activeTab = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? ScriptumTheme.cyanGlow.withValues(alpha: 0.22)
              : Colors.transparent,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? ScriptumTheme.cyanGlow
                  : Colors.white.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? ScriptumTheme.cyanGlow
                    : Colors.white.withValues(alpha: 0.65),
              ),
            ),
            if (badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: ScriptumTheme.goldAccent.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$badgeCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: ScriptumTheme.goldAccent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnailGrid() {
    return GridView.builder(
      key: const ValueKey('page_grid'),
      controller: _gridScrollController,
      padding: const EdgeInsets.only(bottom: 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.72,
      ),
      itemCount: _totalPages,
      itemBuilder: (context, index) {
        final pageNumber = index + 1;
        final vPage = widget.virtualPages[index];
        final isCurrent = pageNumber == widget.currentPage;
        final hasAnnotations =
        !(widget.pageAnnotations[pageNumber]?.isEmpty ?? true);

        return GestureDetector(
          key: ObjectKey(vPage),
          onTap: () {
            HapticFeedback.lightImpact();
            widget.onPageSelected(pageNumber);
            Navigator.of(context).pop();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isCurrent
                  ? ScriptumTheme.cyanGlow.withValues(alpha: 0.15)
                  : Colors.white.withValues(alpha: 0.04),
              border: Border.all(
                color: isCurrent
                    ? ScriptumTheme.cyanGlow
                    : Colors.white.withValues(alpha: 0.10),
                width: isCurrent ? 2.0 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      // Page Preview (Supports Instant Rotation & Blank Inserted Pages)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          color: Colors.white,
                          width: double.infinity,
                          height: double.infinity,
                          child: vPage.isBlankPage
                              ? const Center(
                            child: Text(
                              'Blank Note Page',
                              style: TextStyle(
                                color: Colors.black38,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                              : RotatedBox(
                            quarterTurns: vPage.rotationQuarterTurns,
                            child: PdfPageView(
                              document: widget.document,
                              pageNumber: vPage.sourcePageNumber!,
                            ),
                          ),
                        ),
                      ),

                      // Top-Right Annotated Badge
                      if (hasAnnotations)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: ScriptumTheme.goldAccent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit_rounded,
                              size: 11,
                              color: Colors.black,
                            ),
                          ),
                        ),

                      // Top-Left 3-Dot Page Actions Menu (Rotate, Insert, Delete)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Material(
                          color: Colors.transparent,
                          child: PopupMenuButton<PageOperation>(
                            tooltip: 'Page Options',
                            color: const Color(0xFF151924),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.14),
                              ),
                            ),
                            onSelected: (op) {
                              HapticFeedback.mediumImpact();
                              widget.onPageOperation(pageNumber, op);
                              setState(() {});
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: PageOperation.rotateClockwise,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.rotate_right_rounded,
                                      size: 18,
                                      color: ScriptumTheme.cyanGlow,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Rotate 90°',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: PageOperation.insertAfter,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.post_add_rounded,
                                      size: 18,
                                      color: ScriptumTheme.goldAccent,
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      'Insert Page After',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                              if (_totalPages > 1)
                                const PopupMenuItem(
                                  value: PageOperation.delete,
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.delete_outline_rounded,
                                        size: 18,
                                        color: ScriptumTheme.dangerRed,
                                      ),
                                      SizedBox(width: 10),
                                      Text(
                                        'Delete Page',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: ScriptumTheme.dangerRed,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.2),
                                ),
                              ),
                              child: const Icon(
                                Icons.more_vert_rounded,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isCurrent) ...[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: ScriptumTheme.cyanGlow,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      'Page $pageNumber',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                        isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isCurrent
                            ? ScriptumTheme.cyanGlow
                            : Colors.white.withValues(alpha: 0.78),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOutlineList() {
    if (_loadingOutline) {
      return const Center(
        child: CircularProgressIndicator(color: ScriptumTheme.cyanGlow),
      );
    }

    if (_outline.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.menu_book_rounded,
              size: 44,
              color: Colors.white.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 12),
            Text(
              'No embedded outline found in this PDF.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Switch to the Pages tab to browse live page thumbnails.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.38),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('outline_list'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: _outline.length,
      itemBuilder: (context, index) {
        return _buildOutlineNode(_outline[index], 0);
      },
    );
  }

  Widget _buildOutlineNode(PdfOutlineNode node, int depth) {
    final targetPage = node.dest?.pageNumber;
    final isCurrentChapter = targetPage == widget.currentPage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: targetPage == null
              ? null
              : () {
            HapticFeedback.lightImpact();
            widget.onPageSelected(targetPage);
            Navigator.of(context).pop();
          },
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 2),
            padding: EdgeInsets.only(
              left: 12.0 + (depth * 20.0),
              right: 14.0,
              top: 10.0,
              bottom: 10.0,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: isCurrentChapter
                  ? ScriptumTheme.cyanGlow.withValues(alpha: 0.12)
                  : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(
                  depth == 0
                      ? Icons.bookmark_rounded
                      : Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: depth == 0
                      ? ScriptumTheme.cyanGlow
                      : Colors.white.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.title,
                    style: TextStyle(
                      fontSize: depth == 0 ? 14 : 13,
                      fontWeight:
                      depth == 0 ? FontWeight.w600 : FontWeight.w400,
                      color: isCurrentChapter
                          ? ScriptumTheme.cyanGlow
                          : Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                if (targetPage != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'p. $targetPage',
                      style: const TextStyle(
                        fontSize: 11,
                        color: ScriptumTheme.cyanGlow,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (node.children.isNotEmpty)
          ...node.children.map((child) => _buildOutlineNode(child, depth + 1)),
      ],
    );
  }
}