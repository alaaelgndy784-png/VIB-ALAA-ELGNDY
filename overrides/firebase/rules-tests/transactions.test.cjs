const {test,before,after,beforeEach}=require('node:test');
const {readFileSync}=require('node:fs');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,writeBatch,getDoc,serverTimestamp,runTransaction,deleteDoc,getDocs,collection,query,orderBy}=require('firebase/firestore');
const assert=require('node:assert/strict');
let env;
before(async()=>{env=await initializeTestEnvironment({projectId:'demo-vib',firestore:{rules:readFileSync('../firestore.rules','utf8')}})});
after(async()=>{await env.cleanup()});
beforeEach(async()=>{await env.clearFirestore();await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  await setDoc(doc(db,'users/staff'),{role:'employee',active:true,name:'Staff',branchId:'staffbranch'});
  await setDoc(doc(db,'users/owner'),{role:'owner',active:true,name:'Owner'});
  await setDoc(doc(db,'users/inactive'),{role:'employee',active:false,branchId:'staffbranch'});
  await setDoc(doc(db,'customers/customer'),{name:'Customer',phone:'010',balance:100,active:true});
  await setDoc(doc(db,'suppliers/supplier'),{name:'Supplier',balance:100,active:true});
  await setDoc(doc(db,'settings/cash'),{balance:500});
  for(let i=0;i<8;i++){
    await setDoc(doc(db,'products/p'+i),{name:'Product'+i,active:true,price:12.35,purchasePrice:5});
    await setDoc(doc(db,'stock/main_p'+i),{branchId:'main',productId:'p'+i,quantity:10});
  }
})});
function newEmployeeCustomer(overrides={}) {
  return {name:'New Customer',phone:'01123456789',address:'',note:'',openingBalance:0,balance:0,active:true,
    createdAt:serverTimestamp(),updatedAt:serverTimestamp(),...overrides};
}
test('employee customer creation is disabled until owner grants the explicit permission',async()=>{
 const staff=env.authenticatedContext('staff').firestore();
 await assertFails(setDoc(doc(staff,'customers/staff-denied'),newEmployeeCustomer()));
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'users/staff'),{canAddCustomer:true},{merge:true}));
 await assertSucceeds(setDoc(doc(staff,'customers/staff-added'),newEmployeeCustomer()));
 await assertFails(setDoc(doc(staff,'customers/staff-opening-balance'),newEmployeeCustomer({openingBalance:50,balance:50})));
});
test('customer-add permission does not authorize adding suppliers',async()=>{
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'users/staff'),{canAddCustomer:true},{merge:true}));
 const staff=env.authenticatedContext('staff').firestore();
 await assertFails(setDoc(doc(staff,'suppliers/staff-added'),newEmployeeCustomer()));
});
function saleBatch(db,{n=1,paid,customer=true,mutate=()=>{},omit='',saleId='sale',cashBefore=500,createCash=false,unitPrice=12.35}={}){
  const items=Array.from({length:n},(_,i)=>({productId:'p'+i,productName:'Product'+i,quantity:2,unitPrice,lineTotal:unitPrice*2,purchasePriceAtSale:5}));
  const total=n*unitPrice*2,payment=paid??total,due=total-payment;
  const s={id:saleId,branchId:'staffbranch',stockBranchId:'main',employeeId:'staff',customerId:customer?'customer':'',
    customerName:customer?'Customer':'',customerPhone:customer?'010':'',customerPreviousBalance:customer?100:0,
    customerBalanceAfter:customer?100+due:0,items,itemCount:n,stockIndex:Object.fromEntries(items.map((x,i)=>[x.productId,i])),
    total,paid:payment,due,cashBefore,cashAfter:cashBefore+payment,paymentStatus:due>0?'credit':'cash',status:'completed',createdAt:serverTimestamp(),requestKey:'test'};
  if(n===1)Object.assign(s,{productId:'p0',productName:'Product0',quantity:2,unitPrice});
  mutate(s);
  const batch=writeBatch(db);batch.set(doc(db,'sales/'+saleId),s);
  for(const x of items){
    if(omit!==x.productId)batch.update(doc(db,'stock/main_'+x.productId),{quantity:10-x.quantity,lastSaleId:saleId});
    if(omit!=='stockMovement')batch.set(doc(db,'stockMovements/'+saleId+'_'+x.productId),{productId:x.productId,productName:x.productName,
      branchId:'main',kind:'sale',quantity:-x.quantity,balanceAfter:10-x.quantity,referenceId:saleId,actorId:'staff',createdAt:serverTimestamp()});
  }
  if(due>0){
    if(omit!=='customer')batch.update(doc(db,'customers/customer'),{balance:100+due,lastSaleId:saleId,updatedAt:serverTimestamp()});
    if(omit!=='customerMovement')batch.set(doc(db,'accountMovements/'+saleId+'_customer'),{accountType:'customers',accountId:'customer',accountName:'Customer',
      kind:'sale',amount:due,balanceBefore:100,balanceAfter:100+due,referenceId:saleId,actorId:'staff',createdAt:serverTimestamp()});
  }
  if(payment>0){
    if(omit!=='cash')(createCash ? batch.set.bind(batch) : batch.update.bind(batch))(doc(db,'settings/cash'),{balance:cashBefore+payment,lastSaleId:saleId,updatedAt:serverTimestamp()});
    if(omit!=='cashMovement')batch.set(doc(db,'accountMovements/'+saleId+'_cash'),{accountType:'cash',accountId:customer?'customer':'',accountName:customer?'Customer':'',
      kind:'sale',amount:payment,delta:payment,balanceBefore:cashBefore,balanceAfter:cashBefore+payment,referenceId:saleId,reason:'Sale',actorId:'staff',createdAt:serverTimestamp()});
  }
  return batch.commit();
}
test('staff reads main stock and nonexistent own retry invoice',async()=>{
  const db=env.authenticatedContext('staff').firestore();await assertSucceeds(getDoc(doc(db,'stock/main_p0')));
  await assertSucceeds(getDoc(doc(db,'sales/new')));
});
for(const n of [1,2,3,4])for(const paid of [0,10,undefined])test(`${n} lines paid ${paid}`,async()=>{
  const db=env.authenticatedContext('staff').firestore();await assertSucceeds(saleBatch(db,{n,paid}));
  const s=(await getDoc(doc(db,'sales/sale'))).data();assert.equal(s.itemCount,n);
});
test('cash sale without customer',async()=>assertSucceeds(saleBatch(env.authenticatedContext('staff').firestore(),{n:4,customer:false})));
for(const omit of ['p0','stockMovement','cash','customer','cashMovement','customerMovement'])test('missing '+omit+' rejects atomically',async()=>{
  const db=env.authenticatedContext('staff').firestore();await assertFails(saleBatch(db,{paid:10,omit}));
  assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,10);
});
for(const [name,mutate] of [
  ['wrong price',s=>{s.items[0].unitPrice=1;s.items[0].lineTotal=2}],
  ['wrong branch',s=>{s.branchId='other'}],['wrong actor',s=>{s.employeeId='owner'}],
  ['wrong total',s=>{s.total=1}],['negative paid',s=>{s.paid=-1}],
  ['duplicate item',s=>{s.items[1]={...s.items[0]};s.stockIndex={p0:0}}],
  ['oversell',s=>{s.items[0].quantity=11}],['fake cost',s=>{s.items[0].purchasePriceAtSale=0}],
])test(name+' denied',async()=>assertFails(saleBatch(env.authenticatedContext('staff').firestore(),{n:2,mutate})));
test('inactive employee denied',async()=>assertFails(saleBatch(env.authenticatedContext('inactive').firestore())));
test('staff cannot edit sales or purchases or create invoice edit journal',async()=>{
  const owner=env.authenticatedContext('owner').firestore(),staff=env.authenticatedContext('staff').firestore();
  await setDoc(doc(owner,'sales/old'),{status:'completed',branchId:'staffbranch',total:10,paid:10,due:0});
  await assertFails(setDoc(doc(staff,'sales/old'),{total:100},{merge:true}));
  await assertFails(setDoc(doc(staff,'purchases/new'),{total:100}));
  await assertFails(setDoc(doc(staff,'invoiceEdits/new'),{actorId:'staff'}));
});
test('owner additions update same invoice with revision and journal',async()=>{
  const db=env.authenticatedContext('owner').firestore();
  await setDoc(doc(db,'purchases/old'),{status:'completed',total:10,paid:5,due:5,createdAt:serverTimestamp()});
  const batch=writeBatch(db);
  batch.update(doc(db,'purchases/old'),{items:[{productId:'p0',quantity:3,unitCost:5,lineTotal:15}],itemCount:1,total:15,paid:10,due:5,
    paymentStatus:'credit',revision:1,updatedAt:serverTimestamp(),lastEditedBy:'owner'});
  batch.set(doc(db,'invoiceEdits/edit'),{invoiceId:'old',actorId:'owner'});
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(doc(db,'invoiceEdits/edit'),{actorId:'owner'},{merge:true}));
});
test('employee receipt still reduces customer balance and credits cash atomically',async()=>{
  const db=env.authenticatedContext('staff').firestore(),b=writeBatch(db),ts=serverTimestamp();
  b.set(doc(db,'receipts/r'),{customerId:'customer',customerName:'Customer',customerPhone:'010',amount:20,balanceBefore:100,balanceAfter:80,
    cashBefore:500,cashAfter:520,actorId:'staff',actorName:'Staff',branchId:'staffbranch',note:'',createdAt:ts,customerMovementId:'rc',cashMovementId:'rk'});
  b.update(doc(db,'customers/customer'),{balance:80,lastReceiptId:'r',updatedAt:ts});
  b.update(doc(db,'settings/cash'),{balance:520,lastReceiptId:'r',updatedAt:ts});
  for(const cash of [false,true])b.set(doc(db,'accountMovements/'+(cash?'rk':'rc')),{accountType:cash?'cash':'customers',accountId:'customer',accountName:'Customer',kind:cash?'customerCollection':'collection',amount:20,...(cash?{delta:20}:{}),balanceBefore:cash?500:100,balanceAfter:cash?520:80,referenceId:'r',reason:'',actorId:'staff',branchId:'staffbranch',createdAt:ts});
  await assertSucceeds(b.commit());
});
test('replaying saved sale cannot deduct stock twice',async()=>{
  const db=env.authenticatedContext('staff').firestore();await saleBatch(db,{paid:10});
  await assertFails(saleBatch(db,{paid:10}));
  assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,8);
});
test('unregistered signed-in user can read own profile and request pending access',async()=>{
  const db=env.authenticatedContext('new',{email:'new@example.com'}).firestore();
  await assertSucceeds(getDoc(doc(db,'users/new')));
  await assertSucceeds(setDoc(doc(db,'users/new'),{role:'pending',active:false,name:'New',phone:'010',createdAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db,'users/new'),{role:'owner',active:true},{merge:true}));
});
test('maximum mixed invoice after prior receipt and sale markers',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();await setDoc(doc(db,'settings/cash'),{lastReceiptId:'older',lastSaleId:'older'},{merge:true});
    await setDoc(doc(db,'customers/customer'),{lastReceiptId:'older',lastSaleId:'older'},{merge:true});
    for(let i=0;i<4;i++)await setDoc(doc(db,'stock/main_p'+i),{lastSaleId:'older'},{merge:true});
  });
  await assertSucceeds(saleBatch(env.authenticatedContext('staff').firestore(),{n:4,paid:10}));
});
test('first mixed sale creates cash record atomically',async()=>{
  await env.withSecurityRulesDisabled(ctx=>deleteDoc(doc(ctx.firestore(),'settings/cash')));
  await assertSucceeds(saleBatch(env.authenticatedContext('staff').firestore(),{n:4,paid:10,cashBefore:0,createCash:true}));
});
test('five staff lines are rejected before partial writes',async()=>assertFails(saleBatch(env.authenticatedContext('staff').firestore(),{n:5})));
test('orphan stock movement is denied',async()=>assertFails(setDoc(doc(env.authenticatedContext('staff').firestore(),'stockMovements/orphan_p0'),{
  productId:'p0',productName:'Product0',branchId:'main',kind:'sale',quantity:-2,balanceAfter:8,referenceId:'orphan',actorId:'staff',createdAt:serverTimestamp()})));

