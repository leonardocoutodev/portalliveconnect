import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const rawSecrets = Deno.env.get("SUPABASE_SECRET_KEYS");
const SERVICE_KEY = rawSecrets ? JSON.parse(rawSecrets)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const PAGBANK_TOKEN = Deno.env.get("PAGBANK_TOKEN") || "";
const PAGBANK_ENV = (Deno.env.get("PAGBANK_ENV") || "sandbox").toLowerCase();
const API_BASE = PAGBANK_ENV === "production" ? "https://api.pagseguro.com" : "https://sandbox.api.pagseguro.com";
const WEBHOOK_URL = SUPABASE_URL + "/functions/v1/pagbank-portal-webhook";
const PORTAL_ORIGIN = "https://www.liveconnect.com.br";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "content-type, apikey, x-client-info"
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...cors }
});
const uuid = (v: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v || "")) ? String(v) : "";
const cents = (v: unknown) => Math.round(Number(v || 0) * 100);
const safeName = (v: unknown) => String(v || "Formação Live Connect").replace(/[<>]/g, "").slice(0, 80);

async function provider(path: string, init: RequestInit = {}) {
  if (!PAGBANK_TOKEN) throw new Error("pagbank_not_configured");
  const response = await fetch(API_BASE + path, {
    ...init,
    headers: {
      Authorization: "Bearer " + PAGBANK_TOKEN,
      Accept: "application/json",
      ...(init.body ? { "Content-Type": "application/json" } : {}),
      ...(init.headers || {})
    }
  });
  const raw = await response.text();
  let data: any = {};
  try { data = raw ? JSON.parse(raw) : {}; } catch { data = { raw }; }
  if (!response.ok) {
    const e: any = new Error(data?.error_messages?.[0]?.description || data?.message || data?.error || ("pagbank_http_" + response.status));
    e.status = response.status;
    e.data = data;
    throw e;
  }
  return data;
}

async function context(token: string) {
  const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await supabase.rpc("portal_payment_bridge_context", { p_token: token });
  if (error || !data?.ok) throw new Error(data?.error || error?.message || "payment_context_not_found");
  return data;
}

function payLink(data: any) {
  return (Array.isArray(data?.links) ? data.links : []).find((x: any) => String(x?.rel || "").toUpperCase() === "PAY")?.href || null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method === "GET") {
    return json({ ok: true, provider: "pagbank", environment: PAGBANK_ENV, configured: !!PAGBANK_TOKEN });
  }
  if (req.method !== "POST") return json({ ok: false, error: "method_not_allowed" }, 405);

  try {
    const body = await req.json().catch(() => ({}));
    const action = String(body.action || "");

    if (action === "health") {
      if (!PAGBANK_TOKEN) return json({ ok: true, provider: "pagbank", environment: PAGBANK_ENV, configured: false });
      try {
        await provider("/checkouts/CHEC_00000000-0000-0000-0000-000000000000");
        return json({ ok: true, provider: "pagbank", environment: PAGBANK_ENV, configured: true, authenticated: true });
      } catch (e: any) {
        const status = Number(e?.status || 0);
        const authenticated = status === 400 || status === 404;
        return json({ ok: authenticated, provider: "pagbank", environment: PAGBANK_ENV, configured: true, authenticated, provider_status: status || null }, authenticated ? 200 : 502);
      }
    }

    if (action === "create") {
      const token = uuid(body.token);
      if (!token) return json({ ok: false, error: "invalid_token" }, 400);
      const c = await context(token);
      const amount = cents(c.amount);
      if (amount <= 0) return json({ ok: false, error: "nothing_to_pay" }, 409);

      const fast = String(c.commercial_mode || "") === "profissao_rapida";
      const installments = Math.max(1, Math.min(12, Number(c.installments || 1)));
      const backBase = PORTAL_ORIGIN + "/pagamento/?token=" + encodeURIComponent(token);

      const payload: any = {
        reference_id: token,
        customer: {
          name: safeName(c.customer_name || c.lead_name || "Aluno Live Connect"),
          email: String(c.customer_email || c.lead_email || "").trim()
        },
        customer_modifiable: true,
        items: [{
          reference_id: "LC-" + token.slice(0, 18),
          name: safeName(c.course_name),
          quantity: 1,
          unit_amount: amount
        }],
        payment_methods: fast
          ? [{ type: "CREDIT_CARD" }]
          : [{ type: "PIX" }, { type: "BOLETO" }, { type: "CREDIT_CARD" }],
        payment_methods_configs: [{
          type: "CREDIT_CARD",
          config_options: [{ option: "INSTALLMENTS_LIMIT", value: String(installments) }]
        }],
        redirect_url: backBase + "&return=success",
        return_url: backBase,
        redirect_waiting_time: 5,
        notification_urls: [WEBHOOK_URL],
        payment_notification_urls: [WEBHOOK_URL]
      };

      if (!payload.customer.email) delete payload.customer;
      const data = await provider("/checkouts", { method: "POST", body: JSON.stringify(payload) });
      const href = payLink(data);
      if (!data?.id || !href) return json({ ok: false, error: "pagbank_checkout_invalid_response" }, 502);
      return json({ ok: true, provider: "pagbank", id: String(data.id), init_point: href, checkout_url: href, environment: PAGBANK_ENV });
    }

    if (action === "lookup") {
      const id = String(body.id || "").trim();
      if (/^CHEC_/i.test(id)) {
        const data = await provider("/checkouts/" + encodeURIComponent(id));
        return json({ ok: true, provider: "pagbank", kind: "checkout", data });
      }
      if (/^ORDE_/i.test(id)) {
        const data = await provider("/orders/" + encodeURIComponent(id));
        return json({ ok: true, provider: "pagbank", kind: "order", data });
      }
      if (/^CHAR_/i.test(id)) {
        const data = await provider("/charges/" + encodeURIComponent(id));
        return json({ ok: true, provider: "pagbank", kind: "charge", data });
      }
      return json({ ok: false, error: "invalid_provider_id" }, 400);
    }

    return json({ ok: false, error: "invalid_action" }, 400);
  } catch (e: any) {
    console.error("liveconnect-pagbank-bridge", e);
    const message = e instanceof Error ? e.message : String(e);
    return json({ ok: false, error: message === "pagbank_not_configured" ? message : "provider_error", message }, message === "pagbank_not_configured" ? 503 : 502);
  }
});