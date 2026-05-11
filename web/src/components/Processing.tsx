interface Props {
  current: number;
  total: number;
  onCancel: () => void;
}

export function Processing({ current, total, onCancel }: Props) {
  const pct = total > 0 ? Math.min(100, (current / total) * 100) : 0;
  return (
    <div className="processing">
      <div className="processing__label">
        Analyzing motion · sample {current} of {total}
      </div>
      <div className="processing__bar">
        <div className="processing__fill" style={{ width: `${pct}%` }} />
      </div>
      <button className="btn btn--ghost" onClick={onCancel}>Cancel</button>
    </div>
  );
}
