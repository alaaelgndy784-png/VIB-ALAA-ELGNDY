const {test}=require('node:test');
const assert=require('node:assert/strict');
const crypto=require('node:crypto');
const {database,HttpsError,FieldValue:FV}=require('./test-fixtures');
const {signature,callbackSignature,verifyCallback,reconcile,createLink,refundFull,refreshRequest}=require('./geidea');
const KEY='00000000-0000-0000-0000-000000000001',INTENT='00000000-0000-0000-0000-000000000022',ORDER='00000000-0000-0000-0000-000000000011',OTHER='00000000-0000-0000-0000-000000000012';
function setup(mode='live') {
  const db=database();db.put('users/owner',{role:'owner',active:true});
  db.put('sales/invoice',{status:'completed',customerId:'c',total:100,paid:0,due:100,receiptPaid:0,revision:0});
  db.put('paymentRequests/abcdefghijklmnopqrst',{invoiceId:'invoice',customerId:'c',customerName:'عميل',amountCents:10000,paymentIntentId:INTENT,mode,state:'pending',revision:0});
  db.put('geideaIntents/'+INTENT,{requestId:'abcdefghijklmnopqrst',mode,merchantPublicKey:KEY});
  return db;
}
function snapshot(patch={}) {return {orderId:ORDER,paymentIntent:{id:INTENT},amount:100,totalCapturedAmount:100,totalRefundedAmount:0,
  currency:'EGP',status:'Success',detailedStatus:'Paid',merchantPublicKey:KEY,isTest:false,...patch};}
const config={enabled:true,mode:'live',publicKey:KEY,password:'FAKE_TEST',webhookUrl:'https://example.test/webhook'};
const input={requestId:'ABCDEFGHIJKLMNOPQRST',invoiceId:'invoice',phone:'+201000000000',email:'customer@example.test'};
test('callback HMAC covers documented fields and rejects altered amount, merchant and empty signature',()=>{
  const order=snapshot({merchantReferenceId:'reference'}),ts='2026-10-03T09:00:00Z';
  const expected=crypto.createHmac('sha256','FAKE_TEST').update(KEY+'100.00EGP'+ORDER+'Successrefer ence'.replace(' ','')+ts).digest('base64');
  assert.equal(callbackSignature(order,ts,config),expected);
  assert.equal(verifyCallback(order,ts,expected,config),true);
  assert.equal(verifyCallback({...order,amount:101},ts,expected,config),false);
  assert.equal(verifyCallback(order,ts,'',config),false);
});
test('successful callback retries collect once, reduce customer debt, preserve cash and stock',async()=>{
  const db=setup();await reconcile(db,FV,snapshot());await reconcile(db,FV,snapshot());
  assert.equal(db.read('customers/c').balance,0);assert.equal(db.read('sales/invoice').receiptPaid,100);
  assert.equal(db.read('sales/invoice').onlinePaid,100);assert.equal(db.read('settings/cash').balance,50);
  assert.equal(db.read('settings/geideaClearing').balance,100);assert.equal(db.read('stock/main_a').quantity,10);
});
test('test-mode success never updates live invoice, accounts, clearing or cash',async()=>{
  const db=setup('test');await reconcile(db,FV,snapshot({isTest:true}));
  assert.equal(db.read('customers/c').balance,100);assert.equal(db.read('sales/invoice').receiptPaid,0);
  assert.equal(db.read('settings/geideaClearing'),undefined);assert.equal(db.read('settings/cash').balance,50);
});
test('partial and full refunds restore exact debt and never deduct cash; stale refund is ignored',async()=>{
  const db=setup();await reconcile(db,FV,snapshot());
  await reconcile(db,FV,snapshot({totalRefundedAmount:25,detailedStatus:'PartiallyRefunded'}));
  assert.equal(db.read('customers/c').balance,25);assert.equal(db.read('sales/invoice').onlinePaid,75);
  await reconcile(db,FV,snapshot());assert.equal(db.read('customers/c').balance,25);
  await reconcile(db,FV,snapshot({totalRefundedAmount:100,detailedStatus:'Refunded'}));
  assert.equal(db.read('customers/c').balance,100);assert.equal(db.read('sales/invoice').onlinePaid,0);
  assert.equal(db.read('sales/invoice').receiptPaid,0);assert.equal(db.read('settings/geideaClearing').balance,0);
  assert.equal(db.read('settings/cash').balance,50);
});
test('changed invoice is flagged for review while actual received funds remain traceable',async()=>{
  const db=setup();db.put('sales/invoice',{...db.read('sales/invoice'),receiptPaid:60});
  assert.equal((await reconcile(db,FV,snapshot())).state,'review');
  assert.equal(db.read('customers/c').balance,100);assert.equal(db.read('sales/invoice').receiptPaid,60);
  assert.equal(db.read('settings/geideaClearing').balance,100);
});
test('two successful provider transactions cannot pay the same invoice twice',async()=>{
  const db=setup();await reconcile(db,FV,snapshot());await reconcile(db,FV,snapshot({orderId:OTHER}));
  assert.equal(db.read('customers/c').balance,0);assert.equal(db.read('sales/invoice').receiptPaid,100);
  assert.equal(db.read('settings/geideaClearing').balance,200);assert.equal(db.read('geideaTransactions/'+OTHER).state,'review');
});
test('general customer receipts remain account credit after card collection and refund',async()=>{
  const db=setup();db.put('customers/c',{...db.read('customers/c'),balance:20});await reconcile(db,FV,snapshot());
  assert.equal(db.read('customers/c').balance,-80);
  await reconcile(db,FV,snapshot({totalRefundedAmount:100,detailedStatus:'Refunded'}));assert.equal(db.read('customers/c').balance,20);
});
for(const [name,patch] of [['wrong merchant',{merchantPublicKey:OTHER}],['wrong amount',{amount:99.99}],['test substituted for live',{isTest:true}],['invalid refunded total',{totalRefundedAmount:100.01}]]) {
  test(name+' cannot change accounting',async()=>{const db=setup();await assert.rejects(reconcile(db,FV,snapshot(patch)));
    assert.equal(db.read('customers/c').balance,100);assert.equal(db.read('settings/geideaClearing'),undefined);});
}
test('pending, failed and authorization-only callbacks do not count as payment',async()=>{
  for(const patch of [{totalCapturedAmount:0,status:'InProgress'},{totalCapturedAmount:0,status:'Failed'},{totalCapturedAmount:0,detailedStatus:'Authorized'}]){const db=setup();assert.equal((await reconcile(db,FV,snapshot(patch))).state,'ignored');
    assert.equal(db.read('customers/c').balance,100);}
});
test('payment received after invoice return does not rewrite debt or restock goods',async()=>{
  const db=setup();db.put('sales/invoice',{...db.read('sales/invoice'),status:'returned'});await reconcile(db,FV,snapshot());
  assert.equal(db.read('geideaTransactions/'+ORDER).state,'review');assert.equal(db.read('customers/c').balance,100);
});
test('repeated link creation reuses exact request, never repeats provider call',async()=>{
  const db=setup();let calls=0;
  const fetcher=async()=>{calls++;return {ok:true,json:async()=>({responseCode:'000',paymentIntent:{paymentIntentId:OTHER,merchantPublicKey:KEY,link:'https://merchant.geidea.net/payByLink/test',amount:100,currency:'EGP',eInvoiceDetails:{merchantReferenceId:input.requestId}}})};};
  const first=await createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1000);
  const next=await createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1001);
  assert.equal(first.checkoutUrl,next.checkoutUrl);assert.equal(calls,1);assert.equal(db.read('settings/cash').balance,50);
});
test('unknown network outcome blocks duplicate payment creation',async()=>{
  const db=setup();let calls=0;const fetcher=async()=>{calls++;throw Error('timeout');};
  await assert.rejects(createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1000));
  assert.equal(db.read('paymentRequests/'+input.requestId).state,'creation_unknown');
  await assert.rejects(createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1001));assert.equal(calls,1);
});
test('staff cannot create a payment link, and disabled service cannot call provider',async()=>{
  const db=setup();const never=async()=>{throw Error('UNEXPECTED_NETWORK');};
  await assert.rejects(createLink(db,FV,HttpsError,'staff',input,config,never),{code:'permission-denied'});
  await assert.rejects(createLink(db,FV,HttpsError,'owner',input,{...config,enabled:false},never),{code:'failed-precondition'});
});
test('uncertain card refund cannot be submitted twice while awaiting confirmation',async()=>{
  const db=setup();await reconcile(db,FV,snapshot());let refundCalls=0;
  const fetcher=async(url)=>{
    if(url.includes('/pgw/api/v1/order/'))return {ok:true,json:async()=>({responseCode:'000',order:snapshot()})};
    if(url.endsWith('/refund')){refundCalls++;throw Error('timeout');}throw Error('UNEXPECTED_API');
  };
  await assert.rejects(refundFull(db,FV,HttpsError,'owner',ORDER,config,fetcher));
  assert.equal(db.read('geideaTransactions/'+ORDER).refundState,'unknown');
  await assert.rejects(refundFull(db,FV,HttpsError,'owner',ORDER,config,fetcher),{code:'failed-precondition'});
  assert.equal(refundCalls,1);assert.equal(db.read('settings/cash').balance,50);
});

