# Prototype Instructions

Run the local server yourself and open the preview in the browser available to this environment. Do not give the user server-start instructions when you can run it.

Before making substantial visual changes, use the Product Design plugin's `get-context` skill when the visual source is unclear or no longer matches the current goal. When the user gives durable prototype-specific design feedback, preferences, or decisions, record them in `AGENTS.md`.

When implementing from a selected generated mock, treat that image as the source of truth for layout, component anatomy, density, spacing, color, typography, visible content, and hierarchy.

Build app UI in `src/`. Keep `.openai/hosting.json`, `worker/index.js`, `scripts/prepare-sites-build.mjs`, and `tests/sites-worker.test.mjs` intact so the same local prototype can be handed to Sites. Before a Sites handoff, run `npm run build` and `npm run test:sites`; the build must leave `dist/client/index.html`, `dist/server/index.js`, and `dist/.openai/hosting.json`.

## Durable product decisions

- Keep the document outline on the right side, visually dense and secondary to the editor.
- The outline divider must support live horizontal resizing, keyboard resizing, double-click reset, local width persistence, and collapse when dragged below its minimum width.
- Preserve the dark, compact macOS desktop-editor proportions from the selected CleanShot reference.
- Do not add a persistent global icon rail. The document list is the leftmost in-window region, and low-frequency actions belong in the native macOS menu bar, keyboard shortcuts, or a single quiet overflow menu in the web prototype.
- Do not add an account system or reserve UI for one in the current product scope. No avatar, sign-in, profile, subscription, account-status, or cloud-sync surfaces; local file state may appear only when it directly helps the editing task.
- Opening an existing `.md` through Finder, drag-and-drop, `⌘O`, or a path binds the document to that path immediately and uses the normal save flow.
- `⌘N` and “新建文稿” create an unnamed recovery-buffer document without showing a save-location prompt. First explicit save, `⌘W`, or app quit is when the user chooses the final filename and location.
- Auto-save is enabled by default and persisted locally. It saves path-backed documents in place after a short pause; for unnamed documents it only updates recovery state and never silently chooses a final path.
- Closing a buffered document, or a modified path-backed document while auto-save is off, uses the Mac-style “保存 / 不保存 / 取消” decision flow.
- App quit processes every document that still needs a decision in sequence; choosing “取消” at any point aborts the quit operation.
