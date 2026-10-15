import 'package:flutter/material.dart';
import '../../../core/theme/scriptum_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../annotations/models/annotation_models.dart';

class FloatingDock extends StatelessWidget {
  final ScriptumTool selectedTool;
  final Color selectedColor;
  final double strokeSize;
  final ValueChanged<ScriptumTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onStrokeSizeChanged;
  final VoidCallback onInsertImageTap;

  const FloatingDock({
    super.key,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeSize,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onStrokeSizeChanged,
    required this.onInsertImageTap,
  });

  bool get _showStylePalette =>
      selectedTool == ScriptumTool.pen ||
          selectedTool == ScriptumTool.highlighter;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Pop-up Color & Stroke Size Bar
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(animation),
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: _showStylePalette
              ? GlassContainer(
            key: const ValueKey('style_palette'),
            margin: const EdgeInsets.only(bottom: 12),
            borderRadius: 22,
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Color Swatches
                ...ScriptumTheme.inkColors.map((color) {
                  final isSelected = selectedColor.toARGB32() == color.toARGB32();
                  return GestureDetector(
                    onTap: () => onColorSelected(color),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: isSelected ? 28 : 22,
                      height: isSelected ? 28 : 22,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? ScriptumTheme.cyanGlow
                              : Colors.white.withValues(alpha: 0.25),
                          width: isSelected ? 2.5 : 1.0,
                        ),
                        boxShadow: isSelected
                            ? [
                          BoxShadow(
                            color: color.withValues(alpha: 0.55),
                            blurRadius: 10,
                          )
                        ]
                            : null,
                      ),
                    ),
                  );
                }),
                Container(
                  height: 20,
                  width: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: Colors.white.withValues(alpha: 0.15),
                ),
                // Stroke Thickness Slider
                const Icon(Icons.line_weight_rounded, size: 16),
                SizedBox(
                  width: 130,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 7,
                      ),
                    ),
                    child: Slider(
                      value: strokeSize,
                      min: 1.5,
                      max: 16.0,
                      activeColor: ScriptumTheme.cyanGlow,
                      onChanged: onStrokeSizeChanged,
                    ),
                  ),
                ),
              ],
            ),
          )
              : const SizedBox.shrink(),
        ),

        // 2. Primary Tool Dock
        GlassContainer(
          borderRadius: 24,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DockButton(
                icon: Icons.pan_tool_alt_rounded,
                tooltip: 'Pan & Zoom',
                isSelected: selectedTool == ScriptumTool.pan,
                onTap: () => onToolSelected(ScriptumTool.pan),
              ),
              _DockButton(
                icon: Icons.edit_rounded,
                tooltip: 'Stylus Freehand',
                isSelected: selectedTool == ScriptumTool.pen,
                onTap: () => onToolSelected(ScriptumTool.pen),
              ),
              _DockButton(
                icon: Icons.highlight_rounded,
                tooltip: 'Highlighter',
                isSelected: selectedTool == ScriptumTool.highlighter,
                onTap: () => onToolSelected(ScriptumTool.highlighter),
              ),
              _DockButton(
                icon: Icons.cleaning_services_rounded,
                tooltip: 'Stroke Eraser',
                isSelected: selectedTool == ScriptumTool.eraser,
                onTap: () => onToolSelected(ScriptumTool.eraser),
              ),
              Container(
                height: 22,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: Colors.white.withValues(alpha: 0.14),
              ),
              _DockButton(
                icon: Icons.add_photo_alternate_rounded,
                tooltip: 'Insert Picture',
                isSelected: false,
                accentColor: ScriptumTheme.goldAccent,
                onTap: onInsertImageTap,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? accentColor;

  const _DockButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor = accentColor ?? ScriptumTheme.cyanGlow;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: isSelected ? 18 : 14,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: isSelected
                  ? LinearGradient(
                colors: [
                  activeColor.withValues(alpha: 0.28),
                  activeColor.withValues(alpha: 0.08),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
                  : null,
              border: Border.all(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.55)
                    : Colors.transparent,
              ),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected
                  ? activeColor
                  : (accentColor ?? Colors.white.withValues(alpha: 0.7)),
            ),
          ),
        ),
      ),
    );
  }
}