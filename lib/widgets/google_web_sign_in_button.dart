import 'package:flutter/widgets.dart';

import 'google_web_sign_in_button_stub.dart'
    if (dart.library.html) 'google_web_sign_in_button_web.dart'
    as impl;

/// The platform's own rendered Google Sign-In button, required on the web
/// (see [GoogleSignIn.supportsAuthenticate]) since a custom button can't
/// trigger the identity flow there. Returns null on platforms — Android,
/// iOS, desktop — where a normal button calling
/// `GoogleAuthService.signInInteractively` works instead.
Widget? googleWebSignInButton() => impl.googleWebSignInButton();
