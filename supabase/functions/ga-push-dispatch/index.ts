import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { sendPushNotification, WebPushError, topicFromString } from "npm:@mmmike/web-push@1.3.0/send";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store"
};

const text = (v: unknown, max = 4000) => String(v ?? "").trim().slice(0, max);
const isUuid = (v: unknown) => /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v ?? ""));
const unique = <T>(items: T[]) => [...new Set(items)];

function response(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

function dateBR(v: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(v)) return v;
  const [y,m,d] = v.split("-");
  return `${d}/${m}/${y}`;
}

async function context(req: Request) {
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const auth = req.headers.get("Authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) throw Object.assign(new Error("Sessão ausente."), { status: 401 });

  const { data: userData, error: userError } = await admin.auth.getUser(token);
  const user = userData?.user;
  if (userError || !user) throw Object.assign(new Error("Sessão inválida."), { status: 401 });

  const { data: profile, error: profileError } = await admin
    .from("ga_profiles")
    .select("id,institution_id,name,role,active")
    .eq("id", user.id)
    .maybeSingle();

  if (profileError || !profile || !profile.active) {
    throw Object.assign(new Error("Perfil acadêmico inativo ou inexistente."), { status: 403 });
  }

  return { admin, user, profile };
}

async function vapidConfig(admin: any) {
  const { data, error } = await admin
    .from("ga_push_config")
    .select("vapid_public_key,vapid_private_key,vapid_subject")
    .eq("id", 1)
    .maybeSingle();
  if (error || !data?.vapid_public_key || !data?.vapid_private_key) {
    throw new Error("Configuração de push indisponível.");
  }
  return {
    publicKey: data.vapid_public_key,
    privateKey: data.vapid_private_key,
    subject: data.vapid_subject
  };
}

async function profilesFromStudents(admin: any, institutionId: string, query: any) {
  let q = admin
    .from("ga_students")
    .select("id,profile_id")
    .eq("institution_id", institutionId)
    .eq("status", "Ativo")
    .not("profile_id", "is", null);
  if (query.student_id) q = q.eq("id", query.student_id);
  if (query.class_id) q = q.eq("class_id", query.class_id);
  if (query.course_id) q = q.eq("course_id", query.course_id);
  if (Array.isArray(query.student_ids) && query.student_ids.length) q = q.in("id", query.student_ids);
  const { data, error } = await q;
  if (error) throw error;
  return unique((data || []).map((x: any) => x.profile_id).filter(Boolean));
}

async function sendToUsers(
  admin: any,
  profile: any,
  eventType: string,
  sourceId: string | null,
  title: string,
  body: string,
  userIds: string[],
  url = "./#mymessages",
  priority = "Normal"
) {
  const ids = unique(userIds.filter(isUuid));
  if (!ids.length) return { targeted_users: 0, subscriptions: 0, delivered: 0, gone: 0, failed: 0 };

  const { data: rows, error } = await admin
    .from("ga_push_subscriptions")
    .select("id,user_id,endpoint,subscription,failure_count")
    .eq("institution_id", profile.institution_id)
    .eq("active", true)
    .in("user_id", ids);
  if (error) throw error;

  const subscriptions = rows || [];
  if (!subscriptions.length) {
    return { targeted_users: ids.length, subscriptions: 0, delivered: 0, gone: 0, failed: 0 };
  }

  const vapid = await vapidConfig(admin);
  const topic = await topicFromString(`${eventType}:${sourceId || title}`);
  const urgency = priority === "Urgente" ? "high" : priority === "Importante" ? "normal" : "low";
  const tag = `ga-${eventType}-${sourceId || "notice"}`.slice(0, 64);

  let delivered = 0, gone = 0, failed = 0;
  const histories: any[] = [];

  for (let i = 0; i < subscriptions.length; i += 20) {
    const chunk = subscriptions.slice(i, i + 20);
    await Promise.all(chunk.map(async (row: any) => {
      let status = "delivered";
      let errorText: string | null = null;
      try {
        const ok = await sendPushNotification(
          row.subscription,
          { title, body, url, tag },
          vapid,
          { ttl: 86400, urgency, topic, timeoutMs: 15000 }
        );
        if (!ok) {
          status = "gone";
          gone++;
          await admin.from("ga_push_subscriptions").delete().eq("id", row.id);
        } else {
          delivered++;
          await admin.from("ga_push_subscriptions").update({
            last_success_at: new Date().toISOString(),
            last_error: null,
            failure_count: 0,
            updated_at: new Date().toISOString()
          }).eq("id", row.id);
        }
      } catch (err) {
        failed++;
        status = "failed";
        errorText = err instanceof WebPushError
          ? `HTTP ${err.statusCode}: ${text(err.message, 500)}`
          : text((err as Error)?.message || err, 500);
        await admin.from("ga_push_subscriptions").update({
          last_error: errorText,
          failure_count: Number(row.failure_count || 0) + 1,
          updated_at: new Date().toISOString()
        }).eq("id", row.id);
      }
      histories.push({
        institution_id: profile.institution_id,
        user_id: row.user_id,
        event_type: eventType,
        source_id: sourceId,
        title,
        body,
        endpoint: row.endpoint,
        status,
        error: errorText
      });
    }));
  }

  if (histories.length) await admin.from("ga_push_history").insert(histories);

  return {
    targeted_users: ids.length,
    subscriptions: subscriptions.length,
    delivered,
    gone,
    failed
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return response({ ok: false, error: "method_not_allowed" }, 405);

  try {
    const { admin, user, profile } = await context(req);
    const payload = await req.json().catch(() => ({}));
    const action = text(payload.action, 40);

    if (action === "status") {
      const [{ data: cfg }, { count }] = await Promise.all([
        admin.from("ga_push_config").select("vapid_public_key").eq("id", 1).maybeSingle(),
        admin.from("ga_push_subscriptions").select("id", { count: "exact", head: true })
          .eq("user_id", user.id).eq("active", true)
      ]);
      return response({
        ok: true,
        supported_role: profile.role === "Aluno",
        subscribed: Number(count || 0) > 0,
        subscription_count: Number(count || 0),
        vapid_public_key: cfg?.vapid_public_key || null
      });
    }

    if (action === "subscribe") {
      if (profile.role !== "Aluno") return response({ ok: false, error: "student_only" }, 403);
      const sub = payload.subscription;
      const endpoint = text(sub?.endpoint, 3000);
      const p256dh = text(sub?.keys?.p256dh, 1000);
      const auth = text(sub?.keys?.auth, 1000);
      if (!endpoint || !p256dh || !auth) return response({ ok: false, error: "invalid_subscription" }, 400);

      const row = {
        user_id: user.id,
        institution_id: profile.institution_id,
        endpoint,
        subscription: {
          endpoint,
          expirationTime: sub.expirationTime ?? null,
          keys: { p256dh, auth }
        },
        user_agent: text(payload.user_agent, 1000) || null,
        active: true,
        last_error: null,
        failure_count: 0,
        updated_at: new Date().toISOString()
      };

      const { error } = await admin.from("ga_push_subscriptions").upsert(row, { onConflict: "endpoint" });
      if (error) throw error;

      const result = await sendToUsers(
        admin, profile, "welcome", user.id,
        "Notificações da Live Connect ativadas",
        "Pronto! Você receberá avisos acadêmicos importantes neste aparelho.",
        [user.id],
        "./#mymessages",
        "Normal"
      );

      return response({ ok: true, subscribed: true, ...result });
    }

    if (action === "unsubscribe") {
      const endpoint = text(payload.endpoint, 3000);
      if (endpoint) {
        await admin.from("ga_push_subscriptions").delete().eq("user_id", user.id).eq("endpoint", endpoint);
      } else {
        await admin.from("ga_push_subscriptions").delete().eq("user_id", user.id);
      }
      return response({ ok: true, subscribed: false });
    }

    if (action === "test") {
      if (profile.role !== "Aluno") return response({ ok: false, error: "student_only" }, 403);
      const result = await sendToUsers(
        admin, profile, "test", user.id,
        "Teste de notificação",
        "Se você recebeu este aviso, as notificações da Live Connect estão funcionando.",
        [user.id],
        "./#mymessages",
        "Importante"
      );
      return response({ ok: true, ...result });
    }

    const staff = ["Direção", "Secretaria", "Professor"].includes(profile.role);
    if (!staff) return response({ ok: false, error: "staff_only" }, 403);

    if (action === "message") {
      const messageId = text(payload.message_id, 80);
      if (!isUuid(messageId)) return response({ ok: false, error: "invalid_message_id" }, 400);

      const { data: message, error } = await admin.from("ga_messages")
        .select("id,institution_id,audience,student_id,class_id,subject,body,priority,created_by,deleted_at")
        .eq("id", messageId)
        .eq("institution_id", profile.institution_id)
        .maybeSingle();
      if (error || !message || message.deleted_at) return response({ ok: false, error: "message_not_found" }, 404);
      if (profile.role === "Professor" && message.created_by !== user.id) return response({ ok: false, error: "forbidden" }, 403);
      if (profile.role === "Professor" && message.audience === "all") return response({ ok: false, error: "professor_cannot_broadcast_all" }, 403);

      let userIds: string[] = [];
      if (message.audience === "student" && message.student_id) {
        userIds = await profilesFromStudents(admin, profile.institution_id, { student_id: message.student_id });
      } else if (message.audience === "class" && message.class_id) {
        userIds = await profilesFromStudents(admin, profile.institution_id, { class_id: message.class_id });
      } else if (message.audience === "all") {
        userIds = await profilesFromStudents(admin, profile.institution_id, {});
      }

      const result = await sendToUsers(
        admin, profile, "message", message.id,
        text(message.subject, 140) || "Novo comunicado",
        text(message.body, 1000) || "Você recebeu uma nova mensagem da Live Connect.",
        userIds,
        "./#mymessages",
        message.priority || "Normal"
      );
      return response({ ok: true, ...result });
    }

    if (action === "grade") {
      const assessmentId = text(payload.assessment_id, 80);
      const studentIds = Array.isArray(payload.student_ids) ? payload.student_ids.filter(isUuid).slice(0, 500) : [];
      if (!isUuid(assessmentId) || !studentIds.length) return response({ ok: false, error: "invalid_grade_target" }, 400);

      const { data: assessment } = await admin.from("ga_assessments")
        .select("id,name,subject_id,institution_id")
        .eq("id", assessmentId).eq("institution_id", profile.institution_id).maybeSingle();
      if (!assessment) return response({ ok: false, error: "assessment_not_found" }, 404);

      let allowedStudentIds = studentIds;
      if (profile.role === "Professor") {
        const { data: ownRows } = await admin.from("ga_grades")
          .select("student_id")
          .eq("institution_id", profile.institution_id)
          .eq("assessment_id", assessmentId)
          .eq("updated_by", user.id)
          .in("student_id", studentIds);
        allowedStudentIds = unique((ownRows || []).map((x: any) => x.student_id));
      }

      const [{ data: subject }, userIds] = await Promise.all([
        admin.from("ga_subjects").select("name").eq("id", assessment.subject_id).maybeSingle(),
        profilesFromStudents(admin, profile.institution_id, { student_ids: allowedStudentIds })
      ]);

      const result = await sendToUsers(
        admin, profile, "grade", assessment.id,
        "Sua nota foi atualizada",
        `Uma nota de ${text(subject?.name || "uma disciplina", 120)} — ${text(assessment.name, 120)} foi lançada. Abra o portal para conferir.`,
        userIds,
        "./#mygrades",
        "Importante"
      );
      return response({ ok: true, ...result });
    }

    if (action === "attendance") {
      const classId = text(payload.class_id, 80);
      const classDate = text(payload.class_date, 20);
      if (!isUuid(classId) || !/^\d{4}-\d{2}-\d{2}$/.test(classDate)) {
        return response({ ok: false, error: "invalid_attendance_target" }, 400);
      }

      let q = admin.from("ga_attendance").select("student_id")
        .eq("institution_id", profile.institution_id)
        .eq("class_id", classId)
        .eq("class_date", classDate);
      if (profile.role === "Professor") q = q.eq("updated_by", user.id);
      const { data: attendanceRows, error } = await q;
      if (error) throw error;
      const studentIds = unique((attendanceRows || []).map((x: any) => x.student_id));
      const userIds = await profilesFromStudents(admin, profile.institution_id, { student_ids: studentIds });

      const result = await sendToUsers(
        admin, profile, "attendance", `${classId}:${classDate}`,
        "Frequência atualizada",
        `Sua frequência da aula de ${dateBR(classDate)} foi atualizada. Abra o portal para conferir.`,
        userIds,
        "./#myattendance",
        "Normal"
      );
      return response({ ok: true, ...result });
    }

    if (action === "material") {
      const materialId = text(payload.material_id, 80);
      if (!isUuid(materialId)) return response({ ok: false, error: "invalid_material_id" }, 400);

      const { data: material, error } = await admin.from("ga_materials")
        .select("id,institution_id,course_id,class_id,title,module_name,published_by,active")
        .eq("id", materialId)
        .eq("institution_id", profile.institution_id)
        .maybeSingle();
      if (error || !material || !material.active) return response({ ok: false, error: "material_not_found" }, 404);
      if (profile.role === "Professor" && material.published_by !== user.id) return response({ ok: false, error: "forbidden" }, 403);

      let userIds: string[] = [];
      if (material.class_id) {
        userIds = await profilesFromStudents(admin, profile.institution_id, { class_id: material.class_id });
      } else if (material.course_id) {
        userIds = await profilesFromStudents(admin, profile.institution_id, { course_id: material.course_id });
      }

      const result = await sendToUsers(
        admin, profile, "material", material.id,
        `Novo material: ${text(material.title, 120)}`,
        material.module_name ? `Novo conteúdo disponível no módulo ${text(material.module_name, 120)}.` : "Novo material disponível no seu curso.",
        userIds,
        "./#mymaterials",
        "Normal"
      );
      return response({ ok: true, ...result });
    }

    return response({ ok: false, error: "unknown_action" }, 400);
  } catch (err) {
    console.error("ga-push-dispatch", err);
    const status = Number((err as any)?.status || 500);
    return response({ ok: false, error: text((err as Error)?.message || err, 500) }, status);
  }
});