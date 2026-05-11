import type { SegmentationParams } from '../detector/types';

interface Props {
  params: SegmentationParams;
  onChange: (params: SegmentationParams) => void;
  onReset: () => void;
}

interface SliderProps {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit: string;
  help: string;
  onChange: (value: number) => void;
}

function Slider({ label, value, min, max, step, unit, help, onChange }: SliderProps) {
  return (
    <div className="slider">
      <div className="slider__row">
        <label className="slider__label">{label}</label>
        <span className="slider__value">
          {step < 1 ? value.toFixed(2) : value} {unit}
        </span>
      </div>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(e) => onChange(parseFloat(e.target.value))}
      />
      <div className="slider__help">{help}</div>
    </div>
  );
}

export function ParameterPanel({ params, onChange, onReset }: Props) {
  const set = <K extends keyof SegmentationParams>(key: K, value: SegmentationParams[K]) =>
    onChange({ ...params, [key]: value });

  return (
    <div className="panel">
      <div className="panel__header">
        <h3>Detection parameters</h3>
        <button className="btn btn--ghost" onClick={onReset}>Reset</button>
      </div>
      <Slider
        label="Threshold multiplier (k)"
        value={params.thresholdMultiplier}
        min={0.05} max={1.0} step={0.01}
        unit=""
        help="Pause = sample below median × k. Lower = stricter."
        onChange={(v) => set('thresholdMultiplier', v)}
      />
      <Slider
        label="Min pause duration"
        value={params.minPauseDuration}
        min={0.1} max={3.0} step={0.1}
        unit="s"
        help="Reject pauses shorter than this — filters brief dips."
        onChange={(v) => set('minPauseDuration', v)}
      />
      <Slider
        label="Max pause duration"
        value={params.maxPauseDuration}
        min={1} max={30} step={0.5}
        unit="s"
        help="Reject pauses longer than this — filters water breaks."
        onChange={(v) => set('maxPauseDuration', v)}
      />
      <Slider
        label="Smoothing window"
        value={params.smoothingWindow}
        min={0.0} max={2.0} step={0.05}
        unit="s"
        help="Larger = ignores sub-rep flicker, but blurs short pauses."
        onChange={(v) => set('smoothingWindow', v)}
      />
    </div>
  );
}