function chatBatch(db,{employeeId='staff',senderId='staff',senderName='Staff',senderRole='employee',text='Question about invoice',messageId='m1',summary=true,audio={}}={}){
 const batch=writeBatch(db);
 batch.set(doc(db,`staffChats/${employeeId}/messages/${messageId}`),{senderId,senderName,senderRole,text,...audio,createdAt:serverTimestamp()});
 if(summary)batch.set(doc(db,`staffChats/${employeeId}`),{employeeId,employeeName:'Staff',branchId:'staffbranch',lastMessageId:messageId,lastText:text,lastSenderId:senderId,lastSenderRole:senderRole,lastMessageAt:serverTimestamp()},{merge:true});
 return batch.commit();
}
test('staff sends message, owner reads and replies; both can query message history',async()=>{
 const staff=env.authenticatedContext('staff').firestore(),owner=env.authenticatedContext('owner').firestore();
 await assertSucceeds(chatBatch(staff));
 const first=(await assertSucceeds(getDoc(doc(owner,'staffChats/staff')))).data();
 assert.equal(first.lastText,'Question about invoice');
 await assertSucceeds(setDoc(doc(owner,'staffChats/staff'),{ownerReadAt:first.lastMessageAt},{merge:true}));
 await assertSucceeds(chatBatch(owner,{senderId:'owner',senderName:'Owner',senderRole:'owner',text:'Reply from manager',messageId:'m2'}));
 const reply=(await getDoc(doc(staff,'staffChats/staff'))).data();
 assert.equal(reply.lastSenderRole,'owner');
 await assertSucceeds(setDoc(doc(staff,'staffChats/staff'),{employeeReadAt:reply.lastMessageAt},{merge:true}));
 await assertSucceeds(getDocs(query(collection(staff,'staffChats/staff/messages'),orderBy('createdAt','desc'))));
 await assertSucceeds(getDocs(collection(owner,'staffChats')));
});
test('other employee cannot read, query, write, or mark another employee chat',async()=>{
 const staff=env.authenticatedContext('staff').firestore();await chatBatch(staff);
 await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),'users/other'),{role:'employee',active:true,name:'Other',branchId:'staffbranch'}));
 const other=env.authenticatedContext('other').firestore();
 await assertFails(getDoc(doc(other,'staffChats/staff')));
 await assertFails(getDocs(collection(other,'staffChats/staff/messages')));
 await assertFails(chatBatch(other,{senderId:'other',senderName:'Other',messageId:'m2'}));
 await assertFails(setDoc(doc(other,'staffChats/staff'),{employeeReadAt:serverTimestamp()},{merge:true}));
 await assertFails(getDocs(collection(staff,'staffChats')));
});
for(const [name,options] of [['fake sender',{senderId:'owner'}],['fake role',{senderRole:'owner'}],['fake name',{senderName:'Owner'}],['empty text',{text:''}],['oversize text',{text:'x'.repeat(2001)}],['missing summary',{summary:false}]])
 test('chat rejects '+name,async()=>assertFails(chatBatch(env.authenticatedContext('staff').firestore(),options)));
