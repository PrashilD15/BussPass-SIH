/// [AppSheet] — the canonical modal bottom sheet scaffold.
///
/// Four screens drew their own drag handle, corner radius and safe-area
/// padding; they now share this one.
library;

import 'package:flutter/material.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// Show [builder]'s content in an [AppSheet]. Mirrors [showModalBottomSheet]
/// with the app's tokens pre-applied.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    builder: (sheetContext) => AppSheet(
      child: builder(sheetContext),
    ),
  );
}

/// A bottom sheet body with the house shape: top radius 28, raised surface,
/// hairline, and a title row.
class AppSheet extends StatelessWidget {
  final String? title;
  final Widget child;

  /// Trailing widget in the title row (e.g. a close [IconAction]).
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const AppSheet({
    super.key,
    this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(
        AppSpacing.xl, AppSpacing.xs, AppSpacing.xl, AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      decoration: BoxDecoration(
        color: palette.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.radiusXl)),
      ),
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null || trailing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    if (title != null)
                      Expanded(
                        child: Text(
                          title!,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      )
                    else
                      const Spacer(),
                    ?trailing,
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );
  }
}
