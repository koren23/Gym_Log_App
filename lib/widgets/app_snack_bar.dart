import 'package:flutter/material.dart';

/// One consistent snackbar style for the whole app (icon + message, red for
/// errors) instead of each screen calling the stock `ScaffoldMessenger`
/// directly with its own ad hoc content. Pass [onUndo] to show a trailing
/// "Undo" action (e.g. for a reversible delete) instead of/alongside the
/// plain message.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
  VoidCallback? onUndo,
}) {
  final theme = Theme.of(context);
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        backgroundColor: isError ? theme.colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? theme.colorScheme.onError : theme.colorScheme.onInverseSurface,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: isError ? theme.colorScheme.onError : null,
                ),
              ),
            ),
          ],
        ),
        action: onUndo == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                textColor: isError ? theme.colorScheme.onError : theme.colorScheme.inversePrimary,
                onPressed: onUndo,
              ),
      ),
    );
}
