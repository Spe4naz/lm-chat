import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'models.dart';
import 'screens/home_screen.dart';
import 'screens/welcome_screen.dart';
import 'theme.dart';
import 'window_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(ChangeNotifierProvider.value(value: state, child: const LmChatApp()));
}

class LmChatApp extends StatelessWidget {
  const LmChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    final setupDone = context.select<AppState, bool>(
      (state) => state.data.setupDone,
    );
    final appTheme = context.select<AppState, AppThemeMode>(
      (state) => state.data.themeMode,
    );
    final appLanguage = context.select<AppState, AppLanguage>(
      (state) => state.data.appLanguage,
    );
    final fontFamily = context.select<AppState, String?>(
      (state) => state.data.effectiveFontFamily,
    );
    final fontScale = context.select<AppState, double>(
      (state) => state.data.fontScale,
    );
    final uiDensity = context.select<AppState, UiDensity>(
      (state) => state.data.uiDensity,
    );
    return MaterialApp(
      title: 'LM Chat',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(
        Brightness.light,
        fontFamily: fontFamily,
        density: uiDensity,
      ),
      darkTheme: buildTheme(
        Brightness.dark,
        fontFamily: fontFamily,
        density: uiDensity,
      ),
      themeMode: switch (appTheme) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      locale: switch (appLanguage) {
        AppLanguage.system => null,
        AppLanguage.ru => const Locale('ru'),
        AppLanguage.en => const Locale('en'),
      },
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: _AppTextScaler(media.textScaler, fontScale),
          ),
          child: _TitleBarSync(child: child!),
        );
      },
      home: setupDone ? const HomeScreen() : const WelcomeScreen(),
    );
  }
}

/// Keeps the native Windows caption in sync with the active Flutter theme.
class _TitleBarSync extends StatelessWidget {
  const _TitleBarSync({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    unawaited(WindowChrome.setDarkTitleBar(dark));
    return child;
  }
}

/// Applies the in-app text size on top of the system accessibility scale.
class _AppTextScaler extends TextScaler {
  const _AppTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => base.scale(1.0) * factor;

  @override
  String toString() => 'app($textScaleFactor)';
}
