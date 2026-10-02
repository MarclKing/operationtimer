class KmTextParser {
  static String? extract(Iterable<String> lines) {
    final candidates = <_Candidate>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      final scanText = line
          .replaceAll(RegExp(r'\b\d{1,2}:\d{2}\b'), ' ')
          .replaceAll(RegExp(r'\b\d{1,2}[./-]\d{1,2}[./-]\d{2,4}\b'), ' ')
          .replaceAll(
            RegExp(r'[+-]?\d+(?:[.,]\d+)?\s*(?:°\s*[cf]?|grad)', caseSensitive: false),
            ' ',
          )
          .replaceAll(RegExp(r'\b\d{1,4}[.,]\d\b'), ' ');

      // Jede Zahlengruppe einzeln: "123.456", "123 456" oder "123456"
      final groups = RegExp(r'\d{1,3}(?:[.\s]\d{3})+|\d+')
          .allMatches(scanText)
          .map((m) => m.group(0)!.replaceAll(RegExp(r'[.\s]'), ''));

      for (final digits in groups) {
        final value = int.tryParse(digits);
        if (value == null || value < 1000 || value > 999999) continue;

        candidates.add(_Candidate(
          value: value,
          digitCount: digits.length,
          hasKmLabel: lower.contains('km'),
        ));
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) {
      if (a.hasKmLabel != b.hasKmLabel) return a.hasKmLabel ? -1 : 1;
      if (a.digitCount != b.digitCount) return b.digitCount.compareTo(a.digitCount);
      return b.value.compareTo(a.value);
    });
    return candidates.first.value.toString();
  }
}

class _Candidate {
  final int value;
  final int digitCount;
  final bool hasKmLabel;

  const _Candidate({
    required this.value,
    required this.digitCount,
    required this.hasKmLabel,
  });
}