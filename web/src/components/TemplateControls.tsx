interface Props {
  /** Current video time — drives "Set to current time" buttons. */
  currentTime: number;
  /** User's pending start/end selections (before "Find similar reps"). */
  pendingStart: number | null;
  pendingEnd: number | null;
  /** Whether matching has been run with the current selection. */
  hasResult: boolean;
  onSetStart: () => void;
  onSetEnd: () => void;
  onClear: () => void;
  onRun: () => void;
}

function fmt(t: number | null): string {
  if (t === null) return '—:——';
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, '0')}`;
}

export function TemplateControls({
  currentTime,
  pendingStart,
  pendingEnd,
  hasResult,
  onSetStart,
  onSetEnd,
  onClear,
  onRun,
}: Props) {
  const haveBoth = pendingStart !== null && pendingEnd !== null;
  const duration = haveBoth
    ? Math.abs((pendingEnd as number) - (pendingStart as number))
    : 0;

  const order = haveBoth && (pendingEnd as number) < (pendingStart as number);

  return (
    <div className="panel">
      <div className="panel__header">
        <h3>Mark one rep</h3>
        {(pendingStart !== null || pendingEnd !== null) && (
          <button className="btn btn--ghost" onClick={onClear}>Clear</button>
        )}
      </div>

      <div className="template-controls__hint">
        Scrub the video to the start of a clean rep, click <em>Set start</em>.
        Scrub to the end of the same rep, click <em>Set end</em>. Then click
        <em> Find similar reps</em>.
      </div>

      <div className="template-controls__row">
        <div className="template-controls__field">
          <div className="template-controls__label">Start</div>
          <div className="template-controls__value">{fmt(pendingStart)}</div>
          <button className="btn btn--ghost" onClick={onSetStart}>
            Set start ({fmt(currentTime)})
          </button>
        </div>
        <div className="template-controls__field">
          <div className="template-controls__label">End</div>
          <div className="template-controls__value">{fmt(pendingEnd)}</div>
          <button className="btn btn--ghost" onClick={onSetEnd}>
            Set end ({fmt(currentTime)})
          </button>
        </div>
      </div>

      <div className="template-controls__summary">
        {haveBoth ? (
          order ? (
            <span className="template-controls__warn">
              End is before start — we'll swap them when matching.
            </span>
          ) : (
            <>Selected: {duration.toFixed(2)}s</>
          )
        ) : (
          <span className="template-controls__dim">No range selected yet.</span>
        )}
      </div>

      <button
        className="btn template-controls__run"
        disabled={!haveBoth || duration < 0.4}
        onClick={onRun}
      >
        {hasResult ? 'Re-run with this selection' : 'Find similar reps'}
      </button>
      {haveBoth && duration < 0.4 && (
        <div className="template-controls__warn">Template must be at least 0.4s long.</div>
      )}
    </div>
  );
}
