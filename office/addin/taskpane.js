// SPDX-License-Identifier: Apache-2.0
// The native helper supplies the system language, even if Office uses another language.
const strings = JSON.parse(document.getElementById('cfm-strings').textContent);
const t = (key, ...args) => (strings['pane.' + key] || key).replace(/\{(\d+)\}/g, (match, index) => index < args.length ? String(args[index]) : match);
let host = null;
let busy = false;
let awaitingClose = false;
const byId = id => document.getElementById(id);
const token = document.querySelector('meta[name="cfm-token"]').content;
if (typeof Office !== 'undefined') Office.onReady(info => {
    host = info.host === Office.HostType.Word ? 'word' : info.host === Office.HostType.PowerPoint ? 'powerpoint' : info.host === Office.HostType.Excel ? 'excel' : null;
    byId('host').textContent = t('host', info.host || 'Office');
    if (host) byId('office-note').hidden = true;
    refresh();
});
async function refresh() {
    try {
        const response = await fetch('/api/status', { cache: 'no-store' });
        if (!response.ok) throw new Error(t('connectionUnavailable'));
        const data = await response.json();
        if (!data.ready) throw new Error(t('starting'));
        const activity = data.activity || {};
        byId('dot').className = activity.error ? 'error' : 'ready';
        byId('status').textContent = activity.error ? t('actionError') : activity.busy ? t('processing') : data.editing ? t('editing') : activity.recoverable ? t('draft') : t('ready');
        byId('detail').textContent = activity.error ? activity.error : activity.busy ? activity.message : data.editing ? t('editHint') : activity.recoverable ? t('draftHint') : t('pasteHint');
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
        byId('status').textContent = t('unavailable');
        byId('detail').textContent = t('setupHint');
        byId('edit').disabled = true;
        byId('paste').disabled = true;
    }
}
async function action(kind) {
    busy = true; byId('edit').disabled = true; byId('paste').disabled = true;
    byId('message').textContent = kind === 'paste' ? t('pasting') : t('opening');
    try {
        const response = await fetch(`/api/${kind}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-ChemOffice-Token': token }, body: JSON.stringify({ host }) });
        const data = await response.json();
        if (!response.ok) throw new Error(data.error || t('failed'));
        awaitingClose = kind === 'edit';
        byId('message').textContent = kind === 'paste' ? t('pasted') : t('opened');
    } catch (error) { byId('message').textContent = error.message; }
    finally { busy = false; refresh(); }
}
byId('edit').addEventListener('click', () => action('edit'));
byId('paste').addEventListener('click', () => action('paste'));
byId('host').textContent = t('host', 'Word + PowerPoint + Excel');
refresh();
setInterval(refresh, 2500);
