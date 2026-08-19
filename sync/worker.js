/* Cloudflare Worker: liefert die App aus, verwaltet Konten und je Konto einen Datensatz.

   Endpunkte
     POST /api/register  {email, key, invite}  -> Konto anlegen (Einladung nötig)
     POST /api/login     {email, key}          -> anmelden
     POST /api/logout                          -> abmelden
     GET  /api/me                              -> {email} oder 401
     GET  /api/data                            -> {rev, updated, items} des angemeldeten Kontos
     PUT  /api/data      {rev, items}          -> speichern, 409 bei überholtem Stand

   Zum Passwort: der Browser leitet aus Passwort und E-Mail per PBKDF2 (400.000 Runden)
   einen Schlüssel ab und schickt nur diesen. Der Server hängt einen kontoeigenen Zufallswert
   an und speichert davon einen SHA-256-Hash. Das Passwort im Klartext sieht der Server nie,
   und wer die Datenbank stiehlt, muss pro Rateversuch die 400.000 Runden nachrechnen.

   Sitzungen stecken in einem signierten Cookie (HMAC über Konto-ID und Ablaufzeit), damit
   keine Datenbankabfrage pro Aufruf nötig ist. Abmelden löscht das Cookie; ein gestohlenes
   Cookie bliebe bis zum Ablauf gültig – dafür ist die Laufzeit auf 30 Tage begrenzt.
*/

const SESSION_DAYS = 30;
const LEGACY_SLOT = 'bewerbungen';        // Datenbestand aus der Zeit vor den Konten
const MAX_ITEMS = 20000;
const FAILS_ALLOWED = 20;                 // Fehlversuche je Viertelstunde und Herkunft

const te = new TextEncoder();
const hex = buf => [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, '0')).join('');

const json = (data, status = 200, headers = {}) => new Response(JSON.stringify(data), {
  status,
  headers: {'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store', ...headers},
});

/* ─────────── Bausteine ─────────── */

const sha256 = async text => hex(await crypto.subtle.digest('SHA-256', te.encode(text)));

function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const randomHex = bytes => hex(crypto.getRandomValues(new Uint8Array(bytes)));

const CODE_ALPHABET = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';   // 32 Zeichen, ohne 0/O und 1/I
const newCode = () => [...crypto.getRandomValues(new Uint8Array(8))]
  .map(b => CODE_ALPHABET[b % CODE_ALPHABET.length]).join('');

