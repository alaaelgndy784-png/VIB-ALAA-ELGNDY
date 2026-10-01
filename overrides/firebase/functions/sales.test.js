const test = require('node:test');
const assert = require('node:assert/strict');
const {saveStaffSale} = require('./sales');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const FieldValue = {serverTimestamp: () => 'SERVER_TIME'};
function database() {
  let data = new Map([
    ['users/staff', {role: 'employee', active: true, branchId: 'staffBranch'}],
    ['products/a', {name: 'صنف أ', active: true, price: 10.1, purchasePrice: 7}],
    ['products/b', {name: 'صنف ب', active: true, price: 20, purchasePrice: 12}],
    ['stock/main_a', {branchId: 'main', productId: 'a', quantity: 10}],
    ['stock/main_b', {branchId: 'main', productId: 'b', quantity: 10}],
    ['customers/c', {name: 'عميل', phone: '010', balance: 100, active: true}],
    ['settings/cash', {balance: 50}],
  ]);
  const db = {
    collection(name) { return {doc(id) { return {path: name + '/' + id, id}; }}; },
    read(path) { return data.get(path); },
    put(path, value) { data.set(path, value); },
    size() { return data.size; },
    async runTransaction(callback) {
      const pending = [];
      const tx = {
        async get(ref) {
          assert.equal(pending.length, 0, 'All reads must precede all writes');
          return {ref, exists: data.has(ref.path), data: () => data.get(ref.path)};
        },
        set(ref, value, opts) { pending.push([ref, value, opts?.merge]); },
        update(ref, value) { assert.ok(data.has(ref.path)); pending.push([ref, value, true]); },
      };
      const result = await callback(tx);
      const next = new Map(data);
      for (const [ref, value, merge] of pending)
        next.set(ref.path, merge ? {...next.get(ref.path), ...value} : value);
      data = next;
      return result;
    },
  };
  return db;
}
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
