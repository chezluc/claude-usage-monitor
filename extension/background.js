// background.js — Claude Usage Monitor (MV3 service worker)

const LOCAL_SERVER = 'http://127.0.0.1:4480';
const ALARM_NAME   = 'refresh-usage';
const USAGE_URL    = 'https://claude.ai/settings/usage';
const INTERVAL_KEY = 'refreshInterval';
const DEFAULT_INTERVAL = 1;

async function getInterval() {
  return new Promise((resolve) => {
    chrome.storage.local.get([INTERVAL_KEY], (res) => {
      resolve(res[INTERVAL_KEY] ?? DEFAULT_INTERVAL);
    });
  });
}

async function setInterval_(minutes) {
  await chrome.storage.local.set({ [INTERVAL_KEY]: minutes });
  await chrome.alarms.clear(ALARM_NAME);
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: minutes });
}

function parseUsageText(body) {
  const plans = [];
  const defs = [
    { re: /Current session[\s\S]*?(\d+)%\s*used/i, name: 'Current session', section: 'Plan usage limits', rr: /Current session[\s\S]*?(Resets?\s+in\s+\d+\s+(hr\s+)?\d+\s+min)/i },
    { re: /All models[\s\S]*?(\d+)%\s*used/i, name: 'All models', section: 'Weekly limits', rr: /All models[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
    { re: /Sonnet only[\s\S]*?(\d+)%\s*used/i, name: 'Sonnet only', section: 'Weekly limits', rr: /Sonnet only[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
    { re: /Opus[\s\S]*?(\d+)%\s*used/i, name: 'Opus', section: 'Weekly limits', rr: /Opus[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
    { re: /Haiku[\s\S]*?(\d+)%\s*used/i, name: 'Haiku', section: 'Weekly limits', rr: /Haiku[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
  ];
  for (const d of defs) {
    const m = body.match(d.re);
    if (m) {
      const rm = body.match(d.rr);
      plans.push({ name: d.name, used: 0, total: 0, percent: parseInt(m[1], 10), resetDate: '', resetLabel: rm ? rm[1] : '', section: d.section });
    }
  }
  if (plans.length === 0) return null;
  const p = plans[0];
  return { used: 0, total: 0, percent: p.percent, resetDate: '', lastUpdated: new Date().toISOString(), plans };
}

function sendToLocalServer(data) {
  fetch(LOCAL_SERVER + '/usage', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(data),
  }).then(() => {
    console.log('[Claude Usage] Posted:', data.percent + '%', data.plans?.length, 'plans');
  }).catch((e) => {
    console.warn('[Claude Usage] POST failed:', e.message);
  });
}

async function triggerRefresh() {
  let tabs = await chrome.tabs.query({ url: USAGE_URL + '*' });
  let tab = tabs[0];

  if (!tab) {
    tab = await chrome.tabs.create({ url: USAGE_URL, active: false });
    await new Promise((r) => setTimeout(r, 5000));
  }

  try {
    // Just grab the page text — runs in ISOLATED world (default), no CORS issues
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      func: () => document.body.innerText,
    });

    const bodyText = results?.[0]?.result;
    if (!bodyText) {
      console.warn('[Claude Usage] No body text returned');
      return;
    }

    const data = parseUsageText(bodyText);
    if (data) {
      sendToLocalServer(data);
    } else {
      console.warn('[Claude Usage] Could not parse usage from page text');
    }
  } catch (e) {
    console.warn('[Claude Usage] executeScript failed:', e.message);
  }
}

// ── Event listeners ─────────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(async () => {
  const interval = await getInterval();
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: interval });
  triggerRefresh();
});

chrome.runtime.onStartup.addListener(async () => {
  const interval = await getInterval();
  const existing = await chrome.alarms.get(ALARM_NAME);
  if (!existing) {
    chrome.alarms.create(ALARM_NAME, { periodInMinutes: interval });
  }
  triggerRefresh();
});

chrome.alarms.onAlarm.addListener(async (alarm) => {
  if (alarm.name === ALARM_NAME) {
    await triggerRefresh();
  }
});

// Scrape when user navigates to usage page (debounced)
let lastAutoScrape = 0;
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url?.startsWith(USAGE_URL)) {
    const now = Date.now();
    if (now - lastAutoScrape > 30000) {
      lastAutoScrape = now;
      setTimeout(() => triggerRefresh(), 2000);
    }
  }
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.type === 'REFRESH_NOW') {
    triggerRefresh().then(() => sendResponse({ ok: true }));
    return true;
  }
  if (msg.type === 'SET_INTERVAL') {
    setInterval_(Number(msg.minutes)).then(() => sendResponse({ ok: true }));
    return true;
  }
});
