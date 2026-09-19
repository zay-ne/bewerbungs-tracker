import { useState } from 'react'
import { fmtDatum, losAm, naechstesGespraech, STUFEN, type Bewerbung, type Stufe } from './lib/model'

const Pille = ({ status }: { status: Stufe }) => {
  const s = STUFEN[status]
  return (
    <span
      className="inline-flex h-[22px] items-center gap-1.5 rounded-full px-2.5 text-[12.5px] font-semibold"
      style={{ background: `color-mix(in srgb, ${s.farbe} 14%, transparent)`, color: s.farbe }}
    >
      <i className="size-[5px] rounded-full bg-current" />
      {s.label}
    </span>
  )
}

const Knopf = ({ kind, ...rest }: { kind: string } & React.ButtonHTMLAttributes<HTMLButtonElement>) => (
  <button
    {...rest}
    className="h-9 rounded-full px-3.5 text-[13.5px] font-medium transition-transform duration-200 active:scale-95"
    style={{ background: 'var(--senke)' }}
  >
    {kind}
  </button>
)

type Props = {
  b: Bewerbung
  weiter: (status: Stufe) => void
  loeschen: () => void
}

export default function Zeile({ b, weiter, loeschen }: Props) {
  const [offen, setOffen] = useState(false)
  const datum = losAm(b)
  const abgeschlossen = !!STUFEN[b.status].ende

  return (
    <div className="zeile">
      <button
        onClick={() => setOffen((x) => !x)}
        className="flex w-full items-start gap-3 px-4 py-3.5 text-left"
      >
        <span
          className="mt-0.5 grid size-9 flex-none place-items-center rounded-[11px] text-[13px] font-bold"
          style={{ background: 'var(--senke)', color: 'var(--text2)' }}
        >
          {b.company.slice(0, 2).toUpperCase() || '—'}
        </span>

        <span className="min-w-0 flex-1">
          <span className="block truncate font-semibold">{b.company || '—'}</span>
          {b.role && <span className="block truncate text-[14px]" style={{ color: 'var(--text2)' }}>{b.role}</span>}
          <span className="mt-1.5 flex items-center gap-2.5 text-[13.5px]">
            {datum && <span style={{ color: 'var(--text2)' }} className="tabular-nums">{fmtDatum(datum)}</span>}
            <Pille status={b.status} />
          </span>
        </span>

        <span
          className="mt-1 grid size-7 flex-none place-items-center rounded-[9px] text-[17px] transition-transform duration-200"
          style={{ background: 'var(--senke)', color: 'var(--text3)', transform: offen ? 'rotate(90deg)' : 'none' }}
        >
          ›
        </span>
      </button>

      {/* Hoehe direkt am Element: keine Klasse, die eine Regel ueberstimmen koennte.
          ponytail: feste Obergrenze 420px, bei mehr Inhalt auf Messung umstellen. */}
      <div
        style={{
          overflow: 'hidden',
          maxHeight: offen ? 420 : 0,
          opacity: offen ? 1 : 0,
          transition: 'max-height .3s var(--feder), opacity .2s ease',
        }}
      >
          <div className="space-y-2 px-4 pb-4 text-[14px]">
            {[
              ['Ort', b.location],
              ['Kanal', b.channel],
              ['Gehalt', b.salary != null ? b.salary.toLocaleString('de-DE') + ' €' : ''],
              ['Schluss', fmtDatum(b.deadline)],
            ]
              .filter(([, wert]) => wert)
              .map(([name, wert]) => (
                <div key={name} className="flex justify-between gap-4">
                  <span className="text-[11.5px] font-semibold uppercase tracking-wider" style={{ color: 'var(--text3)' }}>{name}</span>
                  <span className="truncate">{wert}</span>
                </div>
              ))}

            {b.history.length > 1 && (
              <p style={{ color: 'var(--text2)' }}>
                {b.history.map((h) => `${STUFEN[h.status].kurz}${h.date ? ' · ' + fmtDatum(h.date) : ''}`).join('  →  ')}
              </p>
            )}

            <div className="flex flex-wrap gap-2 pt-1">
              {b.status === 'planned' && <Knopf kind="→ Beworben" onClick={(e) => { e.stopPropagation(); weiter('applied') }} />}
              {!abgeschlossen && b.status !== 'planned' && (
                <Knopf kind={'+ ' + STUFEN[naechstesGespraech(b)].kurz} onClick={(e) => { e.stopPropagation(); weiter(naechstesGespraech(b)) }} />
              )}
              {!abgeschlossen && (
                <>
                  <Knopf kind="🎉 Zusage" onClick={(e) => { e.stopPropagation(); weiter('accepted') }} />
                  <Knopf kind="❌ Absage" onClick={(e) => { e.stopPropagation(); weiter('rejected') }} />
                  <Knopf kind="🕓 Keine Antwort" onClick={(e) => { e.stopPropagation(); weiter('noreply') }} />
                </>
              )}
              {b.url && (
                <a
                  href={b.url}
                  target="_blank"
                  rel="noopener noreferrer"
                  onClick={(e) => e.stopPropagation()}
                  className="grid h-9 place-items-center rounded-full px-3.5 text-[13.5px] font-medium"
                  style={{ background: 'var(--senke)', color: 'var(--accent)' }}
                >
                  Ausschreibung ↗
                </a>
              )}
              <Knopf kind="Löschen" onClick={(e) => { e.stopPropagation(); loeschen() }} />
            </div>
          </div>
      </div>
    </div>
  )
}
