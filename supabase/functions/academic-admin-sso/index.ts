import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const LIVE_URL = "https://utfxjadpntvbrhnkghbf.supabase.co";
const LIVE_PUBLISHABLE_KEY = "sb_publishable_ZsaxQ9DDaeQ9JOSPpxO20Q_l0XwyiyC";
const LIVE_PROJECT_REF = "utfxjadpntvbrhnkghbf";
const ALLOWED_ORIGINS = new Set([
  "https://admin.liveconnectios.workers.dev",
  "https://www.liveconnect.com.br",
  "https://liveconnect.com.br",
  "http://localhost:8788",
  "http://127.0.0.1:8788"
]);

function headers(origin: string) {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.has(origin) ? origin : "https://admin.liveconnectios.workers.dev",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
    "Content-Type": "application/json; charset=utf-8"
  };
}
function reply(origin: string, body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: headers(origin) });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin") || "";
  if (req.method === "OPTIONS") {
    if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(origin, { error: "Origem não autorizada." }, 403);
    return new Response("ok", { headers: headers(origin) });
  }
  if (req.method !== "POST") return reply(origin, { error: "Método não permitido." }, 405);
  if (origin && !ALLOWED_ORIGINS.has(origin)) return reply(origin, { error: "Origem não autorizada." }, 403);

  try {
    const authorization = req.headers.get("Authorization") || "";
    if (!authorization.startsWith("Bearer ")) return reply(origin, { error: "Sessão administrativa ausente." }, 401);

    const sourceUserResponse = await fetch(`${LIVE_URL}/auth/v1/user`, {
      headers: {
        "apikey": LIVE_PUBLISHABLE_KEY,
        "Authorization": authorization,
        "Accept": "application/json"
      }
    });
    if (!sourceUserResponse.ok) return reply(origin, { error: "Sessão administrativa inválida ou expirada." }, 401);
    const sourceUser = await sourceUserResponse.json();
    if (!sourceUser?.id) return reply(origin, { error: "Usuário administrativo não identificado." }, 401);

    const sourceProfileResponse = await fetch(
      `${LIVE_URL}/rest/v1/profiles?id=eq.${encodeURIComponent(sourceUser.id)}&select=id,role,active&limit=1`,
      {
        headers: {
          "apikey": LIVE_PUBLISHABLE_KEY,
          "Authorization": authorization,
          "Accept": "application/json"
        }
      }
    );
    if (!sourceProfileResponse.ok) return reply(origin, { error: "Não foi possível validar o perfil administrativo." }, 403);
    const sourceProfiles = await sourceProfileResponse.json();
    const sourceProfile = Array.isArray(sourceProfiles) ? sourceProfiles[0] : null;
    if (!sourceProfile?.active) return reply(origin, { error: "Acesso administrativo inativo." }, 403);

    const academicUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(academicUrl, serviceRole, {
      auth: { persistSession: false, autoRefreshToken: false }
    });

    const { data: link, error: linkError } = await admin
      .from("ga_sso_links")
      .select("id,target_user_id,active")
      .eq("source_project_ref", LIVE_PROJECT_REF)
      .eq("source_user_id", sourceUser.id)
      .eq("active", true)
      .maybeSingle();

    if (linkError) return reply(origin, { error: "Falha ao consultar o vínculo acadêmico." }, 500);
    if (!link) return reply(origin, { error: "Este usuário do Admin não possui acesso acadêmico automático." }, 403);

    const { data: targetProfile, error: profileError } = await admin
      .from("ga_profiles")
      .select("id,name,role,active")
      .eq("id", link.target_user_id)
      .maybeSingle();

    if (profileError || !targetProfile) return reply(origin, { error: "Perfil acadêmico vinculado não foi localizado." }, 404);
    if (!targetProfile.active) return reply(origin, { error: "Perfil acadêmico vinculado está inativo." }, 403);

    const { data: targetUserData, error: userError } = await admin.auth.admin.getUserById(link.target_user_id);
    const targetEmail = targetUserData?.user?.email || "";
    if (userError || !targetEmail) return reply(origin, { error: "Conta acadêmica vinculada não possui e-mail de autenticação." }, 409);

    const { data: generated, error: linkGenerateError } = await admin.auth.admin.generateLink({
      type: "magiclink",
      email: targetEmail
    });

    const tokenHash = generated?.properties?.hashed_token || "";
    if (linkGenerateError || !tokenHash) return reply(origin, { error: "Não foi possível criar a sessão acadêmica automática." }, 500);

    await admin
      .from("ga_sso_links")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", link.id);

    return reply(origin, {
      ok: true,
      token_hash: tokenHash,
      verification_type: "email",
      profile: {
        id: targetProfile.id,
        name: targetProfile.name,
        role: targetProfile.role
      }
    });
  } catch (error) {
    console.error("academic-admin-sso", error);
    return reply(origin, { error: "Não foi possível concluir o acesso acadêmico automático." }, 500);
  }
});