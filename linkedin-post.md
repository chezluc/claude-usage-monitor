**I built a macOS menu bar app that shows my Claude usage in real-time.**

If you're a heavy Claude user, you know the feeling — mid-conversation, you hit a usage limit you didn't see coming.

So I built Claude Usage Monitor: a lightweight Swift menu bar app paired with a Chrome extension that scrapes your claude.ai/settings/usage page and displays it right in your menu bar.

What it shows:
- Progress bar + percentage in the menu bar
- Reset countdown timer
- Full breakdown: Current session, All models, Sonnet only
- Color-coded: blue → yellow → red as usage climbs

How it works:
- Chrome MV3 extension scrapes the usage page every minute
- POSTs the data to a local HTTP server (127.0.0.1 only)
- Native Swift/SwiftUI menu bar app displays it with animated bars

No API key needed. No data leaves your machine. Just your browser session + a local app.

Built with Claude Code in a single session. The irony of using Claude to build a tool that monitors Claude usage is not lost on me.

Open source: https://github.com/chezluc/claude-usage-monitor

#Claude #Anthropic #macOS #SwiftUI #DeveloperTools #AI #Productivity
