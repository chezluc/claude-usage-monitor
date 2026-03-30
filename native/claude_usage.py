#!/usr/bin/env python3
"""
claude_usage.py — macOS menu bar app for Claude usage monitoring.

Acts as a Chrome native messaging host (reads from stdin / writes to stdout
using the 4-byte little-endian length-prefix protocol) AND as a rumps menu
bar app simultaneously. The native messaging loop runs in a background thread.

Also polls ~/Dropbox/claude-menu-bar-app/usage_cache.json every 60 s as a
fallback in case the Chrome side goes quiet.
"""

import json
import os
import struct
import sys
import threading
import time
from datetime import datetime, timezone
from pathlib import Path

import rumps

# ── Constants ──────────────────────────────────────────────────────────────────
CACHE_FILE = Path.home() / "Dropbox" / "claude-menu-bar-app" / "usage_cache.json"
POLL_INTERVAL = 60          # seconds between cache-file polls
CLAUDE_USAGE_URL = "https://claude.ai/settings/usage"


# ── Helpers ───────────────────────────────────────────────────────────────────

def read_cache() -> dict | None:
    try:
        if CACHE_FILE.exists():
            with open(CACHE_FILE, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return None


def write_cache(data: dict) -> None:
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CACHE_FILE, "w") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"[cache write error] {e}", file=sys.stderr)


def format_reset_date(raw: str) -> str:
    """Try to parse ISO timestamps into a friendly string like 'Jun 1'."""
    if not raw:
        return "Unknown"
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        return dt.strftime("%b %-d")
    except Exception:
        return raw


def format_last_updated(iso: str) -> str:
    if not iso:
        return "Never"
    try:
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        local = dt.astimezone()
        return local.strftime("%-I:%M %p")
    except Exception:
        return iso


def make_bar(percent: float, width: int = 10) -> str:
    """Return a unicode progress bar, e.g. '████████░░' for 80%."""
    filled = round(max(0, min(100, percent)) / 100 * width)
    empty = width - filled
    return "\u2588" * filled + "\u2591" * empty


def battery_title(percent: float | None) -> str:
    """Return a battery-style title string like '▐████████░░▌ 87%'."""
    if percent is None:
        return "\u258c\u2591" * 10 + "\u258c \u2591" * 0 + "\u258c\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u258c ?"
    bar = make_bar(percent, width=10)
    pct_str = f"{int(round(percent))}%"
    title = f"\u258c{bar}\u258c {pct_str}"
    if percent >= 90:
        title = f"\u26a0 {title}"
    return title


# ── Native messaging protocol ─────────────────────────────────────────────────

def _read_native_message() -> dict | None:
    """Read one message from stdin using Chrome native messaging protocol."""
    raw_length = sys.stdin.buffer.read(4)
    if len(raw_length) < 4:
        return None
    msg_length = struct.unpack("<I", raw_length)[0]
    raw_msg = sys.stdin.buffer.read(msg_length)
    if not raw_msg:
        return None
    return json.loads(raw_msg.decode("utf-8"))


def _send_native_message(data: dict) -> None:
    """Send one message to stdout using Chrome native messaging protocol."""
    msg = json.dumps(data).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(msg)))
    sys.stdout.buffer.write(msg)
    sys.stdout.buffer.flush()


# ── Menu bar app ──────────────────────────────────────────────────────────────

# Sentinel object used as a separator placeholder in menu rebuild
_SEP = object()


