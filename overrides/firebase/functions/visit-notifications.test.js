'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {visitNotification} = require('./visit-notifications');

test('visit push contains exactly employee and customer', () => {
  const m = visitNotification('v1', {
    consented: true, employeeId:'e1', customerId:'c1',
    employeeName:'حمادة', customerName:'معرض محمد علي',
  });
  assert.equal(m.notification.body, 'حمادة سجل زيارة عند معرض محمد علي');
  assert.equal(m.data.visitId, 'v1');
  assert.equal(m.android.notification.channelId, 'vib_manager_visit_push_v1');
  assert.ok(!('latitude' in m.data));
  assert.ok(!('longitude' in m.data));
});
test('no consent means no notification', () => {
  assert.equal(visitNotification('v1',{
    consented:false, employeeId:'e1', customerId:'c1',
    employeeName:'حمادة', customerName:'تاجر',
  }), null);
});
