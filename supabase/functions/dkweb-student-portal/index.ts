import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const BRIDGE_URL = Deno.env.get("DKWEB_BRIDGE_URL") ?? "";
const BRIDGE_SECRET = Deno.env.get("DKWEB_BRIDGE_SECRET") ?? "";

const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store, max-age=0",
  "X-Content-Type-Options": "nosniff",
};

function response(status: number, payload: Record<string, unknown>) {
  return new Response(JSON.stringify(payload), { status, headers: jsonHeaders });
}

function asObject(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

async function hmacHex(secret: string, message: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(message));
  return Array.from(new Uint8Array(signature))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function ouroIdentity(sessionToken: string) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const tokenHash = await sha256Hex(sessionToken);
    const result = await fetch(`${SUPABASE_URL}/rest/v1/rpc/portal_student_dkweb_identity`, {
      method: "POST",
      headers: {
        apikey: SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ p_token_hash: tokenHash }),
      signal: controller.signal,
    });
    let data: Record<string, unknown> | null = null;
    try {
      data = asObject(await result.json());
    } catch {
      data = null;
    }
    if (!result.ok || data?.ok !== true) {
      const error = String(data?.error ?? "");
      return {
        ok: false as const,
        status: error === "ouro_identity_unavailable" ? 503 : 401,
      };
    }
    const subject = String(data.subject ?? "").trim();
    const cpf = String(data.cpf ?? "").replace(/\D/g, "");
    if (!subject || cpf.length !== 11) {
      return { ok: false as const, status: 409 };
    }
    return { ok: true as const, identity: { subject: `ouro:${subject}`, cpf } };
  } catch {
    return { ok: false as const, status: 503 };
  } finally {
    clearTimeout(timeout);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return response(405, { ok: false, error: "method_not_allowed" });
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !BRIDGE_URL || BRIDGE_SECRET.length < 32) {
    return response(503, { ok: false, error: "dkweb_service_not_configured" });
  }
  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return response(401, { ok: false, error: "unauthorized" });
  }
  const sessionToken = authorization.slice(7).trim();
  if (sessionToken.length < 32 || sessionToken.length > 180) {
    return response(401, { ok: false, error: "unauthorized" });
  }
  let body: Record<string, unknown> = {};
  try {
    body = asObject(await req.json()) ?? {};
  } catch {
    return response(400, { ok: false, error: "invalid_payload" });
  }
  if ((body.action ?? "summary") !== "summary") {
    return response(400, { ok: false, error: "invalid_action" });
  }

  const ouro = await ouroIdentity(sessionToken);
  if (!ouro.ok) {
    const status = ouro.status === 503 ? 503 : ouro.status === 409 ? 409 : 401;
    return response(status, {
      ok: false,
      error: status === 503
        ? "ouro_service_unavailable"
        : status === 409
        ? "ouro_identity_incomplete"
        : "ouro_session_invalid",
    });
  }

  const bridgePayload = JSON.stringify({ action: "summary", identity: ouro.identity });
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const signature = await hmacHex(BRIDGE_SECRET, `${timestamp}.${bridgePayload}`);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 12_000);
  try {
    const bridge = await fetch(BRIDGE_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-LC-Timestamp": timestamp,
        "X-LC-Signature": signature,
      },
      body: bridgePayload,
      signal: controller.signal,
    });
    const text = await bridge.text();
    let data: Record<string, unknown> = { ok: false, error: "dkweb_invalid_response" };
    try {
      data = asObject(JSON.parse(text)) ?? data;
    } catch {
      // A resposta bruta nunca é devolvida para não vazar detalhes do servidor.
    }
    return response(bridge.status, data);
  } catch {
    return response(503, { ok: false, error: "dkweb_bridge_unavailable" });
  } finally {
    clearTimeout(timeout);
  }
});
