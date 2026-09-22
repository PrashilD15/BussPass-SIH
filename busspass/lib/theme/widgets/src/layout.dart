/// Layout helpers: [SplitRow], [SettingsRow], [SettingsGroup].
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

import 'surfaces.dart' show AppCard;

/// A horizontal row of hairline-separated cells that all share available width.
class SplitRow extends StatelessWidget {
  final List<Widget> children;

  const SplitRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final cells = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        cells.add(Container(
          width: 1,
          height: 34,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          color: palette.hairline,
        ));
      }
      cells.add(Expanded(child: children[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: cells);
  }
}

/// A settings-style row.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? iconColor;
  final bool destructive;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.iconColor,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    final tint = destructive
        ? palette.danger
        : (iconColor ?? palette.inkSoft);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        borderRadius: AppSpacing.brMd,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
          child: Row(
            children: [
              Icon(icon, size: 21, color: tint),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: destructive ? palette.danger : palette.ink,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: palette.inkFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// A grouped list of [SettingsRow]s inside one bordered surface.
class SettingsGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;

  const SettingsGroup({super.key, this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xxl + AppSpacing.md),
          child: Divider(height: 1, color: palette.hairline),
        ));
      }
      rows.add(children[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(
                left: AppSpacing.xs, bottom: AppSpacing.sm),
            child: Text(
              title!.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
        AppCard(padding: EdgeInsets.zero, child: Column(children: rows)),
      ],
    );
  }
}
