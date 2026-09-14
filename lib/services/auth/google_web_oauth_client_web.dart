import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import '../../core/constants/oauth_config.dart';
import '../settings/app_settings_service.dart';

const _kAuthEndpoint = 'https://accounts.google.com/o/oauth2/v2/auth';
const _kTokenEndpoint = 'https://oauth2.googleapis.com/token';
const _kRevokeEndpoint = 'https://oauth2.googleapis.com/revoke';
const _kScopes = 'openid email https://www.googleapis.com/auth/spreadsheets';

/// Hand-rolled OAuth authorization-code + PKCE flow against Google's
/// endpoints directly, used only on the web build. Exists because Google
/// Identity Services' browser token client (what `google_sign_in_web` uses)
/// never issues a refresh token to JS, and its silent-restore check depends
/// on a cross-site cookie that Safari blocks by default — both of which
/// make the standard web sign-in flow effectively useless as a "stay
/// signed in" mechanism on iOS. This flow instead gets a refresh token once
/// and stores it in the PWA's own first-party local storage; refreshing
/// from it is a plain HTTPS POST with no cookie/iframe dependency, so it
/// isn't affected by Safari's blocking at all.
class GoogleWebOAuthClient {
  GoogleWebOAuthClient(this._settings);

  final AppSettingsService _settings;

  String? _accessToken;
  DateTime? _accessTokenExpiry;
  bool _completedPendingRedirect = false;

  String? get email => _settings.lastSignedInEmail;

  bool get hasStoredRefreshToken => _settings.webRefreshToken != null;

  /// Call once at startup. If the page just landed back from Google's
  /// consent screen (`code`/`state`/`error` in the URL), completes the
  /// token exchange, persists the refresh token + email, and strips those
  /// params from the URL either way. Idempotent within a single page load.
  Future<void> completePendingRedirectIfAny() async {
    if (_completedPendingRedirect) return;
    _completedPendingRedirect = true;

    final uri = Uri.base;
    final code = uri.queryParameters['code'];
    final error = uri.queryParameters['error'];
    final returnedState = uri.queryParameters['state'];
    if (code == null && error == null) return; // not a redirect return

    final expectedState = _settings.webPendingPkceState;
    final verifier = _settings.webPendingPkceVerifier;
    await _settings.clearWebPendingPkce();
    _stripAuthParamsFromUrl();

    if (error != null || code == null) return; // user denied / no code
    if (expectedState == null ||
        verifier == null ||
        returnedState != expectedState) {
      return; // mismatched/missing state — don't trust this code
    }

    final response = await http.post(
      Uri.parse(_kTokenEndpoint),
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUri,
        'client_id': kGoogleServerClientId,
        'client_secret': kGoogleWebClientSecret,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) return;
    await _storeTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  /// Redeems the stored refresh token for a fresh access token if we don't
  /// already have one valid for a few more minutes. Throws [StateError] if
  /// there's no refresh token or Google rejects it — callers should treat
  /// that as "not signed in".
  Future<String> getValidAccessToken() async {
    final token = _accessToken;
    final expiry = _accessTokenExpiry;
    if (token != null &&
        expiry != null &&
        expiry.isAfter(DateTime.now().add(const Duration(minutes: 2)))) {
      return token;
    }

    final refreshToken = _settings.webRefreshToken;
    if (refreshToken == null) {
      throw StateError('No stored Google refresh token.');
    }

    final response = await http.post(
      Uri.parse(_kTokenEndpoint),
      body: {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': kGoogleServerClientId,
        'client_secret': kGoogleWebClientSecret,
      },
    );
    if (response.statusCode != 200) {
      // Refusal usually means the refresh token was revoked/expired.
      await _settings.setWebRefreshToken(null);
      throw StateError('Google rejected the stored refresh token.');
    }
    await _storeTokenResponse(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
    return _accessToken!;
  }

  /// Starts the interactive flow: generates a PKCE verifier/challenge and
  /// CSRF state, stashes them for the return trip, and navigates the page
  /// to Google's consent screen. Never returns normally — the flow resumes
  /// via [completePendingRedirectIfAny] on the next page load.
  Future<void> startInteractiveSignIn() async {
    final verifier = _randomUrlSafe(64);
    final challenge = base64UrlEncode(
      sha256.convert(utf8.encode(verifier)).bytes,
    ).replaceAll('=', '');
    final state = _randomUrlSafe(24);
    await _settings.setWebPendingPkce(verifier: verifier, state: state);

    final authUri = Uri.parse(_kAuthEndpoint).replace(
      queryParameters: {
        'client_id': kGoogleServerClientId,
        'redirect_uri': _redirectUri,
        'response_type': 'code',
        'scope': _kScopes,
        'access_type': 'offline',
        'prompt': 'consent',
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
    web.window.location.href = authUri.toString();
  }

  /// Clears the stored refresh token/email and best-effort revokes it with
  /// Google. Does not navigate anywhere.
  Future<void> signOut() async {
    final refreshToken = _settings.webRefreshToken;
    _accessToken = null;
    _accessTokenExpiry = null;
    await _settings.setWebRefreshToken(null);
    await _settings.setLastSignedInEmail(null);
    if (refreshToken != null) {
      try {
        await http.post(
          Uri.parse(_kRevokeEndpoint),
          body: {'token': refreshToken},
        );
      } catch (_) {
        // Best-effort only — local state is already cleared either way.
      }
    }
  }

  String get _redirectUri => '${Uri.base.origin}/';

  Future<void> _storeTokenResponse(Map<String, dynamic> json) async {
    _accessToken = json['access_token'] as String;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _accessTokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));

    final refreshToken = json['refresh_token'] as String?;
    if (refreshToken != null) {
      await _settings.setWebRefreshToken(refreshToken);
    }
    final idToken = json['id_token'] as String?;
    final email = idToken == null ? null : _emailFromIdToken(idToken);
    if (email != null) {
      await _settings.setLastSignedInEmail(email);
    }
  }

  void _stripAuthParamsFromUrl() {
    final clean = Uri.base.replace(queryParameters: const {});
    web.window.history.replaceState(null, '', clean.toString());
  }

  static String _randomUrlSafe(int length) {
    final random = Random.secure();
    final bytes = List<int>.generate(length, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static String? _emailFromIdToken(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final claims = jsonDecode(payload) as Map<String, dynamic>;
      return claims['email'] as String?;
    } catch (_) {
      return null;
    }
  }
}
