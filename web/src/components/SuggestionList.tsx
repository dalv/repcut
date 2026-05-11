import type { Suggestion } from '../detector/types';

interface Props {
  suggestions: Suggestion[];
  activeId: string | null;
  currentTime: number;
  onPlay: (s: Suggestion) => void;
}

function fmt(t: number): string {
  const m = Math.floor(t / 60);
  const s = t - m * 60;
  return `${m}:${s.toFixed(2).padStart(5, '0')}`;
}

export function SuggestionList({ suggestions, activeId, currentTime, onPlay }: Props) {
  if (suggestions.length === 0) {
    return (
      <div className="suggestions suggestions--empty">
        No reps detected with current parameters. Try lowering threshold k or smoothing window.
      </div>
    );
  }
  return (
    <div className="suggestions">
      <div className="suggestions__title">Detected reps · {suggestions.length}</div>
      <ul className="suggestions__list">
        {suggestions.map((s, i) => {
          const active = activeId === s.id;
          const playing = active && currentTime >= s.startTime && currentTime <= s.endTime;
          return (
            <li
              key={s.id}
              className={`suggestion ${active ? 'suggestion--active' : ''} ${playing ? 'suggestion--playing' : ''}`}
            >
              <div className="suggestion__num">#{i + 1}</div>
              <div className="suggestion__body">
                <div className="suggestion__range">
                  {fmt(s.startTime)} → {fmt(s.endTime)}
                  <span className="suggestion__dur"> · {(s.endTime - s.startTime).toFixed(2)}s</span>
                </div>
                <div className="suggestion__pause">
                  setup hold: {fmt(s.pauseStart)}–{fmt(s.pauseEnd)} · peak: {fmt(s.peakTime)}
                </div>
              </div>
              <button className="btn" onClick={() => onPlay(s)}>Play</button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}
