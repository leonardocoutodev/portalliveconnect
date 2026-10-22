import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const PORTAL_ORIGIN="https://www.liveconnect.com.br";
const allowedOrigins=new Set([
  PORTAL_ORIGIN,
  "https://liveconnect.com.br",
  "https://portallc.netlify.app"
]);

function originAllowed(origin:string){
  return !origin||allowedOrigins.has(origin)||origin.startsWith("http://localhost:")||origin.startsWith("http://127.0.0.1:");
}
function headers(req:Request){
  const origin=req.headers.get("origin")||"";
  return {
    "Content-Type":"application/json; charset=utf-8",
    "Access-Control-Allow-Origin":originAllowed(origin)&&origin?origin:PORTAL_ORIGIN,
    "Vary":"Origin",
    "Access-Control-Allow-Headers":"content-type, apikey, x-client-info",
    "Access-Control-Allow-Methods":"POST, OPTIONS",
    "Cache-Control":"no-store, max-age=0"
  };
}
function reply(req:Request,body:unknown,status=200){
  return new Response(JSON.stringify(body),{status,headers:headers(req)});
}
function secretKey(){
  const modern=Deno.env.get("SUPABASE_SECRET_KEYS");
  if(modern){
    try{
      const parsed=JSON.parse(modern);
      if(parsed?.default)return String(parsed.default);
    }catch{}
  }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")??"";
}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:headers(req)});
  if(req.method!=="POST")return reply(req,{ok:false,error:"method_not_allowed"},405);

  const origin=req.headers.get("origin")||"";
  if(!originAllowed(origin))return reply(req,{ok:false,error:"origin_not_allowed"},403);

  try{
    const body=await req.json().catch(()=>({}));
    if(String(body?.website??"").trim())return reply(req,{ok:true});

    const url=Deno.env.get("SUPABASE_URL")??"";
    const key=secretKey();
    if(!url||!key)return reply(req,{ok:false,error:"service_unavailable"},503);

    const supabase=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
    const {data,error}=await supabase.rpc("portal_ead_request_create",{p_payload:body});

    if(error){
      const detail=String(error.message||"");
      const known=[
        "privacy_consent_required","product_required","full_name_required",
        "invalid_whatsapp","invalid_email","invalid_cpf","invalid_rg",
        "invalid_birth_date","invalid_address","guardian_data_invalid",
        "product_unavailable","product_mapping_incomplete","ead_catalog_disabled"
      ];
      const code=known.find(x=>detail.includes(x))||"request_invalid";
      const status=code==="product_unavailable"||code==="product_mapping_incomplete"?409:400;
      return reply(req,{ok:false,error:code},status);
    }

    return reply(req,{
      ...data,
      message:"Solicitação recebida. A equipe Live Connect fará a cobrança e a matrícula será efetivada após a confirmação do pagamento."
    });
  }catch(error){
    console.error("portal-ead-enrollment-request",error);
    return reply(req,{ok:false,error:"internal_error"},500);
  }
});