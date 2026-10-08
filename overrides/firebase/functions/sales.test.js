const test = require('node:test');
const assert = require('node:assert/strict');
const {saveStaffSale} = require('./sales');
const {database, HttpsError, FieldValue} = require('./test-fixtures');
function input(overrides = {}) {
  return {requestId: 'abcdefghijklmnopqrst', customerId: 'c', credit: true, paid: 15,
    items: [{productId: 'a', quantity: 2, unitPrice: 10.1}, {productId: 'b', quantity: 1, unitPrice: 20}],
    ...overrides};
}
const save = (db, data) => saveStaffSale(db, FieldValue, HttpsError, 'staff', data);
test('Grouped credit sale atomically updates shared stock, debt, cash and history', async () => {
  const db = database();
  const result = await save(db, input());
  assert.equal(result.total, 40.2); assert.equal(result.due, 25.2);
  assert.equal(db.read('stock/main_a').quantity, 8);
  assert.equal(db.read('stock/main_b').quantity, 9);
  assert.equal(db.read('customers/c').balance, 125.2);
  assert.equal(db.read('settings/cash').balance, 65);
  assert.equal(db.read('sales/abcdefghijklmnopqrst').branchId, 'staffBranch');
  assert.equal(db.read('sales/abcdefghijklmnopqrst').stockBranchId, 'main');
  assert.equal(db.read('sales/abcdefghijklmnopqrst').items.length, 2);
  const count = db.size();
  await save(db, input());
  assert.equal(db.size(), count); assert.equal(db.read('stock/main_a').quantity, 8);
  assert.equal(db.read('settings/cash').balance, 65);
});
test('Cash sale without customer charges full total', async () => {
  const db = database();
  await save(db, input({customerId: '', credit: false, paid: 40.2}));
  assert.equal(db.read('settings/cash').balance, 90.2);
  assert.equal(db.read('customers/c').balance, 100);
});
test('Stock shortage leaves all balances and every line unchanged', async () => {
  const db = database(); db.put('stock/main_b', {quantity: 0});
  const count = db.size();
  await assert.rejects(save(db, input()), {code: 'failed-precondition'});
  assert.equal(db.read('stock/main_a').quantity, 10);
  assert.equal(db.read('settings/cash').balance, 50); assert.equal(db.size(), count);
});
test('Rejects tampered price, duplicate items, non-finite payment and inactive employee', async () => {
  await assert.rejects(save(database(), input({items: [{productId: 'a', quantity: 1, unitPrice: 1}]})), {code: 'failed-precondition'});
  await assert.rejects(save(database(), input({items: [input().items[0], input().items[0]]})), {code: 'invalid-argument'});
  await assert.rejects(save(database(), input({paid: NaN})), {code: 'invalid-argument'});
  const db = database(); db.put('users/staff', {role: 'employee', active: false, branchId: 'x'});
  await assert.rejects(save(db, input()), {code: 'permission-denied'});
});
test('Idempotency refuses changed payload and rechecks account activation', async () => {
  const db = database(); await save(db, input());
  await assert.rejects(save(db, input({paid: 10})), {code: 'already-exists'});
  db.put('users/staff', {role: 'employee', active: false, branchId: 'x'});
  await assert.rejects(save(db, input()), {code: 'permission-denied'});
});
test('percentage discount is validated and saved from the live product price', async () => {
  const db = database();
  await save(db, input({customerId: '', credit: false, paid: 0,
    items: [{productId: 'a', quantity: 1, unitPrice: 9.09, basePrice: 10.1, discountPercent: 10}]}));
  const line = db.read('sales/abcdefghijklmnopqrst').items[0];
  assert.equal(line.basePrice, 10.1); assert.equal(line.discountPercent, 10);
  assert.equal(line.purchasePriceAtSale, 7); assert.equal(line.lineTotal, 9.09);
});
test('manual employee price requires explicit profile permission', async () => {
  const rejected = database();
  await assert.rejects(save(rejected, input({items: [{productId: 'a', quantity: 1, unitPrice: 9, basePrice: 10.1, discountPercent: 0}]})),
    {code: 'permission-denied'});
  const allowed = database(); allowed.put('users/staff', {...allowed.read('users/staff'), canEditSalePrice: true});
  await save(allowed, input({customerId: '', credit: false, paid: 0,
    items: [{productId: 'a', quantity: 1, unitPrice: 9, basePrice: 10.1, discountPercent: 0}]}));
  assert.equal(allowed.read('sales/abcdefghijklmnopqrst').items[0].unitPrice, 9);
});
test('50-line invoice is one save, and a later sale cannot oversell', async () => {
  const db = database(); const items = [];
  for (let i = 0; i < 50; i++) {
    const id = 'p' + i;
    db.put('products/' + id, {active: true, name: id, price: 1, purchasePrice: 0.5});
    db.put('stock/main_' + id, {quantity: 1, branchId: 'main', productId: id});
    items.push({productId: id, quantity: 1, unitPrice: 1});
  }
  await save(db, input({items, paid: 50, credit: false, customerId: ''}));
  assert.equal(db.read('sales/abcdefghijklmnopqrst').items.length, 50);
  await assert.rejects(save(db, input({requestId: 'ABCDEFGHIJKLMNOPQRST', items, paid: 50, credit: false, customerId: ''})), {code: 'failed-precondition'});
  assert.equal(db.read('settings/cash').balance, 100);
});
