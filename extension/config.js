// Default OmniRoute connection settings.
// setup.ps1 in the kit repo overwrites this file with a fresh per-machine
// admin token (see the "OmniRoute Cookie Pusher (kit)" entry in the
// dashboard's API keys). You can also override it in the popup's Settings
// (persisted in chrome.storage). To rotate manually:
//   omniroute tokens create --name "Cookie Pusher" --scope admin
export const DEFAULT_URL = 'http://localhost:20128';
export const DEFAULT_API_KEY = '';

// Local cookie bridges — cookies are pushed here directly instead of into a
// gateway connection.
//   mimo-web-bridge   (20135) — Xiaomi MiMo AI Studio
//   meta-web-bridge    (20136) — Meta AI (Llama models)
//   gemini-chat-bridge (20138) — Google Gemini Chat
export const BRIDGE_URL = 'http://127.0.0.1:20135';
export const GEMINI_CHAT_BRIDGE_URL = 'http://127.0.0.1:20138';
