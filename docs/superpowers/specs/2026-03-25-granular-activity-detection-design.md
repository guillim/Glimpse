# Granular Agent Activity Detection

## Summary

Expand agent activity detection from 4 coarse states to 8 granular states by parsing tool_use blocks from JSONL session logs. Increase polling from 5s to 2s for more responsive visual feedback.

## New Activity States

| Activity | Tool signal | Emoji |
|----------|-----------|-------|
| `reading` | `Read`, `Glob`, `Grep` | 📖 |
| `writing` | `Edit`, `Write` | ✏️ |
| `running` | `Bash` | ⚡ |
| `thinking` | text block, no tool_use | 🧠 |
| `spawning` | `Agent` | 🐣 |
| `searching` | `WebSearch`, `WebFetch` | 🔍 |
| `waiting` | `end_turn` + age > 30s | ❓ |
| `sleeping` | file age > 60s | 💤 |

## Classification Priority

Walk JSONL lines backwards. Last tool_use block determines state:

1. `Bash` → `.running`
2. `Agent` → `.spawning`
3. `WebSearch` / `WebFetch` → `.searching`
4. `Edit` / `Write` → `.writing`
5. `Read` / `Glob` / `Grep` → `.reading`
6. text block only → `.thinking`
7. `end_turn` + age > 30s → `.waiting`
8. Fallback → `.sleeping`

## Polling Interval

2 seconds (down from 5s). Tail-reads ~32KB per file, negligible overhead.

## Files Changed

- `Glimpse/SessionMonitor.swift` — new Activity cases, updated classification, 2s timer
- `Glimpse/CharacterNode.swift` — new emoji mapping
