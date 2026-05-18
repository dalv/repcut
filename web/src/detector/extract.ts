import type { MotionSignal } from './types';

export interface ExtractOptions {
  /** How often to sample. 5 fps is plenty for finding 0.5s+ pauses. */
  samplingFps?: number;
  /** Downsampled frame dimensions for the diff. Tiny on purpose. */
  downsampleWidth?: number;
  downsampleHeight?: number;
  onProgress?: (current: number, total: number) => void;
  /** Abort the extraction (e.g. user cancels). */
  signal?: AbortSignal;
}

const DEFAULTS: Required<Omit<ExtractOptions, 'onProgress' | 'signal'>> = {
  samplingFps: 5,
  downsampleWidth: 160,
  downsampleHeight: 90,
};

/**
 * Walk the video by seeking, decode each sample at low resolution, and
 * compute frame-to-frame mean-absolute-difference. Produces the 1-D
 * motion-energy signal we'll segment on.
 *
 * Why seeking (and not requestVideoFrameCallback + playback): seeking is
 * universally supported, doesn't depend on real-time playback, and lets us
 * pick a fixed sampling rate independent of the source frame rate. Slow
 * (~30ms per seek), but acceptable for a validation prototype on videos
 * of typical training-session length.
 */
export async function extractMotionSignal(
  file: File,
  options: ExtractOptions = {},
): Promise<MotionSignal> {
  const opts = { ...DEFAULTS, ...options };

  const url = URL.createObjectURL(file);
  const video = document.createElement('video');
  video.src = url;
  video.muted = true;
  video.preload = 'auto';
  video.playsInline = true;
  // Some browsers refuse to load without being in DOM. Hide it.
  video.style.position = 'fixed';
  video.style.top = '-9999px';
  video.style.left = '-9999px';
  video.style.width = '1px';
  video.style.height = '1px';
  document.body.appendChild(video);

  try {
    await waitForMetadata(video);
    const duration = video.duration;
    if (!isFinite(duration) || duration <= 0) {
      throw new Error('Could not determine video duration.');
    }

    const totalSamples = Math.max(2, Math.floor(duration * opts.samplingFps));
    const energy = new Float32Array(totalSamples);

    const canvas = document.createElement('canvas');
    canvas.width = opts.downsampleWidth;
    canvas.height = opts.downsampleHeight;
    const ctx = canvas.getContext('2d', { willReadFrequently: true });
    if (!ctx) throw new Error('Could not acquire 2D canvas context.');

    let previousGray: Uint8ClampedArray | null = null;
    const pixelCount = opts.downsampleWidth * opts.downsampleHeight;

    for (let i = 0; i < totalSamples; i++) {
      if (options.signal?.aborted) {
        throw new DOMException('Extraction aborted', 'AbortError');
      }

      const time = (i / opts.samplingFps);
      await seekTo(video, Math.min(time, duration - 0.001));

      ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
      const { data } = ctx.getImageData(0, 0, canvas.width, canvas.height);
      const gray = toGrayscale(data, pixelCount);

      if (previousGray) {
        energy[i] = meanAbsoluteDifference(gray, previousGray);
      } else {
        energy[i] = 0;
      }
      previousGray = gray;

      options.onProgress?.(i + 1, totalSamples);
    }

    return {
      fps: opts.samplingFps,
      duration,
      energy,
    };
  } finally {
    video.removeAttribute('src');
    video.load();
    video.remove();
    URL.revokeObjectURL(url);
  }
}

function waitForMetadata(video: HTMLVideoElement): Promise<void> {
  return new Promise((resolve, reject) => {
    if (video.readyState >= 1 && isFinite(video.duration) && video.duration > 0) {
      resolve();
      return;
    }
    const onLoaded = () => {
      cleanup();
      resolve();
    };
    const onError = () => {
      cleanup();
      reject(new Error('Failed to load video metadata.'));
    };
    const cleanup = () => {
      video.removeEventListener('loadedmetadata', onLoaded);
      video.removeEventListener('error', onError);
    };
    video.addEventListener('loadedmetadata', onLoaded);
    video.addEventListener('error', onError);
  });
}

/**
 * Seek to `time` and resolve when the frame at that time is decoded and
 * ready to be drawn. Falls back to a timeout in case `seeked` doesn't
 * fire (some browsers silently swallow seeks to current time).
 */
function seekTo(video: HTMLVideoElement, time: number): Promise<void> {
  return new Promise((resolve) => {
    // If we're already at the right time and have data, skip waiting.
    const eps = 1e-3;
    if (Math.abs(video.currentTime - time) < eps && video.readyState >= 2) {
      resolve();
      return;
    }
    let done = false;
    const finish = () => {
      if (done) return;
      done = true;
      video.removeEventListener('seeked', finish);
      resolve();
    };
    video.addEventListener('seeked', finish);
    video.currentTime = time;
    // Belt + suspenders: don't deadlock if the browser eats the event.
    setTimeout(finish, 500);
  });
}

function toGrayscale(rgba: Uint8ClampedArray, pixelCount: number): Uint8ClampedArray {
  const out = new Uint8ClampedArray(pixelCount);
  for (let i = 0; i < pixelCount; i++) {
    const r = rgba[i * 4];
    const g = rgba[i * 4 + 1];
    const b = rgba[i * 4 + 2];
    // Rec. 601 luma coefficients.
    out[i] = (r * 299 + g * 587 + b * 114) >> 10; // ~ /1000, fast
  }
  return out;
}

function meanAbsoluteDifference(a: Uint8ClampedArray, b: Uint8ClampedArray): number {
  let sum = 0;
  const n = a.length;
  for (let i = 0; i < n; i++) {
    const d = a[i] - b[i];
    sum += d < 0 ? -d : d;
  }
  return sum / n;
}
