import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:busspass/theme/app_colors.dart';
import 'package:busspass/theme/app_theme.dart';
import 'package:busspass/theme/widgets/app_widgets.dart';
import 'package:busspass/theme/widgets/brand_mark.dart';
import 'package:busspass/features/onboarding/presentation/language_screen.dart';
import 'package:busspass/features/onboarding/presentation/smart_splash_screen.dart';
import 'package:busspass/features/dashboard/presentation/dashboard_screen.dart';
import 'package:busspass/data/providers/auth_provider.dart';
import 'package:busspass/data/providers/app_providers.dart';
import 'package:busspass/data/providers/state_provider.dart';
import 'package:busspass/data/repositories/local_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await EasyLocalization.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final localStore = await LocalStore.open();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('mr'),
        Locale('kn'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(localStore),
        ],
        child: const BussPassApp(),
      ),
    ),
  );
}

class BussPassApp extends ConsumerWidget {
  const BussPassApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(
      settingsProvider.select((s) => s.themeMode),
    );
    final largeText = ref.watch(
      settingsProvider.select((s) => s.largeText),
    );
    final stc = ref.watch(effectiveSTCProvider);
    final lightPalette = AppPalette.forSTC(stc.stcCode, Brightness.light);
    final darkPalette = AppPalette.forSTC(stc.stcCode, Brightness.dark);

    // Honour the reduce-motion preference app-wide: the shared stagger
    // helpers no-op when it's on.
    StaggerAnimation.enabled =
        !ref.watch(settingsProvider.select((s) => s.reduceMotion));

    return MaterialApp(
      title: 'BussPass – Your Travel Partner',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: buildLightTheme(lightPalette),
      darkTheme: buildDarkTheme(darkPalette),
      themeMode: switch (themeMode) {
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
        AppThemeMode.system => ThemeMode.system,
      },
      // The in-app "Larger text" accessibility preference rides on the
      // platform textScaler so every textTheme role scales consistently.
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: largeText ? 1.15 : 1.0,
        maxScaleFactor: 1.4,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthWrapper(),
    );
  }
}

/// The cold-start splash: brand loader over the themed canvas, shown while auth
/// state resolves. Replaces a bare centred spinner.
class _SplashScaffold extends StatelessWidget {
  const _SplashScaffold();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Scaffold(
      backgroundColor: palette.canvas,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            BrandLoader(size: 72),
            SizedBox(height: AppSpacing.xl),
            BrandWordmark(),
          ],
        ),
      ),
    );
  }
}

class AuthWrapper extends ConsumerWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    return authState.when(
      data: (user) {
        if (user != null) {
          // Show smart splash first (state detection), then dashboard.
          return SmartSplashScreen(
            onReady: () {
              // Navigate replacing the current route so back button doesn't
              // return to the splash.
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => const DashboardScreen(),
                ),
                (_) => false,
              );
            },
          );
        }
        return const LanguageScreen();
      },
      loading: () => const _SplashScaffold(),
      error: (error, stackTrace) => Scaffold(
        body: ErrorState(
          title: 'Could not start',
          message: 'Something went wrong while opening BussPass. '
              'Check your connection and try again.',
          detail: error,
        ),
      ),
    );
  }
}
