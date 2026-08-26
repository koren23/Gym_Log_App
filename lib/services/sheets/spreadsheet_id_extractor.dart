final RegExp _kSpreadsheetIdPattern = RegExp(
  r'/spreadsheets/d/([a-zA-Z0-9-_]+)',
);

/// Extracts the spreadsheet ID from a Google Sheets URL, or returns null if
/// [input] doesn't look like a valid Sheets URL/ID.
String? extractSpreadsheetId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final match = _kSpreadsheetIdPattern.firstMatch(trimmed);
  if (match != null) return match.group(1);

  // Allow pasting the raw ID directly.
  if (RegExp(r'^[a-zA-Z0-9-_]{20,}$').hasMatch(trimmed)) return trimmed;

  return null;
}
