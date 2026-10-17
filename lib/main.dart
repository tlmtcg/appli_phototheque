import 'dart:async';

import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!Env.isConfigured) {
    debugPrint(
      'ERREUR : SUPABASE_URL ou SUPABASE_PUBLISH_KEY est vide. '
      'Vérifiez les --dart-define dans le workflow GitHub Actions.',
    );
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Configuration manquante : variables Supabase vides.'),
          ),
        ),
      ),
    );
    return;
  }

  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  } catch (e, stack) {
    debugPrint('Échec de l\'initialisation de Supabase : $e');
    debugPrint('$stack');
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Échec de l\'initialisation de Supabase :\n$e',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  late final StreamSubscription<AuthState> _authSubscription;
  Session? _session;

  @override
  void initState() {
    super.initState();
    _session = Supabase.instance.client.auth.currentSession;
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) => setState(() => _session = data.session),
    );
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phototheque',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _session != null ? const HomeScreen() : const LoginScreen(),
    );
  }
}
