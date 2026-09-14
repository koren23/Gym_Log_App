import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final lastSignedInEmail = ref.watch(appSettingsServiceProvider).lastSignedInEmail;

    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.fitness_center, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Sign in with the Google account that owns your workout sheet.',
                textAlign: TextAlign.center,
              ),
              if (lastSignedInEmail != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last signed in as $lastSignedInEmail — sign in again to '
                  'continue.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 24),
              if (authState.error != null) ...[
                Text(
                  'Sign-in failed: ${authState.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                icon: const Icon(Icons.login),
                label: const Text('Sign in with Google'),
                onPressed: authState.isLoading
                    ? null
                    : () => ref
                          .read(authStateProvider.notifier)
                          .signInInteractively(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
