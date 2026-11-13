import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme.dart';

class ProfileSetupScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const ProfileSetupScreen({super.key, required this.onComplete});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Entre un prénom');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser!;
      await Supabase.instance.client.from('profiles').insert({
        'id': user.id,
        'display_name': name,
      });
      widget.onComplete();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.waving_hand_rounded,
                size: 64,
                color: AppColors.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Bienvenue !',
                textAlign: TextAlign.center,
                style: theme.textTheme.displaySmall,
              ),
              const SizedBox(height: 12),
              Text(
                'Comment veux-tu être appelé(e)\ndans la famille ?',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Jacqueline, Micheline, Célestin, Augustin...',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isLoading ? null : _save,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('C\'est parti !'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

