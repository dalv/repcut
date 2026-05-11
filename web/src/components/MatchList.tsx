import type { Match } from '../detector/types';

interface Props {
  matches: Match[];
  currentTime: number;
  activeId: string | null;
  onPlay: (m: Match) => void;
}

function fmt(t: number): string {
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, '0')}`;
}

export function MatchList({ matches, currentTime, activeId, onPlay }: Props) {
  if (matches.length === 0) {
    return (
      <div className="suggestions suggestions--empty">
        No similar reps found. Lower the correlation threshold, try a longer
        or shorter template selection, or mark a different rep as the example.
      </div>
    );
  }
  return (
    <div className="suggestions">
      <div className="suggestions__title">Similar reps · {matches.length}</div>
      <ul className="suggestions__list">
        {matches.map((m, i) => {
          const active = activeId === m.id;
          const playing = active && currentTime >= m.startTime && currentTime <= m.endTime;
          return (
            <li
              key={m.id}
              className={`suggestion ${active ? 'suggestion--active' : ''} ${playing ? 'suggestion--playing' : ''} ${m.isTemplate ? 'suggestion--template' : ''}`}
            >
              <div className="suggestion__num">
                #{i + 1}
                {m.isTemplate && <span className="suggestion__badge">template</span>}
              </div>
              <div className="suggestion__body">
                <div className="suggestion__range">
                  {fmt(m.startTime)} → {fmt(m.endTime)}
                  <span className="suggestion__dur"> · {(m.endTime - m.startTime).toFixed(2)}s</span>
                </div>
                <div className="suggestion__pause">
                  correlation: {m.correlation.toFixed(3)}
                </div>
              </div>
              <button className="btn" onClick={() => onPlay(m)}>Play</button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
