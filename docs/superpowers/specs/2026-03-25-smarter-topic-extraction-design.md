# Smarter Topic Extraction for Agent Activity Label

**Date:** 2026-03-25
**Status:** Approved

## Problem

The current `extractTopic` method in `SessionMonitor.swift` naively takes the first 4 words of the user's most recent message. This produces unhelpful labels like "i want to improve" instead of meaningful summaries like "improve label".

## Solution

Replace `extractTopic` with a keyword-based extractor that finds the action verb and its object, falling back to meaningful-word extraction when no verb is found.

## Algorithm

### Stop Words (shared across both paths)

Articles and prepositions to skip when collecting meaningful words:

```
the, a, an, in, to, for, from, with, on, at, of, by, is, are, was, it, that, this
```

### Steps

1. Take first line of user message, trim whitespace
2. Strip known filler prefixes (case-insensitive). Apply iteratively until no prefix matches. Match longest prefix first to avoid partial matches (e.g., "i want to" before "i"):
   - "i want to", "i'd like to", "i need to", "can you", "could you", "would you", "please", "let's", "hey", "so", "ok", "okay"
3. Lowercase the result, split into words
4. Scan for the first known action verb from the curated set (see below)
5. **If verb found:** collect the verb + up to 3 non-stop-words after it
6. **If no verb found:** drop all stop words, take the first 4 remaining words
7. Cap at 30 characters total (including "..." suffix). If the joined result exceeds 30 chars, truncate to the last complete word that fits within 27 chars and append "..."

## Action Verb Set

```
fix, add, improve, refactor, update, remove, create, implement, build, change,
move, rename, replace, delete, write, make, set, configure, enable, disable,
debug, test, check, find, search, explore, review, clean, optimize, merge,
deploy, push, pull, revert, undo, upgrade, install, setup, migrate, convert,
extract, split, combine, integrate, connect, disconnect, handle, support,
allow, prevent, show, hide, toggle, resize, format, sort, filter, validate,
parse, serialize, decode, encode, fetch, send, upload, download, run, start,
stop, restart, launch, open, close, log, monitor, track, watch
```

## Examples

| Input | Output |
|---|---|
| "i want to improve the label indicating what the agent is working on" | "improve label" |
| "can you fix the bug in SessionMonitor" | "fix bug SessionMonitor" |
| "add a countdown timer to the scene" | "add countdown timer" |
| "please refactor extractTopic" | "refactor extractTopic" |
| "the label is broken when idle" | "label broken when idle" |
| "SessionMonitor.swift has a memory leak" | "SessionMonitor.swift has mem..." |
| "/commit" | "/commit" |
| "please can you fix the tests" | "fix tests" |

## Scope

- **Only file changed:** `Glimpse/SessionMonitor.swift` — the `extractTopic(from:)` static method
- **No UI changes:** `CharacterNode` already displays whatever `extractTopic` returns
- **No new dependencies:** Pure Swift string manipulation

## Edge Cases

- Empty or whitespace-only messages → return ""
- Slash commands (e.g., "/commit") → returned as-is (no verb match, no filler to strip)
- Messages that are only filler ("please", "ok") → return "" after stripping
- Very long words (e.g., long file paths) → truncated at 30 char cap with "..."
- Messages starting with code fences (```) → treated as normal text; known limitation, produces unhelpful output on rare code-only messages
- Character counting uses Swift's `String.count` (grapheme clusters), consistent with existing code
