import { useEffect, useMemo, useRef, useState } from 'react';
import type {
  Match,
  MotionSignal,
  SegmentationParams,
  Suggestion,
  TemplateParams,
  TemplateRange,
} from '../detector/types';
import { DEFAULT_PARAMS, DEFAULT_TEMPLATE_PARAMS } from '../detector/types';
import { segmentByPauses } from '../detector/segment';
import { segmentByTemplate } from '../detector/template';
import { MotionChart, type ChartBand, type ChartMarker } from './MotionChart';
import { ParameterPanel } from './ParameterPanel';
import { SuggestionList } from './SuggestionList';
import { TemplateControls } from './TemplateControls';
import { TemplateParameterPanel } from './TemplateParameterPanel';
import { MatchList } from './MatchList';

type Mode = 'template' | 'pauses';

interface Props {
  file: File;
  signal: MotionSignal;
  onReset: () => void;
}

export function Results({ file, signal, onReset }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [mode, setMode] = useState<Mode>('template');
  const [currentTime, setCurrentTime] = useState(0);

  // ---- Pause mode state (kept alive across mode switches as a debug view) ----
  const [pauseParams, setPauseParams] = useState<SegmentationParams>(DEFAULT_PARAMS);
  const pauseResult = useMemo(() => segmentByPauses(signal, pauseParams), [signal, pauseParams]);

  // ---- Template mode state ----
  const [pendingStart, setPendingStart] = useState<number | null>(null);
  const [pendingEnd, setPendingEnd] = useState<number | null>(null);
  const [confirmedRange, setConfirmedRange] = useState<TemplateRange | null>(null);
  const [templateParams, setTemplateParams] = useState<TemplateParams>(DEFAULT_TEMPLATE_PARAMS);
  const templateResult = useMemo(() => {
    if (!confirmedRange) return null;
    return segmentByTemplate(signal, confirmedRange, templateParams);
  }, [signal, confirmedRange, templateParams]);

  // ---- Active match (for playback indicator) ----
  const [activeSuggestionId, setActiveSuggestionId] = useState<string | null>(null);
  const [activeMatchId, setActiveMatchId] = useState<string | null>(null);

  // ---- Object URL for the video player ----
  const videoUrl = useMemo(() => URL.createObjectURL(file), [file]);
  useEffect(() => () => URL.revokeObjectURL(videoUrl), [videoUrl]);

  // ---- Track playhead ----
  useEffect(() => {
    const v = videoRef.current;
    if (!v) return;
    const onTime = () => setCurrentTime(v.currentTime);
    v.addEventListener('timeupdate', onTime);
    v.addEventListener('seeked', onTime);
    return () => {
      v.removeEventListener('timeupdate', onTime);
      v.removeEventListener('seeked', onTime);
    };
  }, []);

  function seek(time: number) {
    const v = videoRef.current;
    if (v) v.currentTime = time;
  }

  function playSuggestion(s: Suggestion) {
    const v = videoRef.current;
    if (!v) return;
    setActiveSuggestionId(s.id);
    v.currentTime = s.startTime;
    void v.play();
  }

  function playMatch(m: Match) {
    const v = videoRef.current;
    if (!v) return;
    setActiveMatchId(m.id);
    v.currentTime = m.startTime;
    void v.play();
  }

  function runTemplateMatching() {
    if (pendingStart === null || pendingEnd === null) return;
    const a = Math.min(pendingStart, pendingEnd);
    const b = Math.max(pendingStart, pendingEnd);
    setConfirmedRange({ startTime: a, endTime: b });
  }

  function clearSelection() {
    setPendingStart(null);
    setPendingEnd(null);
    setConfirmedRange(null);
    setActiveMatchId(null);
  }

  // ---- Compute chart overlays based on the active mode ----
  const chartBands: ChartBand[] = [];
  const chartMarkers: ChartMarker[] = [];
  let thresholdLine: number | undefined;
  let smoothedForChart = pauseResult.smoothed;

  if (mode === 'pauses') {
    thresholdLine = pauseResult.threshold;
    for (const p of pauseResult.pauses) {
      chartBands.push({ start: p.start, end: p.end, kind: 'pause' });
    }
    for (const s of pauseResult.suggestions) {
      chartMarkers.push({ time: s.peakTime, kind: 'peak' });
    }
  } else {
    // Template mode
    if (templateResult) smoothedForChart = templateResult.smoothed;
    if (confirmedRange) {
      // Matches (excluding the template match itself rendered as 'template').
      for (const m of templateResult?.matches ?? []) {
        chartBands.push({
          start: m.startTime,
          end: m.endTime,
          kind: m.isTemplate ? 'template' : 'match',
        });
      }
      // If the template offset didn't naturally appear as a match (e.g.
      // threshold too high), still render the user's marked range.
      const sawTemplate = (templateResult?.matches ?? []).some(m => m.isTemplate);
      if (!sawTemplate) {
        chartBands.push({
          start: confirmedRange.startTime,
          end: confirmedRange.endTime,
          kind: 'template',
        });
      }
    } else if (pendingStart !== null && pendingEnd !== null) {
      const a = Math.min(pendingStart, pendingEnd);
      const b = Math.max(pendingStart, pendingEnd);
      chartBands.push({ start: a, end: b, kind: 'selection' });
    } else if (pendingStart !== null) {
      // Single click — show a thin marker at the start
      chartBands.push({ start: pendingStart, end: pendingStart + 0.05, kind: 'selection' });
    } else if (pendingEnd !== null) {
      chartBands.push({ start: pendingEnd, end: pendingEnd + 0.05, kind: 'selection' });
    }
  }

  return (
    <div className="results">
      <header className="results__header">
        <div>
          <div className="results__title">{file.name}</div>
          <div className="results__sub">
            {signal.duration.toFixed(1)}s · sampled at {signal.fps} fps · {signal.energy.length} samples
          </div>
        </div>
        <div className="results__header-actions">
          <div className="mode-toggle" role="tablist">
            <button
              className={`mode-toggle__btn ${mode === 'template' ? 'mode-toggle__btn--active' : ''}`}
              onClick={() => setMode('template')}
            >
              Template matching
            </button>
            <button
              className={`mode-toggle__btn ${mode === 'pauses' ? 'mode-toggle__btn--active' : ''}`}
              onClick={() => setMode('pauses')}
            >
              Pause detection
            </button>
          </div>
          <button className="btn btn--ghost" onClick={onReset}>Load another</button>
        </div>
      </header>

      <div className="results__player">
        <video
          ref={videoRef}
          src={videoUrl}
          controls
          playsInline
          className="results__video"
        />
      </div>

      <MotionChart
        smoothed={smoothedForChart}
        rawEnergy={signal.energy}
        fps={signal.fps}
        thresholdLine={thresholdLine}
        bands={chartBands}
        markers={chartMarkers}
        duration={signal.duration}
        currentTime={currentTime}
        onSeek={seek}
        correlationCurve={mode === 'template' ? templateResult?.correlation : undefined}
        correlationThreshold={mode === 'template' && templateResult ? templateParams.minCorrelation : undefined}
      />

      {mode === 'template' ? (
        <div className="results__cols">
          <div className="results__col">
            <TemplateControls
              currentTime={currentTime}
              pendingStart={pendingStart}
              pendingEnd={pendingEnd}
              hasResult={templateResult !== null}
              onSetStart={() => setPendingStart(currentTime)}
              onSetEnd={() => setPendingEnd(currentTime)}
              onClear={clearSelection}
              onRun={runTemplateMatching}
            />
            <TemplateParameterPanel
              params={templateParams}
              onChange={setTemplateParams}
              onReset={() => setTemplateParams(DEFAULT_TEMPLATE_PARAMS)}
            />
          </div>
          <MatchList
            matches={templateResult?.matches ?? []}
            currentTime={currentTime}
            activeId={activeMatchId}
            onPlay={playMatch}
          />
        </div>
      ) : (
        <div className="results__cols">
          <ParameterPanel
            params={pauseParams}
            onChange={setPauseParams}
            onReset={() => setPauseParams(DEFAULT_PARAMS)}
          />
          <SuggestionList
            suggestions={pauseResult.suggestions}
            activeId={activeSuggestionId}
            currentTime={currentTime}
            onPlay={playSuggestion}
          />
        </div>
      )}
    </div>
  );
}
