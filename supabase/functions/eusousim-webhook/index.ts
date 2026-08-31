import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { clean, normalizeStageKey, parseSimEvent, type JsonRecord } from "./parser.ts";

const SUPABASE_URL=Deno.env.get("SUPABASE_URL")??"";
function backendKey(){
  const s=Deno.env.get("SUPABASE_SECRET_KEYS");
  if(s){try{const p=JSON.parse(s) as Record<string,string>;if(p.default)return p.default;}catch{}}
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
}
const BACKEND_KEY=backendKey();
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store"}});
const encoded=(v:string)=>encodeURIComponent(v);
const sha256=async(text:string)=>{const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(text));return [...new Uint8Array(d)].map(b=>b.toString(16).padStart(2,"0")).join("")};

async function rest(path:string,init:RequestInit={},prefer="return=representation"){
  if(!SUPABASE_URL||!BACKEND_KEY)throw new Error("backend_not_configured");
  const legacy=!BACKEND_KEY.startsWith("sb_secret_");
  const res=await fetch(`${SUPABASE_URL}/rest/v1/${path}`,{...init,headers:{apikey:BACKEND_KEY,...(legacy?{Authorization:`Bearer ${BACKEND_KEY}`}:{}),"content-type":"application/json",Prefer:prefer,...(init.headers??{})}});
  const text=await res.text();const data=text?JSON.parse(text):null;
  if(!res.ok)throw new Error(data?.code||data?.message||`db_${res.status}`);
  return data;
}
function endpointKeyFrom(url:URL){const s=url.pathname.split("/").filter(Boolean);const i=s.lastIndexOf("eusousim-webhook");return clean(i>=0?s[i+1]:s.at(-1),160)}
function statusFor(endpoint:JsonRecord,stageId:string,stageName:string){
  const m=endpoint.stage_mapping&&typeof endpoint.stage_mapping==="object"?endpoint.stage_mapping as Record<string,unknown>:{};
  for(const k of [stageId,normalizeStageKey(stageName)].filter(Boolean)){const v=clean(m[k],80);if(v)return v;}
  return "novo_lead";
}
const appointmentStage=(s:string)=>/VISITA AGENDADA|REAGENDAMENTO|AGENDAD/.test(normalizeStageKey(s));
const completedStage=(s:string)=>/COMPARECEU|MATRICUL|CADASTRAD/.test(normalizeStageKey(s));

