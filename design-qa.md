# Downleaf Native MVP — Design QA

final result: passed

## Comparison input

- Reference prototype: `prototype/qa/implementation-v6-lifecycle.jpg`
  - 1280 × 720
  - Dark editor state with long-form content and the right outline visible.
- Native implementation: `qa/native-final.jpg`
  - 1180 × 760
  - Native AppKit editor state with the right outline visible, captured during the final multi-document lifecycle verification.
- Combined comparison: `qa/visual-comparison.png`
  - 2540 × 848
  - Both source and implementation are contained without cropping in one inspection image.

## Visual comparison

- The native implementation preserves the reference's dark, low-noise writing surface, generous readable measure, subtle divider, and visually secondary right outline.
- The persistent left document/function area from the earlier prototype is intentionally absent. This follows the final requirement that low-frequency navigation and actions live in macOS menus rather than a permanent rail.
- The native toolbar is intentionally reduced to reading-mode selection and outline visibility. Formatting, file operations, search, settings, and recent files remain in standard menus or the command palette.
- The editor keeps Markdown source visible rather than imitating the prototype's rich-text presentation. Heading scale and syntax color still provide a clear reading hierarchy without changing the file model.
- Native window chrome, system spacing, controls, focus behavior, selection, and typography are used instead of recreating Mac controls in a web layer.
- The implementation screenshot contains a short lifecycle-test document rather than the reference's long fixture. Long-document outline density, nesting, scrolling, and jumping were verified separately in the live native app, so this content difference is not a product blocker.

## Findings and fixes

1. Outline arrow-key navigation originally activated the selected heading. It now only changes selection; Return performs the jump.
2. Reopening the outline could momentarily retain a dragged width. The saved/default width is now applied immediately and remains about 260 pt.
3. Dragging the divider below the minimum now collapses the outline, and double-clicking restores the default width.
4. The standard application quit path could show a generic multi-document summary. `⌘Q` now reviews dirty documents one at a time with the exact Save / Don't Save / Cancel flow; Cancel aborts the remaining quit sequence.
5. Account, profile, subscription, cloud, telemetry, and the left global function rail are absent from both UI and architecture.

## Interaction and runtime verification

- Existing `.md` file opened through the native Open flow and stayed bound to its path.
- Named document auto-save ON: edits moved from waiting state to saved state and changed the file on disk.
- Auto-save OFF: edits stayed dirty, did not write to disk, and triggered the close confirmation.
- Untitled document: no save panel on creation; local recovery snapshot was created after editing; first Save requested a location.
- Close confirmation: Save, Don't Save, and Cancel were each exercised; cancelling the Save panel also aborted closing.
- Multi-document quit: documents were reviewed sequentially; cancelling the second review kept the application and document open.
- Editor, split preview, and reading modes all rendered and switched without changing the source text.
- Outline click jump, current-section following, collapse/expand, keyboard navigation, focus shortcut, width drag, minimum-width collapse, double-click reset, visibility persistence, and reopen width were exercised.
- Narrow-window auto-collapse is implemented in the split-view resize path; direct window-edge dragging was the only interaction not reproducible through the available desktop automation.
- Command palette opened with `⌘K` and dismissed with Escape.
- Automated suite: 15 tests passed with 0 failures, covering encoding round trips, renderer safety, outline parsing, mode switching, layout stability, and right-anchored outline animation geometry.

## Remaining distribution work

- The local build uses an ad-hoc signature and is Apple Silicon (`arm64`). Developer ID signing, notarization, universal packaging, and DMG creation are release-distribution tasks, not MVP behavior blockers.
