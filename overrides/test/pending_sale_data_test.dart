import 'package:flutter_test/flutter_test.dart';
import '../lib/pending_sale_data.dart';

Map<String,dynamic> request(int n)=>{'customerId':'customer','credit':true,'paid':10.0,'total':-999,
  'items':[for(var i=0;i<n;i++){'productId':'p$i','quantity':2,'unitPrice':11.115,'basePrice':12.35,'discountPercent':10}]};
void main() {
  test('five and fifty item proposals recalculate totals instead of trusting supplied totals',() {
    for(final n in [5,50]) {
      final parsed=PendingSaleData.parse(request(n));
      expect(parsed.lines.length,n);expect(parsed.total,closeTo(n*22.23,0.000001));expect(parsed.paid,10);
      expect(parsed.lines.first.discount,10);expect(parsed.lines.first.basePrice,12.35);
    }
  });
  test('malformed or nonfinite proposal cannot be approved',() {
    for(final change in <void Function(Map<String,dynamic>)>[
      (d)=>d['items']=[],(d)=>d['items']=request(51)['items'],(d)=>d['customerId']='',
      (d)=>d['paid']=double.nan,(d)=>d['paid']=double.infinity,(d)=>d['paid']=-1,(d)=>d['paid']=100000,
      (d)=>d['credit']=false,(d)=>(d['items'] as List)[0]['quantity']=0,
      (d)=>(d['items'] as List)[0]['quantity']=1.5,(d)=>(d['items'] as List)[0]['quantity']=1000001,
      (d)=>(d['items'] as List)[0]['unitPrice']=double.nan,
      (d)=>(d['items'] as List)[0]['basePrice']=double.infinity,
      (d)=>(d['items'] as List)[0]['discountPercent']=101,
      (d)=>(d['items'] as List)[1]['productId']='p0',
      (d)=>(d['items'] as List)[0]['productId']='bad/path',
    ]) {final draft=request(5);change(draft);expect(()=>PendingSaleData.parse(draft),throwsFormatException);}
  });
  test('cash proposal must pay the complete calculated amount',() {
    final draft=request(5);draft['credit']=false;draft['paid']=5*22.23;
    expect(PendingSaleData.parse(draft).paid,closeTo(111.15,0.000001));
  });
}
