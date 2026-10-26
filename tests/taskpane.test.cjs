// SPDX-License-Identifier: Apache-2.0
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const elements = Object.fromEntries(['dot','status','detail','edit','message','host','office-note'].map(id => [id,{textContent:'',className:'',disabled:false,addEventListener(){}}]));
let health = {ready:false,editing:false};
const context = vm.createContext({
  document:{getElementById:id=>elements[id],querySelector:()=>({content:'test-token'})},
  fetch:async()=>({ok:true,json:async()=>health}),setInterval(){}
});
vm.runInContext(fs.readFileSync('office/addin/taskpane.js','utf8'),context);
(async()=>{
  vm.runInContext("host = 'word'",context);
  await vm.runInContext('refresh()',context);
  assert.equal(elements.edit.disabled,true);
  assert.notEqual(elements.dot.className,'ready');
  console.log('PASS HTTP success without monitor readiness keeps editing disabled');
  health = {ready:true,editing:false};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.edit.disabled,false);
  assert.equal(elements.dot.className,'ready');
  console.log('PASS Monitor readiness automatically enables the Office action');
  health = {ready:true,editing:true};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.status.textContent,'ChemDraw edit in progress');
  console.log('PASS Active editing remains visible after setup');
  health = {ready:false,editing:false};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.edit.disabled,true);
  assert.match(elements.detail.textContent,/完成安装/);
  console.log('PASS Lost readiness guides the user back to installation');
})().catch(error=>{console.error(error);process.exitCode=1;});
