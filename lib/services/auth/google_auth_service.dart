import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart';

import '../../core/constants/oauth_config.dart';
import '../settings/app_settings_service.dart';
import 'google_web_oauth_client.dart';

/// Platform-neutral signed-in identity. Wraps the native plugin's account on
/// mobile/desktop; on web there's no `GoogleSignInAccount` instance once the
/// web path bypasses `google_sign_in_web` (see [GoogleWebOAuthClient]), so
/// this is just the email decoded from the OAuth id_token there.
class SignedInAccount {
  const SignedInAccount({required this.email});

  final String email;
}

/// Wraps Google sign-in to authenticate the user and produce an
/// authenticated [http.Client] for the Sheets API, scoped to
/// [SheetsApi.spreadsheetsScope] (plus `openid email` on web) only.
///
/// Native platforms (Android/iOS/desktop) use the `google_sign_in` plugin
/// (v7 API), backed by the OS's own credential store — this stays signed in
/// indefinitely with no code here needed to make that happen.
///
/// The web build instead uses [GoogleWebOAuthClient], a hand-rolled OAuth
/// authorization-code+PKCE flow — `google_sign_in_web`'s browser token
/// client never issues a refresh token to JS, and its silent-restore check
/// depends on a cross-site cookie Safari blocks by default, making it
/// unusable as a "stay signed in" mechanism on iOS. See
/// [GoogleWebOAuthClient]'s doc comment for the full reasoning.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  static const List<String> _scopes = [SheetsApi.spreadsheetsScope];

  bool _initialized = false;
  GoogleSignInAccount? _nativeAccount;
  GoogleWebOAuthClient? _webClient;

  SignedInAccount? get currentAccount {
    if (kIsWeb) {
      final email = _webClient?.email;
      return email == null ? null : SignedInAccount(email: email);
    }
    final account = _nativeAccount;
    return account == null ? null : SignedInAccount(email: account.email);
  }

  bool get isSignedIn => currentAccount != null;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) {
      final client = GoogleWebOAuthClient(await AppSettingsService.create());
      _webClient = client;
      await client.completePendingRedirectIfAny();
      return;
    }
    await GoogleSignIn.instance.initialize(serverClientId: kGoogleServerClientId);
  }

  /// Attempts a silent sign-in (no UI). Returns true if it succeeded.
  Future<bool> signInSilently() async {
    await ensureInitialized();
    if (kIsWeb) {
      final client = _webClient!;
      if (!client.hasStoredRefreshToken) return false;
      try {
        await client.getValidAccessToken();
        return true;
      } catch (_) {
        return false;
      }
    }

    final account = await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    _nativeAccount = account;
    if (account == null) return false;

    final authz = await account.authorizationClient.authorizationForScopes(
      _scopes,
    );
    return authz != null;
  }

  /// Runs the interactive sign-in flow and requests the Sheets scope.
  ///
  /// On web this navigates the page away to Google's consent screen and
  /// never returns meaningfully — the app resumes via
  /// [GoogleWebOAuthClient.completePendingRedirectIfAny] on the next load.
  /// Throws [GoogleSignInException] on native failure/cancellation.
  Future<void> signInInteractively() async {
    await ensureInitialized();
    if (kIsWeb) {
      await _webClient!.startInteractiveSignIn();
      return;
    }
    final account = await GoogleSignIn.instance.authenticate();
    _nativeAccount = account;
    await account.authorizationClient.authorizeScopes(_scopes);
  }

  Future<void> signOut() async {
    if (kIsWeb) {
      await _webClient?.signOut();
      return;
    }
    await GoogleSignIn.instance.signOut();
    _nativeAccount = null;
  }

  /// Builds a [SheetsApi] client authenticated as the current account.
  /// Throws [StateError] if no account is signed in.
  Future<SheetsApi> buildSheetsApi() async {
    if (kIsWeb) {
      final client = _webClient;
      if (client == null || !client.hasStoredRefreshToken) {
        throw StateError('No signed-in Google account.');
      }
      return SheetsApi(_WebAuthorizedHttpClient(client));
    }
    final account = _nativeAccount;
    if (account == null) {
      throw StateError('No signed-in Google account.');
    }
    final httpClient = _AuthorizedHttpClient(account, _scopes);
    return SheetsApi(httpClient);
  }
}

/// An [http.Client] that attaches a fresh Sheets-scope bearer token to every
/// request, on native platforms. Tokens are fetched lazily per-request
/// rather than cached here, since `google_sign_in`'s authorization client
/// already caches/refreshes internally.
class _AuthorizedHttpClient extends http.BaseClient {
  _AuthorizedHttpClient(this._account, this._scopes);

  final GoogleSignInAccount _account;
  final List<String> _scopes;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final headers = await _account.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
    );
    if (headers != null) {
      request.headers.addAll(headers);
    }
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}

/// The web counterpart to [_AuthorizedHttpClient]: attaches a bearer token
/// minted (or refreshed) via [GoogleWebOAuthClient] to every request.
class _WebAuthorizedHttpClient extends http.BaseClient {
  _WebAuthorizedHttpClient(this._client);

  final GoogleWebOAuthClient _client;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _client.getValidAccessToken();
    request.headers['Authorization'] = 'Bearer $token';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
