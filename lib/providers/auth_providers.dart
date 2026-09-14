import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/auth/google_auth_service.dart';
import 'settings_providers.dart';

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService.instance;
});

class AuthState {
  const AuthState({this.account, this.isLoading = false, this.error});

  final SignedInAccount? account;
  final bool isLoading;
  final Object? error;

  bool get isSignedIn => account != null;

  // Kept as `true` always: on every platform now, a signed-in account
  // implies the Sheets scope was already granted as part of that same
  // sign-in step (native always worked this way; the web PKCE flow now
  // requests identity + Sheets scope together in one consent screen too).
  bool get hasSheetsAccess => isSignedIn;

  AuthState copyWith({
    SignedInAccount? account,
    bool clearAccount = false,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) => AuthState(
    account: clearAccount ? null : (account ?? this.account),
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  GoogleAuthService get _service => ref.read(googleAuthServiceProvider);

  Future<void> signInSilently() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final ok = await _service.signInSilently();
      state = AuthState(account: ok ? _service.currentAccount : null);
      final email = _service.currentAccount?.email;
      if (ok && email != null) {
        ref.read(appSettingsServiceProvider).setLastSignedInEmail(email);
      }
    } catch (e) {
      state = AuthState(error: e);
    }
  }

  Future<void> signInInteractively() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.signInInteractively();
      final account = _service.currentAccount;
      state = AuthState(account: account);
      if (account != null) {
        ref.read(appSettingsServiceProvider).setLastSignedInEmail(
          account.email,
        );
      }
    } catch (e) {
      state = AuthState(error: e);
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
    state = const AuthState();
  }
}

final authStateProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