test('inactive and signed out cannot access chats',async()=>{
 await chatBatch(env.authenticatedContext('staff').firestore());
 for(const context of [env.authenticatedContext('inactive'),env.unauthenticatedContext()]){
  await assertFails(getDoc(doc(context.firestore(),'staffChats/staff/messages/m1')));
  await assertFails(chatBatch(context.firestore(),{messageId:'m2'}));
 }
});
test('messages are immutable and staff cannot change owner read status',async()=>{
 const staff=env.authenticatedContext('staff').firestore();await chatBatch(staff);
 await assertFails(setDoc(doc(staff,'staffChats/staff/messages/m1'),{text:'edited'},{merge:true}));
 await assertFails(deleteDoc(doc(staff,'staffChats/staff/messages/m1')));
 await assertFails(setDoc(doc(staff,'staffChats/staff'),{ownerReadAt:serverTimestamp()},{merge:true}));
});

async function seedEditableSale({receiptId='',latestReceipt=false,linkedOther=false}={}){
 await env.withSecurityRulesDisabled(async ctx=>{
  const db=ctx.firestore();
  await setDoc(doc(db,'sales/editable'),{id:'editable',branchId:'staffbranch',customerId:'customer',status:'completed',total:30,paid:0,due:30,revision:0,createdAt:new Date('2026-01-01'),...(receiptId?{receiptId,receiptPaid:10}:{})});
  if(latestReceipt){
   await setDoc(doc(db,'receipts/prior'),{customerId:'customer',amount:10,createdAt:new Date('2026-01-02'),...(linkedOther?{invoiceId:'other'}:{})});
   await setDoc(doc(db,'customers/customer'),{lastReceiptId:'prior'},{merge:true});
  }
 });
}
function editSaleBatch(db){
 const b=writeBatch(db);
 b.update(doc(db,'sales/editable'),{total:20,paid:0,due:20,items:[{productId:'p0',quantity:2,unitPrice:10,lineTotal:20}],itemCount:1,stockIndex:{p0:0},revision:1,lastEditedBy:'owner',updatedAt:serverTimestamp()});
 return b.commit();
}
test('owner can replace unlinked invoice contents on same ID',async()=>{
 await seedEditableSale();await assertSucceeds(editSaleBatch(env.authenticatedContext('owner').firestore()));
});
test('linked receipt prevents financial invoice edit even for owner',async()=>{
 await seedEditableSale({receiptId:'r'});await assertFails(editSaleBatch(env.authenticatedContext('owner').firestore()));
});
test('legacy general customer receipt blocks older invoice edits',async()=>{
 await seedEditableSale({latestReceipt:true});await assertFails(editSaleBatch(env.authenticatedContext('owner').firestore()));
});
test('receipt explicitly linked to another invoice does not lock this invoice',async()=>{
 await seedEditableSale({latestReceipt:true,linkedOther:true});await assertSucceeds(editSaleBatch(env.authenticatedContext('owner').firestore()));
});
test('staff cannot replace invoice financial contents',async()=>{
 await seedEditableSale();await assertFails(editSaleBatch(env.authenticatedContext('staff').firestore()));
});
test('owner can atomically record a partial sales return on an invoice with a linked receipt',async()=>{
 await seedEditableSale({receiptId:'linked'});
 const db=env.authenticatedContext('owner').firestore(),b=writeBatch(db),ts=serverTimestamp();
 b.set(doc(db,'salesReturns/partial1'),{sourceInvoiceId:'editable',returnType:'partial',sourceItemIndex:0,
  items:[{sourceItemIndex:0,productId:'p0',productName:'Product0',quantity:1,unitPrice:12.35,lineTotal:12.35}],
  total:12.35,cashRefund:0,debtReduction:12.35,branchId:'main',customerId:'customer',customerName:'Customer',
  invoiceNumber:'1',internalNumber:1,invoiceBarcode:'',createdAt:ts,actorId:'owner'});
 b.update(doc(db,'sales/editable'),{partialReturnQuantities:{'0':1},partialReturnTotal:12.35,
  partialCashRefund:0,partialDebtReduction:12.35,lastPartialReturnId:'partial1'});
 await assertSucceeds(b.commit());
 assert.equal((await getDoc(doc(db,'sales/editable'))).data().partialReturnTotal,12.35);
});
test('owner cannot update partial-return summary without a matching return record',async()=>{
 await seedEditableSale({receiptId:'linked'});
 const db=env.authenticatedContext('owner').firestore();
 await assertFails(setDoc(doc(db,'sales/editable'),{partialReturnQuantities:{'0':1},partialReturnTotal:12.35,
  partialCashRefund:0,partialDebtReduction:12.35,lastPartialReturnId:'missing'},{merge:true}));
});
test('staff receipt links invoice atomically and prevents later edits',async()=>{
 await seedEditableSale();
 const db=env.authenticatedContext('staff').firestore(),b=writeBatch(db),ts=serverTimestamp();
 b.set(doc(db,'receipts/linked'),{invoiceId:'editable',customerId:'customer',customerName:'Customer',customerPhone:'010',amount:20,balanceBefore:100,balanceAfter:80,
  cashBefore:500,cashAfter:520,actorId:'staff',actorName:'Staff',branchId:'staffbranch',note:'',createdAt:ts,customerMovementId:'lc',cashMovementId:'lk'});
 b.update(doc(db,'customers/customer'),{balance:80,lastReceiptId:'linked',updatedAt:ts});
 b.update(doc(db,'settings/cash'),{balance:520,lastReceiptId:'linked',updatedAt:ts});
 b.update(doc(db,'sales/editable'),{receiptId:'linked',receiptPaid:20});
 for(const cash of [false,true])b.set(doc(db,'accountMovements/'+(cash?'lk':'lc')),{accountType:cash?'cash':'customers',accountId:'customer',accountName:'Customer',kind:cash?'customerCollection':'collection',amount:20,...(cash?{delta:20}:{}),balanceBefore:cash?500:100,balanceAfter:cash?520:80,referenceId:'linked',reason:'',actorId:'staff',branchId:'staffbranch',createdAt:ts});
 await assertSucceeds(b.commit());
 await assertFails(editSaleBatch(env.authenticatedContext('owner').firestore()));
});
test('orphan invoice receipt link is denied',async()=>{
 await seedEditableSale();
 await assertFails(setDoc(doc(env.authenticatedContext('owner').firestore(),'sales/editable'),{receiptId:'fake',receiptPaid:20},{merge:true}));
});

