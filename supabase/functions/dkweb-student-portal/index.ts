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

function randomToken(bytes = 32): string {
  const raw = crypto.getRandomValues(new Uint8Array(bytes));
  let s = "";
  for (const b of raw) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

async function parseJson(res: Response): Promise<Record<string, unknown> | null> {
  try { return asObject(await res.json()); } catch { return null; }
}

async function rpc(name: string, payload: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_ROLE_KEY,
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  const data = await parseJson(res);
  if (!res.ok) throw new Error(`rpc_${name}`);
  return data;
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
        status: error === "ouro_identity_unavailable"
          ? 503
          : error === "ouro_identity_incomplete"
          ? 409
          : 401,
      };
    }
    const subject = String(data.subject ?? "").trim();
    const cpf = String(data.cpf ?? "").replace(/\D/g, "");
    const login = String(data.login ?? "").trim().toLowerCase();
    const validLogin = /^[a-z0-9._@-]{2,100}$/i.test(login);
    const dkId = Number(data.dk_id_aluno ?? 0);
    const dkSchool = String(data.dk_codigo_escola ?? "").trim();

    if (Number.isInteger(dkId) && dkId > 0 && dkSchool) {
      return {
        ok: true as const,
        identity: {
          subject: subject || `dk:${dkId}`,
          cpf: "",
          login: validLogin ? login : "",
          dk_id_aluno: dkId,
          dk_codigo_escola: dkSchool,
        },
      };
    }

    if (!subject || (cpf.length !== 11 && !validLogin)) {
      return { ok: false as const, status: 409 };
    }
    return {
      ok: true as const,
      identity: {
        subject: `ouro:${subject}`,
        cpf: cpf.length === 11 ? cpf : "",
        login: validLogin ? login : "",
      },
    };
  } catch {
    return { ok: false as const, status: 503 };
  } finally {
    clearTimeout(timeout);
  }
}


