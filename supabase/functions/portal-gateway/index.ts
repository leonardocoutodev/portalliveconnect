import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const BASE=Deno.env.get('SUPABASE_URL')!;
const allowed=new Set(['https://portallc.netlify.app','https://liveconnect.com.br','https://www.liveconnect.com.br']);
function okOrigin(o:string){return !o||allowed.has(o)||o.startsWith('http://localhost:')||o.startsWith('http://127.0.0.1:')||/^https:\/\/[a-z0-9-]+--portallc\.netlify\.app$/i.test(o)}
function cors(req:Request){const o=req.headers.get('origin')||'';return {'Access-Control-Allow-Origin':okOrigin(o)&&o?o:'https://portallc.netlify.app','Vary':'Origin','Access-Control-Allow-Headers':'authorization, content-type, apikey, x-client-info','Access-Control-Allow-Methods':'GET, POST, OPTIONS','Cache-Control':'no-store'}}
const services:Record<string,string>={enrollment:'portal-enrollment-submit',lead:'portal-lead-submit',young:'portal-young-apprentice-submit',analytics:'portal-analytics-event',payment:'portal-payment',ouro:'ouro-student-portal'};
async function probe(slug:string,body:unknown,auth?:string){const h:Record<string,string>={'Content-Type':'application/json'};if(auth)h.Authorization=auth;const r=await fetch(`${BASE}/functions/v1/${slug}`,{method:'POST',headers:h,body:JSON.stringify(body)});let data:any={};try{data=await r.json()}catch{}return {status:r.status,error:data?.error||null,ok:data?.ok===true}}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors(req)});
 const u=new URL(req.url);
 if(req.method==='GET'&&u.searchParams.get('selftest')==='1'){
   const results={
     enrollment:await probe(services.enrollment,{}),
     lead:await probe(services.lead,{}),
     young:await probe(services.young,{}),
     analytics:await probe(services.analytics,{event_type:'invalid',session_id:'selftest-session'}),
     payment:await probe(services.payment,{action:'status',token:'11111111-1111-4111-8111-111111111111'}),
     ouro:await probe(services.ouro,{action:'me'})
   };
   const expected=results.enrollment.status===400&&results.lead.status===400&&results.young.status===400&&results.analytics.status===400&&[400,404].includes(results.payment.status)&&results.ouro.status===401;
   return new Response(JSON.stringify({ok:expected,origin:'https://portallc.netlify.app',services:results}),{status:expected?200:500,headers:{'Content-Type':'application/json; charset=utf-8',...cors(req)}});
 }
 if(req.method!=='POST')return new Response(JSON.stringify({ok:false,error:'method_not_allowed'}),{status:405,headers:{'Content-Type':'application/json',...cors(req)}});
 const origin=req.headers.get('origin')||'';if(!okOrigin(origin))return new Response(JSON.stringify({ok:false,error:'origin_not_allowed'}),{status:403,headers:{'Content-Type':'application/json',...cors(req)}});
 const service=String(u.searchParams.get('service')||''); const slug=services[service];
 if(!slug)return new Response(JSON.stringify({ok:false,error:'invalid_service'}),{status:400,headers:{'Content-Type':'application/json',...cors(req)}});
 const body=await req.arrayBuffer();
 const h:Record<string,string>={'Content-Type':req.headers.get('content-type')||'application/json'};
 const auth=req.headers.get('authorization'); if(auth)h.Authorization=auth;
 const apikey=req.headers.get('apikey'); if(apikey)h.apikey=apikey;
 const r=await fetch(`${BASE}/functions/v1/${slug}`,{method:'POST',headers:h,body});
 const out=await r.arrayBuffer();
 const ct=r.headers.get('content-type')||'application/json; charset=utf-8';
 return new Response(out,{status:r.status,headers:{'Content-Type':ct,...cors(req)}});
});