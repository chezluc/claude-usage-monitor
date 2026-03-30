// background.js — Claude Usage Monitor (MV3 service worker)

const LOCAL_SERVER = 'http://127.0.0.1:4480';
const ALARM_NAME   = 'refresh-usage';
const USAGE_URL    = 'https://claude.ai/settings/usage';
const CACHE_KEY    = 'usageData';
const INTERVAL_KEY = 'refreshInterval';
const DEFAULT_INTERVAL = 5; // minutes

// ── Helpers ──────────────────────────────────────────────────────────────────

async function getInterval() {
  return new Promise((resolve) => {
    chrome.storage.local.get([INTERVAL_KEY], (res) => {
      resolve(res[INTERVAL_KEY] ?? DEFAULT_INTERVAL);
    });
  });
}

async function setInterval_(minutes) {
  await chrome.storage.local.set({ [INTERVAL_KEY]: minutes });
  // Recreate alarm with new interval
  await chrome.alarms.clear(ALARM_NAME);
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: minutes });
}

async function storeUsageData(data) {
  const record = { ...data, lastUpdated: new Date().toISOString() };
  await chrome.storage.local.set({ [CACHE_KEY]: record });
  return record;
}

function sendToLocalServer(data) {
  fetch(LOCAL_SERVER + '/usage', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).catch((e) => {
    console.warn('[Claude Usage] Local server POST failed:', e.message);
  });
}

// ── Tab management ───────────────────────────────────────────────────────────

async function findUsageTab() {
  const tabs = await chrome.tabs.query({ url: USAGE_URL + '*' });
  return tabs[0] ?? null;
}

async function executeContentScript(tabId) {
  try {
    await chrome.scripting.executeScript({
      target: { tabId },
      files: ['content.js'],
    });
  } catch (e) {
    console.warn('[Claude Usage] executeScript error:', e);
  }
}

async function triggerRefresh() {
  let tab = await findUsageTab();

  if (tab) {
    // Tab exists — just re-run the content script
    await executeContentScript(tab.id);
  } else {
    // Open tab silently (no focus)
    tab = await chrome.tabs.create({ url: USAGE_URL, active: false });
    // Wait for it to load
    await new Promise((resolve) => setTimeout(resolve, 3500));
    // Execute content script
    await executeContentScript(tab.id);
  }
}

// ── Event listeners ──────────────────────────────────────────────────────────

// Install / startup
chrome.runtime.onInstalled.addListener(async () => {
  const interval = await getInterval();
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: interval });
  console.log('[Claude Usage] Installed. Alarm set for every', interval, 'minutes.');
});

chrome.runtime.onStartup.addListener(async () => {
  const interval = await getInterval();
  // Ensure alarm exists after browser restart
  const existing = await chrome.alarms.get(ALARM_NAME);
  if (!existing) {
    chrome.alarms.create(ALARM_NAME, { periodInMinutes: interval });
  }
});

// Alarm fires → trigger refresh
chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === ALARM_NAME) {
    await triggerRefresh();
  }
});

// Messages from content script or popup
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'USAGE_DATA') {
    (async () => {
      const record = await storeUsageData(msg.data);
      sendToLocalServer(record);
      sendResponse({ ok: true });
    })();
    return true; // keep channel open for async response
  }

  if (msg.type === 'REFRESH_NOW') {
    triggerRefresh().then(() => sendResponse({ ok: true })).catch((e) => sendResponse({ ok: false, error: String(e) }));
    return true;
  }

  if (msg.type === 'GET_DATA') {
    chrome.storage.local.get([CACHE_KEY], (res) => {
      sendResponse(res[CACHE_KEY] ?? null);
    });
    return true;
  }

  if (msg.type === 'SET_INTERVAL') {
    const minutes = Number(msg.minutes);
    if (!isNaN(minutes) && minutes > 0) {
      setInterval_(minutes).then(() => sendResponse({ ok: true })).catch((e) => sendResponse({ ok: false, error: String(e) }));
    } else {
      sendResponse({ ok: false, error: 'Invalid interval' });
    }
    return true;
  }

  if (msg.type === 'GET_INTERVAL') {
    getInterval().then((v) => sendResponse(v));
    return true;
  }
});
