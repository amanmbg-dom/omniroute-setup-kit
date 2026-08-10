// Default OmniRoute connection settings.
// setup.ps1 in the kit repo overwrites this file with a fresh per-machine
// admin token (see the "OmniRoute Cookie Pusher (kit)" entry in the
// dashboard's API keys). You can also override it in the popup's Settings
// (persisted in chrome.storage). To rotate manually:
//   omniroute tokens create --name "Cookie Pusher" --scope admin
export const DEFAULT_URL = 'http://localhost:20128';
export const DEFAULT_API_KEY = '';
