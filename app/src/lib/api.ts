/** Dieselben acht Endpunkte wie bisher. Der Worker bleibt unangetastet. */

import { normalisieren, type Bewerbung } from './model';

export type Konto = { email: string; plan: 'free' | 'pro'; limit: number; admin: boolean } | null;
export type Stand = { rev: number; items: Bewerbung[]; updated?: string };

const json = async (weg: string, init?: RequestInit) => {
  const res = await fetch(weg, { ...init, headers: { 'content-type': 'application/json', ...init?.headers } });
  return { ok: res.ok, status: res.status, daten: await res.json().catch(() => ({})) };
};

export async function werBinIch(): Promise<{ konto: Konto; demo: boolean } | 'offline'> {
  try {
    const { ok, daten } = await json('/api/me');
    if ((daten as { demo?: boolean }).demo) return { konto: null, demo: true };
    return { konto: ok ? (daten as NonNullable<Konto>) : null, demo: false };
  } catch {
    return 'offline';
  }
}

export async function holen(): Promise<Stand> {
  const { daten } = await json('/api/data');
  const d = daten as { rev?: number; items?: unknown[]; updated?: string };
  return { rev: d.rev ?? 0, updated: d.updated, items: (d.items ?? []).map((x) => normalisieren(x as Bewerbung)) };
}

/** Schreibt mit Revisionsnummer: 409 heißt fremder Stand, 402 heißt Grenze erreicht. */
export async function speichern(rev: number, items: Bewerbung[]) {
  const { ok, status, daten } = await json('/api/data', { method: 'PUT', body: JSON.stringify({ rev, items }) });
  return { ok, status, daten: daten as { rev?: number; updated?: string; items?: unknown[] } };
}

export const anmelden = (email: string, key: string) =>
  json('/api/login', { method: 'POST', body: JSON.stringify({ email, key }) });

export const abmelden = () => json('/api/logout', { method: 'POST' });

/** Passwort niemals im Klartext senden: der Browser rechnet daraus einen Schlüssel. */
export async function schluessel(email: string, passwort: string) {
  const basis = await crypto.subtle.importKey('raw', new TextEncoder().encode(passwort), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: new TextEncoder().encode('bewerbungen|' + email), iterations: 400000, hash: 'SHA-256' },
    basis, 256,
  );
  return [...new Uint8Array(bits)].map((b) => b.toString(16).padStart(2, '0')).join('');
}
