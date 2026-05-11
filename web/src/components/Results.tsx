import { useEffect, useMemo, useRef, useState } from 'react';
import type { MotionSignal, SegmentationParams, Suggestion } from '../detector/types';
import { DEFAULT_PARAMS } from '../detector/types';
import { segmentByPauses } from '../detector/segment';
import { MotionChart } from './MotionChart';
import { ParameterPanel } from './ParameterPanel';
import { SuggestionList } from './SuggestionList';

interface Props {
  file: File;
  signal: MotionSignal;
  onReset: () => void;
}

export function Results({ file, signal, onReset }: Props) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const [params, setParams] = useState<SegmentationParams>(DEFAULT_PARAMS);
  const [currentTime, setCurrentTime] = useState(0);
  const [activeSuggestionId, setActiveSuggestionId] = useState<string | null>(null);

  // Re-segment instantly on parameter change — the expensive frame
  // extraction stays cached upstream.
  const result = useMemo(() => segmentByPauses(signal, params), [signal, params]);

  // Object URL for the video player.
  const videoUrl = useMemo(() => URL.createObjectURL(file), [file]);
  useEffect(() => () => URL.revokeObjectURL(videoUrl), [videoUrl]);

  // Track playhead.
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

  return (
    <div className="results">
      <header className="results__header">
        <div>
          <div className="results__title">{file.name}</div>
          <div className="results__sub">
            {signal.duration.toFixed(1)}s · sampled at {signal.fps} fps · {signal.energy.length} samples
          </div>
        </div>
        <button className="btn btn--ghost" onClick={onReset}>Load another</button>
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
        smoothed={result.smoothed}
        rawEnergy={signal.energy}
        fps={signal.fps}
        threshold={result.threshold}
        pauses={result.pauses}
        suggestions={result.suggestions}
        duration={signal.duration}
        currentTime={currentTime}
        onSeek={seek}
      />

      <div className="results__cols">
        <ParameterPanel
          params={params}
          onChange={setParams}
          onReset={() => setParams(DEFAULT_PARAMS)}
        />
        <SuggestionList
          suggestions={result.suggestions}
          activeId={activeSuggestionId}
          currentTime={currentTime}
          onPlay={playSuggestion}
        />
      </div>
    </div>
  );
}
