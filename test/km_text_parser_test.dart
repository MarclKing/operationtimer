import 'package:flutter_test/flutter_test.dart';
import 'package:OpTimes/utils/km_text_parser.dart';

void main() {
  group('KmTextParser', () {
    test('reads a mileage when OCR combines it with time and temperature', () {
      expect(
        KmTextParser.extract(['12:32 +21.0°C 123.456 km']),
        '123456',
      );
    });

    test('ignores dates and decimal trip counters', () {
      expect(KmTextParser.extract(['03.07.2026', '9.917,7']), isNull);
    });

    test('prefers a value labeled as kilometers', () {
      expect(KmTextParser.extract(['12345', '98765 km']), '98765');
    });
  });
}