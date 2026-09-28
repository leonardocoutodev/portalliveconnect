import { createClient } from "npm:@supabase/supabase-js@2.57.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const rawSecrets = Deno.env.get("SUPABASE_SECRET_KEYS");
const SERVICE_KEY = rawSecrets ? JSON.parse(rawSecrets)["default"] : Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BRIDGE = SUPABASE_URL + "/functions/v1/liveconnect-pagbank-bridge";

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }
});
const money = (v: unknown) => Math.round(Number(v || 0) * 100) / 100;
const uuid = (v: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v || "")) ? String(v) : "";

function mappedStatus(status: string) {
  const s = String(status || "").toUpperCase();
  if (s === "PAID") return "approved";
  if (s === "CANCELED" || s === "CANCELLED") return "cancelled";
  if (s === "DECLINED") return "rejected";
  return "pending";
}
function mappedMethod(charge: any) {
  const t = String(charge?.payment_method?.type || "").toUpperCase();
  if (t === "PIX") return "pix";
  if (t === "BOLETO") return "boleto";
  if (t === "DEBIT_CARD") return "debito";
  if (t === "CREDIT_CARD") return "credito";
  return null;
}
async function verifiedLookup(id: string) {
  const r = await fetch(BRIDGE, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action: "lookup", id })
  });
  const data = await r.json().catch(() => ({}));
  if (!r.ok || !data?.ok) throw new Error(data?.error || "provider_lookup_failed");
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ ok: true, provider: "pagbank", webhook: true });

  const body: any = await req.json().catch(() => ({}));
  const rawId = String(body?.id || req.headers.get("x-product-id") || "").trim();
  if (!/^(CHEC|ORDE|CHAR)_[A-Z0-9-]+$/i.test(rawId)) return json({ ok: true, ignored: true });

  try {
    const verified = await verifiedLookup(rawId);
    const data: any = verified.data || {};
    const supabase = createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });

    let reference = uuid(data?.reference_id || body?.reference_id);
    let checkoutId = /^CHEC_/i.test(rawId) ? rawId : null;
    let charge: any = null;

    if (verified.kind === "order") {
      const charges = Array.isArray(data?.charges) ? data.charges : [];
      charge = charges.find((c: any) => String(c?.status || "").toUpperCase() === "PAID") || charges[0] || null;
    } else if (verified.kind === "charge") {
      charge = data;
      // A charge does not reliably carry the portal token. We only process it when the
      // signed provider response itself has a UUID reference. Otherwise wait for ORDER webhook.
    } else if (verified.kind === "checkout") {
      checkoutId = String(data?.id || rawId);
      const payments = Array.isArray(data?.payments) ? data.payments : [];
      const p = payments.find((x: any) => String(x?.status || "").toUpperCase() === "PAID") || payments[0] || null;
      if (p?.id && /^ORDE_/i.test(String(p.id))) {
        const orderVerified = await verifiedLookup(String(p.id));
        const order = orderVerified.data || {};
        reference = uuid(order?.reference_id || reference);
        const charges = Array.isArray(order?.charges) ? order.charges : [];
        charge = charges.find((c: any) => String(c?.status || "").toUpperCase() === "PAID") || charges[0] || null;
      }
    }

    let session: any = null;
    if (reference) {
      const q = await supabase.from("payment_checkout_sessions").select("*").eq("public_token", reference).maybeSingle();
      session = q.data;
    }
    if (!session && checkoutId) {
      const q = await supabase.from("payment_checkout_sessions").select("*").eq("provider", "pagbank").eq("provider_checkout_id", checkoutId).maybeSingle();
      session = q.data;
    }
    if (!session) return json({ ok: true, ignored: true, reason: "session_not_found" });

    const providerStatus = String(charge?.status || data?.status || body?.status || "");
    const status = mappedStatus(providerStatus);
    const wasApproved = session.status === "approved";
    const paidAt = status === "approved" ? (charge?.paid_at || new Date().toISOString()) : null;
    const chargeId = charge?.id ? String(charge.id) : (/^CHAR_/i.test(rawId) ? rawId : null);
    const orderId = verified.kind === "order" ? String(data?.id || rawId) : null;
    const amountCents = Number(charge?.amount?.value || 0);
    const expectedCents = Math.round(Number(session.amount || 0) * 100);
    const currency = String(charge?.amount?.currency || "BRL");

    if (status === "approved" && (amountCents !== expectedCents || currency !== "BRL")) {
      await supabase.from("payment_checkout_sessions").update({
        status: "error",
        provider: "pagbank",
        provider_payment_id: chargeId || orderId,
        metadata: { ...(session.metadata || {}), provider_error: "amount_mismatch", provider_amount_cents: amountCents, provider_currency: currency },
        updated_at: new Date().toISOString()
      }).eq("id", session.id);
      return json({ ok: false, error: "amount_mismatch" }, 409);
    }

    await supabase.from("payment_checkout_sessions").update({
      provider: "pagbank",
      provider_checkout_id: checkoutId || session.provider_checkout_id || null,
      provider_payment_id: chargeId || orderId || session.provider_payment_id || null,
      status,
      paid_at: paidAt,
      metadata: {
        ...(session.metadata || {}),
        provider: "pagbank",
        provider_status: providerStatus || null,
        provider_order_id: orderId,
        provider_charge_id: chargeId,
        provider_verified_at: new Date().toISOString()
      },
      updated_at: new Date().toISOString()
    }).eq("id", session.id);

    const paymentIds = Array.isArray(session?.metadata?.payment_ids) ? session.metadata.payment_ids.map(String) : [];
    const method = mappedMethod(charge);
    if (paymentIds.length && charge) {
      const common: any = {
        provider: "pagbank",
        provider_payment_id: chargeId || orderId,
        provider_status: providerStatus,
        provider_updated_at: new Date().toISOString(),
        provider_metadata: {
          order_id: orderId,
          checkout_id: checkoutId || session.provider_checkout_id || null,
          payment_method: charge?.payment_method?.type || null,
          payment_response: charge?.payment_response || null
        }
      };
      if (status === "approved") Object.assign(common, { status: "pago", paid_at: paidAt, method });
      await supabase.from("payments").update(common).in("id", paymentIds);
    }

    if (status === "approved") {
      const { data: enrollment } = await supabase.from("enrollments").select("commercial_mode,course_id").eq("id", session.enrollment_id).maybeSingle();
      const fast = enrollment?.commercial_mode === "profissao_rapida";
      if (fast) {
        await supabase.from("enrollments").update({
          enrollment_payment_status: "pago",
          first_month_payment_status: "isento",
          payment_method: method || "credito"
        }).eq("id", session.enrollment_id);
      } else {
        const { data: rows } = await supabase.from("payments").select("kind,status,method").eq("enrollment_id", session.enrollment_id).in("kind", ["matricula", "primeira_mensalidade"]);
        const matricula = (rows || []).find((p: any) => p.kind === "matricula");
        const first = (rows || []).find((p: any) => p.kind === "primeira_mensalidade");
        await supabase.from("enrollments").update({
          enrollment_payment_status: matricula?.status || "pendente",
          first_month_payment_status: first?.status || "pendente",
          payment_method: method || matricula?.method || first?.method || null
        }).eq("id", session.enrollment_id);
      }

      const courseId = String(enrollment?.course_id || session?.metadata?.course_id || "");
      let queueStatus = "";
      if (courseId) {
        const { data: q } = await supabase.from("portal_enrollment_queue").select("status").eq("lead_id", session.lead_id).eq("course_id", courseId).order("updated_at", { ascending: false }).limit(1).maybeSingle();
        queueStatus = String(q?.status || "");
      }
      const completed = ["matriculada_ouro", "matriculada_manual"].includes(queueStatus);
      await supabase.from("leads").update({ status: completed ? "matricula_confirmada" : "pre_inscricao", archived: false, updated_at: new Date().toISOString() }).eq("id", session.lead_id);

      if (!wasApproved) {
        await supabase.from("lead_activities").insert({
          lead_id: session.lead_id,
          activity_type: "pagamento_portal_aprovado",
          description: "Pagamento online aprovado — R$ " + money(session.amount).toFixed(2).replace(".", ","),
          metadata: {
            checkout_session_id: session.id,
            enrollment_id: session.enrollment_id,
            commercial_mode: enrollment?.commercial_mode || "tradicional",
            provider: "pagbank",
            provider_payment_id: chargeId || orderId,
            amount: Number(session.amount),
            method: method || null
          }
        });
      }
    }

    return json({ ok: true, provider: "pagbank", status });
  } catch (error) {
    console.error("pagbank-portal-webhook", error);
    return json({ ok: false, error: "provider_verification_failed" }, 502);
  }
});