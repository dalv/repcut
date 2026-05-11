import type { TemplateParams } from '../detector/types';

interface Props {
  params: TemplateParams;
  onChange: (params: TemplateParams) => void;
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

export function TemplateParameterPanel({ params, onChange, onReset }: Props) {
  const set = <K extends keyof TemplateParams>(key: K, value: TemplateParams[K]) =>
    onChange({ ...params, [key]: value });

  return (
    <div className="panel">
      <div className="panel__header">
        <h3>Matching parameters</h3>
        <button className="btn btn--ghost" onClick={onReset}>Reset</button>
      </div>
      <Slider
        label="Min correlation"
        value={params.minCorrelation}
        min={0.1} max={0.95} step={0.01}
        unit=""
        help="A match must score at least this against the template. Lower = more matches, more false positives."
        onChange={(v) => set('minCorrelation', v)}
      />
      <Slider
        label="Non-max suppression"
        value={params.nmsWindowMultiplier}
        min={0.5} max={4.0} step={0.1}
        unit="× template length"
        help="Minimum gap between matches. Raise if you're seeing overlapping detections of the same rep."
        onChange={(v) => set('nmsWindowMultiplier', v)}
      />
      <Slider
        label="Smoothing window"
        value={params.smoothingWindow}
        min={0.0} max={2.0} step={0.05}
        unit="s"
        help="Smooths both the template and the signal before correlating. Larger = focuses on coarse shape, ignores micro-peaks."
        onChange={(v) => set('smoothingWindow', v)}
      />
    </div>
  );
}
