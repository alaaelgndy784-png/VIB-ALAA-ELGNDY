import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  group('parseReceiptAmount', () {
    test('parses Arabic digits and Arabic decimal separator', () {
      expect(parseReceiptAmount('١٢٣٫٥٠'), 123.5);
    });

    test('parses Arabic thousands and decimal separators', () {
      expect(parseReceiptAmount('١٬٢٣٤٫٥٠'), 1234.5);
    });

    test('rejects invalid and non-finite values', () {
      expect(parseReceiptAmount('غير صحيح'), isNull);
      expect(parseReceiptAmount('NaN'), isNull);
      expect(parseReceiptAmount('Infinity'), isNull);
    });
  });
}
