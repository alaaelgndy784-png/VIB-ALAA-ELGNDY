const {onCall, onRequest, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret,defineString,defineBoolean} = require('firebase-functions/params');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {saveStaffSale} = require('./sales');
const {appendInvoice} = require('./invoice-edits');
const geidea=require('./geidea');
initializeApp();
exports.createStaffSale = onCall({region: 'us-central1', maxInstances: 5}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'سجل دخولك أولًا');
  return saveStaffSale(getFirestore(), FieldValue, HttpsError, request.auth.uid, request.data);
});

// Credentials stay in Secret Manager, never in the Android APK or Firestore.
const giPassword=defineSecret('GEIDEA_API_PASSWORD');
const giPublic=defineString('GEIDEA_PUBLIC_KEY',{default:''}),giMode=defineString('GEIDEA_MODE',{default:'test'});
const giHook=defineString('GEIDEA_WEBHOOK_URL',{default:''}),giEnabled=defineBoolean('GEIDEA_ENABLED',{default:false});
const giOptions={region:'us-central1',maxInstances:5,timeoutSeconds:120,secrets:[giPassword]};
function cfg(){return {enabled:giEnabled.value(),mode:giMode.value(),publicKey:giPublic.value(),password:giPassword.value(),webhookUrl:giHook.value()};}
async function paymentOwner(request){
  if(!request.auth)throw new HttpsError('unauthenticated','سجل دخولك أولًا');
  await getFirestore().runTransaction(tx=>geidea.owner(tx,getFirestore(),request.auth.uid,HttpsError));
  return request.auth.uid;
}
exports.geideaStatus=onCall({region:'us-central1',maxInstances:5},async request=>{
  await paymentOwner(request);return {enabled:giEnabled.value(),mode:giMode.value(),provider:'Geidea',bank:'بنك مصر'};
});
exports.createGeideaLink=onCall(giOptions,async request=>{
  const uid=await paymentOwner(request);
  return geidea.createLink(getFirestore(),FieldValue,HttpsError,uid,request.data,cfg());
});
exports.listGeideaPayments=onCall({region:'us-central1',maxInstances:5},async request=>{
  await paymentOwner(request);const db=getFirestore();
  const [requests,transactions,clearing]=await Promise.all([db.collection('paymentRequests').orderBy('createdAt','desc').limit(50).get(),
    db.collection('geideaTransactions').orderBy('createdAt','desc').limit(50).get(),db.collection('settings').doc('geideaClearing').get()]);
  return {requests:requests.docs.map(d=>({requestId:d.id,...geidea.publicRequest(d.data())})),
    transactions:transactions.docs.map(d=>{const s=d.data();return {transactionId:d.id,invoiceId:s.invoiceId||'',customerName:s.customerName||'',
      mode:s.mode,state:s.state,gross:s.grossCents/100,refunded:s.refundedCents/100,net:(s.grossCents-s.refundedCents)/100,
      refundState:s.refundState||'',reviewReason:s.reviewReason||''};}),clearingBalance:clearing.data()?.balance??0};
});
exports.refreshGeideaPayment=onCall(giOptions,async request=>{
  const uid=await paymentOwner(request);
  return geidea.refreshRequest(getFirestore(),FieldValue,HttpsError,uid,request.data?.requestId,cfg());
});
exports.refundGeideaPayment=onCall(giOptions,async request=>{
  const uid=await paymentOwner(request);
  return geidea.refundFull(getFirestore(),FieldValue,HttpsError,uid,request.data?.transactionId,cfg());
});
exports.geideaWebhook=onRequest(giOptions,async(req,res)=>{
  if(req.method!=='POST')return res.status(405).send('POST required');
  const settings=cfg();
  if(!settings.enabled)return res.status(503).send('inactive');
  const body=req.body;
  const timestamp=body?.timeStamp??body?.timestamp;
  if(timestamp && !geidea.verifyCallback(body?.order,timestamp,body?.signature,settings))return res.status(403).send('invalid signature');
  // Legacy documented callbacks omit timestamps. Their bodies are only hints: an authenticated
  // server inquiry of an already mapped merchant order is the sole payment authority.
  try {
    const orderId=geidea.providerId(body?.order?.orderId);
    const saved=(await getFirestore().collection('geideaTransactions').doc(orderId).get()).data();
    const intentId=geidea.providerId(body.order?.paymentIntent?.id??saved?.paymentIntentId);
    const mapping=(await getFirestore().collection('geideaIntents').doc(intentId).get()).data();
    if(!mapping)return res.status(200).send('unmatched');
    const snapshot=await geidea.inquire(intentId,orderId,settings);
    return res.status(200).json(await geidea.reconcile(getFirestore(),FieldValue,snapshot));
  }catch(_){return res.status(503).send('retry');}
});
exports.appendInvoiceItems = onCall({region: 'us-central1', maxInstances: 5}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'سجل دخولك أولًا');
  return appendInvoice(getFirestore(), FieldValue, HttpsError, request.auth.uid, request.data);
});
