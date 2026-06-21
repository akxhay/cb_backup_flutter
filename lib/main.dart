import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/chat_list_screen.dart';
import 'services/chat_repository.dart';
import 'services/self_identity_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final identity = SelfIdentityService();
  await identity.load();

  final repo = ChatRepository();
  await repo.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<SelfIdentityService>.value(value: identity),
        ChangeNotifierProvider<ChatRepository>.value(value: repo),
      ],
      child: const CbbackupApp(),
    ),
  );
}

class CbbackupApp extends StatelessWidget {
  const CbbackupApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CB Backup',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: const ChatListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