class ClaudeUsageApp(rumps.App):
    def __init__(self):
        # Start with "no data" battery bar
        super().__init__(
            name="Claude Usage Monitor",
            title="\u258c\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u2591\u258c ?",
            quit_button=None,   # we add our own so we control placement
        )

        self._data: dict | None = None
        self._lock = threading.Lock()

        # ── Static menu items ──────────────────────────────────────────────────
        self.refresh_item = rumps.MenuItem(
            "\u21bb  Refresh Now", callback=self.on_refresh
        )

        # Settings submenu (interval selector)
        self.settings_menu = rumps.MenuItem("\u2699  Settings \u25b8")
        intervals = [
            ("1 minute",   1),
            ("5 minutes",  5),
            ("15 minutes", 15),
            ("30 minutes", 30),
        ]
        self._interval_items: dict[int, rumps.MenuItem] = {}
        for label, minutes in intervals:
            item = rumps.MenuItem(label, callback=self._make_interval_callback(minutes))
            self._interval_items[minutes] = item
            self.settings_menu.add(item)

        self.open_item = rumps.MenuItem(
            "\u2197  Open Usage Page", callback=self.on_open
        )
        self.quit_item = rumps.MenuItem("Quit", callback=self.on_quit)

        # Bootstrap with placeholders; _rebuild_menu() will fill real content
        self._usage_items: list[rumps.MenuItem] = []
        self._updated_item: rumps.MenuItem | None = None

        self._build_empty_menu()

        # Load any cached data immediately
        cached = read_cache()
        if cached:
            self._apply_data(cached, notify=False)

        # Start background threads
        self._start_native_thread()
        self._start_poll_thread()

    # ── Menu building ──────────────────────────────────────────────────────────

    def _build_empty_menu(self) -> None:
        placeholder = rumps.MenuItem("No data yet — open claude.ai/settings/usage")
        updated = rumps.MenuItem("  Updated —")
        self._usage_items = [placeholder]
        self._updated_item = updated

        self.menu.clear()
        for item in [
            placeholder,
            updated,
            None,
            self.refresh_item,
            self.settings_menu,
            None,
            self.open_item,
            None,
            self.quit_item,
        ]:
            self.menu.add(item)

    def _rebuild_menu(self, plans: list[dict], last_iso: str) -> None:
        """Rebuild the dynamic portion of the menu from a list of plan dicts."""
        usage_items: list[rumps.MenuItem] = []

        for plan in plans:
            name     = plan.get("name", "Messages")
            used     = plan.get("used", 0)
            total    = plan.get("total", 0)
            pct      = plan.get("percent", 0)
            reset_raw = plan.get("resetDate", "")

            bar      = make_bar(pct)
            reset_str = f"Resets {format_reset_date(reset_raw)}" if reset_raw else ""

            # Line 1: "Claude Pro  ·  87% used"  (or just the plan name)
            line1 = f"{name}  \u00b7  {pct}% used"
            # Line 2: "████████░░  45 / 52 messages  ·  Resets Jun 1"
            count_str = f"{used:,} / {total:,}"
            line2_parts = [f"{bar}  {count_str}"]
            if reset_str:
                line2_parts.append(reset_str)
            line2 = "  \u00b7  ".join(line2_parts)

            # Two-line display as a single MenuItem (newlines render in menu)
            text = f"{line1}\n{line2}"
            item = rumps.MenuItem(text)   # no callback = non-clickable
            usage_items.append(item)

        updated_text = f"  Updated {format_last_updated(last_iso)}" if last_iso else "  Updated —"
        updated_item = rumps.MenuItem(updated_text)

        self._usage_items = usage_items
        self._updated_item = updated_item

        self.menu.clear()
        for item in usage_items:
            self.menu.add(item)
        self.menu.add(updated_item)
        self.menu.add(None)
        self.menu.add(self.refresh_item)
        self.menu.add(self.settings_menu)
        self.menu.add(None)
        self.menu.add(self.open_item)
        self.menu.add(None)
        self.menu.add(self.quit_item)

    # ── Data application ──────────────────────────────────────────────────────

    def _apply_data(self, data: dict, notify: bool = True) -> None:
        with self._lock:
            self._data = data

        error     = data.get("error", "")
        last_iso  = data.get("lastUpdated", "")

        # Build plans list — prefer explicit plans array
        raw_plans = data.get("plans")
        if raw_plans and isinstance(raw_plans, list) and len(raw_plans) > 0:
            plans = raw_plans
        else:
            # Synthesise a single plan from flat fields
            used    = data.get("used", 0)
            total   = data.get("total", 0)
            percent = data.get("percent", 0)
            reset   = data.get("resetDate", "")
            if total or used:
                plans = [{"name": "Messages", "used": used, "total": total,
                          "percent": percent, "resetDate": reset}]
            else:
                plans = []

        # Determine overall percent for menu bar title
        if plans:
            # Use first plan's percent (or weighted average if wanted)
            overall_pct = plans[0].get("percent", 0)
        elif error:
            overall_pct = None
        else:
            overall_pct = None

        # Update title
        self.title = battery_title(overall_pct)

        # Rebuild menu
        if plans:
            self._rebuild_menu(plans, last_iso)
        else:
            self._build_empty_menu()

    # ── Native messaging thread ───────────────────────────────────────────────

    def _start_native_thread(self) -> None:
        t = threading.Thread(target=self._native_loop, daemon=True, name="native-msg")
        t.start()

    def _native_loop(self) -> None:
        """Blocking loop that reads messages from Chrome via stdin."""
        while True:
            try:
                msg = _read_native_message()
                if msg is None:
                    # stdin closed — Chrome disconnected; keep running for cache polling
                    time.sleep(5)
                    continue
                write_cache(msg)
                rumps.App._call_or_reschedule(lambda m=msg: self._apply_data(m))
            except Exception as e:
                print(f"[native loop error] {e}", file=sys.stderr)
                time.sleep(2)

    # ── Cache-polling fallback thread ─────────────────────────────────────────

    def _start_poll_thread(self) -> None:
        t = threading.Thread(target=self._poll_loop, daemon=True, name="cache-poll")
        t.start()

    def _poll_loop(self) -> None:
        last_mtime = None
        while True:
            try:
                if CACHE_FILE.exists():
                    mtime = CACHE_FILE.stat().st_mtime
                    if mtime != last_mtime:
                        last_mtime = mtime
                        data = read_cache()
                        if data:
                            rumps.App._call_or_reschedule(
                                lambda d=data: self._apply_data(d, notify=False)
                            )
            except Exception as e:
                print(f"[poll error] {e}", file=sys.stderr)
            time.sleep(POLL_INTERVAL)

    # ── Menu callbacks ────────────────────────────────────────────────────────

    def on_refresh(self, _sender):
        """Re-read cache file immediately."""
        data = read_cache()
        if data:
            self._apply_data(data)
        else:
            rumps.notification(
                "Claude Usage Monitor",
                "No data",
                "Keep a claude.ai/settings/usage tab open in Chrome.",
            )

    def on_open(self, _sender):
        import subprocess
        subprocess.Popen(["open", CLAUDE_USAGE_URL])

    def on_quit(self, _sender):
        rumps.quit_application()

    def _make_interval_callback(self, minutes: int):
        def callback(_sender):
            for m, item in self._interval_items.items():
                item.state = (m == minutes)
            rumps.notification(
                "Claude Usage Monitor",
                "Refresh interval updated",
                f"Refresh interval set to {minutes} minute(s).\n"
                "Note: interval changes take effect in the Chrome extension settings.",
            )
        return callback


# ── Entry point ───────────────────────────────────────────────────────────────

if __name__ == "__main__":
    app = ClaudeUsageApp()
    app.run()
