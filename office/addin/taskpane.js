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
    byId('dot').className = 'ready';
    byId('status').textContent = data.editing ? 'ChemDraw edit in progress' : 'Ready to keep drawing';
    byId('detail').textContent = data.editing ? 'Close with ⌘W to update Office.' : 'Double-click a ChemOffice drawing, or use the button below.';
    if (awaitingClose && !data.editing) {
      byId('message').textContent = '';
      awaitingClose = false;
    }
    byId('edit').disabled = !host || busy;
  } catch (_) {
    byId('dot').className = '';
    byId('status').textContent = 'Local helper is unavailable';
    byId('detail').textContent = 'Open Start ChemOffice.command, then reopen this panel.';
    byId('edit').disabled = true;
  }
}
byId('edit').addEventListener('click', async () => {
  busy = true; byId('edit').disabled = true;
  byId('message').textContent = 'Opening the selected drawing in ChemDraw…';
  try {
    const response = await fetch('/api/edit', {method:'POST', headers:{'Content-Type':'application/json','X-ChemOffice-Token':token}, body:JSON.stringify({host})});
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || 'The drawing could not be opened.');
    awaitingClose = true;
    byId('message').textContent = 'Your drawing is open in ChemDraw. Close with ⌘W to return.';
  } catch (error) { byId('message').textContent = error.message; }
  finally { busy = false; refresh(); }
});
refresh();
setInterval(refresh, 2500);
