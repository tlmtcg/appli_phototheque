import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:phototheque/screens/profile_setup_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/env.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Charger .env
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('DOTENV chargé. Contenu : ${dotenv.env}');
  } catch (e) {
    runApp(_ErrorApp(message: 'Fichier .env introuvable.\n$e'));
    return;
  }

  // 2. Vérifier que les variables sont présentes
  if (!Env.isConfigured) {
    runApp(
      const _ErrorApp(
        message: 'SUPABASE_URL ou SUPABASE_PUBLISH_KEY manquant dans .env.',
      ),
    );
    return;
  }

  // 3. Initialiser Supabase
  try {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
  } catch (e, stack) {
    debugPrint('Échec init Supabase : $e\n$stack');
    runApp(_ErrorApp(message: 'Supabase :\n$e'));
    return;
  }

  runApp(const MainApp());
}

class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Configuration manquante.\n\n$message',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
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
      title: 'Photothèque',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: _session != null
          ? _AuthGate(session: _session!)
          : const LoginScreen(),
    );
  }
}

class _AuthGate extends StatefulWidget {
  final Session session;
  const _AuthGate({required this.session});

  @override
  State<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<_AuthGate> {
  bool? _hasProfile;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    try {
      final profile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', widget.session.user.id)
          .maybeSingle();
      if (mounted) setState(() => _hasProfile = profile != null);
    } catch (_) {
      if (mounted) setState(() => _hasProfile = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasProfile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_hasProfile!) {
      return ProfileSetupScreen(
        onComplete: () => setState(() => _hasProfile = true),
      );
    }
    return const HomeScreen();
  }
}
