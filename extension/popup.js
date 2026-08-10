// OmniRoute Cookie Pusher — popup UI (ES module).
// All logic lives in core.js (shared with the background service worker).
'use strict';

import {
  DEFAULTS,
  PROVIDERS,
  getSettings,
  grabCredential,
  pushConnection,
  runAll,
  checkExpiredAndRefresh,
} from './core.js';

function render(results) {
  const el = document.getElementById('results');
  el.innerHTML = '';
  if (!results) return;
  let ok = 0, skip = 0, needTab = 0, err = 0;
  for (const r of results) {
    const row = document.createElement('div');
    row.className = 'row';
    const name = document.createElement('span');
    name.className = 'name';
    name.textContent = r.label;
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = r.free ? 'free' : 'sub';
    const status = document.createElement('span');
    status.className = 'status';
    if (r.status === 'ok') {
      ok++;
      status.className += ' ok';
      status.textContent = '✓ pushed';
      row.title = r.note ? `Pushed (${r.note})` : 'Pushed';
    } else if (r.status === 'skip' && r.reason === 'need-tab') {
      needTab++;
      status.className += ' warn';
      status.textContent = 'open tab needed';
    } else if (r.status === 'skip') {
      skip++;
      status.className += ' muted';
      status.textContent = 'not signed in';
    } else {
      err++;
      status.className += ' bad';
      status.textContent = 'error';
      row.title = r.error || '';
    }
    row.append(name, tag, status);
    el.appendChild(row);
  }
  const footer = document.getElementById('footer');
  footer.textContent = `${ok} pushed · ${skip} not signed in · ${needTab} need open tab · ${err} errors`;
}

function renderError(message) {
  const el = document.getElementById('results');
  el.innerHTML = '';
  const row = document.createElement('div');
  row.className = 'row';
  row.innerHTML = `<span class="name">${String(message).replace(/</g, '&lt;')}</span><span class="status bad">error</span>`;
  el.appendChild(row);
}

async function init() {
  const urlInput = document.getElementById('url');
  const keyInput = document.getElementById('apikey');
  const autoToggle = document.getElementById('autoRefresh');
  const hoursSelect = document.getElementById('refreshHours');
  const settings = await getSettings();
  urlInput.value = settings.url;
  keyInput.value = settings.apiKey;
  autoToggle.checked = settings.autoRefresh;
  hoursSelect.value = String(settings.refreshHours);

  async function saveSettings() {
    await chrome.storage.local.set({
      url: urlInput.value.trim(),
      apiKey: keyInput.value.trim(),
      autoRefresh: autoToggle.checked,
      refreshHours: Number(hoursSelect.value) || 6,
    });
    chrome.runtime.sendMessage({ type: 'settings-updated' }).catch(() => {});
  }

  autoToggle.addEventListener('change', saveSettings);
  hoursSelect.addEventListener('change', saveSettings);

  const btn = document.getElementById('go');
  btn.addEventListener('click', async () => {
    btn.disabled = true;
    btn.textContent = 'Grabbing…';
    try {
      const s = await getSettings();
      render(await runAll(s));
    } catch (e) {
      renderError(e.message);
      document.getElementById('footer').textContent = 'Is OmniRoute running on localhost:20128? (Start-OmniRoute)';
    } finally {
      btn.disabled = false;
      btn.textContent = 'Grab & push sessions';
    }
  });

  const btnExpired = document.getElementById('checkExpired');
  btnExpired.addEventListener('click', async () => {
    btnExpired.disabled = true;
    btnExpired.textContent = 'Checking…';
    try {
      const s = await getSettings();
      const results = await checkExpiredAndRefresh(s);
      if (!results.length) {
        render([]);
        document.getElementById('footer').textContent = 'No expired sessions found — all connections healthy.';
      } else {
        render(results);
      }
    } catch (e) {
      renderError(e.message);
    } finally {
      btnExpired.disabled = false;
      btnExpired.textContent = 'Check expired';
    }
  });

  const footer = document.getElementById('footer');
  footer.textContent = `Auto-refresh ${autoToggle.checked ? `ON — full grab every ${settings.refreshHours}h + expiry check every 30m` : 'OFF'}`;
}

init();

// Debug/testing hook (also used by the automated load test).
window.__omniroute = {
  PROVIDERS,
  DEFAULTS,
  getSettings,
  grabCredential,
  pushConnection,
  runAll,
  checkExpiredAndRefresh,
};
