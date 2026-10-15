import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'core/theme/scriptum_theme.dart';
import 'features/workspace/workspace_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky, overlays: []);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const ScriptumApp());
}

class ScriptumApp extends StatelessWidget {
  const ScriptumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scriptum',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ScriptumTheme.darkTheme,
      home: const WorkspaceScreen(),
    );
  }
}