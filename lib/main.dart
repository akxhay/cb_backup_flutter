import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/chat_list_screen.dart';
import 'services/chat_repository.dart';
import 'services/self_identity_service.dart';
import 'services/theme_service.dart';

import 'services/ad_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AdService.init();

  final identity = SelfIdentityService();
  await identity.load();

  final repo = ChatRepository();
  await repo.load();

  final themeService = ThemeService();
  await themeService.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SelfIdentityService>.value(value: identity),
        ChangeNotifierProvider<ChatRepository>.value(value: repo),
        ChangeNotifierProvider<ThemeService>.value(value: themeService),
      ],
      child: const CbbackupApp(),
    ),
  );
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF00A884),
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? const Color(0xFF111B21) : const Color(0xFFFFFFFF),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 1,
      backgroundColor: isDark ? const Color(0xFF1F2C34) : const Color(0xFFF0F2F5),
      foregroundColor: isDark ? const Color(0xFFE9EDEF) : const Color(0xFF111B21),
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: DividerThemeData(
      color: isDark ? const Color(0xFF2A3942) : const Color(0xFFE9EDEF),
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: const Color(0xFF00A884),
      foregroundColor: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}

class CbbackupApp extends StatelessWidget {
  const CbbackupApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp(
      title: 'CB Backup',
      themeMode: themeService.themeMode,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      home: const ChatListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
