export type JsonRecord = Record<string, unknown>;

export const clean = (value: unknown, max = 500): string =>
  typeof value === "string" ? value.replace(/\u0000/g, "").trim().slice(0, max) :
  typeof value === "number" && Number.isFinite(value) ? String(value).slice(0, max) : "";

export const digits = (value: unknown): string => clean(value, 80).replace(/\D/g, "").slice(0, 15);

const asRecord = (value: unknown): JsonRecord =>
  value && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};

const read = (record: JsonRecord, keys: string[]): unknown => {
  for (const key of keys) {
    const value = record[key];
    if (value !== undefined && value !== null && value !== "") return value;
  }
  return undefined;
};

const first = (...values: unknown[]): unknown => values.find(value => value !== undefined && value !== null && value !== "");

export const normalizeStageKey = (value: unknown): string =>
  clean(value, 160).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toUpperCase().replace(/\s+/g, " ");

function appointmentIso(dateValue: unknown, timeValue: unknown = ""): string {
  const rawDate = clean(dateValue, 80);
  const rawTime = clean(timeValue, 40);
  if (!rawDate) return "";

  const direct = rawTime ? `${rawDate} ${rawTime}` : rawDate;
  const isoLike = direct.match(/^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?(?:([+-]\d{2}:?\d{2}|Z))?$/i);
  if (isoLike) {
    const [, y, mo, d, hh = "00", mm = "00", ss = "00", zone = ""] = isoLike;
    const local = `${y}-${mo}-${d}T${hh.padStart(2, "0")}:${mm}:${ss}${zone || "-03:00"}`;
    const parsed = new Date(local);
    return Number.isNaN(parsed.getTime()) ? "" : parsed.toISOString();
  }

  const br = direct.match(/^(\d{1,2})\/(\d{1,2})\/(\d{4})(?:[ ,T-]+(\d{1,2})(?::|h)(\d{2})(?::(\d{2}))?)?$/i);
  if (br) {
    const [, d, mo, y, hh = "00", mm = "00", ss = "00"] = br;
    const parsed = new Date(`${y}-${mo.padStart(2, "0")}-${d.padStart(2, "0")}T${hh.padStart(2, "0")}:${mm}:${ss}-03:00`);
    return Number.isNaN(parsed.getTime()) ? "" : parsed.toISOString();
  }

  const parsed = new Date(direct);
  return Number.isNaN(parsed.getTime()) ? "" : parsed.toISOString();
}

export type ParsedSimEvent = {
  eventType: string;
  providerEventId: string;
  externalLeadId: string;
  name: string;
  phone: string;
  email: string;
  interest: string;
  company: string;
  stageId: string;
  stageName: string;
  appointmentAt: string;
  occurredAt: string;
};

export function parseSimEvent(input: unknown, headerDeliveryId = ""): ParsedSimEvent {
  const root = asRecord(input);
  const payload = asRecord(first(root.payload, root.data));
  const lead = asRecord(first(root.lead, payload.lead, root.contact, payload.contact, payload));
  const stage = asRecord(first(root.stage, payload.stage, lead.stage, root.funnel_stage, payload.funnel_stage));
  const appointment = asRecord(first(
    root.appointment, payload.appointment, root.agendamento, payload.agendamento,
    root.visit, payload.visit, root.visita, payload.visita, lead.appointment, lead.agendamento,
  ));

  const eventType = clean(first(
    read(root, ["event", "event_type", "trigger_event", "type"]),
    read(payload, ["event", "event_type", "trigger_event", "type"]),
    "unknown",
  ), 120).toLowerCase();

  const providerEventId = clean(first(
    headerDeliveryId,
    read(root, ["delivery_uuid", "delivery_id", "event_id", "webhook_id"]),
    read(payload, ["delivery_uuid", "delivery_id", "event_id", "webhook_id"]),
  ), 180);

  const phone = digits(first(
    read(lead, ["phone", "telefone", "whatsapp", "numero", "number"]),
    read(root, ["phone", "telefone", "whatsapp", "numero", "number"]),
  ));

  const externalLeadId = clean(first(
    read(lead, ["id", "lead_id", "external_id", "uuid"]),
    read(root, ["lead_id", "external_lead_id", "contact_id"]),
    read(payload, ["lead_id", "external_lead_id", "contact_id"]),
    phone ? `phone:${phone}` : "",
  ), 180);

  const appointmentAtRaw = first(
    read(appointment, ["scheduled_at", "appointment_at", "visit_at", "datetime", "date_time", "data_hora", "data_hora_agendamento", "data_hora_visita"]),
    read(lead, ["scheduled_at", "appointment_at", "visit_at", "data_hora_agendamento", "data_hora_visita"]),
    read(root, ["scheduled_at", "appointment_at", "visit_at", "data_hora_agendamento", "data_hora_visita"]),
    read(payload, ["scheduled_at", "appointment_at", "visit_at", "data_hora_agendamento", "data_hora_visita"]),
  );
  const appointmentDate = first(
    read(appointment, ["date", "appointment_date", "visit_date", "data", "data_agendamento", "data_visita"]),
    read(lead, ["appointment_date", "visit_date", "data_agendamento", "data_visita"]),
    read(root, ["appointment_date", "visit_date", "data_agendamento", "data_visita"]),
    read(payload, ["appointment_date", "visit_date", "data_agendamento", "data_visita"]),
  );
  const appointmentTime = first(
    read(appointment, ["time", "appointment_time", "visit_time", "hora", "horario", "hora_agendamento", "hora_visita"]),
    read(lead, ["appointment_time", "visit_time", "hora_agendamento", "hora_visita", "horario"]),
    read(root, ["appointment_time", "visit_time", "hora_agendamento", "hora_visita", "horario"]),
    read(payload, ["appointment_time", "visit_time", "hora_agendamento", "hora_visita", "horario"]),
  );
  const appointmentAt = appointmentIso(appointmentAtRaw || appointmentDate, appointmentAtRaw ? "" : appointmentTime);
  const occurredAt = appointmentIso(first(read(root, ["occurred_at"]), read(payload, ["occurred_at"])));

  return {
    eventType,
    providerEventId,
    externalLeadId,
    name: clean(first(
      read(lead, ["full_name", "nome", "name", "push_name"]),
      read(root, ["full_name", "nome", "name"]),
    ), 160),
    phone,
    email: clean(first(read(lead, ["email", "e_mail"]), read(root, ["email", "e_mail"])), 180).toLowerCase(),
    interest: clean(first(
      read(lead, ["interest", "interesse", "course", "curso"]),
      read(root, ["interest", "interesse", "course", "curso"]),
    ), 240),
    company: clean(first(read(lead, ["company", "empresa"]), read(root, ["company", "empresa"])), 160),
    stageId: clean(first(
      read(stage, ["id", "stage_id", "funnel_stage_id"]),
      read(lead, ["stage_id", "funnel_stage_id", "id_da_etapa_no_funil"]),
      read(root, ["stage_id", "funnel_stage_id", "id_da_etapa_no_funil"]),
    ), 120),
    stageName: clean(first(
      read(stage, ["name", "nome", "stage_name"]),
      read(lead, ["stage_name", "etapa"]),
      read(root, ["stage_name", "etapa"]),
    ), 160),
    appointmentAt,
    occurredAt,
  };
}

