/* Cloudflare Worker: liefert die App aus und hält den Datenbestand in KV.

   Zwei Endpunkte, mehr braucht es nicht:
     GET  /api/data  -> { rev, updated, items }
     PUT  /api/data  -> { rev, items }  (rev muss zum Serverstand passen, sonst 409)

   Der Zugriff verlangt das Token aus dem Secret TOKEN; die Seite selbst ist
   öffentlich und bleibt ohne Token leer. */

const SLOT = 'bewerbungen';
const MAX_ITEMS = 20000;

const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
  },
});

/** Vergleich in konstanter Zeit, damit das Token nicht erratbar wird. */
function tokenOk(given, expected) {
  if (!expected || !given || given.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ expected.charCodeAt(i);
  return diff === 0;
}

function tokenFrom(req) {
  const auth = req.headers.get('authorization') || '';
  return auth.startsWith('Bearer ') ? auth.slice(7) : '';
}

async function readStore(env) {
  const raw = await env.DB.get(SLOT);
  if (!raw) return { rev: 0, updated: null, items: [] };
  try {
    const data = JSON.parse(raw);
    return {
      rev: Number(data.rev) || 0,
      updated: data.updated || null,
      items: Array.isArray(data.items) ? data.items : [],
    };
  } catch {
    return { rev: 0, updated: null, items: [] };
  }
}

async function handleApi(req, env) {
  if (!tokenOk(tokenFrom(req), env.TOKEN)) return json({ error: 'unauthorized' }, 401);

  if (req.method === 'GET') return json(await readStore(env));

  if (req.method === 'PUT') {
    let body;
    try {
      body = await req.json();
    } catch {
      return json({ error: 'invalid json' }, 400);
    }
    if (!Array.isArray(body?.items)) return json({ error: 'items expected' }, 400);
    if (body.items.length > MAX_ITEMS) return json({ error: 'too many items' }, 413);

    const current = await readStore(env);
    // Schutz vor stillem Überschreiben: der Client muss den Stand kennen, den er ändert
    if (Number(body.rev) !== current.rev) return json({ error: 'conflict', ...current }, 409);

    const next = { rev: current.rev + 1, updated: new Date().toISOString(), items: body.items };
    await env.DB.put(SLOT, JSON.stringify(next));
    return json({ rev: next.rev, updated: next.updated });
  }

  return json({ error: 'method not allowed' }, 405);
}

export default {
  async fetch(req, env) {
    const { pathname } = new URL(req.url);
    if (pathname === '/api/data') return handleApi(req, env);
    if (pathname === '/api/health') return json({ ok: true });
    return env.ASSETS.fetch(req);
  },
};
