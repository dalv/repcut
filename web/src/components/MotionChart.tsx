import { useMemo } from 'react';
import type { Pause, Suggestion } from '../detector/types';

interface Props {
  smoothed: Float32Array;
  rawEnergy: Float32Array;
  fps: number;
  threshold: number;
  pauses: Pause[];
  suggestions: Suggestion[];
  duration: number;
  currentTime: number;
  onSeek: (time: number) => void;
  height?: number;
}

/**
 * SVG chart of motion energy. Pauses are green bands, threshold is a
 * dashed horizontal line, suggestion boundaries are vertical markers,
 * playhead is a red line. Click anywhere to seek.
 */
export function MotionChart({
  smoothed,
  rawEnergy,
  fps,
  threshold,
  pauses,
  suggestions,
  duration,
  currentTime,
  onSeek,
  height = 160,
}: Props) {
  const width = 800; // viewBox width — scales via CSS

  const { smoothedPath, rawPath, yMax } = useMemo(() => {
    let max = threshold;
    for (let i = 0; i < smoothed.length; i++) if (smoothed[i] > max) max = smoothed[i];
    for (let i = 0; i < rawEnergy.length; i++) if (rawEnergy[i] > max) max = rawEnergy[i];
    max = Math.max(max, 1e-6);

    const toX = (i: number, n: number) => (i / Math.max(1, n - 1)) * width;
    const toY = (v: number) => height - (v / max) * (height - 4) - 2;

    const buildPath = (arr: Float32Array) => {
      if (arr.length === 0) return '';
      let d = `M ${toX(0, arr.length).toFixed(2)} ${toY(arr[0]).toFixed(2)}`;
      for (let i = 1; i < arr.length; i++) {
        d += ` L ${toX(i, arr.length).toFixed(2)} ${toY(arr[i]).toFixed(2)}`;
      }
      return d;
    };

    return {
      smoothedPath: buildPath(smoothed),
      rawPath: buildPath(rawEnergy),
      yMax: max,
    };
  }, [smoothed, rawEnergy, threshold, height]);

  const thresholdY = height - (threshold / yMax) * (height - 4) - 2;
  const xForTime = (t: number) => (t / Math.max(0.001, duration)) * width;

  function handleClick(e: React.MouseEvent<SVGSVGElement>) {
    const rect = (e.currentTarget as SVGSVGElement).getBoundingClientRect();
    const ratio = (e.clientX - rect.left) / rect.width;
    onSeek(Math.max(0, Math.min(duration, ratio * duration)));
  }

  return (
    <div className="chart">
      <svg
        viewBox={`0 0 ${width} ${height}`}
        preserveAspectRatio="none"
        className="chart__svg"
        onClick={handleClick}
      >
        {/* Pause bands */}
        {pauses.map((p, i) => (
          <rect
            key={`pause-${i}`}
            x={xForTime(p.start)}
            y={0}
            width={xForTime(p.end) - xForTime(p.start)}
            height={height}
            fill="rgba(80, 200, 120, 0.22)"
          />
        ))}

        {/* Raw energy (faint) */}
        <path d={rawPath} stroke="rgba(200,200,200,0.35)" strokeWidth={1} fill="none" />

        {/* Smoothed energy */}
        <path d={smoothedPath} stroke="rgba(120, 180, 255, 0.95)" strokeWidth={1.5} fill="none" />

        {/* Threshold line */}
        <line
          x1={0}
          y1={thresholdY}
          x2={width}
          y2={thresholdY}
          stroke="rgba(255, 180, 60, 0.85)"
          strokeWidth={1}
          strokeDasharray="4 3"
        />

        {/* Suggestion boundary markers */}
        {suggestions.map((s) => (
          <g key={`sug-${s.id}`}>
            <line
              x1={xForTime(s.startTime)} y1={0}
              x2={xForTime(s.startTime)} y2={height}
              stroke="rgba(120, 180, 255, 0.5)"
              strokeWidth={0.5}
            />
            <line
              x1={xForTime(s.endTime)} y1={0}
              x2={xForTime(s.endTime)} y2={height}
              stroke="rgba(120, 180, 255, 0.5)"
              strokeWidth={0.5}
            />
          </g>
        ))}

        {/* Playhead */}
        <line
          x1={xForTime(currentTime)} y1={0}
          x2={xForTime(currentTime)} y2={height}
          stroke="rgba(255, 80, 80, 0.95)"
          strokeWidth={1.5}
        />
      </svg>
      <div className="chart__legend">
        <span className="legend-swatch legend-swatch--smoothed" /> smoothed motion
        <span className="legend-swatch legend-swatch--raw" /> raw
        <span className="legend-swatch legend-swatch--threshold" /> threshold
        <span className="legend-swatch legend-swatch--pause" /> detected pause
        <span style={{ marginLeft: 'auto', opacity: 0.7 }}>fps: {fps} · click chart to seek</span>
      </div>
    </div>
  );
}
