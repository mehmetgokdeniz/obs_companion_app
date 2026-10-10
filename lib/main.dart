import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/obs_provider.dart';
import 'views/home_view.dart';
import 'views/setup_view.dart';

void main() {
  runApp(const ObsApp());
}

ThemeData _glassTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF8B5CF6),
    brightness: Brightness.dark,
    surface: const Color(0xFF140D22),
    primary: const Color(0xFF9B6BFF),
    secondary: const Color(0xFFB394FF),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFF0F0919),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
      ),
      margin: EdgeInsets.zero,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1B1430).withValues(alpha: 0.82),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.black.withValues(alpha: 0.15),
      surfaceTintColor: Colors.transparent,
      indicatorColor: const Color(0xFF9B6BFF).withValues(alpha: 0.35),
      elevation: 0,
      shadowColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Colors.white,
      textColor: Colors.white,
    ),
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ),
  );
}

class ObsApp extends StatelessWidget {
  const ObsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ObsProvider()..initApp(),
      child: MaterialApp(
        title: 'OBS Companion',
        theme: _glassTheme(),
        home: const _Root(),
      ),
    );
  }
}

/// Yapılandırma durumuna göre ana ekrana veya kurulum ekranına yönlendirir.
///
/// Token bir kez girildikten sonra uygulama doğrudan veri ekranını açar;
/// kullanıcı OBS'e giriş ekranı görmez.
class _Root extends StatelessWidget {
  const _Root();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ObsProvider>();

    switch (provider.session) {
      case SessionState.unknown:
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      case SessionState.ready:
        return const HomeView();
      case SessionState.needsSetup:
        return const SetupView();
    }
  }
}
