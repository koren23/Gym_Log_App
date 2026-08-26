/// Capitalizes the first letter of each word — used to display muscle
/// names from the hand-typed "Exercises" sheet (e.g. "upper chest") in a
/// consistent title-cased style, matching the app's other section headers.
String titleCase(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');
