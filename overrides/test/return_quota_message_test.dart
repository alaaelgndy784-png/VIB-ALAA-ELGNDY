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

  test('local sale PDF uses provisional identity and omits unconfirmed balances', () {
    final source=<String,dynamic>{'total':250.0,'paid':100.0,
      'draftStoredAtMs':123456789,'customerBalanceAfter':900.0,
      'customerPreviousBalance':750.0,'receiptPaid':20.0,
      'items':[{'productName':'Sample','quantity':2,'unitPrice':125.0}]};
    final pdf=localSalePdfData('unique-local-id',source);
    expect(pdf['invoiceNumber'],'L-unique-local-id');
    expect(pdf['localUnconfirmed'],isTrue);
    expect(pdf['status'],'pending');
    expect(pdf['due'],150.0);
    expect(pdf.containsKey('customerBalanceAfter'),isFalse);
    expect(pdf.containsKey('customerPreviousBalance'),isFalse);
    expect(pdf.containsKey('receiptPaid'),isFalse);
    expect(source['customerBalanceAfter'],900.0);
    expect(localSalePdfData('id',{...source,'invoiceNumber':'001234'})['invoiceNumber'],'001234');
  });

  test('offline return cannot be presented as confirmed', () {
    final message = returnFailureMessage(FirebaseException(
      plugin: 'cloud_firestore', code: 'unavailable'));
    expect(message, contains('لا يمكن تأكيد'));
  });
}
