import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

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
            backgroundColor: AppColors.ink,
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
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ── Header ───────────────────────────────────────────────────
              Text(
                'Sign in',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 32,
                    ),
              ).animate().fadeIn(delay: 100.ms).slideY(begin: 0.15),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your state bus pass, anywhere in India.\nBook, track, and travel smarter.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.15),

              const SizedBox(height: AppSpacing.xxl),

              // ── Feature Pills ────────────────────────────────────────────
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  _FeatureTag(
                          icon: Icons.map_rounded, label: 'Live Routes')
                      .animate()
                      .fadeIn(delay: 300.ms)
                      .scale(curve: Curves.easeOutBack),
                  _FeatureTag(
                          icon: Icons.confirmation_num_rounded,
                          label: 'Digital Pass')
                      .animate()
                      .fadeIn(delay: 400.ms)
                      .scale(curve: Curves.easeOutBack),
                  _FeatureTag(
                          icon: Icons.language_rounded, label: 'Regional')
                      .animate()
                      .fadeIn(delay: 500.ms)
                      .scale(curve: Curves.easeOutBack),
                ],
              ),

              const Spacer(),

              // ── Sign-in Buttons ──────────────────────────────────────────
              Text(
                'Continue with',
                style: Theme.of(context).textTheme.labelLarge,
              ).animate().fadeIn(delay: 600.ms),
              const SizedBox(height: AppSpacing.lg),

              PrimaryButton(
                label: 'Google',
                onPressed: _isGoogleLoading ? null : _signInWithGoogle,
                loading: _isGoogleLoading,
                icon: Icons.g_mobiledata_rounded,
                backgroundColor: AppColors.surface,
              ).animate().fadeIn(delay: 700.ms).slideY(begin: 0.15),

              const SizedBox(height: AppSpacing.md),

              // Facebook (disabled / coming soon)
              Container(
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.facebook_rounded,
                        color: AppColors.inkMuted, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    const Text(
                      'Facebook',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.15),

              const SizedBox(height: AppSpacing.xxl),

              // ── Footer ───────────────────────────────────────────────────
              Text(
                'By continuing, you agree to our Terms of Service\nand Privacy Policy.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: 900.ms),

              const SizedBox(height: AppSpacing.lg),
            ],
          ),
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
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.brandLight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.brandDeep),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.brandDeep,
            ),
          ),
        ],
      ),
    );
  }
}