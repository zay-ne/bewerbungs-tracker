/** Datenmodell, unverändert zum alten Stand: der Verlauf trägt alles,
 *  der aktuelle Status ist die letzte Station. */

export type Stufe =
  | 'planned' | 'applied' | 'iv1' | 'iv2' | 'iv3' | 'ivN'
  | 'offer' | 'accepted' | 'rejected' | 'noreply' | 'withdrawn';

export type Station = { status: Stufe; date: string };

export type Bewerbung = {
  id: string;
  company: string;
  role: string;
  salary: number | null;
  salaryType: string;
  salaryPeriod: string;
  employment: string;
  location: string;
  channel: string;
  url: string;
  applied: string;
  deadline: string;
  status: Stufe;
  history: Station[];
};

export const STUFEN: Record<Stufe, { label: string; kurz: string; emoji: string; farbe: string; ende?: true }> = {
  planned:   { label: 'Geplant',        kurz: 'Geplant',     emoji: '🗒️', farbe: 'var(--gray)' },
  applied:   { label: 'Beworben',       kurz: 'Beworben',    emoji: '📮', farbe: 'var(--accent)' },
  iv1:       { label: '1. Gespräch',    kurz: '1. Gespr.',   emoji: '💬', farbe: 'var(--purple)' },
  iv2:       { label: '2. Gespräch',    kurz: '2. Gespr.',   emoji: '💬', farbe: 'var(--purple)' },
  iv3:       { label: '3. Gespräch',    kurz: '3. Gespr.',   emoji: '💬', farbe: 'var(--purple)' },
  ivN:       { label: 'Weiteres Gespräch', kurz: 'Gespräch', emoji: '💬', farbe: 'var(--purple)' },
  offer:     { label: 'Angebot erhalten', kurz: 'Angebot',   emoji: '📄', farbe: 'var(--orange)' },
  accepted:  { label: 'Zusage',         kurz: 'Zusage',      emoji: '🎉', farbe: 'var(--green)', ende: true },
  rejected:  { label: 'Absage',         kurz: 'Absage',      emoji: '❌', farbe: 'var(--red)', ende: true },
  noreply:   { label: 'Keine Antwort',  kurz: 'Keine Antw.', emoji: '🕓', farbe: 'var(--sand)', ende: true },
  withdrawn: { label: 'Zurückgezogen',  kurz: 'Zurückgez.',  emoji: '↩️', farbe: 'var(--gray)', ende: true },
};

export const GESPRAECHE: Stufe[] = ['iv1', 'iv2', 'iv3', 'ivN'];

const istDatum = (v: unknown) => typeof v === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(v);
export const heute = () => new Date().toLocaleDateString('sv-SE');

/** Tag, an dem die Bewerbung wirklich rausging. Leer, solange sie nur geplant ist. */
export function losAm(b: Bewerbung): string {
  const station = b.history.find((h) => h.status === 'applied');
  if (station) return istDatum(station.date) ? station.date : (istDatum(b.applied) ? b.applied : '');
  return b.status === 'planned' ? '' : (istDatum(b.applied) ? b.applied : '');
}

/** Fremde oder alte Datensätze auf die eigene Form bringen. */
export function normalisieren(o: Partial<Bewerbung> & Record<string, unknown>): Bewerbung {
  const status: Stufe = (o.status && STUFEN[o.status as Stufe] ? o.status : 'applied') as Stufe;
  let history = Array.isArray(o.history) ? o.history.filter((h) => h && STUFEN[h.status]) : [];
  if (!history.length) history = [{ status, date: istDatum(o.applied) ? (o.applied as string) : heute() }];
  if (history[history.length - 1].status !== status) history.push({ status, date: heute() });
  const zahl = Number(o.salary);
  return {
    id: String(o.id || crypto.randomUUID()),
    company: String(o.company ?? '').trim(),
    role: String(o.role ?? '').trim(),
    salary: o.salary !== null && o.salary !== undefined && String(o.salary) !== '' && Number.isFinite(zahl) ? zahl : null,
    salaryType: String(o.salaryType ?? 'expected'),
    salaryPeriod: String(o.salaryPeriod ?? 'year'),
    employment: String(o.employment ?? ''),
    location: String(o.location ?? '').trim(),
    channel: String(o.channel ?? '').trim(),
    url: /^https?:\/\//i.test(String(o.url ?? '').trim()) ? String(o.url).trim() : '',
    applied: istDatum(o.applied) ? (o.applied as string) : '',
    deadline: istDatum(o.deadline) ? (o.deadline as string) : '',
    status,
    history,
  };
}

