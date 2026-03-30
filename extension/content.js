// content.js — Claude Usage Monitor
// Runs in ISOLATED world on https://claude.ai/settings/usage
// Scrapes usage bars from DOM, sends to background via chrome.runtime

(function () {
  'use strict';

  function scrapeDOM() {
    const body = document.body;
    if (!body) return null;
    const bodyText = body.innerText ?? '';
    const plans = [];

    // Find all "XX% used" leaf elements
    const allEls = body.querySelectorAll('*');
    for (const el of allEls) {
      const text = el.innerText?.trim() ?? '';
      if (!/^\d+%\s*used$/i.test(text) || text.length > 20) continue;

      const pctMatch = text.match(/(\d+)%\s*used/i);
      if (!pctMatch) continue;
      const percent = parseInt(pctMatch[1], 10);

      let container = el.parentElement;
      for (let i = 0; i < 6 && container; i++) {
        if (/resets?\s/i.test(container.innerText ?? '') && (container.innerText ?? '').length < 300) break;
        container = container.parentElement;
      }
      if (!container) container = el.parentElement;

      const lines = (container.innerText ?? '').split('\n').map(l => l.trim()).filter(Boolean);
      let name = '', resetLabel = '';

      for (const line of lines) {
        if (/^\d+%\s*used$/i.test(line)) continue;
        if (/^(plan usage|weekly limit|learn more|last updated|extra usage|turn on extra)/i.test(line)) continue;
        if (/^resets?\s/i.test(line)) { resetLabel = line; continue; }
        if (!name) name = line;
      }
      if (!name) name = 'Usage';

      let section = 'Usage';
      if (/current session/i.test(name)) section = 'Plan usage limits';
      else if (/all models|sonnet|opus|haiku|claude/i.test(name)) section = 'Weekly limits';

      if (!plans.find(p => p.name === name)) {
        plans.push({ name, used: 0, total: 0, percent, resetDate: '', resetLabel, section });
      }
    }

    // Regex fallback
    if (plans.length === 0) {
      const blocks = [
        { re: /Current session[\s\S]*?(\d+)%\s*used/i, name: 'Current session', sec: 'Plan usage limits', rr: /Current session[\s\S]*?(Resets?\s+in\s+\d+\s+hr\s+\d+\s+min)/i },
        { re: /All models[\s\S]*?(\d+)%\s*used/i, name: 'All models', sec: 'Weekly limits', rr: /All models[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
        { re: /Sonnet only[\s\S]*?(\d+)%\s*used/i, name: 'Sonnet only', sec: 'Weekly limits', rr: /Sonnet only[\s\S]*?(Resets?\s+\w+\s+[\d:]+\s*[AP]M)/i },
      ];
      for (const b of blocks) {
        const m = bodyText.match(b.re);
        if (m) {
          const rm = bodyText.match(b.rr);
          plans.push({ name: b.name, used: 0, total: 0, percent: parseInt(m[1], 10), resetDate: '', resetLabel: rm ? rm[1] : '', section: b.sec });
        }
      }
    }

    if (plans.length === 0) return null;
    const p = plans[0];
    return { used: p.used, total: p.total, percent: p.percent, resetDate: p.resetDate, lastUpdated: new Date().toISOString(), plans, source: 'dom' };
  }

  function send(data) {
    try { chrome.runtime.sendMessage({ type: 'USAGE_DATA', data }); } catch(e) {}
  }

  setTimeout(() => {
    const data = scrapeDOM();
    if (data) send(data);
    else send({ used:0, total:0, percent:0, resetDate:'', plans:[], source:'dom_empty', error:'No data' });
  }, 3000);

  setInterval(() => { const d = scrapeDOM(); if (d) send(d); }, 60000);

  chrome.runtime.onMessage.addListener((msg, _, resp) => {
    if (msg.type === 'SCRAPE_NOW') {
      const d = scrapeDOM();
      resp(d || { used:0,total:0,percent:0,resetDate:'',plans:[],source:'none',error:'No data' });
      if (d) send(d);
    }
    return true;
  });
})();