async function syncFollowup(endpoint:JsonRecord,leadId:string,externalLeadId:string,leadName:string,parsed:ReturnType<typeof parseSimEvent>,historicalImport:boolean){
  const endpointId=clean(endpoint.id,80),now=new Date().toISOString();
  let links=await rest(`eusousim_followup_links?endpoint_id=eq.${encoded(endpointId)}&external_lead_id=eq.${encoded(externalLeadId)}&select=*&limit=1`) as JsonRecord[];
  let link=links?.[0]??null;
  if(!link){
    links=await rest(`eusousim_followup_links?endpoint_id=eq.${encoded(endpointId)}&lead_id=eq.${encoded(leadId)}&status=in.(scheduled,needs_time)&select=*&order=updated_at.desc&limit=1`) as JsonRecord[];
    link=links?.[0]??null;
  }
  if(completedStage(parsed.stageName)){
    if(!link)return {action:"none"};
    const fid=clean(link.followup_id,80);
    if(fid)await rest(`followups?id=eq.${encoded(fid)}`,{method:"PATCH",body:JSON.stringify({status:"concluido",completed_at:now})},"return=minimal");
    await rest(`eusousim_followup_links?id=eq.${encoded(clean(link.id,80))}`,{method:"PATCH",body:JSON.stringify({status:"completed",last_event_type:parsed.eventType,updated_at:now})},"return=minimal");
    return {action:"completed"};
  }
  if(!appointmentStage(parsed.stageName))return {action:"none"};
  if(!parsed.appointmentAt&&historicalImport)return {action:"historical_without_time"};

  const needsTime=!parsed.appointmentAt;
  const scheduledAt=parsed.appointmentAt||now;
  const note=needsTime
    ? "[Eu Sou SIM] Confirmar data e hora da visita. O webhook informou visita/reagendamento sem horário."
    : `[Eu Sou SIM] Visita sincronizada para ${new Date(parsed.appointmentAt).toLocaleString("pt-BR",{timeZone:"America/Bahia"})}.`;
  let followupId=clean(link?.followup_id,80);
  if(followupId){
    await rest(`followups?id=eq.${encoded(followupId)}`,{method:"PATCH",body:JSON.stringify({scheduled_at:scheduledAt,note,status:"pendente",completed_at:null})},"return=minimal");
  }else{
    const rows=await rest("followups",{method:"POST",body:JSON.stringify({lead_id:leadId,scheduled_at:scheduledAt,note,status:"pendente"})}) as JsonRecord[];
    followupId=clean(rows?.[0]?.id,80);
  }
  const body={endpoint_id:endpointId,external_lead_id:externalLeadId,lead_id:leadId,followup_id:followupId,scheduled_at:parsed.appointmentAt||null,status:needsTime?"needs_time":"scheduled",last_event_type:parsed.eventType,updated_at:now};
  if(link?.id)await rest(`eusousim_followup_links?id=eq.${encoded(clean(link.id,80))}`,{method:"PATCH",body:JSON.stringify(body)},"return=minimal");
  else await rest("eusousim_followup_links?on_conflict=endpoint_id,external_lead_id",{method:"POST",body:JSON.stringify(body)},"resolution=merge-duplicates,return=minimal");

  await rest("notifications",{method:"POST",body:JSON.stringify({
    type:"eusousim_appointment",
    title:needsTime?"Visita precisa de horário":normalizeStageKey(parsed.stageName).includes("REAGENDAMENTO")?"Visita reagendada":"Nova visita agendada",
    body:needsTime?`${leadName}: confirme data e hora no Eu Sou SIM.`:`${leadName}: ${new Date(parsed.appointmentAt).toLocaleString("pt-BR",{timeZone:"America/Bahia"})}.`,
    severity:needsTime?"warning":"info",
    related_lead_id:leadId
  })},"return=minimal");
  return {action:needsTime?"needs_time":(link?"rescheduled":"scheduled")};
}

