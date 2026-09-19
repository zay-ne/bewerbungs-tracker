import { normalisieren, type Bewerbung, type Stufe } from './model'

/** Beispieldaten für die Vorführung: die Vorführ-Auslieferung hat bewusst keine
 *  Datenablage, also kommen die Daten hier aus dem Browser. */
const muster: { firma: string; rolle: string; ort: string; kanal: string; gehalt: number | null; weg: Stufe[]; alter: number }[] = [
  { firma: 'Charité', rolle: 'Studienkoordinator', ort: 'Berlin', kanal: 'linkedin', gehalt: 52000, weg: ['applied'], alter: 34 },
  { firma: 'N26', rolle: 'Risk Analyst', ort: 'Berlin', kanal: 'website', gehalt: 58000, weg: ['applied', 'noreply'], alter: 41 },
  { firma: 'Celonis', rolle: 'Solution Engineer', ort: 'München', kanal: 'linkedin', gehalt: 65000, weg: ['applied', 'iv1'], alter: 55 },
  { firma: 'TÜV Rheinland', rolle: 'Auditor Medizinprodukte', ort: 'Köln', kanal: 'stepstone', gehalt: 61000, weg: ['applied', 'iv1', 'rejected'], alter: 62 },
  { firma: 'Personio', rolle: 'Customer Success Manager', ort: 'München', kanal: 'linkedin', gehalt: 57000, weg: ['applied', 'iv1', 'iv2'], alter: 70 },
  { firma: 'Fraunhofer', rolle: 'Wissenschaftlicher Mitarbeiter', ort: 'Stuttgart', kanal: 'email', gehalt: 54000, weg: ['applied', 'iv2'], alter: 76 },
  { firma: 'Zalando', rolle: 'Product Analyst', ort: 'Berlin', kanal: 'website', gehalt: 60000, weg: ['applied', 'rejected'], alter: 84 },
  { firma: 'Siemens Healthineers', rolle: 'Applikationsspezialist', ort: 'Erlangen', kanal: 'linkedin', gehalt: 68000, weg: ['applied', 'iv1', 'iv2', 'offer', 'accepted'], alter: 95 },
  { firma: 'Miele', rolle: 'Qualitätsingenieur', ort: 'Gütersloh', kanal: 'stepstone', gehalt: null, weg: ['planned'], alter: 3 },
]

const vorTagen = (n: number) => new Date(Date.now() - n * 86400000).toLocaleDateString('sv-SE')

export const demoDaten = (): Bewerbung[] =>
  muster.map((m, i) =>
    normalisieren({
      id: 'demo-' + i,
      company: m.firma,
      role: m.rolle,
      location: m.ort,
      channel: m.kanal,
      salary: m.gehalt,
      salaryType: 'expected',
      salaryPeriod: 'year',
      status: m.weg[m.weg.length - 1],
      applied: vorTagen(m.alter),
      history: m.weg.map((status, k) => ({ status, date: vorTagen(m.alter - k * 12) })),
      url: 'https://example.com/stelle/' + i,
      deadline: '',
      employment: '',
    }),
  )