test('staff reads print branding but cannot change it or read manager settings',async()=>{
 await env.withSecurityRulesDisabled(async ctx=>{
  await setDoc(doc(ctx.firestore(),'settings/invoiceBranding'),{companyName:'VIB',phone:'01000000000',invoiceFooter:'Thank you'});
  await setDoc(doc(ctx.firestore(),'settings/main'),{companyName:'VIB',resetAt:new Date()});
 });
 const db=env.authenticatedContext('staff').firestore();
 await assertSucceeds(getDoc(doc(db,'settings/invoiceBranding')));
 await assertFails(setDoc(doc(db,'settings/invoiceBranding'),{companyName:'Fake'}));
 await assertFails(getDoc(doc(db,'settings/main')));
});

test('voice messages retain participant permissions and require bounded audio fields',async()=>{
 const staff=env.authenticatedContext('staff').firestore(), owner=env.authenticatedContext('owner').firestore();
 const audio={audioBase64:'YXVkaW8=',audioSeconds:5,audioMime:'audio/mp4'};
 await assertSucceeds(chatBatch(staff,{text:'رسالة صوتية',audio}));
 await assertSucceeds(getDoc(doc(owner,'staffChats/staff/messages/m1')));
 await assertSucceeds(chatBatch(owner,{senderId:'owner',senderName:'Owner',senderRole:'owner',messageId:'reply',text:'رسالة صوتية',audio}));
 for (const [i,bad] of [{audioSeconds:61},{audioSeconds:0},{audioBase64:'x'.repeat(800001)},{audioMime:'video/mp4'},{audioBase64:''}].entries())
   await assertFails(chatBatch(staff,{messageId:'bad'+i,text:'رسالة صوتية',audio:{...audio,...bad}}));
 await assertFails(chatBatch(staff,{messageId:'partial',audio:{audioSeconds:5}}));
 await assertFails(chatBatch(staff,{messageId:'badtext',audio}));
});


function productImportBatch(db, quantities) {
 const batch=writeBatch(db),ts=serverTimestamp();
 quantities.forEach((quantity,i)=>{
  const id='import_test_'+i,marker='productImport_test_'+i;
  batch.set(doc(db,'products/'+id),{name:'Import product '+i,externalCode:'test_'+i,purchasePrice:10.05,price:11.06,active:true,category:'غير مصنف',updatedAt:ts});
  batch.set(doc(db,'stock/main_'+id),{branchId:'main',productId:id,quantity});
  if(quantity!==0){
   batch.set(doc(db,'stockAdjustments/'+marker),{productId:id,productName:'Import product '+i,branchId:'main',before:0,after:quantity,delta:quantity,reason:'Product import',actorId:'owner',createdAt:ts});
   batch.set(doc(db,'stockMovements/'+marker),{productId:id,productName:'Import product '+i,branchId:'main',kind:'adjustment',quantity,balanceAfter:quantity,reason:'Product import',referenceId:marker,actorId:'owner',createdAt:ts});
  }
  batch.set(doc(db,'settings/'+marker),{kind:'productImport',requestKey:'test',productId:id,actorId:'owner',quantityBefore:0,quantityAfter:quantity,productBefore:null,stockBefore:null,createdAt:ts});
 });
 return batch.commit();
}
test('owner imports a full 20-row chunk including zero and negative stocks without changing cash or accounts',async()=>{
 const db=env.authenticatedContext('owner').firestore();
 await assertSucceeds(productImportBatch(db,Array.from({length:20},(_,i)=>i===0?0:i===1?-3:i)));
 assert.equal((await getDoc(doc(db,'stock/main_import_test_0'))).data().quantity,0);
 assert.equal((await getDoc(doc(db,'stock/main_import_test_1'))).data().quantity,-3);
 assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,500);
 assert.equal((await getDoc(doc(db,'customers/customer'))).data().balance,100);
 assert.equal((await getDoc(doc(db,'suppliers/supplier'))).data().balance,100);
 assert.equal((await getDoc(doc(db,'settings/productImport_test_19'))).data().quantityAfter,19);
});
test('fractional import stock rejects the entire chunk including products and replay markers',async()=>{
 const db=env.authenticatedContext('owner').firestore();
 await assertFails(productImportBatch(db,[0,11.92]));
 assert.equal((await getDoc(doc(db,'products/import_test_0'))).exists(),false);
 assert.equal((await getDoc(doc(db,'settings/productImport_test_0'))).exists(),false);
});
test('staff and inactive accounts cannot bulk import products and opening stock',async()=>{
 for(const uid of ['staff','inactive']) await assertFails(productImportBatch(env.authenticatedContext(uid).firestore(),[0,-3,12]));
});


