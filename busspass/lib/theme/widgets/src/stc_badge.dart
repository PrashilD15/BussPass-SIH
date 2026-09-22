/// [STCBadge] — the single rendering of a state transport corporation's
/// identity: logo in a white seal + brand colour from the STC metadata.
///
/// This block was copy-pasted four times across splash, home, search and the
/// picker. It now lives here once.
library;

import 'package:flutter/material.dart';

import 'package:busspass/core/services/state_detection_service.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';

/// All supported STCs, in display order for the switcher.
const List<DetectedSTC> kAllSTCs = [
  DetectedSTC(
    stcCode: 'MSRTC',
    stateName: 'Maharashtra',
    networkAsset: 'assets/data/network.json',
    badgeColor: 0xFFE85400,
  ),
  DetectedSTC(
    stcCode: 'KSRTC',
    stateName: 'Karnataka',
    networkAsset: 'assets/data/ksrtc_network.json',
    badgeColor: 0xFFCC0000,
  ),
  DetectedSTC(
    stcCode: 'GSRTC',
    stateName: 'Gujarat',
    networkAsset: 'assets/data/gsrtc_network.json',
    badgeColor: 0xFF0B5394,
  ),
  DetectedSTC(
    stcCode: 'TSRTC',
    stateName: 'Telangana',
    networkAsset: 'assets/data/tsrtc_network.json',
    badgeColor: 0xFF6D4C9B,
  ),
  DetectedSTC(
    stcCode: 'APSRTC',
    stateName: 'Andhra Pradesh',
    networkAsset: 'assets/data/apsrtc_network.json',
    badgeColor: 0xFF17A04B,
  ),
];

/// A state transport logo seal. The logos are artwork on white paper, so the
/// seal stays white in both brightnesses; the badge colour tints the ring.
class STCBadge extends StatelessWidget {
  final DetectedSTC stc;

  /// Diameter of the white seal.
  final double size;

  /// Draw the STC code beside the seal.
  final bool showLabel;

  const STCBadge({
    super.key,
    required this.stc,
    this.size = 36,
    this.showLabel = false,
  });

  Color get _brand => Color(stc.badgeColor | 0xFF000000);

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final seal = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: context.isDark
              ? _brand.withValues(alpha: 0.65)
              : palette.hairline,
          width: 1.5,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/ST-logos/${stc.stcCode.toLowerCase()}.png',
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => Icon(
            Icons.bus_alert_rounded,
            size: size * 0.5,
            color: _brand,
          ),
        ),
      ),
    );

    if (!showLabel) return seal;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        seal,
        const SizedBox(width: AppSpacing.sm),
        Text(
          stc.stcCode,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: _brand, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
