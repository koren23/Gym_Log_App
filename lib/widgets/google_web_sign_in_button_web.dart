import 'package:flutter/widgets.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:google_sign_in_web/google_sign_in_web.dart';

Widget? googleWebSignInButton() {
  final platform = GoogleSignInPlatform.instance;
  if (platform is! GoogleSignInPlugin) return null;
  return platform.renderButton();
}
