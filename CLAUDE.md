# Glimpse — Claude Code Instructions

## Non-regression
Before implementing any change, review all existing features (session monitoring, character rendering, click-to-activate, menu bar, multi-monitor, power management, keyboard shortcuts, Cursor support). Verify that your changes do not break or degrade any of them.
Ruthlessly iterate on these lessons until mistake rate drops.
Review lessons at session start for relevant project.

## Performance
Glimpse must stay invisible on the system: low CPU, low RAM, minimal GPU. If a proposed approach risks increasing resource usage (heavy polling, large allocations, expensive per-frame work, synchronous I/O on the main thread), stop and ask: **"Are you sure? This may reduce the performance of the app."** before proceeding.

## Plan Mode
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions).
- If something goes sideways, STOP and re-plan immediately — don't keep pushing.
- Use plan mode for verification steps, not just building.
- Write detailed specs upfront to reduce ambiguity.

## Task Management
1. **Plan First**: Write plan to `tasks/todo-XXXXX.md` with checkable items. replace XXXXX with word summarizing the task
2. **Verify Plan**: Check in before starting implementation.
3. **Track Progress**: Mark items complete as you go.
4. **Explain Changes**: High-level summary at each step.
5. **Document Results**: Add review section to `tasks/todo.md`.
6. **Capture Lessons**: After any correction from the user, add a bullet to the "Auto-created Lessons" section at the bottom of this file.
7. **delete the todo**: once finished implementing, ask the user if you can delete the tasks/todo-XXXXX.md to leave the codebase clean of it

## Testing
- Run `xcodebuild test -project Glimpse.xcodeproj -scheme Glimpse -destination 'platform=macOS' -only-testing:GlimpseTests` and confirm all tests pass before considering any feature complete.
- When implementing a big feature, add at least one new test covering its happy path before marking the work as done.
- Tests live in `GlimpseTests/`. `SessionMonitorTests.swift` covers the session pipeline, `CharacterGeneratorTests.swift` covers character generation.

## Verification Before Done
- Never mark a task complete without proving it works.
- Diff behavior between main and your changes when relevant.
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness.

## Subagent Strategy
- Use subagents for research and codebase exploration — keep the main context window clean.
- One task per subagent for focused execution.

## Auto-created Lessons
<!-- Add lessons here after user corrections. One bullet per lesson. -->
