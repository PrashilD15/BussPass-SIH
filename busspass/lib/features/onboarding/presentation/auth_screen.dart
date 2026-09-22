import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
import 'package:busspass/theme/widgets/brand_mark.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  bool _isGoogleLoading = false;

  Future<void> _signInWithGoogle() async {
    HapticFeedback.lightImpact();
    setState(() => _isGoogleLoading = true);
    try {
      final cred = await ref.read(authRepositoryProvider).signInWithGoogle();
      if (cred != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Welcome, ${cred.user?.displayName ?? 'User'}!'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: context.palette.ink,
          ),
        );
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DashboardScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            behavior: SnackBarBehavior.floating,
            backgroundColor: context.palette.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Column(
          children: [
            // ── Premium Brand Header ────────────────────────────────────
            Expanded(
              flex: 5,
              child: Stack(
                children: [
                  // Subtle background blob
                  Positioned(
                    top: -40,
                    right: -60,
                    child: Container(
                      width: 220,
                      height: 220,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.brand.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -30,
                    left: -40,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.accent.withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  // Content
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        BrandLoader(size: 80)
                            .animate()
                            .scale(
                              duration: 600.ms,
                              curve: Curves.easeOutBack,
                            ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'BussPass',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            letterSpacing: -0.5,
                          ),
                        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Your Travel Partner',
                          style: theme.textTheme.bodyMedium,
                        ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ── Sign-in Content ─────────────────────────────────────────
            Expanded(
              flex: 6,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Sign in',
                      style: theme.textTheme.headlineSmall,
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.15),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your state bus pass, anywhere in India.\nBook, track, and travel smarter.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        height: 1.5,
                      ),
                    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.15),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Feature Pills ────────────────────────────────────
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        _FeatureTag(
                                icon: Icons.map_rounded, label: 'Live Routes')
                            .animate()
                            .fadeIn(delay: 600.ms)
                            .scale(curve: Curves.easeOutBack),
                        _FeatureTag(
                                icon: Icons.confirmation_num_rounded,
                                label: 'Digital Pass')
                            .animate()
                            .fadeIn(delay: 700.ms)
                            .scale(curve: Curves.easeOutBack),
                        _FeatureTag(
                                icon: Icons.language_rounded,
                                label: 'Regional')
                            .animate()
                            .fadeIn(delay: 800.ms)
                            .scale(curve: Curves.easeOutBack),
                      ],
                    ),

                    const Spacer(),

                    // ── Sign-in Buttons ──────────────────────────────────
                    Text(
                      'Continue with',
                      style: theme.textTheme.labelLarge,
                    ).animate().fadeIn(delay: 900.ms),
                    const SizedBox(height: AppSpacing.md),

                    PrimaryButton(
                      label: 'Google',
                      onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                      loading: _isGoogleLoading,
                      icon: Icons.g_mobiledata_rounded,
                      backgroundColor: palette.surface,
                    ).animate().fadeIn(delay: 950.ms).slideY(begin: 0.15),

                    const SizedBox(height: AppSpacing.sm),

                    // Facebook (disabled / coming soon)
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg, vertical: 16),
                      borderColor: palette.hairline,
                      color: palette.surfaceAlt,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.facebook_rounded,
                              color: palette.inkMuted, size: 22),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'Facebook',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: palette.inkMuted,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            'Coming soon',
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.inkFaint,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 1000.ms).slideY(begin: 0.15),

                    const SizedBox(height: AppSpacing.xl),

                    // ── Footer ───────────────────────────────────────────
                    Text(
                      'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ).animate().fadeIn(delay: 1100.ms),

                    const SizedBox(height: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: palette.brandLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        border: Border.all(color: palette.brand.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: palette.brandDeep),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: palette.brandDeep,
            ),
          ),
        ],
      ),
    );
  }
}
