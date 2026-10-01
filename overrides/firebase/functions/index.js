const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {initializeApp} = require('firebase-admin/app');
const {getFirestore, FieldValue} = require('firebase-admin/firestore');
const {saveStaffSale} = require('./sales');
initializeApp();
exports.createStaffSale = onCall({region: 'us-central1', maxInstances: 5}, async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'سجل دخولك أولًا');
  return saveStaffSale(getFirestore(), FieldValue, HttpsError, request.auth.uid, request.data);
});
