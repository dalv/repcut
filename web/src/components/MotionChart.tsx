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
  /** Optional secondary strip: correlation against the template at every offset. */
  correlationCurve?: Float32Array;
  /** Min-correlation threshold for the correlation strip's reference line. */
  correlationThreshold?: number;
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
  correlationCurve,
  correlationThreshold,
}: Props) {
  const width = 800;
  const corrHeight = 60;

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

  // ---- Correlation strip (template mode only) ----
  // Correlation range we display: clip to [-0.2, 1.0] for readability.
  const corrYMin = -0.2;
  const corrYMax = 1.0;
  const corrToY = (v: number) => {
    const clamped = Math.max(corrYMin, Math.min(corrYMax, v));
    return corrHeight - ((clamped - corrYMin) / (corrYMax - corrYMin)) * (corrHeight - 4) - 2;
  };
  const corrPath = useMemo(() => {
    if (!correlationCurve || correlationCurve.length === 0) return '';
    // Each correlation[i] corresponds to a window STARTING at sample i,
    // i.e. at time i / fps. So the curve covers [0, (length-1)/fps].
    let d = `M ${(0).toFixed(2)} ${corrToY(correlationCurve[0]).toFixed(2)}`;
    for (let i = 1; i < correlationCurve.length; i++) {
      const x = xForTime(i / fps);
      d += ` L ${x.toFixed(2)} ${corrToY(correlationCurve[i]).toFixed(2)}`;
    }
    return d;
  }, [correlationCurve, fps, duration]);
  const corrThresholdY = correlationThreshold !== undefined ? corrToY(correlationThreshold) : null;
  const corrZeroY = corrToY(0);

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

      {correlationCurve && correlationCurve.length > 0 && (
        <svg
          viewBox={`0 0 ${width} ${corrHeight}`}
          preserveAspectRatio="none"
          className="chart__svg chart__svg--corr"
          onClick={handleClick}
        >
          {/* Zero baseline */}
          <line
            x1={0} y1={corrZeroY} x2={width} y2={corrZeroY}
            stroke="rgba(160, 160, 180, 0.25)"
            strokeWidth={1}
          />
          {/* Threshold line */}
          {corrThresholdY !== null && (
            <line
              x1={0} y1={corrThresholdY} x2={width} y2={corrThresholdY}
              stroke="rgba(255, 180, 60, 0.85)"
              strokeWidth={1}
              strokeDasharray="4 3"
            />
          )}
          {/* Match bands (translucent) — repeat in the correlation strip
              so users can see WHERE on the correlation landscape the
              algorithm picked matches. */}
          {bands
            .filter(b => b.kind === 'match' || b.kind === 'template')
            .map((b, i) => {
              const x = xForTime(b.start);
              const w = Math.max(1, xForTime(b.end) - x);
              return (
                <rect
                  key={`corr-band-${i}`}
                  x={x} y={0} width={w} height={corrHeight}
                  fill={b.kind === 'template' ? 'rgba(255, 200, 60, 0.18)' : 'rgba(120, 180, 255, 0.10)'}
                />
              );
            })}
          {/* The correlation line itself */}
          <path d={corrPath} stroke="rgba(120, 240, 200, 0.95)" strokeWidth={1.2} fill="none" />
          {/* Playhead */}
          <line
            x1={xForTime(currentTime)} y1={0}
            x2={xForTime(currentTime)} y2={corrHeight}
            stroke="rgba(255, 80, 80, 0.7)"
            strokeWidth={1}
          />
          {/* Y-axis labels */}
          <text x={4} y={11} fontSize={10} fill="rgba(200,200,200,0.5)">corr 1.0</text>
          <text x={4} y={corrZeroY + 4} fontSize={10} fill="rgba(200,200,200,0.5)">0</text>
        </svg>
      )}

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
        {correlationCurve && correlationCurve.length > 0 && (
          <><span className="legend-swatch legend-swatch--corr" /> correlation</>
        )}
        <span style={{ marginLeft: 'auto', opacity: 0.7 }}>fps: {fps} · click chart to seek</span>
      </div>
    </div>
  );
}