test('card-paid invoice rejects client return but permits printing; confirmed full refund permits return',async()=>{
 await seedEditableSale();
 await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),'sales/editable'),{onlinePaid:30,onlinePaymentEver:true,receiptPaid:30},{merge:true}));
 const db=env.authenticatedContext('owner').firestore();
 await assertFails(setDoc(doc(db,'sales/editable'),{status:'returned',returnedAt:serverTimestamp()},{merge:true}));
 await assertSucceeds(setDoc(doc(db,'sales/editable'),{printedAt:serverTimestamp(),printedBy:'owner'},{merge:true}));
 await assertFails(editSaleBatch(db));
 await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),'sales/editable'),{onlinePaid:0,receiptPaid:0},{merge:true}));
 await assertSucceeds(setDoc(doc(db,'sales/editable'),{status:'returned',returnedAt:serverTimestamp()},{merge:true}));
});
test('payment requests, provider transactions and clearing totals cannot be fabricated by a client',async()=>{
 const db=env.authenticatedContext('owner').firestore();
 for(const path of ['paymentRequests/fake','geideaIntents/fake','geideaTransactions/fake','settings/geideaClearing'])
   await assertFails(setDoc(doc(db,path),{balance:100,state:'paid'}));
});


async function transferSale(db,{customerId='newcustomer',name='New Customer',phone='011',due=30}={}){
 const b=writeBatch(db);
 b.update(doc(db,'sales/editable'),{customerId,customerName:name,customerPhone:phone,customerBalanceAfter:20+due,
   total:30,paid:30-due,due,paymentStatus:due>0?'credit':'cash',revision:1,lastEditedBy:'owner',updatedAt:serverTimestamp()});
 b.update(doc(db,'customers/customer'),{balance:70,updatedAt:serverTimestamp()});
 b.update(doc(db,'customers/newcustomer'),{balance:20+due,updatedAt:serverTimestamp()});
 b.set(doc(db,'invoiceEdits/transfer'),{invoiceId:'editable',invoiceType:'sales',customerIdBefore:'customer',customerIdAfter:customerId,actorId:'owner'});
 return b.commit();
}
async function seedTransfer(options={}){
 await seedEditableSale(options);
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'customers/newcustomer'),{name:'New Customer',phone:'011',balance:20,active:true}));
}
test('owner transfers unlinked invoice to real customer atomically without changing identity',async()=>{
 await seedTransfer();const db=env.authenticatedContext('owner').firestore();
 await assertSucceeds(transferSale(db));
 const invoice=(await getDoc(doc(db,'sales/editable'))).data();
 assert.equal(invoice.id,'editable');assert.equal(invoice.customerId,'newcustomer');assert.equal(invoice.createdAt.toDate().getTime(),new Date('2026-01-01').getTime());
 assert.equal((await getDoc(doc(db,'customers/customer'))).data().balance,70);
 assert.equal((await getDoc(doc(db,'customers/newcustomer'))).data().balance,50);
});
for(const options of [{receiptId:'r'},{latestReceipt:true}])test('receipt blocks customer transfer and all balances remain unchanged '+JSON.stringify(options),async()=>{
 await seedTransfer(options);const db=env.authenticatedContext('owner').firestore();
 await assertFails(transferSale(db));
 assert.equal((await getDoc(doc(db,'customers/customer'))).data().balance,100);
 assert.equal((await getDoc(doc(db,'customers/newcustomer'))).data().balance,20);
});
for(const options of [{customerId:'missing'},{name:'Fake Customer'},{phone:'Fake Phone'}])test('customer correction rejects invalid target '+JSON.stringify(options),async()=>{
 await seedTransfer();await assertFails(transferSale(env.authenticatedContext('owner').firestore(),options));
});
test('inactive target and staff cannot reassign customer',async()=>{
 await seedTransfer();const owner=env.authenticatedContext('owner').firestore();
 await assertFails(transferSale(env.authenticatedContext('staff').firestore()));
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'customers/newcustomer'),{active:false},{merge:true}));
 await assertFails(transferSale(owner));
});

