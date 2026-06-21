import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/chat_list_screen.dart';
import 'services/chat_repository.dart';
import 'services/self_identity_service.dart';
import 'services/theme_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

class CbbackupApp extends StatelessWidget {
  const CbbackupApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();

    return MaterialApp(
      title: 'CB Backup',
      themeMode: themeService.themeMode,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
          scrolledUnderElevation: 2,
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 1,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 1,
          scrolledUnderElevation: 2,
        ),
        cardTheme: CardThemeData(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      home: const ChatListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
