# Claude Usage Monitor — macOS Menu Bar App

Displays your Claude.ai message usage (e.g. `87%`) in the macOS menu bar by scraping the Claude usage page from a Chrome extension and forwarding the data to a native Python/rumps app.

---

## How it works

```
Chrome (claude.ai/settings/usage)
  └─ content.js scrapes DOM + intercepts API responses
       └─ sends data to background.js via chrome.runtime.sendMessage
            └─ background.js stores data in chrome.storage.local
                 └─ forwards to native host via chrome.runtime.sendNativeMessage
                      └─ claude_usage.py receives via stdin (native messaging)
                           └─ updates menu bar title + writes usage_cache.json
```

A fallback poller in `claude_usage.py` also watches `usage_cache.json` every 60 s, so the menu bar stays alive even if the Chrome connection drops.

---

## Requirements

- macOS (Intel or Apple Silicon)
- Python 3.10+
- Google Chrome or Chrome Canary
- A Claude.ai account with Pro/Team plan (usage page must be accessible)

---

## Setup

### Step 1 — Install Python dependency

```bash
pip3 install rumps
# or with a virtual environment:
python3 -m venv ~/venvs/claude-usage
source ~/venvs/claude-usage/bin/activate
pip install rumps
```

### Step 2 — First install run (creates manifest template)

```bash
cd ~/Dropbox/claude-menu-bar-app/native
chmod +x install.sh
./install.sh
```

This makes `claude_usage.py` executable and copies the native messaging manifest to:
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`
- `~/Library/Application Support/Google/Chrome Canary/NativeMessagingHosts/` (if Canary is installed)

### Step 3 — Load the Chrome extension

1. Open Chrome and go to `chrome://extensions`
2. Enable **Developer Mode** (toggle in the top-right corner)
3. Click **Load unpacked**
4. Select the `extension/` folder inside this repo:
   ```
   ~/Dropbox/claude-menu-bar-app/extension/
   ```
5. Note the **Extension ID** shown on the extension card (a 32-character string like `abcdefghijklmnopabcdefghijklmnop`)

### Step 4 — Re-run install with your Extension ID

```bash
./install.sh --id abcdefghijklmnopabcdefghijklmnop
```

This rewrites the native messaging manifest with the correct `allowed_origins` entry so Chrome trusts your extension to talk to the native host.

### Step 5 — Start the menu bar app

```bash
python3 ~/Dropbox/claude-menu-bar-app/native/claude_usage.py
```

You should see a `?` appear in the menu bar. It will update to a percentage as soon as the first scrape completes.

> **Tip:** Add this command to your Login Items (System Settings → General → Login Items) so it starts automatically.

### Step 6 — Keep or let the extension open the usage tab

The extension will automatically open `https://claude.ai/settings/usage` in a background tab when its refresh alarm fires (default: every 5 minutes). You can also keep the tab open manually for faster updates.

---

## Menu bar items

| Item | Description |
|------|-------------|
| `87%` (title) | Percentage of monthly messages used |
| `87 / 100 messages used` | Raw count |
| `Resets: Apr 15, 2026` | Next reset date |
| `Last updated: 2:34 PM` | When data was last received |
| **Refresh Now** | Re-reads the local cache file immediately |
| **Settings → interval** | Note: interval changes must also be applied in the Chrome extension's background alarm |
| **Open claude.ai/settings/usage** | Opens the usage page in your default browser |
| **Quit** | Exits the menu bar app |

---

## Troubleshooting

### Menu bar shows `?` and never updates

1. Make sure `claude_usage.py` is running.
2. Open `chrome://extensions` and confirm the extension is enabled.
3. Open `https://claude.ai/settings/usage` manually in Chrome and watch for console errors (`F12 → Console`).
4. Check that the Extension ID in the manifest matches the loaded extension:
   ```bash
   cat ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/com.claudeusage.menubar.json
   ```

### Native messaging not connecting

- Confirm the `path` in the manifest is an absolute path to `claude_usage.py`.
- Confirm the file is executable: `ls -la native/claude_usage.py`
- Confirm the `allowed_origins` value exactly matches `chrome-extension://YOUR_ID/` (trailing slash required).

### `rumps` import error

```bash
pip3 install rumps
```

If using a venv, make sure you launch the script from within that venv or use the venv's Python explicitly:
```bash
~/venvs/claude-usage/bin/python native/claude_usage.py
```

---

## File structure

```
claude-menu-bar-app/
├── extension/
│   ├── manifest.json       MV3 Chrome extension manifest
│   ├── background.js       Service worker (alarms, native messaging)
│   ├── content.js          DOM scraper + fetch/XHR interceptor
│   └── icons/
│       ├── PLACEHOLDER.txt (replace with 16/48/128px PNGs)
│       ├── icon16.png      (create these)
│       ├── icon48.png
│       └── icon128.png
├── native/
│   ├── claude_usage.py     rumps menu bar app + native messaging host
│   ├── com.claudeusage.menubar.json  native messaging manifest (template)
│   ├── install.sh          Setup script
│   └── requirements.txt    Python dependencies
├── usage_cache.json        Auto-created at runtime — last known usage data
└── README.md               This file
```
