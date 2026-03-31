# Glimpse — Claude Code Instructions

## Non-regression
Before implementing any change, review all existing features (session monitoring, character rendering, click-to-activate, menu bar, multi-monitor, power management, keyboard shortcuts, Cursor support). Verify that your changes do not break or degrade any of them.

## Performance
Glimpse must stay invisible on the system: low CPU, low RAM, minimal GPU. If a proposed approach risks increasing resource usage (heavy polling, large allocations, expensive per-frame work, synchronous I/O on the main thread), stop and ask: **"Are you sure? This may reduce the performance of the app."** before proceeding.