function academicObj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}
function academicArray(value: unknown): Record<string, unknown>[] {
  return Array.isArray(value)
    ? value.filter((item) => item && typeof item === "object" && !Array.isArray(item)) as Record<string, unknown>[]
    : [];
}
function academicClean(value: unknown): string {
  return String(value ?? "").trim();
}
function academicNorm(value: unknown): string {
  return academicClean(value)
    .toUpperCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ");
}
function academicNumber(value: unknown): number | null {
  const n = Number(academicClean(value).replace(",", "."));
  return Number.isFinite(n) ? n : null;
}
function academicValidDate(value: unknown): boolean {
  const v = academicClean(value);
  return /^\d{4}-\d{2}-\d{2}$/.test(v) && v !== "0000-00-00";
}
function academicModuleKey(row: Record<string, unknown>): string {
  return `${academicClean(row.id_aluno_curso)}|${academicClean(row.id_modulo)}`;
}
function normalizeAcademicSummary(input: Record<string, unknown>): Record<string, unknown> {
  const data: Record<string, unknown> = { ...input };
  const rawModules = academicArray(data.modules);
  const rawGrades = academicArray(data.grades);
  const moduleMap = new Map<string, Record<string, unknown>>();
  let duplicateModulesRemoved = 0;
  let derivedModules = 0;

  for (const original of rawModules) {
    const moduleId = academicClean(original.id_modulo);
    if (!moduleId) continue;
    const row = {
      ...original,
      id_modulo: moduleId,
      id_aluno_curso: academicClean(original.id_aluno_curso),
      modulo: academicClean(original.modulo),
      situacao: academicClean(original.situacao),
    };
    const key = academicModuleKey(row);
    if (moduleMap.has(key)) {
      duplicateModulesRemoved++;
      const current = moduleMap.get(key)!;
      if (!academicClean(current.modulo) && academicClean(row.modulo)) current.modulo = row.modulo;
      if (!academicClean(current.situacao) && academicClean(row.situacao)) current.situacao = row.situacao;
      continue;
    }
    moduleMap.set(key, row);
  }

  const gradeGroups = new Map<string, Record<string, unknown>[]>();
  const regularGrades: Record<string, unknown>[] = [];
  const unscopedGrades: Record<string, unknown>[] = [];
  const seenAssessments = new Set<string>();
  const mediaCandidates = new Map<string, Record<string, unknown>[]>();

  for (const original of rawGrades) {
    const row: Record<string, unknown> = {
      ...original,
      id_modulo: academicClean(original.id_modulo),
      id_aluno_curso: academicClean(original.id_aluno_curso),
      modulo: academicClean(original.modulo),
      avaliacao: academicClean(original.avaliacao),
    };
    const moduleId = academicClean(row.id_modulo);
    if (!moduleId) {
      unscopedGrades.push(row);
      continue;
    }

    const key = academicModuleKey(row);
    const rows = gradeGroups.get(key) ?? [];
    rows.push(row);
    gradeGroups.set(key, rows);

    if (academicNorm(row.avaliacao) === "MEDIA") {
      const medias = mediaCandidates.get(key) ?? [];
      medias.push(row);
      mediaCandidates.set(key, medias);
      continue;
    }

    const assessmentKey = [
      key,
      academicClean(row.id_prova) || academicNorm(row.avaliacao),
      academicClean(row.data),
      academicClean(row.nota),
    ].join("|");
    if (seenAssessments.has(assessmentKey)) continue;
    seenAssessments.add(assessmentKey);
    regularGrades.push(row);
  }

  for (const [key, rows] of gradeGroups) {
    if (moduleMap.has(key)) {
      const current = moduleMap.get(key)!;
      if (!academicClean(current.modulo)) {
        const named = rows.find((row) => academicClean(row.modulo));
        if (named) current.modulo = academicClean(named.modulo);
      }
      continue;
    }

    const first = rows.find((row) => academicClean(row.modulo)) ?? rows[0];
    const hasMedia = (mediaCandidates.get(key) ?? []).length > 0;
    moduleMap.set(key, {
      id_modulo: academicClean(first.id_modulo),
      id_aluno_curso: academicClean(first.id_aluno_curso),
      modulo: academicClean(first.modulo) || `Módulo ${academicClean(first.id_modulo)}`,
      situacao: hasMedia ? "CONCLUIDO" : "EM ANDAMENTO",
    });
    derivedModules++;
  }

  const synthesizedMedia: Record<string, unknown>[] = [];
  let duplicateMediaRemoved = 0;

  for (const [key, rows] of gradeGroups) {
    const candidates = mediaCandidates.get(key) ?? [];
    if (candidates.length > 1) duplicateMediaRemoved += candidates.length - 1;

    const assessments = regularGrades.filter((grade) => academicModuleKey(grade) === key);
    const values = assessments
      .map((grade) => academicNumber(grade.nota))
      .filter((value): value is number => value !== null);

    const base = candidates[0] ?? rows[0] ?? {};
    let media: number | null = null;
    if (values.length) {
      media = Math.round((values.reduce((sum, value) => sum + value, 0) / values.length) * 100) / 100;
    } else if (candidates.length) {
      media = academicNumber(candidates[0].nota);
    }
    if (media === null) continue;

    const dates = assessments
      .map((grade) => academicClean(grade.data))
      .filter(academicValidDate)
      .sort();

    synthesizedMedia.push({
      ...base,
      id_aluno_curso: academicClean(base.id_aluno_curso),
      id_modulo: academicClean(base.id_modulo),
      id_prova: base.id_prova ?? `media-${academicClean(base.id_modulo)}`,
      nota: media.toFixed(2),
      data: dates.length ? dates[dates.length - 1] : (academicClean(base.data) || "0000-00-00"),
      avaliacao: "MÉDIA",
      modulo: academicClean(base.modulo) || academicClean(moduleMap.get(key)?.modulo),
    });
  }

  data.modules = [...moduleMap.values()];
  data.grades = [...regularGrades, ...synthesizedMedia, ...unscopedGrades];
  data.portal_data_version = "5.10.3";
  data.academic_normalization = {
    version: "1",
    modules_raw: rawModules.length,
    modules_normalized: (data.modules as unknown[]).length,
    derived_modules: derivedModules,
    duplicate_modules_removed: duplicateModulesRemoved,
    grades_raw: rawGrades.length,
    grades_normalized: (data.grades as unknown[]).length,
    duplicate_media_removed: duplicateMediaRemoved,
  };
  return data;
}

