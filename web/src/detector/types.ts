/**
 * Motion signal extracted from a video — the expensive artifact. Both V1
 * (pause segmentation) and a future V3 (template matching from a user-
 * marked example) would consume this same signal.
 */
export interface MotionSignal {
  /** Sampling rate of `energy`, in Hz. */
  fps: number;
  /** Video duration in seconds (as reported by HTMLVideoElement). */
  duration: number;
  /** Per-sample mean absolute pixel difference vs. previous sample. */
  energy: Float32Array;
}

/** A detected low-motion window. */
export interface Pause {
  start: number; // seconds
  end: number;   // seconds
}

/** A suggested rep clip. */
export interface Suggestion {
  /** Stable id for React keys / list reordering. */
  id: string;
  /** Clip boundaries the user would export. */
  startTime: number;
  endTime: number;
  /** Pause (= setup hold) that this rep is anchored on. */
  pauseStart: number;
  pauseEnd: number;
  /** Time of the motion peak — the trick execution moment. */
  peakTime: number;
}

/** Tunable parameters for V1 pause-based segmentation. */
export interface SegmentationParams {
  /** Pauses are samples below `median(smoothed) × thresholdMultiplier`. */
  thresholdMultiplier: number;
  /** Reject runs shorter than this. Filters out brief dips. */
  minPauseDuration: number; // seconds
  /** Reject runs longer than this. Filters out water breaks / breaks. */
  maxPauseDuration: number; // seconds
  /** Moving-average window over the raw energy signal. */
  smoothingWindow: number;  // seconds
  /**
   * Seconds to keep AFTER the motion peak. The peak is the trick
   * execution; this offset captures the landing/recovery without
   * including post-rep discussion.
   */
  landingOffset: number;    // seconds
  /** Hard upper limit on a single rep's duration (setup → landing). */
  maxRepDuration: number;   // seconds
}

export const DEFAULT_PARAMS: SegmentationParams = {
  thresholdMultiplier: 0.2,
  minPauseDuration: 0.5,
  maxPauseDuration: 8,
  smoothingWindow: 0.3,
  landingOffset: 0.8,
  maxRepDuration: 6,
};

// ============================================================================
// Template-matching mode (V1 successor — finds reps by shape similarity to a
// user-marked example, after pause-detection failed on real footage where the
// signal never drops to a true pause threshold).
// ============================================================================

/** The user's marked range that anchors template matching. */
export interface TemplateRange {
  startTime: number;
  endTime: number;
}

/** A single match found by template matching. */
export interface Match {
  id: string;
  startTime: number;
  endTime: number;
  /** Pearson correlation against the (z-score normalized) template. */
  correlation: number;
  /** True if this match corresponds to the user's original marked range. */
  isTemplate: boolean;
}

/** Tunable parameters for template-matching mode. */
export interface TemplateParams {
  /** Minimum Pearson correlation to accept a match. */
  minCorrelation: number;        // 0–1
  /** Non-max suppression: minimum gap between matches as a multiple of template length. */
  nmsWindowMultiplier: number;
  /** Smoothing applied to the signal before correlation. */
  smoothingWindow: number;       // seconds
}

export const DEFAULT_TEMPLATE_PARAMS: TemplateParams = {
  minCorrelation: 0.4,
  nmsWindowMultiplier: 1.5,
  smoothingWindow: 0.3,
};