async function hmac(secret, message) {
  const key = await crypto.subtle.importKey('raw', te.encode(secret), {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  return hex(await crypto.subtle.sign('HMAC', key, te.encode(message)));
}

const cleanMail = v => String(v || '').trim().toLowerCase();
/** Einladungscodes verzeihen Kleinschreibung, Bindestriche und Leerzeichen. */
const cleanCode = v => String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
const looksLikeMail = v => /^[^@\s]+@[^@\s.]+\.[^@\s]{2,}$/.test(v);

/* ─────────── Sitzung ─────────── */

async function makeCookie(env, userId, email) {
  const exp = Date.now() + SESSION_DAYS * 86400_000;
  const payload = `${userId}|${email}|${exp}`;
  const value = `${payload}|${await hmac(env.SESSION_SECRET, payload)}`;
  return `sid=${encodeURIComponent(value)}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${SESSION_DAYS * 86400}`;
}

const clearCookie = () => 'sid=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0';

async function currentUser(req, env) {
  const raw = (req.headers.get('cookie') || '')
    .split(';').map(s => s.trim()).find(s => s.startsWith('sid='));
  if (!raw) return null;
  const parts = decodeURIComponent(raw.slice(4)).split('|');
  if (parts.length !== 4) return null;
  const [userId, email, exp, sig] = parts;
  if (!sameString(sig, await hmac(env.SESSION_SECRET, `${userId}|${email}|${exp}`))) return null;
  if (Number(exp) < Date.now()) return null;
  return {id: userId, email};
}

/* ─────────── Bremse gegen Durchprobieren ─────────── */

async function tooManyFails(env, req) {
  const ip = req.headers.get('cf-connecting-ip') || 'unbekannt';
  const bucket = Math.floor(Date.now() / 900_000);
  const key = `fails:${ip}:${bucket}`;
  const count = Number(await env.DB.get(key)) || 0;
  return {over: count >= FAILS_ALLOWED, key, count};
}

async function noteFail(env, gate) {
  // Nur Fehlversuche kosten einen Schreibvorgang
  try { await env.DB.put(gate.key, String(gate.count + 1), {expirationTtl: 900}); } catch {}
}

/* ─────────── Konten ─────────── */

const userKey = mail => `user:${mail}`;
const dataKey = id => `data:${id}`;

async function readUser(env, mail) {
  const raw = await env.DB.get(userKey(mail));
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

async function checkKey(user, sentKey) {
  if (typeof sentKey !== 'string' || sentKey.length < 32 || sentKey.length > 200) return false;
  return sameString(await sha256(sentKey + ':' + user.salt), user.hash);
}

async function register(req, env) {
  const gate = await tooManyFails(env, req);
  if (gate.over) return json({error: 'too many attempts'}, 429);

  let body;
  try { body = await req.json(); } catch { return json({error: 'invalid json'}, 400); }

  const mail = cleanMail(body.email);
  const code = cleanCode(body.invite);
  const sentKey = String(body.key || '');

  if (!looksLikeMail(mail)) return json({error: 'Bitte eine gültige E-Mail-Adresse angeben.'}, 400);
  if (sentKey.length < 32) return json({error: 'Passwort zu kurz.'}, 400);
  if (!code) return json({error: 'Einladungscode fehlt.'}, 400);

  const inviteRaw = await env.DB.get(`invite:${code}`);
  if (!inviteRaw) { await noteFail(env, gate); return json({error: 'Dieser Einladungscode ist unbekannt.'}, 403); }
  let invite;
  try { invite = JSON.parse(inviteRaw); } catch { invite = {}; }
  if (invite.usedBy) return json({error: 'Dieser Einladungscode wurde schon eingelöst.'}, 403);

  if (await readUser(env, mail)) return json({error: 'Für diese Adresse gibt es schon ein Konto.'}, 409);

  const id = randomHex(16);
  const salt = randomHex(16);
  const user = {
    id, email: mail, salt,
    hash: await sha256(sentKey + ':' + salt),
    created: new Date().toISOString(),
  };
  await env.DB.put(userKey(mail), JSON.stringify(user));
  await env.DB.put(`invite:${code}`, JSON.stringify({...invite, usedBy: mail, usedAt: user.created}));

  // Das erste Konto erbt den Bestand aus der Zeit vor den Konten
  const legacy = await env.DB.get(LEGACY_SLOT);
  if (legacy) {
    await env.DB.put(dataKey(id), legacy);
    await env.DB.delete(LEGACY_SLOT);
  }

  return json({email: mail, inherited: !!legacy, admin: isAdmin(env, {email: mail})},
              200, {'set-cookie': await makeCookie(env, id, mail)});
}

async function login(req, env) {
  const gate = await tooManyFails(env, req);
  if (gate.over) return json({error: 'Zu viele Versuche. Bitte später erneut probieren.'}, 429);

  let body;
  try { body = await req.json(); } catch { return json({error: 'invalid json'}, 400); }

  const mail = cleanMail(body.email);
  const user = await readUser(env, mail);
  const ok = user && await checkKey(user, String(body.key || ''));
  if (!ok) {
    await noteFail(env, gate);
    return json({error: 'E-Mail-Adresse oder Passwort stimmt nicht.'}, 401);
  }
  return json({email: user.email, admin: isAdmin(env, {email: user.email})},
              200, {'set-cookie': await makeCookie(env, user.id, user.email)});
}

/* ─────────── Datensatz je Konto ─────────── */

async function readData(env, id) {
  const raw = await env.DB.get(dataKey(id));
  if (!raw) return {rev: 0, updated: null, items: []};
  try {
    const d = JSON.parse(raw);
    return {rev: Number(d.rev) || 0, updated: d.updated || null, items: Array.isArray(d.items) ? d.items : []};
  } catch { return {rev: 0, updated: null, items: []}; }
}

async function handleData(req, env, id) {
  if (req.method === 'GET') return json(await readData(env, id));

  if (req.method === 'PUT') {
    let body;
    try { body = await req.json(); } catch { return json({error: 'invalid json'}, 400); }
    if (!Array.isArray(body?.items)) return json({error: 'items expected'}, 400);
    if (body.items.length > MAX_ITEMS) return json({error: 'too many items'}, 413);

    const current = await readData(env, id);
    if (Number(body.rev) !== current.rev) return json({error: 'conflict', ...current}, 409);

    const next = {rev: current.rev + 1, updated: new Date().toISOString(), items: body.items};
    await env.DB.put(dataKey(id), JSON.stringify(next));
    return json({rev: next.rev, updated: next.updated});
  }
  return json({error: 'method not allowed'}, 405);
}

/* ─────────── Einladungen (nur Hauptkonto) ─────────── */

/** Hauptkonten: eine oder mehrere Adressen, mit Komma getrennt. */
const isAdmin = (env, me) => String(env.ADMIN_EMAIL || '')
  .split(',').map(cleanMail).filter(Boolean).includes(me.email);

async function handleInvites(req, env, me) {
  if (!isAdmin(env, me)) return json({error: 'forbidden'}, 403);

  if (req.method === 'GET') {
    const {keys} = await env.DB.list({prefix: 'invite:'});
    const rows = await Promise.all(keys.map(async k => {
      let d = {};
      try { d = JSON.parse(await env.DB.get(k.name) || '{}'); } catch {}
      return {code: k.name.slice(7), usedBy: d.usedBy || null, usedAt: d.usedAt || null};
    }));
    // Freie Codes zuerst, danach die eingelösten
    rows.sort((a, b) => (a.usedBy ? 1 : 0) - (b.usedBy ? 1 : 0) || a.code.localeCompare(b.code));
    return json({invites: rows});
  }

  if (req.method === 'POST') {
    const code = newCode();
    await env.DB.put(`invite:${code}`,
      JSON.stringify({note: 'in der App erzeugt', created: new Date().toISOString()}));
    return json({code});
  }

  if (req.method === 'DELETE') {
    const code = cleanCode(new URL(req.url).searchParams.get('code'));
    if (!code) return json({error: 'code fehlt'}, 400);
    const raw = await env.DB.get(`invite:${code}`);
    if (!raw) return json({error: 'unbekannt'}, 404);
    let d = {};
    try { d = JSON.parse(raw); } catch {}
    if (d.usedBy) return json({error: 'schon eingelöst'}, 409);
    await env.DB.delete(`invite:${code}`);
    return json({ok: true});
  }

  return json({error: 'method not allowed'}, 405);
}

/* ─────────── Verteiler ─────────── */

/** Die Oberfläche darf nicht im Cache festhängen, sonst laufen Geräte auf einer alten Fassung. */
async function serveAsset(req, env) {
  const res = await env.ASSETS.fetch(req);
  const type = res.headers.get('content-type') || '';
  if (!type.includes('text/html')) return res;
  const fresh = new Response(res.body, res);
  fresh.headers.set('cache-control', 'no-store, must-revalidate');
  return fresh;
}

/** Für die Fehlersuche: nur Weg und Antwortcode, keine Inhalte. */
async function watched(name, promise) {
  const res = await promise;
  console.log(`${name} -> ${res.status}`);
  return res;
}

export default {
  async fetch(req, env) {
    const {pathname} = new URL(req.url);
    if (!pathname.startsWith('/api/')) return serveAsset(req, env);

    if (pathname === '/api/health') return json({ok: true});

    // Reine Vorführ-Auslieferung: kein Konto, keine Ablage, nichts zu holen
    if (env.DEMO_ONLY) {
      return pathname === '/api/me' ? json({demo: true}) : json({error: 'demo only'}, 403);
    }
    if (pathname === '/api/register' && req.method === 'POST') return watched('register', register(req, env));
    if (pathname === '/api/login' && req.method === 'POST') return watched('login', login(req, env));
    if (pathname === '/api/logout') return json({ok: true}, 200, {'set-cookie': clearCookie()});

    const me = await currentUser(req, env);
    if (!me) return json({error: 'unauthorized'}, 401);

    if (pathname === '/api/me') return json({email: me.email, admin: isAdmin(env, me)});
    if (pathname === '/api/data') return handleData(req, env, me.id);
    if (pathname === '/api/invites') return handleInvites(req, env, me);

    return json({error: 'not found'}, 404);
  },
};
