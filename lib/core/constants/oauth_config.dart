export 'oauth_secret_local.dart';

/// The "Web application" type OAuth client ID from the same Google Cloud
/// project as the Sheets API + Android OAuth client. Required by
/// `google_sign_in` 7.x's Credential-Manager-based Android flow as
/// `serverClientId` — this is NOT the Android client ID (which only needs
/// to exist in the Cloud Console, matched via package name + SHA-1, and is
/// never referenced directly in code).
///
/// Also used as the `client_id` for the web build's own hand-rolled OAuth
/// flow (see `GoogleWebOAuthClient`) — its Cloud Console entry's
/// "Authorized redirect URIs" list must include wherever the web build is
/// served from (e.g. the Firebase Hosting URL; `http://localhost` on any
/// port is exempt from needing explicit registration for local testing).
///
/// OAuth client IDs are not secret (unlike client secrets) and are safe to
/// commit/embed in app code — Google's docs treat them as public
/// identifiers.
const String kGoogleServerClientId =
    '607315964443-931jd2ehk6kt0eea0iko7bljc5su7ere.apps.googleusercontent.com';

/// `kGoogleWebClientSecret` (the same OAuth client's secret, used only by
/// the web build's hand-rolled authorization-code+PKCE flow — see
/// `GoogleWebOAuthClient` — to exchange a code/refresh token; native
/// platforms never use this) is exported above from `oauth_secret_local.dart`,
/// a gitignored file not committed to source control — see
/// `oauth_secret_local.example.dart` for setup.
///
/// It's still embedded in the compiled web bundle and NOT cryptographically
/// secret once shipped (browser code can't keep a secret) — keeping it out
/// of git avoids the separate, worse exposure of a public repo/search
/// engines/bots scanning for it, not the shipped-JS exposure itself.
/// Accepted trade-off for a single-user personal app: worst case someone
/// extracts it and can present a consent screen claiming to be this app —
/// they still cannot access anyone's data without that person separately
/// consenting. A production/multi-user app would instead proxy token
/// exchange through a server that holds this value.
