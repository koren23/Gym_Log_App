/// The "Web application" type OAuth client ID from the same Google Cloud
/// project as the Sheets API + Android OAuth client. Required by
/// `google_sign_in` 7.x's Credential-Manager-based Android flow as
/// `serverClientId` — this is NOT the Android client ID (which only needs
/// to exist in the Cloud Console, matched via package name + SHA-1, and is
/// never referenced directly in code).
///
/// Also doubles as the Web platform's `clientId` (see
/// `GoogleAuthService.ensureInitialized`) — a "Web application" client ID
/// is exactly what `google_sign_in`'s web implementation expects. Its
/// Cloud Console entry's "Authorized JavaScript origins" list must include
/// wherever the web build is served from (e.g. the Firebase Hosting URL,
/// and `http://localhost:<port>` for local testing).
///
/// OAuth client IDs are not secret (unlike client secrets) and are safe to
/// commit/embed in app code — Google's docs treat them as public
/// identifiers.
const String kGoogleServerClientId =
    '607315964443-931jd2ehk6kt0eea0iko7bljc5su7ere.apps.googleusercontent.com';
