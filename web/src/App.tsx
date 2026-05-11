import { useCallback, useRef, useState } from 'react';
import { DropZone } from './components/DropZone';
import { Processing } from './components/Processing';
import { Results } from './components/Results';
import { extractMotionSignal } from './detector/extract';
import type { MotionSignal } from './detector/types';

type State =
  | { kind: 'idle' }
  | { kind: 'processing'; current: number; total: number; file: File }
  | { kind: 'error'; message: string }
  | { kind: 'results'; file: File; signal: MotionSignal };

export default function App() {
  const [state, setState] = useState<State>({ kind: 'idle' });
  const abortRef = useRef<AbortController | null>(null);

  const handleFile = useCallback(async (file: File) => {
    const ac = new AbortController();
    abortRef.current = ac;
    setState({ kind: 'processing', current: 0, total: 1, file });
    try {
      const signal = await extractMotionSignal(file, {
        signal: ac.signal,
        onProgress: (current, total) => {
          setState((prev) =>
            prev.kind === 'processing' ? { ...prev, current, total } : prev,
          );
        },
      });
      setState({ kind: 'results', file, signal });
    } catch (err) {
      if (err instanceof DOMException && err.name === 'AbortError') {
        setState({ kind: 'idle' });
        return;
      }
      setState({
        kind: 'error',
        message: err instanceof Error ? err.message : String(err),
      });
    }
  }, []);

  const cancel = useCallback(() => {
    abortRef.current?.abort();
  }, []);

  const reset = useCallback(() => {
    abortRef.current?.abort();
    setState({ kind: 'idle' });
  }, []);

  return (
    <div className="app">
      <header className="app__header">
        <div className="app__brand">RepCut · rep detection prototype</div>
        <div className="app__tag">Phase 1: pause-based segmentation. Pure browser, no upload.</div>
      </header>

      <main className="app__main">
        {state.kind === 'idle' && <DropZone onFile={handleFile} />}
        {state.kind === 'processing' && (
          <Processing
            current={state.current}
            total={state.total}
            onCancel={cancel}
          />
        )}
        {state.kind === 'error' && (
          <div className="error">
            <div className="error__msg">{state.message}</div>
            <button className="btn" onClick={reset}>Try another video</button>
          </div>
        )}
        {state.kind === 'results' && (
          <Results file={state.file} signal={state.signal} onReset={reset} />
        )}
      </main>

      <footer className="app__footer">
        Prototype for validating Phase 1 detection on real acro videos before porting to Swift.
      </footer>
    </div>
  );
}