/* ── Auswahl und Reihenfolge ── */

export type FilterId = 'all' | 'planned' | 'applied' | 'talking' | 'accepted' | 'rejected' | 'noreply';

export const FILTER: { id: FilterId; label: string; passt: (b: Bewerbung) => boolean }[] = [
  { id: 'all',      label: 'Alle',          passt: () => true },
  { id: 'planned',  label: 'Geplant',       passt: (b) => b.status === 'planned' },
  { id: 'applied',  label: 'Beworben',      passt: (b) => b.status === 'applied' },
  { id: 'talking',  label: 'Im Gespräch',   passt: (b) => GESPRAECHE.includes(b.status) || b.status === 'offer' },
  { id: 'accepted', label: 'Zusage',        passt: (b) => b.status === 'accepted' },
  { id: 'rejected', label: 'Absage',        passt: (b) => b.status === 'rejected' },
  { id: 'noreply',  label: 'Keine Antwort', passt: (b) => b.status === 'noreply' },
];

const heuhaufen = (b: Bewerbung) =>
  [b.company, b.role, b.location, b.channel, STUFEN[b.status].label, ...b.history.map((h) => STUFEN[h.status].kurz)]
    .filter(Boolean).join(' ').toLowerCase();

export type SortKey = 'applied' | 'status' | 'company' | 'salary';

const jahresGehalt = (b: Bewerbung) =>
  b.salary == null ? -1 : b.salary * (b.salaryPeriod === 'month' ? 12 : b.salaryPeriod === 'hour' ? 1720 : 1);

const RANG = Object.keys(STUFEN) as Stufe[];

export function auswahl(
  items: Bewerbung[],
  { suche, filter, tag }: { suche: string; filter: FilterId; tag?: string },
): Bewerbung[] {
  const worte = suche.toLowerCase().split(/\s+/).filter(Boolean);
  const passtFilter = FILTER.find((f) => f.id === filter)?.passt ?? (() => true);
  return items.filter((b) => {
    if (tag && losAm(b) !== tag) return false;
    if (!passtFilter(b)) return false;
    if (!worte.length) return true;
    const h = heuhaufen(b);
    return worte.every((w) => h.includes(w));
  });
}

export function sortieren(items: Bewerbung[], key: SortKey, richtung: 1 | -1): Bewerbung[] {
  return [...items].sort((a, b) => {
    let r = 0;
    if (key === 'company') r = a.company.localeCompare(b.company, 'de');
    else if (key === 'salary') r = jahresGehalt(a) - jahresGehalt(b);
    else if (key === 'status') r = RANG.indexOf(a.status) - RANG.indexOf(b.status);
    else r = (losAm(a) || '0000').localeCompare(losAm(b) || '0000');
    return r * richtung || a.company.localeCompare(b.company, 'de');
  });
}

/** Nächste sinnvolle Gesprächsstufe für den Weiter-Knopf. */
export function naechstesGespraech(b: Bewerbung): Stufe {
  const gehabt = b.history.filter((h) => GESPRAECHE.includes(h.status)).length;
  return (['iv1', 'iv2', 'iv3'][gehabt] as Stufe) ?? 'ivN';
}

export const fmtDatum = (d: string) =>
  d ? new Date(d + 'T12:00:00').toLocaleDateString('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' }) : '';
