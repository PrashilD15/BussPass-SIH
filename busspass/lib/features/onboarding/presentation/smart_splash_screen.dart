/// Smart animated boot splash.
///
/// Shows a 3-step animated sequence:
///   1. Checking your location…
///   2. ✓ {State} detected
///   3. Connecting to {STC}…   →   ✓ Ready!
///
/// Each step animates in with a slide+fade and a checkmark tick. After the
/// full sequence the widget calls [onReady] so the parent can navigate to the
/// dashboard.
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:busspass/core/ui/responsive_wrapper.dart';
import 'package:busspass/core/services/state_detection_service.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/features/state/presentation/state_switcher_sheet.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
import 'package:busspass/theme/widgets/brand_mark.dart';

class SmartSplashScreen extends ConsumerStatefulWidget {
  final VoidCallback onReady;
  const SmartSplashScreen({super.key, required this.onReady});

  @override
  ConsumerState<SmartSplashScreen> createState() => _SmartSplashScreenState();
}

class _SmartSplashScreenState extends ConsumerState<SmartSplashScreen>
    with TickerProviderStateMixin {
  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _logoCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;

  // ── Step state ─────────────────────────────────────────────────────────────
  final List<_StepState> _steps = [
    _StepState(
        label: 'Checking your location…',
        icon: Icons.location_searching_rounded),
    _StepState(label: '', icon: Icons.check_circle_rounded),
    _StepState(label: '', icon: Icons.wifi_rounded),
  ];
  int _activeStep = 0;

  // ── Detection result ───────────────────────────────────────────────────────
  DetectedSTC? _detected;

  /// True while the state switcher sheet is open — the boot sequence must not
  /// navigate away underneath it.
  bool _switcherOpen = false;

  /// True once the boot sequence has finished; used to know whether to fire
  /// `onReady` immediately after the sheet closes.
  bool _sequenceDone = false;

  @override
  void initState() {
    super.initState();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutBack),
    );
    _logoFade = CurvedAnimation(parent: _logoCtrl, curve: Curves.easeIn);

    _logoCtrl.forward();

    _logoCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _runSequence();
      }
    });
  }

  Future<void> _runSequence() async {
    _setStep(0, done: false);

    // Resolve the palette before awaiting; `context` is not valid after.
    final successColor = context.palette.success;

    // A rider who explicitly picked a state earlier skips GPS detection —
    // their choice wins, and the step reads "(saved choice)" so it's honest
    // about why there was no detection.
    final explicit = ref.read(selectedSTCProvider);
    final DetectedSTC stc;
    if (explicit != null) {
      stc = explicit;
    } else {
      stc = await ref.read(detectedSTCProvider.future);
    }
    _detected = stc;

    _setStep(0, done: true);
    await Future.delayed(const Duration(milliseconds: 450));

    _steps[1] = _StepState(
      label: explicit != null
          ? '${stc.stateName} (saved choice)'
          : '${stc.stateName} detected',
      icon: Icons.location_on_rounded,
      color: successColor,
    );
    _setStep(1, done: false);
    await Future.delayed(const Duration(milliseconds: 350));
    _setStep(1, done: true);
    await Future.delayed(const Duration(milliseconds: 450));

    _steps[2] = _StepState(
      label: 'Connecting to ${stc.stcCode}…',
      icon: Icons.cloud_sync_rounded,
    );
    _setStep(2, done: false);

    await Future.delayed(const Duration(milliseconds: 900));
    _setStep(2, done: true);
    await Future.delayed(const Duration(milliseconds: 500));

    // If the rider opened the state switcher while we were booting, let them
    // finish that first — the sheet's completion callback navigates instead.
    _sequenceDone = true;
    if (_switcherOpen) return;
    if (mounted) widget.onReady();
  }

  void _setStep(int index, {required bool done}) {
    if (!mounted) return;
    setState(() {
      _activeStep = index;
      _steps[index] = _steps[index].copyWith(isDone: done);
    });
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return ResponsiveWrapper(
      child: Scaffold(
        backgroundColor: palette.canvas,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // ── Logo ──────────────────────────────────────────────────
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoFade,
                    child: Column(
                      children: [
                        BrandLoader(size: 80),
                        const SizedBox(height: AppSpacing.lg),
                        const BrandWordmark(),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // ── Boot steps ────────────────────────────────────────────
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      _BootStep(
                        step: _steps[i],
                        isVisible: i <= _activeStep,
                        stcColor: _detected != null
                            ? Color(_detected!.badgeColor)
                            : palette.brand,
                      ),
                  ],
                ),

                const Spacer(flex: 1),

                // ── STC tag (appears after detection) ─────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: _detected != null
                      ? _STCTag(
                          stc: _detected!,
                          onTap: () async {
                            _switcherOpen = true;
                            final chosen =
                                await showStateSwitcher(context);
                            _switcherOpen = false;
                            if (!mounted) return;
                            if (chosen != null) {
                              setState(() => _detected = chosen);
                            }
                            // If the boot sequence had finished while the
                            // sheet was up, proceed to the dashboard now.
                            if (_sequenceDone) widget.onReady();
                          },
                        )
                      : const SizedBox(height: 44),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Step model ────────────────────────────────────────────────────────────────
class _StepState {
  final String label;
  final IconData icon;
  final bool isDone;
  final Color? color;

  const _StepState({
    required this.label,
    required this.icon,
    this.isDone = false,
    this.color,
  });

  _StepState copyWith({bool? isDone}) => _StepState(
        label: label,
        icon: icon,
        isDone: isDone ?? this.isDone,
        color: color,
      );
}

// ── Animated step row ─────────────────────────────────────────────────────────
class _BootStep extends StatefulWidget {
  final _StepState step;
  final bool isVisible;
  final Color stcColor;

  const _BootStep({
    required this.step,
    required this.isVisible,
    required this.stcColor,
  });

  @override
  State<_BootStep> createState() => _BootStepState();
}

class _BootStepState extends State<_BootStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _slide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));

    if (widget.isVisible) _ctrl.forward();
  }

  @override
  void didUpdateWidget(_BootStep old) {
    super.didUpdateWidget(old);
    if (!old.isVisible && widget.isVisible) _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final step = widget.step;

    if (step.label.isEmpty) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Row(
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: step.isDone
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: palette.success,
                        size: 22,
                        key: const ValueKey('done'),
                      )
                    : SizedBox(
                        width: 22,
                        height: 22,
                        key: const ValueKey('spin'),
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: widget.stcColor,
                        ),
                      ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                step.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: step.isDone
                          ? palette.ink
                          : palette.inkMuted,
                      fontWeight: step.isDone
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── STC tag — also the "change state" affordance ─────────────────────────────
class _STCTag extends StatelessWidget {
  final DetectedSTC stc;
  final VoidCallback onTap;
  const _STCTag({required this.stc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(stc.badgeColor);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            STCBadge(stc: stc, size: 24),
            const SizedBox(width: 8),
            Text(
              stc.stcCode,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '· ${stc.stateName}',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.edit_outlined, size: 13, color: color),
          ],
        ),
      ),
    );
  }
}
