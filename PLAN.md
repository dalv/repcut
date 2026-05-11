# Auto Rep Detection — Plan

Branch: `auto-rep-detection`

## Goal

When a user imports an acro training video containing multiple reps of the
same trick, the app should automatically segment it into one suggested clip
per rep. Each suggestion appears as a row with draggable start/end handles
so the user can fine-tune boundaries before exporting.

## Domain assumptions

1. Camera is approximately static (phone on a tripod or held still). Not
   action-cam, not panning.
2. The video shows acro training: 2 people (base + flyer) or 3 (with
   spotter). Multi-person frames are the norm, not an exception.
3. A "rep" is anchored by a **pause** — the base and flyer holding the
   trick still for ~1–3 seconds. Between reps the team resets, which is
   also a (longer) pause.

Assumption 3 is the load-bearing insight: pauses are the strongest and
cheapest signal to detect. We don't need to recognize the trick or track
people — we need to find quiet windows.

## Detection algorithm (V1)

Pure frame-difference motion energy. No ML, no Vision/pose, no audio.

1. Walk the video with `AVAssetReader` at ~5 fps, decoding small grayscale
   frames (e.g. 160×90).
2. Per frame, compute motion = sum-of-absolute-difference vs. previous
   frame. Yields a 1-D signal: motion energy over time.
3. Smooth with a moving average (~0.3 s window) to suppress single-frame
   noise.
4. Find **sustained low-motion windows**: spans where the smoothed signal
   stays below `median × k` (tunable, start k ≈ 0.2) for at least 0.5 s.
   Each window is a detected pause.
5. Suggested clip = interval from the start of pause *N* to the end of
   pause *N + 1*. This frames each rep as "transition in → held trick →
   transition out," and lets the user's handles narrow or widen as they
   prefer per clip.
6. Filter pauses that are unreasonably long (> ~8 s) — those are water
   breaks or conversation, not rep boundaries.

Estimated implementation: ~150 lines of Swift in a `RepDetector` class
returning `[RepSuggestion]` from an `AVAsset`. Runs on a background `Task`.

### What we explicitly skipped, and why

- **Pose detection (`VNDetectHumanBodyPoseRequest`).** Built into iOS, no
  download, supports multiple people. But Vision is trained on upright
  humans and gets unreliable on inversions (L-base, mid-flip, handstand).
  Pauses are the easy case for pose, but they're also the easy case for
  pixel-diff — so we don't gain enough to justify the cost. Reserved as a
  fallback if pixel-diff produces too many false positives in the real-
  world test.
- **Audio onset detection.** Useful for gymnastics landings (sharp
  transients). Acro pauses are visual and often near-silent. Not worth
  the integration cost in V1.
- **Action classifiers (Create ML).** Would require collecting training
  data per move type. Out of scope for V1.
- **Template matching against a user-selected example.** Powerful, but
  requires a 2-step UX ("tap one rep first, then we find the rest"). V1
  aims for one-shot magic; this is a strong V2 candidate.

## Data model

- `RepSuggestion`: `id`, `start: Double`, `end: Double`, `confidence: Double`, `originStrategy: enum`.
- Reuse existing `ClipMarker` for the confirmed-and-edited version. The
  flow is `RepSuggestion → user edits handles → ClipMarker → export`.
- `RepDetector`: async pipeline taking `AVAsset → [RepSuggestion]`.

Cache detections on disk keyed by source asset `localIdentifier`. Athletes
will reopen the same training video repeatedly; re-running detection each
time is wasted compute.

## UI/UX

A new screen between import and the existing editor:

- Header: "Found N reps · tap to refine" with global "Re-detect" and
  "Add manually" actions.
- Scrollable list, one row per suggestion. Each row shows:
  - A small filmstrip strip for that clip's range.
  - A dual-thumb range slider underneath (drag start, drag end).
  - Include/exclude checkbox.
- Tap a row → expands inline to a full-size player scrubbing only that
  range, with the same dual-thumb handles. No modal context switch.
- Bottom CTA: "Export N selected reps" → flows into existing
  `VideoExporter`.

Implementation notes:
- Range slider thumbs must snap to actual frame boundaries (use `CMTime`
  at the source's frame rate). Float-seconds drift looks bad.
- During drag, preview the boundary frame via `AVAssetImageGenerator`
  with a small cache.
- Existing `TimelineView` is the right fit for the expanded scrub view.
  The per-row strip is a new lightweight component.

## Performance budget

- Detection: at 5 fps and 160×90 grayscale, frame-diff is dominated by
  decode time, not compute. Roughly real-time-ish on an A14+ — a 60 s
  video takes ~6 s of detection work plus negligible peak-finding.
- Run on a background `Task`, show determinate progress, not a spinner.
- Cached results return in ms.

## Known failure modes

- **Camera shake / bump.** Frame-diff reads shake as motion and may miss
  a pause. Acceptable in V1 given A1.
- **Background people walking.** Would create false motion. Rare in acro
  training; not a V1 concern.
- **Slow continuous moves with no static hold.** Won't be detected. User
  adds manually.
- **Very long pause** (long water break, coach giving feedback). Filter
  by max-pause-duration (~8 s).
- **Multiple unrelated moves in one video** (e.g. acro warm-up then
  tricks). Boundaries between move types will look like a giant pause and
  produce one weird clip. Document as known limitation; user trims.

## Recommended first step

Before any UI: build the frame-diff detection as a one-day spike, run it
on 3–5 of your real acro training videos, overlay the detected pause
windows on the timeline (debug view). Validate boundaries align with reps
visually. If yes → build UI on top. If no → layer pose detection (count
low-motion frames only when Vision sees ≥ 2 people in stable poses) and
re-test before committing UI.

## Out of scope for this branch

- V2: template-matching from a user-marked example (Phase 3 in the
  original sketch).
- V2: audio onset assist.
- V2: per-move-type tuning.
- V2: "share to social" formatting.
