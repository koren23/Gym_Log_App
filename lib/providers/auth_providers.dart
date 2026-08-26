import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../services/auth/google_auth_service.dart';
import 'settings_providers.dart';

final googleAuthServiceProvider = Provider<GoogleAuthService>((ref) {
  return GoogleAuthService.instance;
});

class AuthState {
  const AuthState({
    this.account,
    this.hasSheetsAccess = false,
    this.isLoading = false,
    this.error,
  });

  final GoogleSignInAccount? account;

  /// Whether the Sheets scope has actually been granted yet. On native
  /// platforms this is always true as soon as [account] is set (sign-in
  /// and authorization happen together there); on the web, identity and
  /// authorization are two separate steps — see `GoogleAuthService
  /// .requestSheetsAccess`.
  final bool hasSheetsAccess;
  final bool isLoading;
  final Object? error;

  bool get isSignedIn => account != null;

  AuthState copyWith({
    GoogleSignInAccount? account,
    bool clearAccount = false,
    bool? hasSheetsAccess,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) => AuthState(
    account: clearAccount ? null : (account ?? this.account),
    hasSheetsAccess: hasSheetsAccess ?? this.hasSheetsAccess,
    isLoading: isLoading ?? this.isLoading,
    error: clearError ? null : (error ?? this.error),
  );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() {
    // On the web, sign-in can only happen through the platform's own
    // rendered button (see GoogleAuthService.signInInteractively's doc
    // comment), which completes asynchronously via this stream rather than
    // an awaited call. It's identity-only — Sheets access is requested
    // separately, from its own button, once signed in (see
    // requestSheetsAccess below).
    if (kIsWeb) {
      final subscription = _service.onIdentitySignIn.listen((account) {
        state = AuthState(account: account);
        ref.read(appSettingsServiceProvider).setLastSignedInEmail(
          account.email,
        );
      }, onError: (Object e) => state = AuthState(error: e));
      ref.onDispose(subscription.cancel);
    }
    return const AuthState();
  }

  GoogleAuthService get _service => ref.read(googleAuthServiceProvider);

  Future<void> signInSilently() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final ok = await _service.signInSilently();
      state = AuthState(
        account: ok ? _service.currentAccount : null,
        hasSheetsAccess: ok,
      );
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
      final account = await _service.signInInteractively();
      state = AuthState(account: account, hasSheetsAccess: true);
      ref.read(appSettingsServiceProvider).setLastSignedInEmail(
        account.email,
      );
    } catch (e) {
      state = AuthState(error: e);
    }
  }

  /// Web-only: grants the Sheets scope for the account [onIdentitySignIn]
  /// already identified. Must be called directly from a button's
  /// `onPressed` — see `GoogleAuthService.requestSheetsAccess`.
  Future<void> requestSheetsAccess() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _service.requestSheetsAccess();
      state = state.copyWith(hasSheetsAccess: true, isLoading: false);
    } catch (e) {
      state = state.copyWith(error: e, isLoading: false);
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
