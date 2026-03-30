// background.js — Claude Usage Monitor (MV3 service worker)

const LOCAL_SERVER = 'http://127.0.0.1:4480';
const ALARM_NAME   = 'refresh-usage';
const USAGE_URL    = 'https://claude.ai/settings/usage';
const INTERVAL_KEY = 'refreshInterval';
const DEFAULT_INTERVAL = 1; // minutes

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

function sendToLocalServer(data) {
  data.lastUpdated = new Date().toISOString();
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

// ── Scrape code as a string (avoids func serialization issues with regex) ───

const SCRAPE_CODE = `
(function() {
  const body = document.body.innerText;
  const plans = [];
  const defs = [
    { re: /Current session[\\s\\S]*?(\\d+)%\\s*used/i, name: 'Current session', section: 'Plan usage limits', rr: /Current session[\\s\\S]*?(Resets?\\s+in\\s+\\d+\\s+hr\\s+\\d+\\s+min)/i },
    { re: /All models[\\s\\S]*?(\\d+)%\\s*used/i, name: 'All models', section: 'Weekly limits', rr: /All models[\\s\\S]*?(Resets?\\s+\\w+\\s+[\\d:]+\\s*[AP]M)/i },
    { re: /Sonnet only[\\s\\S]*?(\\d+)%\\s*used/i, name: 'Sonnet only', section: 'Weekly limits', rr: /Sonnet only[\\s\\S]*?(Resets?\\s+\\w+\\s+[\\d:]+\\s*[AP]M)/i },
    { re: /Opus[\\s\\S]*?(\\d+)%\\s*used/i, name: 'Opus', section: 'Weekly limits', rr: /Opus[\\s\\S]*?(Resets?\\s+\\w+\\s+[\\d:]+\\s*[AP]M)/i },
    { re: /Haiku[\\s\\S]*?(\\d+)%\\s*used/i, name: 'Haiku', section: 'Weekly limits', rr: /Haiku[\\s\\S]*?(Resets?\\s+\\w+\\s+[\\d:]+\\s*[AP]M)/i },
  ];
  for (const d of defs) {
    const m = body.match(d.re);
    if (m) {
      const rm = body.match(d.rr);
      plans.push({ name: d.name, used: 0, total: 0, percent: parseInt(m[1], 10), resetDate: '', resetLabel: rm ? rm[1] : '', section: d.section });
    }
  }
  const p = plans[0] || { percent: 0 };
  return { used: 0, total: 0, percent: p.percent, resetDate: '', plans };
})();
`;

// ── Refresh logic ───────────────────────────────────────────────────────────

async function triggerRefresh() {
  let tabs = await chrome.tabs.query({ url: USAGE_URL + '*' });
  let tab = tabs[0];

  if (!tab) {
    // Open usage tab in background
    tab = await chrome.tabs.create({ url: USAGE_URL, active: false });
    await new Promise((r) => setTimeout(r, 5000));
  } else {
    // Tab exists — just scrape it (don't reload, page updates itself)
    await new Promise((r) => setTimeout(r, 500));
  }

  try {
    const results = await chrome.scripting.executeScript({
      target: { tabId: tab.id },
      world: 'MAIN',
      args: [],
      func: () => {
        const body = document.body.innerText;
        const plans = [];
        const defs = [
          [/Current session[\s\S]*?(\d+)%\s*used/i, 'Current session', 'Plan usage limits', /Current session[\s\S]*?(Resets?\s+in\s+\d+\s+hr\s+\d+\s+min)/i],
          [/All models[\s\S]*?(\d+)%\s*used/i, 'All models', 'Weekly limits', /All models[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
          [/Sonnet only[\s\S]*?(\d+)%\s*used/i, 'Sonnet only', 'Weekly limits', /Sonnet only[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
          [/Opus[\s\S]*?(\d+)%\s*used/i, 'Opus', 'Weekly limits', /Opus[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
          [/Haiku[\s\S]*?(\d+)%\s*used/i, 'Haiku', 'Weekly limits', /Haiku[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
        ];
        for (const [re, name, section, rr] of defs) {
          const m = body.match(re);
          if (m) {
            const rm = body.match(rr);
            plans.push({ name, used: 0, total: 0, percent: parseInt(m[1], 10), resetDate: '', resetLabel: rm ? rm[1] : '', section });
          }
        }
        const p = plans[0] || { percent: 0 };
        return { used: 0, total: 0, percent: p.percent, resetDate: '', plans };
      },
    });

    const data = results?.[0]?.result;
    if (data && data.plans && data.plans.length > 0) {
      sendToLocalServer(data);
    } else {
      console.warn('[Claude Usage] Scrape returned no plans');
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

// Scrape when user manually navigates to usage page (not our reloads)
let lastRefreshTime = 0;
chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === 'complete' && tab.url?.startsWith(USAGE_URL)) {
    const now = Date.now();
    // Only scrape if we haven't refreshed in the last 30 seconds (avoids reload loop)
    if (now - lastRefreshTime > 30000) {
      lastRefreshTime = now;
      setTimeout(async () => {
        // Just scrape, don't reload — the page is already loaded
        try {
          const results = await chrome.scripting.executeScript({
            target: { tabId: tab.id },
            world: 'MAIN',
            func: () => {
              const body = document.body.innerText;
              const plans = [];
              const defs = [
                [/Current session[\s\S]*?(\d+)%\s*used/i, 'Current session', 'Plan usage limits', /Current session[\s\S]*?(Resets?\s+in\s+\d+\s+hr\s+\d+\s+min)/i],
                [/All models[\s\S]*?(\d+)%\s*used/i, 'All models', 'Weekly limits', /All models[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
                [/Sonnet only[\s\S]*?(\d+)%\s*used/i, 'Sonnet only', 'Weekly limits', /Sonnet only[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i],
              ];
              for (const [re, name, section, rr] of defs) {
                const m = body.match(re);
                if (m) {
                  const rm = body.match(rr);
                  plans.push({ name, used: 0, total: 0, percent: parseInt(m[1], 10), resetDate: '', resetLabel: rm ? rm[1] : '', section });
                }
              }
              const p = plans[0] || { percent: 0 };
              return { used: 0, total: 0, percent: p.percent, resetDate: '', plans };
            },
          });
          const data = results?.[0]?.result;
          if (data?.plans?.length > 0) sendToLocalServer(data);
        } catch (e) {}
      }, 2000);
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
