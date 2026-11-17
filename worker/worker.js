// Mon compte — sauvegarde en ligne (Cloudflare Worker + KV)
// Liaisons à ajouter dans Cloudflare :
//   - KV namespace  -> nom de variable : DATA   (base « mon-compte-data »)
//   - Secret        -> nom : PASSWORD           (ton mot de passe)
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
  "Access-Control-Allow-Headers": "Authorization,Content-Type",
  "Cache-Control": "no-store",
};
const json = (o, status = 200) =>
  new Response(JSON.stringify(o), { status, headers: { ...CORS, "Content-Type": "application/json" } });

function same(a, b) {
  if (typeof a !== "string" || typeof b !== "string" || a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    const url = new URL(req.url);
    if (url.pathname !== "/data") return json({ ok: true, app: "mon-compte" });
    if (!env.DATA || !env.PASSWORD) return json({ error: "Worker mal configuré (DATA ou PASSWORD manquant)" }, 500);
    const auth = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!same(auth, env.PASSWORD)) return json({ error: "Mot de passe incorrect" }, 401);

    if (req.method === "GET") {
      const cur = await env.DATA.get("data");
      return json(cur ? JSON.parse(cur) : { empty: true });
    }
    if (req.method === "PUT") {
      let body;
      try { body = await req.json(); } catch { return json({ error: "JSON invalide" }, 400); }
      if (!body || typeof body !== "object" || !body.data || typeof body.u !== "number")
        return json({ error: "Format invalide" }, 400);
      const prev = await env.DATA.get("data");
      if (prev) await env.DATA.put("data-prev", prev); // garde toujours la version d'avant
      await env.DATA.put("data", JSON.stringify({ u: body.u, data: body.data }));
      return json({ ok: true, u: body.u });
    }
    return json({ error: "Méthode non autorisée" }, 405);
  },
};
