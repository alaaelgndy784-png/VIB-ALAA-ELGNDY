const test = require('node:test');
const assert = require('node:assert/strict');
const {appendInvoice} = require('./invoice-edits');
const {database, HttpsError, FieldValue} = require('./test-fixtures');
function fixture(type = 'sales') {
  const db = database();
  db.put('users/owner', {role: 'owner', active: true});
  db.put('suppliers/s', {name: 'مورد', balance: 200, active: true});
  db.put(type + '/existing', {branchId: 'staffBranch', stockBranchId: 'main',
    status: 'completed', customerId: 'c', supplierId: 's',
    items: [{productId: 'a', productName: 'صنف أ', quantity: 1,
      [type === 'sales' ? 'unitPrice' : 'unitCost']: 10.1, lineTotal: 10.1}],
    total: 10.1, paid: 5, due: 5.1, createdAt: 'ORIGINAL_TIME'});
  return db;
}
function input(type = 'sales', overrides = {}) {
  return {type, invoiceId: 'existing', requestId: 'abcdefghijklmnopqrst', revision: 0,
    items: [{productId: 'b', quantity: 2, unitPrice: type === 'sales' ? 20 : 12}], paid: 10, ...overrides};
}
const save = (db, data, uid = 'owner') => appendInvoice(db, FieldValue, HttpsError, uid, data);
test('Owner appends to same sale ID, preserves date and updates main stock, customer and cash', async () => {
  const db = fixture();
  await save(db, input());
  const invoice = db.read('sales/existing');
  assert.equal(invoice.items.length, 2); assert.equal(invoice.total, 50.1);
  assert.equal(invoice.paid, 15); assert.equal(invoice.due, 35.1);
  assert.equal(invoice.createdAt, 'ORIGINAL_TIME');
  assert.equal(db.read('stock/main_b').quantity, 8);
  assert.equal(db.read('customers/c').balance, 130);
  assert.equal(db.read('settings/cash').balance, 60);
  const size = db.size();
  await save(db, input());
  assert.equal(db.size(), size); assert.equal(db.read('stock/main_b').quantity, 8);
});
test('Owner appends purchase: stock rises, cash falls, supplier balance increases', async () => {
  const db = fixture('purchases');
  await save(db, input('purchases'));
  assert.equal(db.read('purchases/existing').total, 34.1);
  assert.equal(db.read('purchases/existing').due, 19.1);
  assert.equal(db.read('suppliers/s').balance, 214);
  assert.equal(db.read('settings/cash').balance, 40);
  assert.equal(db.read('stock/main_b').quantity, 12);
  assert.equal(db.read('products/b').purchasePrice, 12);
});
test('Employee cannot append sales or purchases even by calling API directly', async () => {
  for (const type of ['sales', 'purchases']) {
    const db = fixture(type), size = db.size();
    await assert.rejects(save(db, input(type), 'staff'), {code: 'permission-denied'});
    assert.equal(db.size(), size);
  }
});
test('Stale revision, returned invoice and shortage reject with no partial changes', async () => {
  const db = fixture(); await save(db, input());
  const size = db.size();
  await assert.rejects(save(db, input('sales', {requestId: 'ABCDEFGHIJKLMNOPQRST'})), {code: 'aborted'});
  assert.equal(db.size(), size);
  const returned = fixture(); returned.put('sales/existing', {...returned.read('sales/existing'), status: 'returned'});
  await assert.rejects(save(returned, input()), {code: 'failed-precondition'});
  const shortage = fixture(); shortage.put('stock/main_b', {quantity: 0});
  await assert.rejects(save(shortage, input()), {code: 'failed-precondition'});
  assert.equal(shortage.read('settings/cash').balance, 50);
});
test('Additional quantity merges existing row and legacy missing-payment invoices are rejected', async () => {
  const db = fixture();
  db.put('sales/existing', {...db.read('sales/existing'), items: [{...db.read('sales/existing').items[0], purchasePriceAtSale: 4}]});
  await save(db, input('sales', {items: [{productId: 'a', quantity: 2, unitPrice: 10.1}], paid: 20.2}));
  assert.equal(db.read('sales/existing').items.length, 1);
  assert.equal(db.read('sales/existing').quantity, 3);
  assert.equal(db.read('sales/existing').items[0].purchasePriceAtSale, 6);
  assert.equal(db.read('sales/existing').due, 5.1);
  const legacy = fixture(); legacy.put('sales/existing', {status: 'completed', total: 10.1});
  await assert.rejects(save(legacy, input()), {code: 'failed-precondition'});
});