Deno.serve(async(req:Request)=>{
  let eventId="";
  try{
    if(req.method!=="POST")return json({ok:false,error:"method_not_allowed"},405);
    const url=new URL(req.url),endpointKey=endpointKeyFrom(url);
    if(endpointKey.length<32)return json({ok:false,error:"not_found"},404);
    const signature=clean(req.headers.get("x-sim-signature"),500);
    if(!signature)return json({ok:false,error:"unauthorized"},401);
    const raw=await req.text();
    if(!raw||raw.length>262144)return json({ok:false,error:"invalid_payload"},400);
    const payload=JSON.parse(raw);
    if(!payload||typeof payload!=="object"||Array.isArray(payload))return json({ok:false,error:"invalid_payload"},400);

    const hash=await sha256(endpointKey);
    const endpoints=await rest(`eusousim_integration_endpoints?endpoint_key_hash=eq.${hash}&is_active=eq.true&select=*&limit=1`) as JsonRecord[];
    const endpoint=endpoints?.[0];if(!endpoint)return json({ok:false,error:"not_found"},404);

    const delivery=clean(req.headers.get("x-sim-delivery-id")||req.headers.get("x-sim-delivery")||req.headers.get("x-webhook-id"),180);
    const parsed=parseSimEvent(payload,delivery),payloadHash=await sha256(raw);
    const dedupe=parsed.providerEventId?`id:${parsed.providerEventId}`:`sha256:${payloadHash}`;
    const events=await rest("eusousim_events?on_conflict=endpoint_id,dedupe_key",{method:"POST",body:JSON.stringify({
      endpoint_id:endpoint.id,dedupe_key:dedupe,provider_event_id:parsed.providerEventId||null,event_type:parsed.eventType,
      external_lead_id:parsed.externalLeadId||null,payload_sha256:payloadHash,payload,status:"received"
    })},"resolution=ignore-duplicates,return=representation") as JsonRecord[];
    if(!events?.length)return json({ok:true,duplicate:true});
    eventId=clean(events[0].id,80);

    if(!parsed.phone||parsed.phone.length<10){
      await rest(`eusousim_events?id=eq.${encoded(eventId)}`,{method:"PATCH",body:JSON.stringify({status:"ignored",error_code:"missing_lead_fields",processed_at:new Date().toISOString()})},"return=minimal");
      return json({ok:true,ignored:true});
    }
    const externalLeadId=parsed.externalLeadId||`phone:${parsed.phone}`;
    let linkRows=await rest(`eusousim_lead_links?provider=eq.eusousim&external_lead_id=eq.${encoded(externalLeadId)}&select=lead_id&limit=1`) as JsonRecord[];
    let leadId=clean(linkRows?.[0]?.lead_id,80),lead:JsonRecord|null=null;
    if(leadId){const rows=await rest(`leads?id=eq.${encoded(leadId)}&select=id,full_name,whatsapp,email,status&limit=1`) as JsonRecord[];lead=rows?.[0]??null;}
    if(!lead){
      const rows=await rest(`leads?whatsapp_normalized=eq.${encoded(parsed.phone)}&select=id,full_name,whatsapp,email,status&limit=1`) as JsonRecord[];
      lead=rows?.[0]??null;leadId=clean(lead?.id,80);
    }
    const mappedStatus=statusFor(endpoint,parsed.stageId,parsed.stageName),now=new Date().toISOString();
    const leadName=parsed.name||clean(lead?.full_name,160)||`Contato ${parsed.phone.slice(-4)}`;
    if(!leadId){
      const rows=await rest("leads",{method:"POST",body:JSON.stringify({
        full_name:leadName,whatsapp:parsed.phone,email:parsed.email||null,status:mappedStatus,source:clean(endpoint.source_label,120)||"Eu Sou SIM",
        professional_goal:parsed.interest||null,lead_score:50
      })}) as JsonRecord[];
      leadId=clean(rows?.[0]?.id,80);
    }else{
      const patch:JsonRecord={full_name:leadName,whatsapp:parsed.phone,status:mappedStatus,source:clean(endpoint.source_label,120)||"Eu Sou SIM",updated_at:now};
      if(parsed.email)patch.email=parsed.email;if(parsed.interest)patch.professional_goal=parsed.interest;
      await rest(`leads?id=eq.${encoded(leadId)}`,{method:"PATCH",body:JSON.stringify(patch)},"return=minimal");
    }
    await rest("eusousim_lead_links?on_conflict=provider,external_lead_id",{method:"POST",body:JSON.stringify({provider:"eusousim",external_lead_id:externalLeadId,lead_id:leadId,last_event_type:parsed.eventType,last_synced_at:now})},"resolution=merge-duplicates,return=minimal");

    const appointment=await syncFollowup(endpoint,leadId,externalLeadId,leadName,parsed,signature==="historical-import");
    await rest("lead_activities",{method:"POST",body:JSON.stringify({lead_id:leadId,activity_type:"integration",description:lead?"Lead atualizado pelo Eu Sou SIM.":"Lead criado pelo Eu Sou SIM.",metadata:{provider:"eusousim",event_type:parsed.eventType,external_lead_id:externalLeadId,source_stage:parsed.stageName||null,appointment_at:parsed.appointmentAt||null}})},"return=minimal");
    await rest(`eusousim_events?id=eq.${encoded(eventId)}`,{method:"PATCH",body:JSON.stringify({status:"processed",lead_id:leadId,external_lead_id:externalLeadId,processed_at:now})},"return=minimal");
    return json({ok:true,processed:true,appointment:appointment.action});
  }catch(error){
    const code=error instanceof Error?clean(error.message,120):"server_error";
    console.error("eusousim-liveconnect",code);
    if(eventId){try{await rest(`eusousim_events?id=eq.${encoded(eventId)}`,{method:"PATCH",body:JSON.stringify({status:"failed",error_code:code,processed_at:new Date().toISOString()})},"return=minimal");}catch{}}
    return json({ok:false,error:"server_error"},500);
  }
});