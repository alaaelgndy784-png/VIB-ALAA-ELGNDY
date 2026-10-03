import 'package:flutter_test/flutter_test.dart';
import '../lib/invoice_serial_core.dart';
class Store {
  final rows=<String,Map<String,dynamic>>{};int version=0;
  Future<InvoiceSerialPlan> allocate(String type,String id) async {
    for(var attempt=0;attempt<100;attempt++){
      final start=version,snapshot={for(final e in rows.entries)e.key:Map<String,dynamic>.from(e.value)};
      final plan=await reserveInvoiceSerial(type,id,(path)async=>snapshot[path]);
      if(version!=start)continue;
      if(!plan.existing){rows[plan.marker]=plan.data;rows[plan.claim]={'invoiceId':id,'invoiceType':type};rows[plan.counter]={'lastNumber':plan.data['internalNumber']};version++;}
      return plan;
    }
    throw StateError('Too much contention');
  }
}
void main(){
  test('32 concurrent invoices and transaction retries receive unique consecutive numbers',()async{
    final store=Store();final plans=await Future.wait(List.generate(32,(i)=>store.allocate('purchases','invoice$i')));
    final numbers=plans.map((p)=>p.data['internalNumber'] as int).toList()..sort();
    expect(numbers,List.generate(32,(i)=>i+1));expect(store.rows['settings/invoiceCounter_purchases']!['lastNumber'],32);
  });
  test('reopening the same purchase reuses its number, including after return',()async{
    final store=Store();final first=await store.allocate('purchases','one');final retry=await store.allocate('purchases','one');
    expect(retry.existing,true);expect(retry.data,first.data);expect(store.rows['settings/invoiceCounter_purchases']!['lastNumber'],1);
  });
  test('sale and purchase series are independent and their barcode values cannot collide',()async{
    final store=Store(),p=await store.allocate('purchases','same'),s=await store.allocate('sales','same');
    expect(p.data['internalNumber'],1);expect(s.data['internalNumber'],1);
    expect(p.data['invoiceBarcode'],'VIB-P-000001');expect(s.data['invoiceBarcode'],'VIB-S-000001');
  });
  test('reset or damaged counter fails before reusing a previously allocated number',()async{
    final store=Store();await store.allocate('purchases','one');store.rows['settings/invoiceCounter_purchases']={'lastNumber':0};
    await expectLater(store.allocate('purchases','two'),throwsStateError);expect(store.rows.containsKey('settings/invoiceSerial_purchases_two'),false);
  });
  test('a changed marker cannot silently replace the original invoice identity or barcode',()async{
    final store=Store();await store.allocate('purchases','one');store.rows['settings/invoiceSerial_purchases_one']!['invoiceBarcode']='VIB-S-000001';
    await expectLater(store.allocate('purchases','one'),throwsStateError);
  });
}
