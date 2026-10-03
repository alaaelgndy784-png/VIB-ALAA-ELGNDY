const crypto = require('node:crypto');
const BASE = 'https://api.merchant.geidea.net';
const MAX_CENTS = 100000000000;
const id = x => typeof x === 'string' && x.length > 0 && x.length <= 128 && !x.includes('/');
function cents(x, signed = false) {
  if (typeof x !== 'number' || !Number.isFinite(x) || Math.abs(x) * 100 > MAX_CENTS || (!signed && x < 0)) throw Error('INVALID_MONEY');
  return Math.round(x * 100);
}
function providerId(x) {
  if (typeof x !== 'string' || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(x)) throw Error('INVALID_PROVIDER_ID');
  return x.toLowerCase();
}
function signature(parts, password) {return crypto.createHmac('sha256',password).update(parts.join('')).digest('base64');}
function callbackSignature(order,timestamp,cfg) {
  return signature([cfg.publicKey,Number(order.amount).toFixed(2),order.currency,order.orderId,order.status,order.merchantReferenceId||'',timestamp],cfg.password);
}
function verifyCallback(order,timestamp,value,cfg) {
  try {const expected=Buffer.from(callbackSignature(order,timestamp,cfg));const actual=Buffer.from(value||'');
    return !!timestamp && actual.length===expected.length && crypto.timingSafeEqual(actual,expected);
  }catch(_){return false;}
}
function headers(cfg) {return {Authorization:'Basic '+Buffer.from(cfg.publicKey+':'+cfg.password).toString('base64'),'Content-Type':'application/json',Accept:'application/json'};}
async function owner(tx, db, uid, ErrorType) {
  const p = (await tx.get(db.collection('users').doc(uid))).data();
  if (p?.active !== true || p.role !== 'owner') throw new ErrorType('permission-denied', 'الدفع الإلكتروني متاح للمدير فقط');
  return p;
}
function assertConfig(cfg, ErrorType) {
  if (!cfg.enabled || !['test','live'].includes(cfg.mode) || !cfg.password || !cfg.webhookUrl?.startsWith('https://'))
    throw new ErrorType('failed-precondition','خدمة الدفع لم تُفعّل بعد؛ فعّل حساب التاجر وإعدادات الربط أولًا');
  try {providerId(cfg.publicKey);}catch(_){throw new ErrorType('failed-precondition','إعدادات حساب جيديا غير مكتملة');}
}
async function api(path, options, fetcher = fetch) {
  const response = await fetcher(BASE + path, {...options, signal: AbortSignal.timeout(20000)});
  if (!response.ok) {const e=Error('GEIDEA_HTTP');e.httpStatus=response.status;throw e;}
  const data=await response.json();
  if (data.responseCode !== '000') {const e=Error('GEIDEA_DECLINED');e.httpStatus=422;throw e;}
  return data;
}
async function inquire(paymentIntentId,orderId,cfg,fetcher=fetch) {
  const data=await api('/pgw/api/v1/order/'+providerId(paymentIntentId)+'/'+providerId(orderId),{headers:headers(cfg)},fetcher);
  if(providerId(data.order?.orderId)!==providerId(orderId) || providerId(data.order?.paymentIntent?.id)!==providerId(paymentIntentId) ||
      providerId(data.order?.merchantPublicKey)!==providerId(cfg.publicKey)) throw Error('PROVIDER_ORDER_MISMATCH');
  return data.order;
}
async function refreshRequest(db,FV,ErrorType,uid,requestId,cfg,fetcher=fetch) {
  assertConfig(cfg,ErrorType);
  if(!id(requestId))throw new ErrorType('invalid-argument','طلب الدفع غير صحيح');
  const row=await db.runTransaction(async tx=>{await owner(tx,db,uid,ErrorType);return (await tx.get(db.collection('paymentRequests').doc(requestId))).data();});
  if(!row?.paymentIntentId || row.mode!==cfg.mode)throw new ErrorType('failed-precondition','راجع الطلب من لوحة جيديا؛ لم يصل تأكيد إنشاء الرابط');
  const data=await api('/payment-intent/api/v1/direct/eInvoice/'+providerId(row.paymentIntentId),{headers:headers(cfg)},fetcher);
  const intent=data.paymentIntent;
  if(providerId(intent?.paymentIntentId)!==row.paymentIntentId || cents(intent.amount)!==row.amountCents || intent.currency!=='EGP' ||
    providerId(intent.merchantPublicKey)!==providerId(cfg.publicKey))throw Error('PROVIDER_INTENT_MISMATCH');
  for(const order of intent.orders||[])await reconcile(db,FV,await inquire(row.paymentIntentId,order.orderId,cfg,fetcher));
  return {state:'updated'};
}
async function createLink(db, FV, ErrorType, uid, input, cfg, fetcher = fetch, clock = Date.now) {
  assertConfig(cfg, ErrorType);
  if (!input || !/^[A-Za-z0-9]{20}$/.test(input.requestId || '') || !id(input.invoiceId) ||
      typeof input.phone !== 'string' || !/^((\+20)|0)?1[0125][0-9]{8}$/.test(input.phone) ||
      typeof input.email !== 'string' || input.email.length > 254 || (input.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.email)))
    throw new ErrorType('invalid-argument', 'راجع رقم الفاتورة وهاتف العميل وبريده الإلكتروني');
  const ref = db.collection('paymentRequests').doc(input.requestId);
  const invoiceRef = db.collection('sales').doc(input.invoiceId);
  const reserved = await db.runTransaction(async tx => {
    const profile=await owner(tx,db,uid,ErrorType);
    const previous = (await tx.get(ref)).data();
    const sale = (await tx.get(invoiceRef)).data();
    const customer = id(sale?.customerId) ? (await tx.get(db.collection('customers').doc(sale.customerId))).data() : null;
    const activeRef = id(sale?.activePaymentRequestId) ? db.collection('paymentRequests').doc(sale.activePaymentRequestId) : null;
    const active = activeRef ? (await tx.get(activeRef)).data() : null;
    if (previous) {
      if (previous.actorId !== uid || previous.invoiceId !== input.invoiceId || previous.phone !== input.phone || previous.email !== input.email)
        throw new ErrorType('already-exists','طلب الدفع موجود ببيانات مختلفة');
      if (previous.state === 'pending' && previous.expiresAtMs > clock() && sale?.status === 'completed' &&
          cents(sale.due) - cents(sale.receiptPaid ?? 0) === previous.amountCents) return {existing:previous};
      throw new ErrorType('failed-precondition','طلب الدفع محفوظ؛ راجع حالته من سجل المدفوعات ولا تكرره');
    }
    if (!sale || (profile.resetAt && (!sale.createdAt || sale.createdAt.toMillis()<profile.resetAt.toMillis())) || sale.status !== 'completed' || !customer || customer.active === false ||
        cents(sale.total) !== cents(sale.paid) + cents(sale.due)) throw new ErrorType('failed-precondition','اختر فاتورة مبيعات صحيحة لعميل مسجل');
    const amountCents = cents(sale.due) - cents(sale.receiptPaid ?? 0);
    if (amountCents <= 0) throw new ErrorType('failed-precondition','الفاتورة مسددة بالفعل');
    if (active && ((active.state === 'pending' && active.expiresAtMs > clock()) || ['creating','creation_unknown'].includes(active.state)))
      throw new ErrorType('failed-precondition','يوجد طلب دفع لهذه الفاتورة؛ افتحه من سجل المدفوعات');
    const row = {actorId:uid,invoiceId:input.invoiceId,customerId:sale.customerId,customerName:customer.name || '',
      phone:input.phone,email:input.email,amountCents,currency:'EGP',mode:cfg.mode,state:'creating',revision:sale.revision ?? 0,
      resetAtMs:profile.resetAt?.toMillis()??0,createdAt:FV.serverTimestamp(),createdAtMs:clock(),expiresAtMs:clock()+3600000};
    tx.set(ref,row); tx.update(invoiceRef,{activePaymentRequestId:ref.id}); return {row};
  });
  if (reserved.existing) return {requestId:ref.id,...publicRequest(reserved.existing,clock())};
  const row = reserved.row;
  const amount=row.amountCents/100;
  let data;
  try {
    data = await api('/payment-intent/api/v1/direct/eInvoice',{method:'POST',headers:headers(cfg),body:JSON.stringify({
      amount,currency:'EGP',callbackUrl:cfg.webhookUrl,
      customer:{name:row.customerName||'عميل',phoneCountryCode:'+20',phoneNumber:row.phone.replace(/^(\+20|0)/,''),...(row.email?{email:row.email}:{})},
      eInvoiceDetails:{subtotal:amount,grandTotal:amount,merchantReferenceId:ref.id,language:'AR',callbackUrl:cfg.webhookUrl,
        preAuthorizeAmount:false,eInvoiceItems:[{description:'سداد فاتورة VIB '+row.invoiceId,price:amount,quantity:1,total:amount}]},
      expiryDate:new Date(row.expiresAtMs).toISOString(),activationDate:new Date(row.createdAtMs).toISOString(),
    })},fetcher);
    const intent=data.paymentIntent,paymentIntentId=providerId(intent?.paymentIntentId);
    const url=new URL(intent.link);
    if(url.protocol!=='https:' || url.hostname!=='merchant.geidea.net' || cents(intent.amount)!==row.amountCents || intent.currency!=='EGP' ||
      providerId(intent.merchantPublicKey)!==providerId(cfg.publicKey) || intent.eInvoiceDetails?.merchantReferenceId!==ref.id)throw Error('INVALID_PAYMENT_LINK');
    await db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data();
      const orderRef = db.collection('geideaIntents').doc(paymentIntentId);
      const mapping = (await tx.get(orderRef)).data();
      if (current?.state !== 'creating' || (mapping && mapping.requestId !== ref.id)) throw Error('ORDER_MAPPING_CONFLICT');
      tx.set(orderRef,{requestId:ref.id,mode:row.mode,merchantPublicKey:providerId(cfg.publicKey),createdAt:FV.serverTimestamp()});
      tx.update(ref,{state:'pending',paymentIntentId,checkoutUrl:url.href,updatedAt:FV.serverTimestamp()});
    });
    return {requestId:ref.id,...publicRequest({...row,state:'pending',checkoutUrl:url.href},clock())};
  } catch (e) {
    const knownFailure = [400,401,403,404,422].includes(e.httpStatus);
    await db.runTransaction(async tx => {
      const current = (await tx.get(ref)).data();
      if (current?.state === 'creating') tx.update(ref,{state:knownFailure?'creation_failed':'creation_unknown',updatedAt:FV.serverTimestamp()});
    });
    throw new ErrorType('unavailable', knownFailure?'شركة الدفع رفضت الطلب؛ راجع إعدادات حساب التاجر':'لم يصل تأكيد إنشاء الرابط؛ راجع سجل المدفوعات قبل إنشاء طلب آخر');
  }
}
function publicRequest(row, now = Date.now()) {
  return {invoiceId:row.invoiceId,customerName:row.customerName,amount:row.amountCents/100,mode:row.mode,
    state:row.state === 'pending' && row.expiresAtMs <= now?'expired':row.state,
    createdAtMs:row.createdAtMs,expiresAtMs:row.expiresAtMs,
    ...(row.state === 'pending' && row.expiresAtMs > now ? {checkoutUrl:row.checkoutUrl}:{}),
    ...(row.lastTransactionId ? {transactionId:row.lastTransactionId}:{}),reviewReason:row.reviewReason || ''};
}
// Called only with a fresh, authenticated provider inquiry response, never a browser redirect.
async function reconcile(db, FV, snapshot) {
  const txnId=providerId(snapshot.orderId), orderId=txnId, intentId=providerId(snapshot.paymentIntent?.id);
  const gross=cents(snapshot.amount),captured=cents(snapshot.totalCapturedAmount??0);
  if(gross<2 || snapshot.currency!=='EGP' || typeof snapshot.isTest!=='boolean')throw Error('INVALID_ORDER');
  if(captured===0)return {state:'ignored'};
  if(snapshot.status!=='Success' || !['Paid','Captured','Settled','PartiallyRefunded','Refunded'].includes(snapshot.detailedStatus))throw Error('UNCONFIRMED_CAPTURE');
  if(captured!==gross)throw Error('UNSUPPORTED_CAPTURE_AMOUNT');
  const refunded=cents(snapshot.totalRefundedAmount??0);
  if(refunded>gross)throw Error('INVALID_REFUND_TOTAL');
  const ref = db.collection('geideaTransactions').doc(txnId);
  return db.runTransaction(async tx => {
    const map = (await tx.get(db.collection('geideaIntents').doc(intentId))).data();
    if (!map || !id(map.requestId)) return {state:'unmatched'};
    const requestRef = db.collection('paymentRequests').doc(map.requestId);
    const request = (await tx.get(requestRef)).data();
    const prev = (await tx.get(ref)).data();
    if (!request || providerId(snapshot.merchantPublicKey)!==map.merchantPublicKey || request.mode !== map.mode ||
        snapshot.isTest !== (request.mode === 'test') || gross !== request.amountCents) throw Error('TRANSACTION_MISMATCH');
    if (prev && (prev.orderId !== orderId || prev.grossCents !== gross)) throw Error('TRANSACTION_REUSE');
    if (prev && refunded < prev.refundedCents) return {state:prev.state}; // stale provider snapshot
    if (request.mode === 'test') {
      const state=refunded===gross?'test_refunded':'test_paid';
      tx.set(ref,{requestId:map.requestId,paymentIntentId:intentId,orderId,grossCents:gross,refundedCents:refunded,mode:'test',state,createdAt:prev?.createdAt??FV.serverTimestamp(),
        ...(prev?.refundTargetCents?{refundTargetCents:prev.refundTargetCents,refundState:refunded>=prev.refundTargetCents?'confirmed':prev.refundState}: {})});
      tx.update(requestRef,{state,lastTransactionId:txnId,updatedAt:FV.serverTimestamp()}); return {state};
    }
    const saleRef=db.collection('sales').doc(request.invoiceId), customerRef=db.collection('customers').doc(request.customerId);
    const sale=(await tx.get(saleRef)).data(), customer=(await tx.get(customerRef)).data();
    const profile=id(request.actorId)?(await tx.get(db.collection('users').doc(request.actorId))).data():{};
    const resetChanged=(profile?.resetAt?.toMillis()??0)!==(request.resetAtMs??0);
    const clearingRef=db.collection('settings').doc('geideaClearing');
    const clearing=(await tx.get(clearingRef)).data();
    const net=gross-refunded, beforeFunds=prev?.netCents ?? 0, fundsDelta=net-beforeFunds;
    let applied=prev?.appliedCents ?? 0, reviewReason=prev?.reviewReason || '';
    if (!prev) {
      const remaining=sale?cents(sale.due)-cents(sale.receiptPaid??0):0;
      if (!sale || !customer || customer.active===false || resetChanged || sale.status !== 'completed' || (sale.revision??0)!==request.revision || remaining<net ||
          (request.primaryTransactionId && request.primaryTransactionId!==txnId)) reviewReason='invoice_changed_or_already_paid';
      else applied=net;
    } else if (prev.appliedCents>0) {
      if (!sale || !customer || customer.active===false || resetChanged || sale.status !== 'completed') reviewReason='refund_account_requires_review';
      else applied=net;
    }
    const delta=applied-(prev?.appliedCents??0);
    const customerBefore=customer?cents(customer.balance??0,true):0;
    const beforeClearing=cents(clearing?.balance??0,true);
    const receiptBefore=sale?cents(sale.receiptPaid??0):0, onlineBefore=sale?cents(sale.onlinePaid??0):0;
    if (delta<0 && (-delta>onlineBefore || -delta>receiptBefore)) throw Error('INVOICE_PAYMENT_CORRUPT');
    const state=reviewReason?'review':refunded===gross?'refunded':refunded>0?'partially_refunded':'paid';
    const now=FV.serverTimestamp();
    if (fundsDelta !== 0) {
      tx.set(clearingRef,{balance:(beforeClearing+fundsDelta)/100,updatedAt:now}, {merge:true});
      tx.set(db.collection('accountMovements').doc('geidea_'+txnId+'_funds_'+refunded),{
        accountType:'geidea',accountId:map.requestId,accountName:request.customerName,kind:fundsDelta>0?'cardCollection':'cardRefund',
        amount:Math.abs(fundsDelta)/100,delta:fundsDelta/100,balanceBefore:beforeClearing/100,balanceAfter:(beforeClearing+fundsDelta)/100,
        referenceId:txnId,invoiceId:request.invoiceId,createdAt:now,reason:'تحصيل إلكتروني — لا يُضاف للصندوق النقدي'});
    }
    if (delta !== 0) {
      tx.update(customerRef,{balance:(customerBefore-delta)/100,updatedAt:now});
      tx.update(saleRef,{receiptPaid:(receiptBefore+delta)/100,onlinePaid:(onlineBefore+delta)/100,onlinePaymentEver:true,lastOnlinePaymentId:txnId});
      tx.set(db.collection('accountMovements').doc('geidea_'+txnId+'_customer_'+refunded),{
        accountType:'customers',accountId:request.customerId,accountName:request.customerName,kind:delta>0?'onlineCollection':'onlineRefund',
        amount:Math.abs(delta)/100,balanceBefore:customerBefore/100,balanceAfter:(customerBefore-delta)/100,referenceId:txnId,
        invoiceId:request.invoiceId,createdAt:now,reason:delta>0?'سداد بالكارت':'رد مبلغ للكارت'});
    }
    tx.set(ref,{requestId:map.requestId,invoiceId:request.invoiceId,customerName:request.customerName,paymentIntentId:intentId,orderId,grossCents:gross,
      refundedCents:refunded,netCents:net,appliedCents:applied,mode:'live',state,reviewReason,
      createdAt:prev?.createdAt??now,updatedAt:now,settlementState:'awaiting_bank_reconciliation',
      ...(prev?.refundTargetCents?{refundTargetCents:prev.refundTargetCents,
        refundState:refunded>=prev.refundTargetCents?'confirmed':prev.refundState}: {})});
    tx.update(requestRef,{state,reviewReason,lastTransactionId:txnId,
      ...(applied>0 && !request.primaryTransactionId?{primaryTransactionId:txnId}:{}),updatedAt:now});
    return {state};
  });
}
async function refundFull(db,FV,ErrorType,uid,transactionId,cfg,fetcher=fetch) {
  assertConfig(cfg,ErrorType);
  const txnId=providerId(transactionId),ref=db.collection('geideaTransactions').doc(txnId);
  const original=await db.runTransaction(async tx=>{await owner(tx,db,uid,ErrorType); const saved=(await tx.get(ref)).data();
    if (!saved || saved.mode!==cfg.mode) throw new ErrorType('not-found','عملية الدفع غير متاحة');return saved;});
  await reconcile(db,FV,await inquire(original.paymentIntentId,txnId,cfg,fetcher));
  const amount=await db.runTransaction(async tx=>{
    await owner(tx,db,uid,ErrorType); const saved=(await tx.get(ref)).data();
    const remaining=saved.mode==='test'?saved.grossCents-saved.refundedCents:saved.netCents;
    if (remaining===0) return 0;
    if (['requested','unknown'].includes(saved.refundState)) throw new ErrorType('failed-precondition','رد الكارت قيد التأكيد؛ حدّث الحالة ولا تكرر الطلب');
    tx.update(ref,{refundState:'requested',refundTargetCents:saved.grossCents,updatedAt:FV.serverTimestamp()});return remaining;
  });
  if (amount===0) return {state:'refunded'};
  try {
    const timestamp=new Date().toISOString(),refundAmount=amount/100;
    await api('/pgw/api/v2/direct/refund',{method:'POST',headers:headers(cfg),body:JSON.stringify({orderId:txnId,refundAmount,
      callbackUrl:cfg.webhookUrl,timestamp,signature:signature([timestamp,cfg.publicKey,String(refundAmount),txnId],cfg.password)})},fetcher);
    return await reconcile(db,FV,await inquire(original.paymentIntentId,txnId,cfg,fetcher));
  } catch(e) {
    await db.runTransaction(async tx=>{const saved=(await tx.get(ref)).data();
      if (saved?.refundState==='requested') tx.update(ref,{refundState:[400,401,403,404,422].includes(e.httpStatus)?'failed':'unknown',updatedAt:FV.serverTimestamp()});});
    throw new ErrorType('unavailable','لم يصل تأكيد رد الكارت؛ حدّث الحالة أو راجع شركة الدفع قبل المحاولة مرة أخرى');
  }
}
module.exports={BASE,signature,callbackSignature,verifyCallback,cents,providerId,owner,assertConfig,api,inquire,createLink,refreshRequest,publicRequest,reconcile,refundFull};
