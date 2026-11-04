import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('quota rejection does not claim a completed return', () {
    final message = returnFailureMessage(FirebaseException(
      plugin: 'cloud_firestore', code: 'resource-exhausted'));
    expect(message, contains('Firebase'));
    expect(message, contains('resource-exhausted'));
    expect(message, contains('لم يتأكد'));
    expect(message, contains('لا تكرر'));
    expect(message, isNot(contains('تم تسجيل المرتجع بنجاح')));
  });

  test('offline return cannot be presented as confirmed', () {
    final message = returnFailureMessage(FirebaseException(
      plugin: 'cloud_firestore', code: 'unavailable'));
    expect(message, contains('لا يمكن تأكيد'));
  });
}