function financeTodayBahia(): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Bahia",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const get = (type: string) => parts.find((part) => part.type === type)?.value ?? "";
  return `${get("year")}-${get("month")}-${get("day")}`;
}

function normalizeFinanceSummary(input: Record<string, unknown>): Record<string, unknown> {
  const data: Record<string, unknown> = { ...input };
  const rawFinance = academicArray(data.finance);
  const courses = academicArray(data.courses);
  const currentCourseIds = new Set(
    courses
      .map((course) => academicClean(course.id_aluno_curso))
      .filter(Boolean),
  );

  const today = financeTodayBahia();
  const seenLaunches = new Set<string>();
  const normalized: Record<string, unknown>[] = [];
  let duplicateLaunchesRemoved = 0;
  let reversedRemoved = 0;
  let otherCourseRowsRemoved = 0;

  for (const original of rawFinance) {
    const reversed = academicNorm(original.estornado) === "S";
    if (reversed) {
      reversedRemoved++;
      continue;
    }

    const courseLink = academicClean(original.id_aluno_curso);
    if (currentCourseIds.size && courseLink && !currentCourseIds.has(courseLink)) {
      otherCourseRowsRemoved++;
      continue;
    }

    const launchId = academicClean(original.numero_lancamento);
    const stableKey = launchId || [
      courseLink,
      academicClean(original.vencimento),
      academicClean(original.historico),
      academicClean(original.valor),
    ].join("|");
    if (seenLaunches.has(stableKey)) {
      duplicateLaunchesRemoved++;
      continue;
    }
    seenLaunches.add(stableKey);

    const dueDate = academicClean(original.vencimento);
    const paid = academicNorm(original.quitado) === "S";
    let portalStatus = "unknown";
    let portalStatusLabel = "A confirmar";

    if (paid) {
      portalStatus = "paid";
      portalStatusLabel = "Pago";
    } else if (academicValidDate(dueDate)) {
      if (dueDate < today) {
        portalStatus = "overdue";
        portalStatusLabel = "Vencido";
      } else if (dueDate === today) {
        portalStatus = "due_today";
        portalStatusLabel = "Vence hoje";
      } else {
        portalStatus = "upcoming";
        portalStatusLabel = "A vencer";
      }
    }

    normalized.push({
      ...original,
      id_aluno_curso: courseLink,
      numero_lancamento: launchId,
      portal_status: portalStatus,
      portal_status_label: portalStatusLabel,
      portal_is_overdue: portalStatus === "overdue",
      portal_is_upcoming: portalStatus === "upcoming",
    });
  }

  const paidRows = normalized.filter((row) => row.portal_status === "paid");
  const overdueRows = normalized.filter((row) => row.portal_status === "overdue");
  const dueTodayRows = normalized.filter((row) => row.portal_status === "due_today");
  const upcomingRows = normalized.filter((row) => row.portal_status === "upcoming");
  const unknownRows = normalized.filter((row) => row.portal_status === "unknown");

  const visibleHistory = normalized.filter((row) =>
    row.portal_status === "paid" ||
    row.portal_status === "overdue" ||
    row.portal_status === "due_today"
  );

  const sortByDueAsc = (a: Record<string, unknown>, b: Record<string, unknown>) =>
    academicClean(a.vencimento).localeCompare(academicClean(b.vencimento));

  const nextDue = [...upcomingRows].sort(sortByDueAsc)[0] ?? null;
  const oldestOverdue = [...overdueRows].sort(sortByDueAsc)[0] ?? null;

  data.finance_all = normalized;
  data.finance = visibleHistory;
  data.finance_upcoming = upcomingRows;
  data.finance_review = unknownRows;
  data.finance_summary = {
    source: "dkweb.caixa",
    as_of_date: today,
    status: overdueRows.length
      ? "overdue"
      : dueTodayRows.length
      ? "due_today"
      : "ok",
    paid_count: paidRows.length,
    overdue_count: overdueRows.length,
    due_today_count: dueTodayRows.length,
    upcoming_count: upcomingRows.length,
    review_count: unknownRows.length,
    next_due_date: nextDue ? academicClean(nextDue.vencimento) : null,
    next_due_amount: nextDue ? academicClean(nextDue.valor) : null,
    oldest_overdue_date: oldestOverdue ? academicClean(oldestOverdue.vencimento) : null,
    future_installments_are_debt: false,
  };
  data.finance_normalization = {
    version: "1",
    rows_raw: rawFinance.length,
    rows_normalized: normalized.length,
    visible_history_rows: visibleHistory.length,
    upcoming_rows: upcomingRows.length,
    reversed_rows_removed: reversedRemoved,
    duplicate_launches_removed: duplicateLaunchesRemoved,
    other_course_rows_removed: otherCourseRowsRemoved,
  };
  data.portal_data_version = "5.10.4";
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return response(405, { ok: false, error: "method_not_allowed" });
  }
  if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !BRIDGE_URL || BRIDGE_SECRET.length < 32) {
    return response(503, { ok: false, error: "dkweb_service_not_configured" });
  }

  let body: Record<string, unknown> = {};
  try {
    body = asObject(await req.json()) ?? {};
  } catch {
    return response(400, { ok: false, error: "invalid_payload" });
  }

  const action = String(body.action ?? "summary");

  if (action === "login") {
    const username = String(body.username ?? "").trim();
    const password = String(body.password ?? "");
    if (!/^\d{1,20}$/.test(username) || !/^\d{4}$/.test(password)) {
      return response(401, { ok: false, error: "invalid_credentials" });
    }

    const bridgePayload = JSON.stringify({
      action: "login",
      username,
      password,
    });
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
      const data = await parseJson(bridge);
      if (!bridge.ok || data?.ok !== true) {
        const err = String(data?.error ?? "invalid_credentials");
        return response(
          err === "ambiguous_credentials" ? 409 : 401,
          { ok: false, error: err === "ambiguous_credentials" ? err : "invalid_credentials" },
        );
      }

      const student = asObject(data.student);
      const idAluno = Number(student?.id_aluno ?? 0);
      const school = String(student?.codigo_escola ?? "").trim();
      const matricula = String(student?.matricula ?? username).trim();
      const name = String(student?.nome ?? "Aluno").trim();
      if (!Number.isInteger(idAluno) || idAluno <= 0 || !school) {
        return response(502, { ok: false, error: "student_not_resolved" });
      }

      const token = randomToken(32);
      const tokenHash = await sha256Hex(token);
      const expiresAt = new Date(Date.now() + 8 * 60 * 60 * 1000).toISOString();

      const created = await rpc("portal_student_create_session", {
        p_token_hash: tokenHash,
        p_ouro_student_id: String(idAluno),
        p_login: matricula,
        p_student_name: name,
        p_expires_at: expiresAt,
      });
      if (created?.ok !== true) {
        return response(500, { ok: false, error: "session_create_failed" });
      }

      const linked = await rpc("portal_student_link_dkweb_session", {
        p_token_hash: tokenHash,
        p_id_aluno: idAluno,
        p_codigo_escola: school,
        p_expires_at: expiresAt,
      });
      if (linked?.ok !== true) {
        return response(500, { ok: false, error: "session_link_failed" });
      }

      return response(200, {
        ok: true,
        token,
        expires_at: expiresAt,
        student: {
          id: String(idAluno),
          login: matricula,
          name,
          portal_mode: "presencial",
          provider: "dkweb",
        },
      });
    } catch {
      return response(503, { ok: false, error: "dkweb_bridge_unavailable" });
    } finally {
      clearTimeout(timeout);
    }
  }

  if (action !== "summary") {
    return response(400, { ok: false, error: "invalid_action" });
  }

  const authorization = req.headers.get("authorization") ?? "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    return response(401, { ok: false, error: "unauthorized" });
  }
  const sessionToken = authorization.slice(7).trim();
  if (sessionToken.length < 32 || sessionToken.length > 180) {
    return response(401, { ok: false, error: "unauthorized" });
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
      data = { ok: false, error: "dkweb_invalid_response" };
    }
    if (bridge.ok && data.ok === true) {
      data = normalizeAcademicSummary(data);
      data = normalizeFinanceSummary(data);
    }
    return response(bridge.status, data);
  } catch {
    return response(503, { ok: false, error: "dkweb_bridge_unavailable" });
  } finally {
    clearTimeout(timeout);
  }
});
