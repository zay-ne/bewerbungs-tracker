import { useEffect, useMemo, useRef, useState } from 'react'
import * as api from './lib/api'
import { demoDaten } from './lib/demo'
import {
  auswahl, FILTER, heute, sortieren, STUFEN,
  type Bewerbung, type FilterId, type SortKey, type Stufe,
} from './lib/model'
import Zeile from './Zeile'

export default function App() {
  const [items, setItems] = useState<Bewerbung[]>([])
  const [rev, setRev] = useState(0)
  const [zustand, setZustand] = useState<'laedt' | 'da' | 'abgemeldet' | 'offline'>('laedt')
  const [demo, setDemo] = useState(false)
  const [suche, setSuche] = useState('')
  const [filter, setFilter] = useState<FilterId>('all')
  const [sort, setSort] = useState<{ key: SortKey; richtung: 1 | -1 }>({ key: 'applied', richtung: -1 })
  const schreibt = useRef(false)

  useEffect(() => {
    (async () => {
      const wer = await api.werBinIch()
      if (wer === 'offline') return setZustand('offline')
      if (!wer.konto && !wer.demo) return setZustand('abgemeldet')
      // Vorführung: der Worker hat dort keine Ablage, die Daten kommen aus dem Browser
      if (wer.demo) {
        setDemo(true)
        setItems(demoDaten())
        setZustand('da')
        return
      }
      const stand = await api.holen()
      setItems(stand.items)
      setRev(stand.rev)
      setZustand('da')
    })()
  }, [])

  /** Speichern ist ein Schreibvorgang mit Revisionsnummer: erst lokal zeigen, dann senden. */
  async function sichern(neu: Bewerbung[]) {
    setItems(neu)
    if (demo || schreibt.current) return
    schreibt.current = true
    const res = await api.speichern(rev, neu)
    schreibt.current = false
    if (res.ok && res.daten.rev) setRev(res.daten.rev)
  }

  const weiter = (b: Bewerbung, status: Stufe) =>
    sichern(items.map((x) => (x.id === b.id
      ? { ...x, status, history: [...x.history, { status, date: heute() }] }
      : x)))

  const sichtbar = useMemo(() => {
    const gefiltert = auswahl(items, { suche, filter })
    return sortieren(gefiltert, sort.key, sort.richtung)
  }, [items, suche, filter, sort])

  const zahlen = useMemo(() => {
    const verschickt = items.filter((b) => b.status !== 'planned').length
    const gespraech = items.filter((b) => b.history.some((h) => h.status.startsWith('iv'))).length
    return { gesamt: items.length, verschickt, gespraech, zusagen: items.filter((b) => b.status === 'accepted').length }
  }, [items])

  return (
    <div className="mx-auto max-w-[1100px] px-4 pb-24 sm:px-6">
      <header className="flex flex-wrap items-center gap-3 pt-8 pb-5">
        <h1 className="text-[30px] font-bold tracking-[-0.045em]">
          <span style={{ color: 'var(--accent)' }}>zap</span>ply!
        </h1>
        <button
          className="ml-auto h-10 rounded-full px-4 text-[15px] font-medium text-white transition-transform duration-200 active:scale-95"
          style={{ background: 'var(--accent)' }}
        >
          + Neue Bewerbung
        </button>
      </header>

      <div className="mb-4 grid grid-cols-2 gap-2.5 sm:grid-cols-4">
        {[
          ['Bewerbungen', zahlen.gesamt],
          ['Verschickt', zahlen.verschickt],
          ['Im Gespräch', zahlen.gespraech],
          ['Zusagen', zahlen.zusagen],
        ].map(([k, v]) => (
          <div key={k as string} className="rounded-[14px] px-3.5 py-3" style={{ background: 'var(--karte)', boxShadow: 'var(--schatten), var(--kante)' }}>
            <div className="text-[12.5px]" style={{ color: 'var(--text2)' }}>{k}</div>
            <div className="text-[25px] font-semibold tabular-nums">{v}</div>
          </div>
        ))}
      </div>

      <div className="sticky top-0 z-10 -mx-4 mb-3 px-4 pt-2 pb-2.5 sm:-mx-6 sm:px-6" style={{ background: 'var(--bg)' }}>
        <input
          value={suche}
          onChange={(e) => setSuche(e.target.value)}
          placeholder="Suchen …"
          className="mb-2.5 h-10 w-full rounded-full px-4 outline-none"
          style={{ background: 'var(--senke)' }}
        />
        <div className="flex gap-2 overflow-x-auto [scrollbar-width:none]">
          {FILTER.map((f) => {
            const anzahl = auswahl(items, { suche, filter: f.id }).length
            if (f.id !== 'all' && !anzahl) return null
            const an = f.id === filter
            return (
              <button
                key={f.id}
                onClick={() => setFilter(f.id)}
                className="flex h-8 flex-none items-center gap-1.5 rounded-full px-3 text-[13px] font-medium transition-transform duration-200 active:scale-95"
                style={{
                  background: an ? 'var(--text)' : 'var(--senke)',
                  color: an ? 'var(--karte)' : 'var(--text2)',
                }}
              >
                {f.label}
                <span className="text-[11.5px] opacity-65 tabular-nums">{anzahl}</span>
              </button>
            )
          })}
          <select
            value={sort.key}
            onChange={(e) => setSort({ ...sort, key: e.target.value as SortKey })}
            className="ml-auto h-8 flex-none rounded-full px-3 text-[13px] outline-none"
            style={{ background: 'var(--senke)' }}
          >
            <option value="applied">Datum</option>
            <option value="status">Status</option>
            <option value="company">Firma</option>
            <option value="salary">Gehalt</option>
          </select>
          <button
            onClick={() => setSort({ ...sort, richtung: sort.richtung === 1 ? -1 : 1 })}
            className="grid size-8 flex-none place-items-center rounded-full"
            style={{ background: 'var(--senke)' }}
          >
            {sort.richtung === 1 ? '↑' : '↓'}
          </button>
        </div>
      </div>

      {zustand === 'laedt' && <p style={{ color: 'var(--text2)' }}>Wird geladen …</p>}
      {zustand === 'abgemeldet' && <p style={{ color: 'var(--text2)' }}>Nicht angemeldet.</p>}
      {zustand === 'offline' && <p style={{ color: 'var(--orange)' }}>Keine Verbindung.</p>}

      {zustand === 'da' && (
        <div className="liste">
          {sichtbar.map((b) => (
            <Zeile
              key={b.id}
              b={b}
              weiter={(status) => weiter(b, status)}
              loeschen={() => sichern(items.filter((x) => x.id !== b.id))}
            />
          ))}
          {!sichtbar.length && (
            <p className="px-4 py-10 text-center" style={{ color: 'var(--text3)' }}>
              Nichts in dieser Auswahl.
            </p>
          )}
        </div>
      )}

      <p className="pt-4 text-[12.5px]" style={{ color: 'var(--text3)' }}>
        {sichtbar.length} von {items.length} · Stand {rev} · {STUFEN.applied.emoji} zapply
      </p>
    </div>
  )
}
