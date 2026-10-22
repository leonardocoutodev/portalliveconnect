import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const ALLOWED_ORIGINS = new Set([
  "https://www.liveconnect.com.br",
  "https://liveconnect.com.br",
  "https://portallc.netlify.app",
]);

function cors(origin: string | null) {
  const allowed = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://www.liveconnect.com.br";
  return {
    "Access-Control-Allow-Origin": allowed,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-client-info",
    "Vary": "Origin",
  };
}

function json(body: unknown, status = 200, origin: string | null = null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...cors(origin),
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "public, max-age=300, s-maxage=300",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function secretKey() {
  const modern = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modern) {
    try {
      const parsed = JSON.parse(modern);
      if (parsed?.default) return String(parsed.default);
    } catch {}
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function money(v: number) {
  return Math.round((v + Number.EPSILON) * 100) / 100;
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors(origin) });
  if (req.method !== "GET") return json({ ok: false, error: "method_not_allowed" }, 405, origin);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const key = secretKey();
    if (!supabaseUrl || !key) {
      return json({ ok: false, error: "catalog_not_configured" }, 503, origin);
    }

    const admin = createClient(supabaseUrl, key, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const [
      settingsResult,
      formationsResult,
      mappingsResult,
      ouroResult,
    ] = await Promise.all([
      admin
        .from("portal_ead_pricing_settings")
        .select("hourly_rate,active,updated_at")
        .eq("id", 1)
        .maybeSingle(),
      admin
        .from("portal_formation_catalog")
        .select("formation_slug,formation_name,portal_workload_hours,portal_duration_months,updated_at")
        .order("formation_name"),
      admin
        .from("portal_formation_module_ouro_map")
        .select("formation_slug,module_order,portal_module_name,ouro_course_id,mapped_ouro_name,mapped_workload_hours,mapped_lessons")
        .order("formation_slug")
        .order("module_order"),
      admin
        .from("ouro_course_catalog_cache")
        .select("ouro_course_id,name,lessons,workload_hours,module_group,description,synced_at"),
    ]);

    if (settingsResult.error) throw settingsResult.error;
    if (formationsResult.error) throw formationsResult.error;
    if (mappingsResult.error) throw mappingsResult.error;
    if (ouroResult.error) throw ouroResult.error;

    const setting = settingsResult.data;
    if (!setting?.active) {
      return json({ ok: false, error: "ead_catalog_disabled" }, 503, origin);
    }

    const hourlyRate = Number(setting.hourly_rate ?? 15);
    const ouroById = new Map(
      (ouroResult.data ?? []).map((x: any) => [String(x.ouro_course_id), x])
    );

    const mappingByFormation = new Map<string, any[]>();
    for (const row of mappingsResult.data ?? []) {
      const slug = String(row.formation_slug);
      if (!mappingByFormation.has(slug)) mappingByFormation.set(slug, []);
      mappingByFormation.get(slug)!.push(row);
    }

    const uniqueModules = new Map<string, any>();
    const formations = (formationsResult.data ?? []).map((formation: any) => {
      const rows = (mappingByFormation.get(String(formation.formation_slug)) ?? [])
        .sort((a, b) => Number(a.module_order) - Number(b.module_order));

      let mappedHours = 0;
      let missingModules = 0;

      const modules = rows.map((row: any) => {
        const id = row.ouro_course_id ? String(row.ouro_course_id) : null;
        const ouro = id ? ouroById.get(id) : null;
        const hoursRaw = row.mapped_workload_hours ?? ouro?.workload_hours ?? null;
        const lessonsRaw = row.mapped_lessons ?? ouro?.lessons ?? null;
        const hours = hoursRaw == null ? null : Number(hoursRaw);
        const lessons = lessonsRaw == null ? null : Number(lessonsRaw);
        const confirmed = Boolean(id && hours && hours > 0);
        const price = confirmed ? money(hours! * hourlyRate) : null;

        if (confirmed) mappedHours += hours!;
        else missingModules += 1;

        const item = {
          ouro_course_id: id,
          order: Number(row.module_order),
          name: String(row.portal_module_name ?? row.mapped_ouro_name ?? ouro?.name ?? ""),
          ouro_name: String(row.mapped_ouro_name ?? ouro?.name ?? ""),
          lessons,
          workload_hours: hours,
          price,
          confirmed,
          description: String(ouro?.description ?? ""),
        };

        if (confirmed && id) {
          const existing = uniqueModules.get(id);
          if (!existing) {
            uniqueModules.set(id, {
              ouro_course_id: id,
              name: item.name,
              ouro_name: item.ouro_name,
              lessons,
              workload_hours: hours,
              price,
              description: item.description,
              module_group: ouro?.module_group ?? null,
              formation_slugs: [String(formation.formation_slug)],
              formation_names: [String(formation.formation_name)],
            });
          } else {
            if (!existing.formation_slugs.includes(String(formation.formation_slug))) {
              existing.formation_slugs.push(String(formation.formation_slug));
              existing.formation_names.push(String(formation.formation_name));
            }
          }
        }

        return item;
      });

      const availableEad = rows.length > 0 && missingModules === 0;
      const actualHours = availableEad ? money(mappedHours) : null;
      const fullPrice = availableEad ? money(mappedHours * hourlyRate) : null;

      return {
        slug: String(formation.formation_slug),
        name: String(formation.formation_name),
        listed_workload_hours: formation.portal_workload_hours == null
          ? null
          : Number(formation.portal_workload_hours),
        ead_workload_hours: actualHours,
        duration_months_reference: formation.portal_duration_months == null
          ? null
          : Number(formation.portal_duration_months),
        module_count: rows.length,
        confirmed_module_count: rows.length - missingModules,
        missing_module_count: missingModules,
        available_ead: availableEad,
        price: fullPrice,
        modules,
      };
    });

    const modules = [...uniqueModules.values()]
      .sort((a, b) => String(a.name).localeCompare(String(b.name), "pt-BR"));

    const availableFormations = formations.filter((x: any) => x.available_ead).length;

    return json({
      ok: true,
      currency: "BRL",
      hourly_rate: hourlyRate,
      pricing_rule: "workload_hours_x_hourly_rate",
      full_course_rule: "sum_confirmed_ouro_module_hours_x_hourly_rate",
      module_rule: "ouro_module_workload_hours_x_hourly_rate",
      stats: {
        formations_total: formations.length,
        formations_priced: availableFormations,
        formations_pending_mapping: formations.length - availableFormations,
        unique_modules_priced: modules.length,
      },
      formations,
      modules,
      generated_at: new Date().toISOString(),
      source: "Live Connect + Ouro Moderno",
    }, 200, origin);
  } catch (error) {
    console.error("portal-ead-catalog", error);
    return json(
      { ok: false, error: "catalog_load_failed" },
      500,
      origin
    );
  }
});