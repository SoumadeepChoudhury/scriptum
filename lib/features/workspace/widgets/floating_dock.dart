import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/scriptum_theme.dart';
import '../../../core/widgets/glass_container.dart';
import '../../annotations/models/annotation_models.dart';

class FloatingDock extends StatelessWidget {
  final ScriptumTool selectedTool;
  final Color selectedColor;
  final double strokeSize;
  final bool stylusOnlyMode;
  final ValueChanged<ScriptumTool> onToolSelected;
  final ValueChanged<Color> onColorSelected;
  final ValueChanged<double> onStrokeSizeChanged;
  final ValueChanged<bool> onStylusOnlyChanged;
  final VoidCallback onInsertImageTap;

  const FloatingDock({
    super.key,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeSize,
    required this.stylusOnlyMode,
    required this.onToolSelected,
    required this.onColorSelected,
    required this.onStrokeSizeChanged,
    required this.onStylusOnlyChanged,
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
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.90, end: 1.0).animate(animation),
                alignment: Alignment.bottomCenter,
                child: child,
              ),
            );
          },
          child: _showStylePalette
              ? GlassContainer(
            key: const ValueKey('style_palette'),
            margin: const EdgeInsets.only(bottom: 12),
            borderRadius: 24,
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 10,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...ScriptumTheme.inkColors.map((color) {
                  final isSelected =
                      selectedColor.toARGB32() == color.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onColorSelected(color);
                    },
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

        // 2. Primary Tool Dock + iOS Stylus Mode Switch
        GlassContainer(
          borderRadius: 26,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DockButton(
                icon: Icons.pan_tool_alt_rounded,
                tooltip: 'Pan & Read',
                isSelected: selectedTool == ScriptumTool.pan,
                onTap: () => onToolSelected(ScriptumTool.pan),
              ),
              _DockButton(
                icon: Icons.edit_rounded,
                tooltip: 'Stylus Pen',
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
                tooltip: 'Eraser',
                isSelected: selectedTool == ScriptumTool.eraser,
                onTap: () => onToolSelected(ScriptumTool.eraser),
              ),
              _DockButton(
                icon: Icons.add_photo_alternate_rounded,
                tooltip: 'Insert Picture',
                isSelected: false,
                accentColor: ScriptumTheme.goldAccent,
                onTap: onInsertImageTap,
              ),

              Container(
                height: 24,
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: Colors.white.withValues(alpha: 0.14),
              ),

              // iOS-Style Stylus-Only / Hand Drawing Mode Toggle
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.white.withValues(alpha: 0.04),
                  border: Border.all(
                    color: stylusOnlyMode
                        ? ScriptumTheme.cyanGlow.withValues(alpha: 0.35)
                        : Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      stylusOnlyMode
                          ? Icons.draw_rounded
                          : Icons.touch_app_rounded,
                      size: 17,
                      color: stylusOnlyMode
                          ? ScriptumTheme.cyanGlow
                          : ScriptumTheme.goldAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      stylusOnlyMode ? 'Stylus Only' : 'Hand + Stylus',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Transform.scale(
                      scale: 0.78,
                      child: CupertinoSwitch(
                        value: stylusOnlyMode,
                        activeTrackColor: ScriptumTheme.cyanGlow,
                        onChanged: (val) {
                          HapticFeedback.lightImpact();
                          onStylusOnlyChanged(val);
                        },
                      ),
                    ),
                  ],
                ),
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
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
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