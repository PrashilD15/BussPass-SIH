/// Buttons: [PrimaryButton], [IconAction].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// The primary call to action.
///
/// Foreground colour is **derived** from the background rather than hardcoded,
/// which is what makes a light-background variant legible. The old
/// implementation hardcoded white text and produced an invisible button when
/// given a white background.
class PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Trailing icon instead of leading.
  final bool iconTrailing;
  final bool loading;
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// Render as an outline instead of a filled surface.
  final bool outlined;
  final bool expand;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.iconTrailing = false,
    this.loading = false,
    this.backgroundColor,
    this.foregroundColor,
    this.outlined = false,
    this.expand = true,
  });

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  /// Pick a foreground that actually contrasts with the given background.
  ///
  /// Uses relative luminance rather than a hardcoded choice, so any background
  /// — brand, white, danger — yields legible content.
  Color _resolveForeground(Color background) {
    if (widget.foregroundColor != null) return widget.foregroundColor!;
    return background.computeLuminance() > 0.55
        ? context.palette.ink
        : Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    final background = widget.outlined
        ? Colors.transparent
        : (widget.backgroundColor ?? palette.brand);
    final foreground = widget.outlined
        ? (widget.foregroundColor ?? palette.ink)
        : _resolveForeground(background);

    final effectiveBackground =
        _enabled ? background : palette.hairline;
    final effectiveForeground =
        _enabled ? foreground : palette.inkFaint;

    final children = <Widget>[];
    if (widget.loading) {
      children.add(SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(effectiveForeground),
        ),
      ));
    } else {
      if (widget.icon != null && !widget.iconTrailing) {
        children.addAll([
          Icon(widget.icon, size: 19, color: effectiveForeground),
          const SizedBox(width: AppSpacing.sm + 2),
        ]);
      }
      children.add(Text(
        widget.label,
        style: theme.textTheme.labelLarge
            ?.copyWith(color: effectiveForeground, fontSize: 15),
      ));
      if (widget.icon != null && widget.iconTrailing) {
        children.addAll([
          const SizedBox(width: AppSpacing.sm + 2),
          Icon(widget.icon, size: 19, color: effectiveForeground),
        ]);
      }
    }

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: _enabled ? (_) {
          HapticFeedback.lightImpact();
          setState(() => _pressed = true);
        } : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        onTap: _enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.975 : 1.0,
          duration: AppMotion.instant,
          curve: AppMotion.enter,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            height: AppSpacing.controlHeight,
            width: widget.expand ? double.infinity : null,
            padding: widget.expand
                ? null
                : const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            decoration: BoxDecoration(
              color: effectiveBackground,
              borderRadius: AppSpacing.brMd,
              border: widget.outlined
                  ? Border.all(
                      color: _enabled
                          ? palette.hairlineStrong
                          : palette.hairline)
                  : null,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

/// A square icon action with a tinted background.
class IconAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final Color? color;
  final Color? background;
  final double size;

  const IconAction({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.color,
    this.background,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final button = Material(
      color: background ?? palette.surface,
      borderRadius: AppSpacing.brMd,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: AppSpacing.brMd,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, size: 21, color: color ?? palette.inkSoft),
        ),
      ),
    );

    final bordered = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppSpacing.brMd,
        border: Border.all(color: palette.hairline),
      ),
      child: button,
    );

    // A tooltip doubles as the accessibility label, so an icon-only control is
    // never unlabelled to a screen reader.
    return tooltip == null
        ? bordered
        : Tooltip(message: tooltip!, child: bordered);
  }
}