async function enablePurchasing(enabled=true){await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'users/staff'),{canPurchase:enabled},{merge:true}));}
function employeePurchase(db,{n=1,paid=10,omit='',mutate=()=>{}}={}){
 const id='ep',items=Array.from({length:n},(_,i)=>({productId:'p'+i,productName:'Product'+i,quantity:2,unitCost:6,lineTotal:12}));
 const total=n*12,due=total-paid,ts=serverTimestamp();
 const s={id,actorId:'staff',actorName:'Staff',branchId:'staffbranch',supplierId:'supplier',supplierName:'Supplier',
  invoiceNumber:'SUP-1',note:'',items,itemCount:n,stockIndex:Object.fromEntries(items.map((x,i)=>[x.productId,i])),
  total,paid,due,cashPosted:true,cashBefore:500,cashAfter:500-paid,supplierPreviousBalance:100,supplierBalanceAfter:100+due,
  paymentStatus:due>0?'credit':'cash',status:'completed',source:'employee',requestKey:'test',createdAt:ts};mutate(s);
 const b=writeBatch(db);b.set(doc(db,'purchases/'+id),s);
 if(omit!=='supplier')b.update(doc(db,'suppliers/supplier'),{balance:100+due,lastPurchaseId:id,updatedAt:ts});
 if(omit!=='supplierMovement')b.set(doc(db,'accountMovements/ep_supplier'),{accountType:'suppliers',accountId:'supplier',accountName:'Supplier',kind:'purchase',amount:due,paid,balanceBefore:100,balanceAfter:100+due,referenceId:id,actorId:'staff',createdAt:ts});
 if(paid>0){
  if(omit!=='cash')b.update(doc(db,'settings/cash'),{balance:500-paid,lastPurchaseId:id,updatedAt:ts});
  if(omit!=='cashMovement')b.set(doc(db,'accountMovements/ep_cash'),{accountType:'cash',accountId:'supplier',accountName:'Supplier',kind:'purchasePayment',amount:paid,delta:-paid,balanceBefore:500,balanceAfter:500-paid,referenceId:id,actorId:'staff',createdAt:ts});
 }
 for(const x of items){
  if(omit!=='stock')b.update(doc(db,'stock/main_'+x.productId),{quantity:12,lastPurchaseId:id});
  if(omit!=='product')b.update(doc(db,'products/'+x.productId),{purchasePrice:6,lastPurchaseId:id,updatedAt:ts});
  if(omit!=='stockMovement')b.set(doc(db,'stockMovements/ep_'+x.productId),{productId:x.productId,productName:x.productName,branchId:'main',kind:'purchase',quantity:2,balanceAfter:12,referenceId:id,actorId:'staff',createdAt:ts});
 }
 return b.commit();
}
for(const n of [1,4])for(const paid of [0,10,n*12])test(`permitted employee purchases ${n} lines paid ${paid} atomically`,async()=>{
 await enablePurchasing();const db=env.authenticatedContext('staff').firestore();await assertSucceeds(employeePurchase(db,{n,paid}));
 assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,12);
 const owner=env.authenticatedContext('owner').firestore();assert.equal((await getDoc(doc(owner,'suppliers/supplier'))).data().balance,100+n*12-paid);
 assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,500-paid);
 await assertFails(employeePurchase(db,{n,paid}));
});
for(const omit of ['supplier','supplierMovement','cash','cashMovement','stock','product','stockMovement'])test('employee purchase missing '+omit+' fails atomically',async()=>{
 await enablePurchasing();const db=env.authenticatedContext('staff').firestore();await assertFails(employeePurchase(db,{omit}));
 assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,10);
});
test('purchase permission defaults denied, revocation and deleted employee are enforced server side',async()=>{
 const db=env.authenticatedContext('staff').firestore();await assertFails(employeePurchase(db));await enablePurchasing();await enablePurchasing(false);await assertFails(employeePurchase(db));
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'users/staff'),{role:'deleted',active:false,canPurchase:true},{merge:true}));
 await assertFails(employeePurchase(db));await assertFails(saleBatch(db));
});
for(const [name,mutate] of [['forged actor',s=>s.actorId='owner'],['forged supplier',s=>s.supplierName='fake'],['wrong total',s=>s.total=1],['duplicate item',s=>{s.items[1]={...s.items[0]};s.stockIndex={p0:0}}],['negative cost',s=>s.items[0].unitCost=-1]])test('employee purchase rejects '+name,async()=>{
 await enablePurchasing();await assertFails(employeePurchase(env.authenticatedContext('staff').firestore(),{n:2,mutate}));
});
test('employee purchase permission cannot be self granted and other employee invoices cannot be read',async()=>{
 const staff=env.authenticatedContext('staff').firestore();await assertFails(setDoc(doc(staff,'users/staff'),{canPurchase:true},{merge:true}));
 await enablePurchasing();await employeePurchase(staff);
 await env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),'users/other'),{role:'employee',active:true,canPurchase:true,branchId:'staffbranch'}));
 await assertFails(getDoc(doc(env.authenticatedContext('other').firestore(),'purchases/ep')));
 await assertSucceeds(getDocs(query(collection(staff,'purchases'),require('firebase/firestore').where('actorId','==','staff'))));
});
test('owner stock edits still work after employee purchase marker',async()=>{
 await enablePurchasing();await employeePurchase(env.authenticatedContext('staff').firestore());
 await assertSucceeds(setDoc(doc(env.authenticatedContext('owner').firestore(),'stock/main_p0'),{quantity:15},{merge:true}));
});

for(const n of [1,4])for(const paid of [0,10,undefined])test(`permitted employee price ${n} lines paid ${paid}`,async()=>{
 await setDoc(doc(env.authenticatedContext('owner').firestore(),'users/staff'),{canEditSalePrice:true},{merge:true});
 await assertSucceeds(saleBatch(env.authenticatedContext('staff').firestore(),{n,paid,unitPrice:15}));
});
test('unpermitted price change denied atomically',async()=>assertFails(saleBatch(env.authenticatedContext('staff').firestore(),{unitPrice:15})));
test('revoked price permission and below cost both denied',async()=>{
 const owner=env.authenticatedContext('owner').firestore(),staff=env.authenticatedContext('staff').firestore();
 await setDoc(doc(owner,'users/staff'),{canEditSalePrice:true},{merge:true});
 await assertFails(saleBatch(staff,{unitPrice:4}));
 await setDoc(doc(owner,'users/staff'),{canEditSalePrice:false},{merge:true});
 await assertFails(saleBatch(staff,{unitPrice:15}));
 await assertFails(setDoc(doc(staff,'users/staff'),{canEditSalePrice:true},{merge:true}));
});
function datedReceipt(db,date,movementDate=date,createdAt=serverTimestamp()){
 const b=writeBatch(db),ts=serverTimestamp();
 b.set(doc(db,'receipts/r'),{customerId:'customer',customerName:'Customer',customerPhone:'010',amount:20,balanceBefore:100,balanceAfter:80,
 cashBefore:500,cashAfter:520,actorId:'staff',actorName:'Staff',branchId:'staffbranch',note:'Chosen date',createdAt,receiptDate:date,customerMovementId:'rc',cashMovementId:'rk'});
 b.update(doc(db,'customers/customer'),{balance:80,lastReceiptId:'r',updatedAt:ts});
 b.update(doc(db,'settings/cash'),{balance:520,lastReceiptId:'r',updatedAt:ts});
 for(const cash of [false,true])b.set(doc(db,'accountMovements/'+(cash?'rk':'rc')),{accountType:cash?'cash':'customers',accountId:'customer',accountName:'Customer',kind:cash?'customerCollection':'collection',amount:20,...(cash?{delta:20}:{}),balanceBefore:cash?500:100,balanceAfter:cash?520:80,referenceId:'r',reason:'',actorId:'staff',branchId:'staffbranch',createdAt:ts,receiptDate:movementDate});
 return b.commit();
}
for(const date of ['2001-01-01T12:00:00Z','2030-12-31T20:00:00Z'])test('chosen receipt date '+date,async()=>{
 const db=env.authenticatedContext('staff').firestore();await assertSucceeds(datedReceipt(db,new Date(date)));
 assert.equal((await getDoc(doc(db,'receipts/r'))).data().receiptDate.toDate().toISOString(),new Date(date).toISOString());
});
for(const date of ['bad date',new Date('1999-12-31'),new Date('2101-01-01')])test('invalid receipt date '+date,async()=>assertFails(datedReceipt(env.authenticatedContext('staff').firestore(),date)));
test('receipt ledger date mismatch denied',async()=>assertFails(datedReceipt(env.authenticatedContext('staff').firestore(),new Date('2026-10-02'),new Date('2026-10-03'))));
test('choosing a date cannot forge immutable audit time',async()=>assertFails(datedReceipt(env.authenticatedContext('staff').firestore(),new Date('2026-10-02'),new Date('2026-10-02'),new Date('2026-10-02'))));

