import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/scichat_provider.dart';
import 'screens/home_screen.dart';
import 'theme/scichat_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const SciChatApp());
}

class SciChatApp extends StatelessWidget {
  const SciChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SciChatProvider()..init(),
      child: Consumer<SciChatProvider>(
        builder: (context, provider, child) {
          return MaterialApp(
            title: 'SciChat',
            debugShowCheckedModeBanner: false,
            theme: SciChatTheme.light,
            darkTheme: SciChatTheme.dark,
            themeMode: provider.themeMode,
            home: const HomeScreen(),
            builder: (context, child) {
              final mq = MediaQuery.of(context);
              final scale = mq.textScaler.scale(1.0).clamp(0.8, 1.2);
              return MediaQuery(
                data: mq.copyWith(
                  textScaler: TextScaler.linear(scale),
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}


