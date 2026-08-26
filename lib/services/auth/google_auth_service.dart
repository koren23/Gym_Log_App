import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:googleapis/sheets/v4.dart';

import '../../core/constants/oauth_config.dart';

/// Wraps `google_sign_in` (v7 API) to authenticate the user and produce an
/// authenticated [http.Client] for the Sheets API, scoped to
/// [SheetsApi.spreadsheetsScope] only.
class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  static const List<String> _scopes = [SheetsApi.spreadsheetsScope];

  bool _initialized = false;
  GoogleSignInAccount? _currentAccount;

  GoogleSignInAccount? get currentAccount => _currentAccount;
  bool get isSignedIn => _currentAccount != null;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    // The web implementation rejects `serverClientId` (it's Android/iOS
    // only there) and expects the same "Web application" client ID as
    // `clientId` instead.
    await GoogleSignIn.instance.initialize(
      clientId: kIsWeb ? kGoogleServerClientId : null,
      serverClientId: kIsWeb ? null : kGoogleServerClientId,
    );
    _initialized = true;
  }

  /// Attempts a silent sign-in (no UI). Returns true if it succeeded.
  Future<bool> signInSilently() async {
    await ensureInitialized();
    final account = await GoogleSignIn.instance
        .attemptLightweightAuthentication();
    _currentAccount = account;
    if (account == null) return false;

    final authz = await account.authorizationClient.authorizationForScopes(
      _scopes,
    );
    return authz != null;
  }

  /// Runs the interactive sign-in flow and requests the Sheets scope.
  /// Throws [GoogleSignInException] on failure/cancellation.
  ///
  /// Only usable on platforms where [GoogleSignIn.supportsAuthenticate] is
  /// true (not the web — see [onWebSignIn] instead).
  Future<GoogleSignInAccount> signInInteractively() async {
    await ensureInitialized();
    final account = await GoogleSignIn.instance.authenticate();
    _currentAccount = account;
    await account.authorizationClient.authorizeScopes(_scopes);
    return account;
  }

  /// Fires whenever the platform's own rendered sign-in button (the only
  /// option on the web, since [signInInteractively] throws there) completes
  /// a sign-in. Identity only — deliberately does NOT also request the
  /// Sheets scope here: browsers only allow the authorization popup when
  /// it's opened directly inside a user-gesture handler (a button's
  /// onPressed), not from an async stream callback like this one, so that
  /// has to happen via a separate, explicit [requestSheetsAccess] call
  /// wired to its own button. See [GoogleAuthNotifier]/`SignInScreen`.
  Stream<GoogleSignInAccount> get onIdentitySignIn => GoogleSignIn.instance
      .authenticationEvents
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .cast<GoogleSignInAuthenticationEventSignIn>()
      .map((e) {
        _currentAccount = e.user;
        return e.user;
      });

  /// Requests the Sheets scope for the already-identified [currentAccount]
  /// — the web counterpart to the scope request bundled inside
  /// [signInInteractively] on other platforms. Must be called directly
  /// from a user-interaction handler (e.g. a button's `onPressed`) on the
  /// web, or the browser will block the consent popup. Throws
  /// [StateError] if no account is signed in yet.
  Future<void> requestSheetsAccess() async {
    final account = _currentAccount;
    if (account == null) {
      throw StateError('No signed-in Google account.');
    }
    await account.authorizationClient.authorizeScopes(_scopes);
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _currentAccount = null;
  }

  /// Builds a [SheetsApi] client authenticated as the current account.
  /// Throws [StateError] if no account is signed in.
  Future<SheetsApi> buildSheetsApi() async {
    final account = _currentAccount;
    if (account == null) {
      throw StateError('No signed-in Google account.');
    }
    final client = _AuthorizedHttpClient(account, _scopes);
    return SheetsApi(client);
  }
}

/// An [http.Client] that attaches a fresh Sheets-scope bearer token to every
/// request. Tokens are fetched lazily per-request rather than cached here,
/// since `google_sign_in`'s authorization client already caches/refreshes
/// internally.
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
