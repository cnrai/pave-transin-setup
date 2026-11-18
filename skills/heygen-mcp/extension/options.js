/* PAVE Connect — options page. Saves origin/token and requests host
   permission for the configured PAVE origin so the relay fetch is allowed. */

const $ = (id) => document.getElementById(id);

chrome.storage.local.get(['origin', 'token'], (r) => {
  $('origin').value = r.origin || '';
  $('token').value = r.token || '';
});

$('save').addEventListener('click', async () => {
  const originInput = $('origin').value.trim().replace(/\/+$/, '');
  const token = $('token').value.trim();
  const status = $('status');

  let parsed;
  try {
    parsed = new URL(originInput);
  } catch {
    status.textContent = 'Enter a valid origin starting with http:// or https://';
    return;
  }
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(parsed.hostname);
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    status.textContent = 'Only http:// loopback or https:// origins are allowed';
    return;
  }
  if (parsed.protocol === 'http:' && !loopback) {
    status.textContent = 'Non-loopback PAVE origins must use https://';
    return;
  }
  const origin = parsed.origin;

  await chrome.storage.local.set({ origin, token });

  let granted = false;
  try {
    granted = await chrome.permissions.request({ origins: [origin + '/*'] });
  } catch (e) {
    granted = false;
  }
  if (!granted) {
    const loopback = /^(http:\/\/127\.0\.0\.1|http:\/\/localhost)/.test(origin);
    status.textContent = loopback
      ? 'Saved. Origin permission declined, but loopback dev targets are usually CORS-open — relay will try anyway.'
      : 'Saved, but origin permission was declined — the relay will only work if ' + origin + ' allows cross-origin fetches (Access-Control-Allow-Origin).';
  } else {
    status.textContent = 'Saved. Relay target: ' + origin + '/api/mcp/oauth-relay';
  }
});