for(const n of [1,4])test('staff percentage discount without manual price permission '+n,async()=>{
 await assertSucceeds(saleBatch(env.authenticatedContext('staff').firestore(),{n,paid:10,unitPrice:12.35*.9,mutate:s=>s.items.forEach(x=>Object.assign(x,{basePrice:12.35,discountPercent:10}))}));
});
test('discount base cannot disguise unauthorized manual price',async()=>assertFails(saleBatch(env.authenticatedContext('staff').firestore(),{unitPrice:11,mutate:s=>Object.assign(s.items[0],{basePrice:15,discountPercent:10})})));
test('invalid discount percentage rejected',async()=>assertFails(saleBatch(env.authenticatedContext('staff').firestore(),{mutate:s=>Object.assign(s.items[0],{discountPercent:-1})})));

function pendingDraft({n=5,mutate=()=>{}}={}) {
  const r={id:'request',employeeId:'staff',employeeName:'Staff',branchId:'staffbranch',customerId:'customer',customerName:'Customer',
    credit:true,paid:10,total:n*24.7,items:Array.from({length:n},(_,i)=>({productId:'p'+i,productName:'Product'+i,
      quantity:2,unitPrice:12.35,basePrice:12.35,discountPercent:0})),status:'pending',createdAt:serverTimestamp(),requestKey:'draft'};
  mutate(r);return r;
}
async function approvePending(db,{shortage=false}={}) {
  return runTransaction(db,async tx=>{
    const ref=doc(db,'pendingSales/request'),r=(await tx.get(ref)).data(),saleRef=doc(db,'sales/request');
    const prior=await tx.get(saleRef);if(prior.exists())return prior.data();
    if(r.status!=='pending')throw new Error('Not pending');
    const stocks=await Promise.all(r.items.map(x=>tx.get(doc(db,'stock/main_'+x.productId))));
    const c=(await tx.get(doc(db,'customers/customer'))).data(),cash=(await tx.get(doc(db,'settings/cash'))).data();
    for(let i=0;i<r.items.length;i++)if(stocks[i].data().quantity<r.items[i].quantity || shortage)throw new Error('Shortage');
    const total=r.items.reduce((sum,x)=>sum+x.quantity*x.unitPrice,0),due=total-r.paid;
    const s={id:'request',sourceRequestId:'request',employeeId:r.employeeId,approvedBy:'owner',branchId:r.branchId,status:'completed',
      customerId:r.customerId,total,paid:r.paid,due,itemCount:r.items.length,items:r.items,createdAt:serverTimestamp()};
    tx.set(saleRef,s);
    for(let i=0;i<r.items.length;i++)tx.update(doc(db,'stock/main_'+r.items[i].productId),{quantity:stocks[i].data().quantity-r.items[i].quantity,lastSaleId:'request'});
    tx.update(doc(db,'customers/customer'),{balance:c.balance+due,lastSaleId:'request'});
    tx.update(doc(db,'settings/cash'),{balance:cash.balance+r.paid,lastSaleId:'request'});
    tx.update(ref,{status:'approved',saleId:'request',reviewedBy:'owner',reviewedAt:serverTimestamp()});
    return s;
  });
}
test('five and fifty item drafts have no financial effect before owner approval',async()=>{
  const db=env.authenticatedContext('staff').firestore();
  for(const n of [5,50])await assertSucceeds(setDoc(doc(db,'pendingSales/'+(n===5?'request':'large')),
    pendingDraft({n,mutate:r=>r.id=n===5?'request':'large'})));
  assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,10);
  assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,500);
  assert.equal((await getDoc(doc(db,'customers/customer'))).data().balance,100);
  assert.equal((await getDoc(doc(db,'sales/request'))).exists(),false);
});
test('manager can queue a sale draft for offline sync but employee cannot impersonate the manager queue',async()=>{
  const owner=env.authenticatedContext('owner').firestore(),staff=env.authenticatedContext('staff').firestore();
  const draft=pendingDraft({n:2,mutate:r=>Object.assign(r,{id:'offline-sale',employeeId:'owner',employeeName:'Owner',branchId:'main',
    managerOffline:true,note:'',allowShortage:false,allowBelowCost:false,overrideReason:''})});
  await assertSucceeds(setDoc(doc(owner,'pendingSales/offline-sale'),draft));
  await assertFails(setDoc(doc(staff,'pendingSales/forged'),{...draft,id:'forged'}));
  await assertFails(setDoc(doc(owner,'pendingSales/extra'),{...draft,id:'extra',unexpected:'field'}));
});
test('manager can queue a cash sale without a customer for offline sync',async()=>{
  const db=env.authenticatedContext('owner').firestore();
  const draft=pendingDraft({n:1,mutate:r=>Object.assign(r,{id:'cash-offline',employeeId:'owner',employeeName:'Owner',branchId:'main',
    customerId:'',customerName:'',credit:false,paid:24.7,managerOffline:true,note:'',allowShortage:false,allowBelowCost:false,overrideReason:''})});
  await assertSucceeds(setDoc(doc(db,'pendingSales/cash-offline'),draft));
});
test('only owner can queue cancellation for an existing receipt or supplier payment',async()=>{
  await env.withSecurityRulesDisabled(async ctx=>{
    const db=ctx.firestore();
    await setDoc(doc(db,'receipts/r-cancel'),{customerId:'customer',amount:10});
    await setDoc(doc(db,'accountMovements/p-cancel'),{kind:'payment',accountId:'supplier',amount:10});
  });
  const owner=env.authenticatedContext('owner').firestore(),staff=env.authenticatedContext('staff').firestore();
  const request={type:'receipt',originalId:'r-cancel',actorId:'owner',status:'pending',createdAt:serverTimestamp()};
  await assertSucceeds(setDoc(doc(owner,'managerOfflineVoucherCancellations/receipt_r-cancel'),request));
  await assertFails(setDoc(doc(staff,'managerOfflineVoucherCancellations/receipt_r-cancel'),{...request,actorId:'staff'}));
  await assertSucceeds(setDoc(doc(owner,'managerOfflineVoucherCancellations/payment_p-cancel'),{...request,type:'payment',originalId:'p-cancel'}));
});
test('only submitting staff or owner can read drafts; employees cannot approve, edit or delete',async()=>{
  const db=env.authenticatedContext('staff').firestore(),ref=doc(db,'pendingSales/request');await setDoc(ref,pendingDraft());
  const other=env.authenticatedContext('other',{role:'employee'}).firestore();
  await assertFails(getDoc(doc(other,'pendingSales/request')));
  await assertFails(setDoc(ref,{status:'approved'},{merge:true}));
  await assertFails(setDoc(ref,{paid:0},{merge:true}));await assertFails(deleteDoc(ref));
  await assertSucceeds(getDocs(query(collection(db,'pendingSales'),require('firebase/firestore').where('employeeId','==','staff'))));
  await assertFails(getDocs(collection(db,'pendingSales')));
});
for(const [name,mutate] of [['forged actor',r=>r.employeeId='owner'],['forged branch',r=>r.branchId='other'],
  ['completed draft',r=>r.status='approved'],['negative payment',r=>r.paid=-1],['too many items',r=>r.items=Array(51).fill({})]])
  test('pending draft rejects '+name,async()=>assertFails(setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft({mutate}))));
