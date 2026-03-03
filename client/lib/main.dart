import 'package:flutter/material.dart';
import 'config.dart';
import 'services/auth_service.dart';
import 'screens/login_screen.dart';
import 'screens/chat_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  await AuthService.init();
  runApp(const ClawChatApp());
}

class ClawChatApp extends StatelessWidget {
  const ClawChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClawChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F23),
        colorScheme: const ColorScheme.dark(primary: Color(0xFFE94560)),
      ),
      home: (AuthService.isLoggedIn && AppConfig.baseUrl.isNotEmpty)
          ? const ChatScreen()
          : const LoginScreen(),
    );
  }
}
