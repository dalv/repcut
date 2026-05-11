import type {
  MotionSignal,
  Pause,
  SegmentationParams,
  Suggestion,
} from './types';

export interface SegmentationResult {
  /** Smoothed energy signal — useful for charting. */
  smoothed: Float32Array;
  /** Threshold value (`median(smoothed) × thresholdMultiplier`). */
  threshold: number;
  /** Detected pauses. */
  pauses: Pause[];
  /** One suggestion per pause; boundaries at midpoints between adjacent pauses. */
  suggestions: Suggestion[];
}

/**
 * Pure, fast: re-run this whenever the user tweaks parameters. The
 * expensive `extractMotionSignal` step is cached upstream.
 */
export function segmentByPauses(
  signal: MotionSignal,
  params: SegmentationParams,
): SegmentationResult {
  const windowSamples = Math.max(1, Math.round(params.smoothingWindow * signal.fps));
  const smoothed = movingAverage(signal.energy, windowSamples);

  const threshold = median(smoothed) * params.thresholdMultiplier;

  const minSamples = Math.max(1, Math.round(params.minPauseDuration * signal.fps));
  const maxSamples = Math.max(minSamples, Math.round(params.maxPauseDuration * signal.fps));

  const pauses = findLowMotionRuns(smoothed, threshold, minSamples, maxSamples, signal.fps);
  const suggestions = pausesToSuggestions(
    pauses,
    smoothed,
    signal.fps,
    signal.duration,
    params.landingOffset,
    params.maxRepDuration,
  );

  return { smoothed, threshold, pauses, suggestions };
}

/** Symmetric moving average. Boundary samples are averaged over a smaller window. */
function movingAverage(input: Float32Array, windowSamples: number): Float32Array {
  const n = input.length;
  const out = new Float32Array(n);
  const half = Math.floor(windowSamples / 2);
  for (let i = 0; i < n; i++) {
    const lo = Math.max(0, i - half);
    const hi = Math.min(n - 1, i + half);
    let sum = 0;
    for (let j = lo; j <= hi; j++) sum += input[j];
    out[i] = sum / (hi - lo + 1);
  }
  return out;
}

function median(arr: Float32Array): number {
  if (arr.length === 0) return 0;
  const sorted = Array.from(arr).sort((a, b) => a - b);
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 0
    ? (sorted[mid - 1] + sorted[mid]) / 2
    : sorted[mid];
}

/** Find contiguous runs of samples below `threshold` whose length is in [minSamples, maxSamples]. */
function findLowMotionRuns(
  signal: Float32Array,
  threshold: number,
  minSamples: number,
  maxSamples: number,
  fps: number,
): Pause[] {
  const pauses: Pause[] = [];
  let runStart = -1;

  const closeRun = (endIndex: number) => {
    if (runStart < 0) return;
    const length = endIndex - runStart;
    if (length >= minSamples && length <= maxSamples) {
      pauses.push({
        start: runStart / fps,
        end: endIndex / fps,
      });
    }
    runStart = -1;
  };

  for (let i = 0; i < signal.length; i++) {
    if (signal[i] < threshold) {
      if (runStart < 0) runStart = i;
    } else {
      closeRun(i);
    }
  }
  closeRun(signal.length);

  return pauses;
}

/**
 * One suggestion per detected pause. A pause is the *setup hold* for a
 * rep (e.g. the bird position before a castaway) — it marks the START
 * of the trick, not its midpoint.
 *
 * Each rep's arc looks like:
 *   ░░░░░ pause(i) ░░░░░ ────/\──── peak ────\____  ...discussion...
 *   setup hold     execution   landing/recovery     (excluded)
 *   |─────────────── clip[i] ──────────────|
 *   start = pause(i).start
 *   end   = peak + landingOffset, capped by maxRepDuration and next pause
 *
 * Peak-based termination is the key: motion drops after the landing
 * but DOESN'T drop to pause-threshold during athlete discussion. So we
 * can't end clips at "next pause" — we'd swallow the talking. Ending a
 * fixed offset after the peak chops cleanly at the landing instead.
 */
function pausesToSuggestions(
  pauses: Pause[],
  smoothed: Float32Array,
  fps: number,
  duration: number,
  landingOffset: number,
  maxRepDuration: number,
): Suggestion[] {
  const suggestions: Suggestion[] = [];
  for (let i = 0; i < pauses.length; i++) {
    const pause = pauses[i];
    const next = pauses[i + 1];

    const start = pause.start;

    // Hard upper bound on the search window: the smaller of next pause's
    // start, or start + maxRepDuration, or end of video.
    const searchEnd = Math.min(
      next ? next.start : duration,
      start + maxRepDuration,
      duration,
    );

    // Find motion peak between the end of the setup hold and the search bound.
    const searchStart = pause.end;
    let peakTime = searchStart;
    let peakValue = -Infinity;
    const iStart = Math.max(0, Math.floor(searchStart * fps));
    const iEnd = Math.min(smoothed.length - 1, Math.floor(searchEnd * fps));
    for (let j = iStart; j <= iEnd; j++) {
      if (smoothed[j] > peakValue) {
        peakValue = smoothed[j];
        peakTime = j / fps;
      }
    }

    // End at peak + offset, clamped by all the upper bounds.
    let end = peakTime + landingOffset;
    if (next) end = Math.min(end, next.start);
    end = Math.min(end, start + maxRepDuration, duration);
    // Safety: never end before the setup pause is over.
    end = Math.max(end, pause.end);

    suggestions.push({
      id: `rep-${i}-${pause.start.toFixed(3)}`,
      startTime: start,
      endTime: end,
      pauseStart: pause.start,
      pauseEnd: pause.end,
      peakTime,
    });
  }
  return suggestions;
}
