import type {
  Match,
  MotionSignal,
  TemplateParams,
  TemplateRange,
} from './types';

export interface TemplateResult {
  /** Smoothed signal used for matching — useful for charting. */
  smoothed: Float32Array;
  /** Correlation score at every valid template offset. */
  correlation: Float32Array;
  /** Number of samples in the template window. */
  templateLength: number;
  /** Accepted matches after NMS, sorted by time. */
  matches: Match[];
}

/**
 * Slide a z-score normalized copy of the template across the signal and
 * compute Pearson correlation at each offset. Accept local maxima above
 * a correlation threshold, then non-max suppress to keep one match per
 * rep.
 *
 * Why z-score normalize each window (not just the template): reps in the
 * same video can differ in absolute motion magnitude — closer to camera,
 * brighter lighting, more or fewer people in frame. Normalizing per
 * window matches on *shape* alone, which is what the real-world chart
 * showed was actually consistent across reps.
 */
export function segmentByTemplate(
  signal: MotionSignal,
  range: TemplateRange,
  params: TemplateParams,
): TemplateResult {
  const smoothed = smoothSignal(signal, params.smoothingWindow);

  const startIdx = clampIdx(Math.round(range.startTime * signal.fps), smoothed.length);
  const endIdx = clampIdx(Math.round(range.endTime * signal.fps), smoothed.length);
  const templateLength = Math.max(0, endIdx - startIdx);

  // Empty correlation array if template is degenerate.
  if (templateLength < 2 || smoothed.length < templateLength) {
    return {
      smoothed,
      correlation: new Float32Array(0),
      templateLength,
      matches: [],
    };
  }

  const rawTemplate = smoothed.subarray(startIdx, endIdx);
  const template = zScoreNormalize(rawTemplate);

  // Slide template across the smoothed signal.
  const maxOffset = smoothed.length - templateLength;
  const correlation = new Float32Array(maxOffset + 1);
  const windowBuf = new Float32Array(templateLength);

  for (let offset = 0; offset <= maxOffset; offset++) {
    // Copy out the window once and z-score normalize it.
    for (let i = 0; i < templateLength; i++) windowBuf[i] = smoothed[offset + i];
    const normalizedWindow = zScoreNormalize(windowBuf);
    correlation[offset] = pearsonCorrelation(template, normalizedWindow);
  }

  const nmsWindow = Math.max(
    1,
    Math.round(templateLength * params.nmsWindowMultiplier),
  );
  const matches = collectMatches(
    correlation,
    params.minCorrelation,
    nmsWindow,
    templateLength,
    startIdx,
    signal.fps,
  );

  return { smoothed, correlation, templateLength, matches };
}

// ---------------------------------------------------------------------------
// Math primitives. Pure functions — translate line-for-line to Swift later.
// ---------------------------------------------------------------------------

function smoothSignal(signal: MotionSignal, windowSeconds: number): Float32Array {
  const w = Math.max(1, Math.round(windowSeconds * signal.fps));
  return movingAverage(signal.energy, w);
}

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

/**
 * Subtract mean, divide by population std. Returns a new array. If the
 * input is flat (std ≈ 0), returns zeros — those windows correlate at 0
 * with anything non-flat, which is what we want.
 */
function zScoreNormalize(arr: Float32Array): Float32Array {
  const n = arr.length;
  const out = new Float32Array(n);
  if (n === 0) return out;

  let sum = 0;
  for (let i = 0; i < n; i++) sum += arr[i];
  const mean = sum / n;

  let sumSq = 0;
  for (let i = 0; i < n; i++) {
    const d = arr[i] - mean;
    sumSq += d * d;
  }
  const std = Math.sqrt(sumSq / n);
  if (std < 1e-9) return out;

  const inv = 1 / std;
  for (let i = 0; i < n; i++) out[i] = (arr[i] - mean) * inv;
  return out;
}

/**
 * Pearson correlation for already z-score normalized vectors of equal
 * length. Reduces to mean(a · b).
 */
function pearsonCorrelation(a: Float32Array, b: Float32Array): number {
  const n = a.length;
  if (n === 0) return 0;
  let sum = 0;
  for (let i = 0; i < n; i++) sum += a[i] * b[i];
  return sum / n;
}

/**
 * Non-max suppression over the 1-D correlation array. Take the highest-
 * scoring offset, accept it, then suppress everything within `nmsWindow`
 * samples on either side. Repeat until no candidates remain above the
 * threshold.
 *
 * The user's marked-template offset will naturally win (correlation = 1)
 * and so be the first accepted match.
 */
function collectMatches(
  correlation: Float32Array,
  threshold: number,
  nmsWindow: number,
  templateLength: number,
  templateOffset: number,
  fps: number,
): Match[] {
  type C = { idx: number; score: number };
  const candidates: C[] = [];
  for (let i = 0; i < correlation.length; i++) {
    if (correlation[i] >= threshold) {
      candidates.push({ idx: i, score: correlation[i] });
    }
  }
  candidates.sort((a, b) => b.score - a.score);

  const accepted: C[] = [];
  for (const c of candidates) {
    let conflict = false;
    for (const a of accepted) {
      if (Math.abs(c.idx - a.idx) < nmsWindow) {
        conflict = true;
        break;
      }
    }
    if (!conflict) accepted.push(c);
  }

  accepted.sort((a, b) => a.idx - b.idx);

  return accepted.map((m, i) => ({
    id: `match-${i}-${m.idx}`,
    startTime: m.idx / fps,
    endTime: (m.idx + templateLength) / fps,
    correlation: m.score,
    isTemplate: m.idx === templateOffset,
  }));
}

function clampIdx(idx: number, length: number): number {
  if (idx < 0) return 0;
  if (idx > length) return length;
  return idx;
}
