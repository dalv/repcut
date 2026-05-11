import { useMemo } from 'react';

export type BandKind = 'pause' | 'template' | 'match' | 'selection';

export interface ChartBand {
  start: number;
  end: number;
  kind: BandKind;
  /** Optional label rendered at the top-left of the band. */
  label?: string;
}

export interface ChartMarker {
  time: number;
  kind: 'peak';
}

interface Props {
  smoothed: Float32Array;
  rawEnergy: Float32Array;
  fps: number;
  /** Optional horizontal dashed line (pause-mode threshold). */
  thresholdLine?: number;
  bands: ChartBand[];
  markers: ChartMarker[];
  duration: number;
  currentTime: number;
  onSeek: (time: number) => void;
  height?: number;
}

const BAND_FILL: Record<BandKind, string> = {
  pause:     'rgba(80, 200, 120, 0.22)',
  template:  'rgba(255, 200, 60, 0.30)',
  match:     'rgba(120, 180, 255, 0.22)',
  selection: 'rgba(255, 200, 60, 0.15)',
};
const BAND_STROKE: Record<BandKind, string> = {
  pause:     'rgba(80, 200, 120, 0.0)',
  template:  'rgba(255, 200, 60, 0.95)',
  match:     'rgba(120, 180, 255, 0.55)',
  selection: 'rgba(255, 200, 60, 0.55)',
};

/**
 * SVG chart of motion energy. Bands and markers are passed in by the
 * caller — pause mode draws pause bands, template mode draws match
 * bands + user's template band. Click anywhere on the chart to seek.
 */
export function MotionChart({
  smoothed,
  rawEnergy,
  fps,
  thresholdLine,
  bands,
  markers,
  duration,
  currentTime,
  onSeek,
  height = 160,
}: Props) {
  const width = 800;

  const { smoothedPath, rawPath, yMax } = useMemo(() => {
    let max = thresholdLine ?? 0;
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

    return { smoothedPath: buildPath(smoothed), rawPath: buildPath(rawEnergy), yMax: max };
  }, [smoothed, rawEnergy, thresholdLine, height]);

  const xForTime = (t: number) => (t / Math.max(0.001, duration)) * width;
  const thresholdY = thresholdLine !== undefined
    ? height - (thresholdLine / yMax) * (height - 4) - 2
    : null;

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
        {/* Bands */}
        {bands.map((b, i) => {
          const x = xForTime(b.start);
          const w = Math.max(1, xForTime(b.end) - x);
          return (
            <g key={`band-${i}`}>
              <rect x={x} y={0} width={w} height={height} fill={BAND_FILL[b.kind]} />
              <rect
                x={x} y={0} width={w} height={height}
                fill="none"
                stroke={BAND_STROKE[b.kind]}
                strokeWidth={1}
              />
            </g>
          );
        })}

        <path d={rawPath} stroke="rgba(200,200,200,0.35)" strokeWidth={1} fill="none" />
        <path d={smoothedPath} stroke="rgba(120, 180, 255, 0.95)" strokeWidth={1.5} fill="none" />

        {thresholdY !== null && (
          <line
            x1={0} y1={thresholdY} x2={width} y2={thresholdY}
            stroke="rgba(255, 180, 60, 0.85)"
            strokeWidth={1}
            strokeDasharray="4 3"
          />
        )}

        {markers.map((m, i) => (
          <polygon
            key={`m-${i}`}
            points={`${xForTime(m.time) - 4},2 ${xForTime(m.time) + 4},2 ${xForTime(m.time)},10`}
            fill="rgba(255, 100, 180, 0.9)"
          />
        ))}

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
        {thresholdLine !== undefined && (
          <>
            <span className="legend-swatch legend-swatch--threshold" /> threshold
          </>
        )}
        {bands.some(b => b.kind === 'pause') && (
          <><span className="legend-swatch legend-swatch--pause" /> setup hold (pause)</>
        )}
        {markers.some(m => m.kind === 'peak') && (
          <><span className="legend-swatch legend-swatch--peak" /> trick peak</>
        )}
        {bands.some(b => b.kind === 'template') && (
          <><span className="legend-swatch legend-swatch--template" /> template</>
        )}
        {bands.some(b => b.kind === 'match') && (
          <><span className="legend-swatch legend-swatch--match" /> similar rep</>
        )}
        <span style={{ marginLeft: 'auto', opacity: 0.7 }}>fps: {fps} · click chart to seek</span>
      </div>
    </div>
  );
}
