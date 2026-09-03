import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';

class PassesTab extends StatelessWidget {
  const PassesTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text('My Passes'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.hairline),
                ),
                child: const Icon(
                  Icons.confirmation_num_outlined,
                  size: 36,
                  color: AppColors.inkMuted,
                ),
              )
                  .animate()
                  .fadeIn()
                  .scale(curve: Curves.easeOutBack),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'No active passes',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 19),
              ).animate().fadeIn(delay: 100.ms),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Purchase a pass or scan a QR code\nto activate your digital ticket.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ).animate().fadeIn(delay: 200.ms),
              const SizedBox(height: AppSpacing.xxl),
              SizedBox(
                width: 220,
                child: PrimaryButton(
                  label: 'Browse Routes',
                  icon: Icons.explore_outlined,
                  onPressed: () {},
                ),
              ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.15),
            ],
          ),
        ),
      ),
    );
  }
}