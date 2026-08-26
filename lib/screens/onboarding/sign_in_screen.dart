import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../providers/auth_providers.dart';
import '../../providers/settings_providers.dart';
import '../../widgets/google_web_sign_in_button.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    // Signed in already, just waiting on the separate "grant Sheets
    // access" step (web only — see GoogleAuthService.requestSheetsAccess).
    final needsSheetsAccess =
        authState.isSignedIn && !authState.hasSheetsAccess;

    // On the web there's no `authenticate()` — sign-in only works through
    // the platform's own rendered button (see
    // GoogleAuthService.signInInteractively's doc comment).
    final webButton =
        needsSheetsAccess || GoogleSignIn.instance.supportsAuthenticate()
        ? null
        : googleWebSignInButton();

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
              Text(
                needsSheetsAccess
                    ? "Signed in as ${authState.account!.email}. One more step — grant access to your workout sheet."
                    : 'Sign in with the Google account that owns your workout sheet.',
                textAlign: TextAlign.center,
              ),
              if (!needsSheetsAccess && lastSignedInEmail != null) ...[
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
              if (needsSheetsAccess)
                FilledButton.icon(
                  icon: const Icon(Icons.table_chart_outlined),
                  label: const Text('Grant access to my sheet'),
                  onPressed: authState.isLoading
                      ? null
                      : () => ref
                            .read(authStateProvider.notifier)
                            .requestSheetsAccess(),
                )
              else if (webButton != null)
                SizedBox(height: 44, child: webButton)
              else
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
