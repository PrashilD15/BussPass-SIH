/// Riverpod providers for state detection and the active STC network.
///
/// Selection, not merging: each state's network is its own bundled dataset, and
/// the app rides exactly one at a time. GPS detection picks a default; the
/// rider can override it, and the override persists across launches. The
/// network chain keys off [effectiveSTCProvider], so switching states reloads
/// the graph, planner, stops, and departures for free.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/core/services/state_detection_service.dart';
import 'package:busspass/data/providers/app_providers.dart';

/// Asynchronously detects the user's state and returns the matching STC.
final detectedSTCProvider = FutureProvider<DetectedSTC>((ref) async {
  return StateDetectionService().detect();
});

/// The rider's explicit state choice. Null means "follow GPS detection".
class SelectedSTCNotifier extends Notifier<DetectedSTC?> {
  @override
  DetectedSTC? build() {
    final code = ref.read(localStoreProvider).readSelectedSTC();
    return code == null ? null : stcMetaFor(code);
  }

  Future<void> select(DetectedSTC stc) async {
    state = stc;
    await ref.read(localStoreProvider).writeSelectedSTC(stc.stcCode);
  }

  /// Back to GPS-detected (or the bundled default).
  Future<void> clear() async {
    state = null;
    await ref.read(localStoreProvider).writeSelectedSTC(null);
  }
}

final selectedSTCProvider =
    NotifierProvider<SelectedSTCNotifier, DetectedSTC?>(
        SelectedSTCNotifier.new);

/// The STC the app actually rides: explicit choice, else GPS detection, else
/// the bundled MSRTC fallback. Everything network-shaped watches this.
final effectiveSTCProvider = Provider<DetectedSTC>((ref) {
  final override = ref.watch(selectedSTCProvider);
  if (override != null) return override;
  return ref.watch(detectedSTCProvider).value ?? DetectedSTC.fallback;
});

/// The active STC code — resolves to "MSRTC" until detection completes.
final activeSTCProvider = Provider<String>((ref) {
  return ref.watch(effectiveSTCProvider).stcCode;
});

/// The active state name.
final activeStateProvider = Provider<String>((ref) {
  return ref.watch(effectiveSTCProvider).stateName;
});

/// The badge color for the active STC.
final activeSTCColorProvider = Provider<int>((ref) {
  return ref.watch(effectiveSTCProvider).badgeColor;
});

/// Returns the STC metadata for a given STC code string (for badge chips in search results).
DetectedSTC stcMetaFor(String stcCode) {
  switch (stcCode.toUpperCase()) {
    case 'KSRTC':
      return const DetectedSTC(
        stcCode: 'KSRTC',
        stateName: 'Karnataka',
        networkAsset: 'assets/data/ksrtc_network.json',
        badgeColor: 0xFFCC0000,
      );
    case 'GSRTC':
      return const DetectedSTC(
        stcCode: 'GSRTC',
        stateName: 'Gujarat',
        networkAsset: 'assets/data/gsrtc_network.json',
        badgeColor: 0xFF0B5394,
      );
    case 'TSRTC':
      return const DetectedSTC(
        stcCode: 'TSRTC',
        stateName: 'Telangana',
        networkAsset: 'assets/data/tsrtc_network.json',
        badgeColor: 0xFF6D4C9B,
      );
    case 'APSRTC':
      return const DetectedSTC(
        stcCode: 'APSRTC',
        stateName: 'Andhra Pradesh',
        networkAsset: 'assets/data/apsrtc_network.json',
        badgeColor: 0xFF17A04B,
      );
    case 'MSRTC':
    default:
      return DetectedSTC.fallback;
  }
}
