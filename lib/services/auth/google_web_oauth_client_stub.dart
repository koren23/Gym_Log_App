import '../settings/app_settings_service.dart';

/// Non-web build target. [GoogleAuthService] always branches on `kIsWeb`
/// before touching this class, so nothing here should ever actually run —
/// every member throws rather than silently no-op'ing, so an accidental
/// call is obvious immediately instead of failing mysteriously later.
class GoogleWebOAuthClient {
  GoogleWebOAuthClient(AppSettingsService settings);

  Future<void> completePendingRedirectIfAny() => _unsupported();
  bool get hasStoredRefreshToken => _unsupported();
  String? get email => _unsupported();
  Future<String> getValidAccessToken() => _unsupported();
  Future<void> startInteractiveSignIn() => _unsupported();
  Future<void> signOut() => _unsupported();

  Never _unsupported() =>
      throw UnsupportedError('GoogleWebOAuthClient is web-only.');
}