test('owner approval posts five items once across retries, retaining submitting employee',async()=>{
  await setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft());
  const db=env.authenticatedContext('owner').firestore();
  await assertSucceeds(approvePending(db));await assertSucceeds(approvePending(db));
  assert.equal((await getDoc(doc(db,'stock/main_p4'))).data().quantity,8);
  assert.ok(Math.abs((await getDoc(doc(db,'customers/customer'))).data().balance-213.5)<.000001);
  assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,510);
  assert.equal((await getDoc(doc(db,'pendingSales/request'))).data().status,'approved');
  assert.equal((await getDoc(doc(db,'sales/request'))).data().employeeId,'staff');
});
test('failed approval leaves proposal pending and all balances unchanged',async()=>{
  await setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft());
  const db=env.authenticatedContext('owner').firestore();await assert.rejects(approvePending(db,{shortage:true}));
  assert.equal((await getDoc(doc(db,'pendingSales/request'))).data().status,'pending');
  assert.equal((await getDoc(doc(db,'sales/request'))).exists(),false);
  assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,10);
  assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,500);
});
test('owner rejection is final and requires a reason; approval requires linked completed sale',async()=>{
  await setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft());
  const db=env.authenticatedContext('owner').firestore(),ref=doc(db,'pendingSales/request');
  await assertFails(setDoc(ref,{status:'approved',saleId:'request',reviewedBy:'owner',reviewedAt:serverTimestamp()},{merge:true}));
  await assertFails(setDoc(ref,{status:'rejected',reviewedBy:'owner',reviewedAt:serverTimestamp(),rejectionReason:''},{merge:true}));
  await assertSucceeds(setDoc(ref,{status:'rejected',reviewedBy:'owner',reviewedAt:serverTimestamp(),rejectionReason:'Stock shortage'},{merge:true}));
  await assertFails(setDoc(ref,{status:'pending'},{merge:true}));
  await assert.rejects(approvePending(db));
  assert.equal((await getDoc(doc(db,'sales/request'))).exists(),false);
});

async function rejectDraft(db){
  await setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft());
  await setDoc(doc(db,'pendingSales/request'),{status:'rejected',reviewedBy:'owner',reviewedAt:serverTimestamp(),rejectionReason:'Re-enter invoice'},{merge:true});
}
function removeDraft(db,extra={}){return setDoc(doc(db,'pendingSales/request'),{removed:true,removedBy:'owner',removedAt:serverTimestamp(),...extra},{merge:true});}
test('owner removes rejected proposal without financial effect and submitting employee sees the hide marker',async()=>{
  const db=env.authenticatedContext('owner').firestore();await rejectDraft(db);await assertSucceeds(removeDraft(db));
  const r=(await getDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'))).data();
  assert.equal(r.removed,true);assert.equal(r.status,'rejected');assert.equal(r.rejectionReason,'Re-enter invoice');assert.equal(r.items.length,5);
  assert.equal((await getDoc(doc(db,'stock/main_p0'))).data().quantity,10);
  assert.equal((await getDoc(doc(db,'settings/cash'))).data().balance,500);
  assert.equal((await getDoc(doc(db,'customers/customer'))).data().balance,100);
  assert.equal((await getDoc(doc(db,'sales/request'))).exists(),false);
  await assertSucceeds(setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/new'),pendingDraft({mutate:r=>r.id='new'})));
});
test('staff cannot remove their rejected proposal; owner cannot erase its audit or payload',async()=>{
  const db=env.authenticatedContext('owner').firestore();await rejectDraft(db);
  await assertFails(removeDraft(env.authenticatedContext('staff').firestore(),{removedBy:'staff'}));
  for(const extra of [{paid:0},{items:[]},{rejectionReason:'Changed'},{reviewedBy:'staff'},{removedBy:'staff'},{removedAt:new Date('2026-01-01')}])await assertFails(removeDraft(db,extra));
  await assertFails(deleteDoc(doc(db,'pendingSales/request')));
});
test('pending and approved proposals cannot be removed',async()=>{
  const db=env.authenticatedContext('owner').firestore();await setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft());
  await assertFails(removeDraft(db));await approvePending(db);await assertFails(removeDraft(db));
});
test('removed rejected proposal cannot be revived, approved, overwritten or permanently deleted',async()=>{
  const db=env.authenticatedContext('owner').firestore();await rejectDraft(db);await removeDraft(db);
  const ref=doc(db,'pendingSales/request');
  await assertFails(setDoc(ref,{removed:false},{merge:true}));await assertFails(setDoc(ref,{status:'pending'},{merge:true}));
  await assertFails(setDoc(ref,{status:'approved',saleId:'request',reviewedBy:'owner',reviewedAt:serverTimestamp()},{merge:true}));
  await assertFails(setDoc(doc(env.authenticatedContext('staff').firestore(),'pendingSales/request'),pendingDraft()));
  await assertFails(deleteDoc(ref));await assert.rejects(approvePending(db));
});