test('captured amounts with failed status or unknown detail never affect accounts',async()=>{
  for(const patch of [{status:'Failed'},{detailedStatus:'Authorized'},{totalCapturedAmount:99}]){
    const db=setup();await assert.rejects(reconcile(db,FV,snapshot(patch)));assert.equal(db.read('customers/c').balance,100);
  }
});
test('refresh inquires authenticated provider details instead of trusting link paid status',async()=>{
  const db=setup();let calls=0;
  const fetcher=async url=>{calls++;return {ok:true,json:async()=>url.includes('/eInvoice/')?
    {responseCode:'000',paymentIntent:{paymentIntentId:INTENT,merchantPublicKey:KEY,amount:100,currency:'EGP',orders:[{orderId:ORDER}]}}:
    {responseCode:'000',order:snapshot()}};};
  await refreshRequest(db,FV,HttpsError,'owner','abcdefghijklmnopqrst',config,fetcher);
  assert.equal(calls,2);assert.equal(db.read('customers/c').balance,0);
});

test('ambiguous HTTP-200 provider error locks link creation instead of allowing another charge request',async()=>{
 const db=setup();let calls=0;
 const fetcher=async()=>{calls++;return {ok:true,json:async()=>({responseCode:'500'})};};
 await assert.rejects(createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1000));
 assert.equal(db.read('paymentRequests/'+input.requestId).state,'creation_unknown');
 await assert.rejects(createLink(db,FV,HttpsError,'owner',input,config,fetcher,()=>1001));assert.equal(calls,1);
});
test('reset account is held for review rather than receiving stale payment or refund balance edits',async()=>{
 const db=setup();db.put('paymentRequests/abcdefghijklmnopqrst',{...db.read('paymentRequests/abcdefghijklmnopqrst'),actorId:'owner',resetAtMs:0});
 db.put('users/owner',{role:'owner',active:true,resetAt:{toMillis:()=>1}});
 assert.equal((await reconcile(db,FV,snapshot())).state,'review');assert.equal(db.read('customers/c').balance,100);
 assert.equal(db.read('settings/geideaClearing').balance,100);
});
