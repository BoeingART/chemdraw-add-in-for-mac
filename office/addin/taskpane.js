// SPDX-License-Identifier: Apache-2.0
let host = null;
let busy = false;
let awaitingClose = false;
const byId = id => document.getElementById(id);
const token = document.querySelector('meta[name="cfm-token"]').content;
if (typeof Office !== 'undefined') Office.onReady(info => {
  host = info.host === Office.HostType.Word ? 'word' : info.host === Office.HostType.PowerPoint ? 'powerpoint' : null;
  byId('host').textContent = `${info.host || 'Office'} · Local preview`;
  if (host) byId('office-note').hidden = true;
  refresh();
});
async function refresh() {
  try {
    const response = await fetch('/api/status', {cache:'no-store'});
    if (!response.ok) throw new Error('Connection unavailable');
    const data = await response.json();
    if (!data.ready) throw new Error('Paste helper is starting');
    const activity = data.activity || {};
    byId('dot').className = activity.error ? 'error' : 'ready';
    byId('status').textContent = activity.error ? 'Drawing action needs attention' : activity.busy ? 'Processing your drawing…' : data.editing ? 'ChemDraw edit in progress' : activity.recoverable ? 'An editing draft is available' : 'Ready to keep drawing';
    byId('detail').textContent = activity.error ? activity.error : activity.busy ? activity.message : data.editing ? 'Close with ⌘W to update Office.' : activity.recoverable ? 'Double-click the original drawing to resume, or paste a new structure.' : 'Paste with ⌘V, right-click → Paste, or use Paste editable drawing.';
    if (activity.error) byId('message').textContent = activity.error;
    else if (activity.message) byId('message').textContent = activity.message;
    if (awaitingClose && !data.editing && !activity.error && !activity.busy) {
      byId('message').textContent = activity.message || '';
      awaitingClose = false;
    }
    byId('edit').disabled = !host || busy || !!activity.busy;
    byId('paste').disabled = !host || busy || !!activity.busy;
  } catch (_) {
    byId('dot').className = '';
    byId('status').textContent = 'Local helper is unavailable';
    byId('detail').textContent = 'Open ChemOffice Add-ins for Mac → 完成安装 to finish permissions and start the paste helper.';
    byId('edit').disabled = true;
    byId('paste').disabled = true;
  }
}
async function action(kind) {
  busy = true; byId('edit').disabled = true; byId('paste').disabled = true;
  byId('message').textContent = kind === 'paste' ? 'Pasting an editable drawing…' : 'Opening the selected drawing in ChemDraw…';
  try {
    const response = await fetch(`/api/${kind}`, {method:'POST', headers:{'Content-Type':'application/json','X-ChemOffice-Token':token}, body:JSON.stringify({host})});
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'The drawing action could not be completed.');
    awaitingClose = kind === 'edit';
    byId('message').textContent = kind === 'paste' ? 'Editable drawing pasted.' : 'Your drawing is open in ChemDraw. Close with ⌘W to return.';
  } catch (error) { byId('message').textContent = error.message; }
  finally { busy = false; refresh(); }
}
byId('edit').addEventListener('click', () => action('edit'));
byId('paste').addEventListener('click', () => action('paste'));
refresh();
setInterval(refresh, 2500);
