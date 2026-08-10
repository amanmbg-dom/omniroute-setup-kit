// OmniRoute Cookie Pusher — background service worker (MV3 module).
// Runs the auto-refresh: a scheduled full grab, plus a frequent check that
// re-pushes any web-cookie connection OmniRoute reports as expired.
import {
  ALARM_FULL,
  ALARM_CHECK,
  getSettings,
  setAlarms,
  refreshAll,
  checkExpiredAndRefresh,
  providersNeedingRefresh,
} from './core.js';

chrome.runtime.onInstalled.addListener(() => {
  setAlarms();
});

chrome.runtime.onStartup.addListener(() => {
  setAlarms();
});

// The popup re-arms alarms whenever the user changes auto-refresh settings.
chrome.runtime.onMessage.addListener((msg) => {
  if (msg && msg.type === 'settings-updated') setAlarms();
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (!alarm || (alarm.name !== ALARM_FULL && alarm.name !== ALARM_CHECK)) return;
  const settings = await getSettings();
  if (!settings.autoRefresh) return;
  try {
    if (alarm.name === ALARM_FULL) {
      const results = await refreshAll(settings);
      console.log('[OmniRoute Cookie Pusher] scheduled refresh:', summarize(results));
    } else {
      const results = await checkExpiredAndRefresh(settings);
      if (results.length) {
        console.log('[OmniRoute Cookie Pusher] expired-session refresh:', summarize(results));
      }
    }
  } catch (e) {
    console.warn('[OmniRoute Cookie Pusher] auto-refresh failed:', e && e.message);
  }
});

function summarize(results) {
  const ok = results.filter((r) => r.status === 'ok').length;
  const skip = results.filter((r) => r.status === 'skip').length;
  const err = results.filter((r) => r.status === 'error').length;
  return `${ok} pushed, ${skip} skipped, ${err} errors`;
}

// Testing hook (used by the automated CDP load test).
globalThis.__omnirouteBg = {
  getSettings,
  setAlarms,
  refreshAll,
  checkExpiredAndRefresh,
  providersNeedingRefresh,
  ALARM_FULL,
  ALARM_CHECK,
};
