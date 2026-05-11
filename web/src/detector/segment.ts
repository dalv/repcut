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
  const suggestions = pausesToSuggestions(pauses, signal.duration);

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
 * One suggestion per pause. Boundaries set to the midpoint between this
 * pause and its neighbors, so each clip is the trick-setup → pause →
 * trick-recovery for exactly one rep.
 */
function pausesToSuggestions(pauses: Pause[], duration: number): Suggestion[] {
  const suggestions: Suggestion[] = [];
  for (let i = 0; i < pauses.length; i++) {
    const pause = pauses[i];
    const prev = pauses[i - 1];
    const next = pauses[i + 1];
    const start = prev ? (prev.end + pause.start) / 2 : 0;
    const end = next ? (pause.end + next.start) / 2 : duration;
    suggestions.push({
      id: `rep-${i}-${pause.start.toFixed(3)}`,
      startTime: start,
      endTime: end,
      pauseStart: pause.start,
      pauseEnd: pause.end,
    });
  }
  return suggestions;
}
