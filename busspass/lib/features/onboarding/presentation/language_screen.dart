import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:busspass/features/onboarding/presentation/auth_screen.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/brand_mark.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen> {
  String _selectedCode = 'en';

  final List<Map<String, String>> _languages = [
    {'code': 'en', 'name': 'English', 'native': 'English'},
    {'code': 'hi', 'name': 'Hindi', 'native': '\u0939\u093f\u0928\u094d\u0926\u0940'},
    {'code': 'mr', 'name': 'Marathi', 'native': '\u092e\u0930\u093e\u0920\u0940'},
    {'code': 'kn', 'name': 'Kannada', 'native': '\u0c95\u0ca8\u0ccd0ca8\u0ccd0d21'},
  ];

  void _onContinue() {
    HapticFeedback.lightImpact();
    context.setLocale(Locale(_selectedCode));
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, animation, _) => const AuthScreen(),
        transitionsBuilder: (_, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.05, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
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
            // ── Premium Brand Header ──────────────────────────────────
            Expanded(
              flex: 4,
              child: Stack(
                children: [
                  // Subtle decorative blob
                  Positioned(
                    top: -20,
                    right: -50,
                    child: Container(
                      width: 180,
                      height: 180,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.brand.withValues(alpha: 0.07),
                      ),
                    ),
                  ),
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const BrandMark(size: 68)
                            .animate()
                            .scale(
                              duration: 500.ms,
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

            // ── Language Selection ─────────────────────────────────────
            Expanded(
              flex: 6,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select Language',
                      style: theme.textTheme.titleLarge,
                    ).animate().fadeIn(delay: 400.ms),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Choose your preferred language for the app.',
                      style: theme.textTheme.bodyMedium,
                    ).animate().fadeIn(delay: 450.ms),
                    const SizedBox(height: AppSpacing.xl),

                    // Premium card grid
                    Expanded(
                      child: GridView.builder(
                        physics: const BouncingScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: AppSpacing.md,
                          mainAxisSpacing: AppSpacing.md,
                          childAspectRatio: 1.3,
                        ),
                        itemCount: _languages.length,
                        itemBuilder: (context, index) {
                          final lang = _languages[index];
                          final isSelected = _selectedCode == lang['code'];

                          return GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedCode = lang['code']!);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? palette.brand
                                    : palette.surface,
                                borderRadius: BorderRadius.circular(
                                    AppSpacing.radiusLg),
                                border: Border.all(
                                  color: isSelected
                                      ? palette.brand
                                      : palette.hairline,
                                  width: isSelected ? 1.5 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color:
                                              palette.brand.withValues(alpha: 0.25),
                                          blurRadius: 16,
                                          offset: const Offset(0, 6),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    lang['native']!,
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: isSelected
                                          ? Colors.white
                                          : palette.ink,
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    lang['name']!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: isSelected
                                          ? Colors.white
                                              .withValues(alpha: 0.7)
                                          : palette.inkMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                              .animate(
                                  delay: Duration(
                                      milliseconds: 400 + (index * 80)))
                              .fadeIn()
                              .slideY(begin: 0.15);
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Continue Button ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
              child: ElevatedButton(
                onPressed: _onContinue,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Continue'),
                    SizedBox(width: AppSpacing.sm),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
                ),
              ).animate().fadeIn(delay: 800.ms).slideY(begin: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}
