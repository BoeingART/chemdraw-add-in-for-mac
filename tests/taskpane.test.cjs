// SPDX-License-Identifier: Apache-2.0
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const elements = Object.fromEntries(['dot','status','detail','edit','paste','message','host','office-note'].map(id => [id,{textContent:'',className:'',disabled:false,addEventListener(){}}]));
let health = {ready:false,editing:false};
const handlers = {};
elements.edit.addEventListener = (name,fn)=>handlers.edit=fn;
elements.paste.addEventListener = (name,fn)=>handlers.paste=fn;
const actions = [];
const context = vm.createContext({
  document:{getElementById:id=>elements[id],querySelector:()=>({content:'test-token'})},
  fetch:async(url,options)=>{ if (options?.method === 'POST') { actions.push({url,options}); return {ok:true,json:async()=>({pasted:true})}; } return {ok:true,json:async()=>health}; },setInterval(){}
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
  health = {ready:true,editing:false,activity:{error:'Paste failed: allow Office access',busy:false}};
  await vm.runInContext('refresh()',context);
  assert.match(elements.message.textContent,/allow Office access/);
  assert.equal(elements.dot.className,'error');
  console.log('PASS Shortcut paste failures surface in the task pane');
  health = {ready:true,editing:false,activity:{busy:true,message:'Rendering'}};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.edit.disabled,true);
  assert.equal(elements.paste.disabled,true);
  assert.equal(elements.detail.textContent,'Rendering');
  console.log('PASS Automation progress disables duplicate actions');
  health = {ready:true,editing:false,activity:{recoverable:true,busy:false}};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.status.textContent,'An editing draft is available');
  assert.equal(elements.paste.disabled,false);
  console.log('PASS A retained draft is not reported as an active edit');
  await handlers.paste();
  assert.equal(actions[0].url,'/api/paste');
  assert.equal(JSON.parse(actions[0].options.body).host,'word');
  assert.equal(actions[0].options.headers['X-ChemOffice-Token'],'test-token');
  console.log('PASS Paste button invokes the authenticated chemistry conversion');
  health = {ready:false,editing:false};
  await vm.runInContext('refresh()',context);
  assert.equal(elements.edit.disabled,true);
  assert.match(elements.detail.textContent,/完成安装/);
  console.log('PASS Lost readiness guides the user back to installation');
})().catch(error=>{console.error(error);process.exitCode=1;});
