import { createClient } from 'npm:@supabase/supabase-js@2.57.0'

const allowed=new Set(['https://www.liveconnect.com.br','https://liveconnect.com.br','https://portallc.netlify.app'])
const cors=(req:Request)=>{
  const o=req.headers.get('origin')||''
  const origin=(!o||allowed.has(o)||o.startsWith('http://localhost:')||o.startsWith('http://127.0.0.1:'))?(o||'https://www.liveconnect.com.br'):'https://www.liveconnect.com.br'
  return {'Content-Type':'application/json; charset=utf-8','Access-Control-Allow-Origin':origin,'Vary':'Origin','Access-Control-Allow-Headers':'content-type, apikey, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store'}
}
const reply=(req:Request,body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors(req)})
const text=(v:unknown,max=1000)=>String(v??'').trim().slice(0,max)
const digits=(v:unknown)=>String(v??'').replace(/\D/g,'')
const norm=(v:unknown)=>String(v??'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim()
const yes=(v:string)=>/\b(sim|quero|vamos|pode|matricul|fechar|agora|prosseguir|continuar)\b/i.test(v)
const wantsHuman=(v:string)=>/\b(humano|atendente|consultor|vendedor|pessoa|equipe)\b/i.test(v)
const slugify=(v:string)=>norm(v).replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'')
const jsonHeaders={'Content-Type':'application/json'}

async function currentOffer(sb:any){
  const today=new Date().toISOString().slice(0,10)
  const {data}=await sb.from('campaigns').select('name,title,offer_text,enrollment_fee,monthly_fee,cta_label,start_date,end_date,priority')
    .eq('active',true).eq('highlight_public',true).lte('start_date',today).or(`end_date.is.null,end_date.gte.${today}`)
    .order('priority',{ascending:false}).limit(1)
  return data?.[0]||null
}
function offerText(o:any){
  if(!o)return ''
  if(o.offer_text)return String(o.offer_text)
  const br=(n:any)=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})
  if(o.enrollment_fee!=null&&o.monthly_fee!=null)return `Condição vigente: matrícula ${br(o.enrollment_fee)} + mensalidades de ${br(o.monthly_fee)}.`
  return o.title||''
}
async function append(sb:any,sessionId:string,sender_type:string,body:string,metadata:any={}){
  await sb.from('commercial_chat_messages').insert({session_id:sessionId,sender_type,body,metadata})
  await sb.from('commercial_chat_sessions').update({last_message_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('id',sessionId)
}
async function ensureLead(sb:any,s:any){
  if(!s.full_name||!s.whatsapp)return null
  const rawPhone=digits(s.whatsapp)
  const phone=(rawPhone.length===10||rawPhone.length===11)?'55'+rawPhone:rawPhone
  const candidates=[rawPhone,phone].filter((x,i,a)=>x&&a.indexOf(x)===i)
  const inList=candidates.join(',')
  const {data:rows,error:lookupError}=await sb.from('leads')
    .select('id,lead_score,status,source')
    .or(`whatsapp.in.(${inList}),whatsapp_normalized.in.(${inList})`)
    .is('deleted_at',null).order('updated_at',{ascending:false}).limit(1)
  if(lookupError)throw lookupError
  const lead=rows?.[0]||null
  const payload:any={
    full_name:s.full_name,whatsapp:phone,age:s.age||null,professional_goal:s.objective||'Qualificação profissional',
    landing_page:s.landing_page||null,referrer:s.referrer||null,utm_source:s.utm_source||null,utm_medium:s.utm_medium||null,
    utm_campaign:s.utm_campaign||null,utm_content:s.utm_content||null,updated_at:new Date().toISOString()
  }
  if(lead?.id){
    await sb.from('leads').update({...payload,lead_score:Math.max(Number(lead.lead_score||0),Number(s.lead_score||35))}).eq('id',lead.id)
    if(!s.lead_id)await sb.from('commercial_chat_sessions').update({lead_id:lead.id}).eq('id',s.id)
    return lead.id
  }
  const {data,error}=await sb.from('leads').insert({...payload,source:'portal_chatbot',status:'pre_inscricao',lead_score:s.lead_score||35}).select('id').single()
  if(error)throw error
  await sb.from('commercial_chat_sessions').update({lead_id:data.id}).eq('id',s.id)
  return data.id
}
async function saveInterest(sb:any,s:any,course:any){
  const leadId=s.lead_id||await ensureLead(sb,s)
  if(!leadId)return
  const kind=String(course.type)==='gratuito'?'curso_gratuito':'curso_pago'
  const {data:recent}=await sb.from('lead_interests').select('id').eq('lead_id',leadId).eq('course_id',course.id).eq('source','portal_chatbot').order('created_at',{ascending:false}).limit(1)
  if(!recent?.length)await sb.from('lead_interests').insert({
    lead_id:leadId,course_id:course.id,interest_type:kind,source:'portal_chatbot',
    metadata:{chat_session_id:s.id,objective:s.objective,lead_score:80}
  })
  await sb.from('lead_activities').insert({
    lead_id:leadId,activity_type:'chatbot_lead_qualificado',
    description:`Chatbot Comercial — interesse em ${course.name}`,
    metadata:{chat_session_id:s.id,course_id:course.id,course_name:course.name}
  })
}
function rankCourses(courses:any[],goal:string){
  const words=norm(goal).split(/\s+/).filter(x=>x.length>=4)
  return [...courses].map(c=>{
    const n=norm(c.name);let score=0
    for(const w of words)if(n.includes(w))score+=3
    if(/admin|empresa|gestao|escritorio|contab/.test(norm(goal))&&/admin|gestao|escritorio|contab|finance/.test(n))score+=4
    if(/informat|comput|excel|office|program|tecnolog|app|web|games/.test(norm(goal))&&/informat|excel|office|program|app|web|games|comput/.test(n))score+=4
    if(/saude|farmac/.test(norm(goal))&&/saude|farmac/.test(n))score+=4
    if(/design|social|marketing|midia/.test(norm(goal))&&/design|social|marketing|youtuber/.test(n))score+=4
    if(/ingles|idioma/.test(norm(goal))&&/ingles/.test(n))score+=4
    if(/beleza/.test(norm(goal))&&/beleza/.test(n))score+=4
    return {c,score}
  }).sort((a,b)=>b.score-a.score||String(a.c.name).localeCompare(String(b.c.name),'pt-BR')).slice(0,5).map(x=>x.c)
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors(req)})
  if(req.method!=='POST')return reply(req,{ok:false,error:'method_not_allowed'},405)
  const o=req.headers.get('origin')||''
  if(o&&!allowed.has(o)&&!o.startsWith('http://localhost:')&&!o.startsWith('http://127.0.0.1:'))return reply(req,{ok:false,error:'origin_not_allowed'},403)
  try{
    const body=await req.json()
    if(text(body.website,100))return reply(req,{ok:true})
    const url=Deno.env.get('SUPABASE_URL')!
    const raw=Deno.env.get('SUPABASE_SECRET_KEYS')
    const secret=raw?JSON.parse(raw)['default']:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const sb=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})
    const action=text(body.action,30)||'message'
    if(action==='start'){
      const meta=body.context&&typeof body.context==='object'?body.context:{}
      const {data:s,error}=await sb.from('commercial_chat_sessions').insert({
        landing_page:text(meta.landing_page||body.landing_page,300)||null,referrer:text(meta.referrer||body.referrer,300)||null,
        utm_source:text(meta.utm_source,120)||null,utm_medium:text(meta.utm_medium,120)||null,utm_campaign:text(meta.utm_campaign,120)||null,utm_content:text(meta.utm_content,120)||null,
        course_interest:text(meta.course_name,180)||null,metadata:{course_slug:text(meta.course_slug,180)||null}
      }).select('id,public_token,stage').single()
      if(error)throw error
      const hello='Olá! Sou o assistente comercial da Live Connect. Vou te ajudar a encontrar a melhor formação e, se fizer sentido, iniciar sua matrícula. Qual é o seu nome?'
      await append(sb,s.id,'assistant',hello,{stage:'name'})
      return reply(req,{ok:true,token:s.public_token,session_id:s.id,stage:'name',message:hello})
    }
    const token=text(body.token,80)
    if(!/^[0-9a-f-]{36}$/i.test(token))return reply(req,{ok:false,error:'invalid_request'},400)
    const {data:s,error}=await sb.from('commercial_chat_sessions').select('*').eq('public_token',token).maybeSingle()
    if(error)throw error
    if(!s)return reply(req,{ok:false,error:'session_not_found'},404)
    if(action==='poll'){
      const {data:staff,error:staffError}=await sb.from('commercial_chat_messages')
        .select('id,body,created_at').eq('session_id',s.id).eq('sender_type','staff')
        .order('created_at',{ascending:false}).limit(40)
      if(staffError)throw staffError
      return reply(req,{ok:true,token,status:s.status,handoff:!!s.assigned_to||s.status==='handoff',messages:[...(staff||[])].reverse()})
    }
    const message=text(body.message,2000)
    if(!message)return reply(req,{ok:false,error:'invalid_request'},400)
    const cutoff=new Date(Date.now()-60000).toISOString()
    const {count}=await sb.from('commercial_chat_messages').select('id',{count:'exact',head:true}).eq('session_id',s.id).gte('created_at',cutoff)
    if((count||0)>24)return reply(req,{ok:false,error:'rate_limited'},429)
    await append(sb,s.id,'visitor',message)
    if(s.assigned_to||s.status==='handoff'){
      return reply(req,{ok:true,token,stage:'handoff',handoff:true,message:'Recebi sua mensagem. Um consultor da Live Connect continuará o atendimento por aqui.'})
    }
    if(wantsHuman(message)){
      await sb.from('commercial_chat_sessions').update({status:'handoff',stage:'handoff',updated_at:new Date().toISOString()}).eq('id',s.id)
      const out='Perfeito. Vou encaminhar seu atendimento para um consultor da Live Connect. Você pode continuar escrevendo por aqui.'
      await append(sb,s.id,'assistant',out,{handoff:true})
      return reply(req,{ok:true,token,stage:'handoff',handoff:true,message:out})
    }
    const offer=await currentOffer(sb)
    const nmsg=norm(message)
    if(/preco|valor|matricula|mensalidade|quanto custa/.test(nmsg)&&s.stage!=='name'&&s.stage!=='whatsapp'){
      const out=offerText(offer)||'As condições variam conforme a formação. Vou usar apenas a oferta vigente no sistema quando você escolher o curso.'
      await append(sb,s.id,'assistant',out,{kind:'pricing'})
      return reply(req,{ok:true,token,stage:s.stage,message:out})
    }
    if(/endereco|onde fica|localizacao/.test(nmsg)){
      const out='A Live Connect fica na Rua Sá Oliveira, 18, Ed. Empresarial Fraga Center, Sala 01, Centro, Ilhéus - BA.'
      await append(sb,s.id,'assistant',out,{kind:'address'})
      return reply(req,{ok:true,token,stage:s.stage,message:out})
    }
    let stage=s.stage||'name'
    let out=''
    if(stage==='name'){
      if(message.length<2){out='Me diga seu nome para eu personalizar o atendimento.'}
      else{
        await sb.from('commercial_chat_sessions').update({full_name:message.slice(0,160),stage:'whatsapp',lead_score:15,updated_at:new Date().toISOString()}).eq('id',s.id)
        out=`Prazer, ${message.split(/\s+/)[0]}! Qual é o seu WhatsApp com DDD? Vou usar somente para registrar seu atendimento e facilitar o fechamento.`
        stage='whatsapp'
      }
    }else if(stage==='whatsapp'){
      const phone=digits(message)
      if(phone.length<10||phone.length>13)out='Não consegui validar o número. Envie seu WhatsApp com DDD, por exemplo: (73) 99999-9999.'
      else{
        const patch:any={whatsapp:phone,stage:'age',lead_score:35,updated_at:new Date().toISOString()}
        await sb.from('commercial_chat_sessions').update(patch).eq('id',s.id)
        const ss={...s,...patch};await ensureLead(sb,ss)
        out='Ótimo. Qual é a sua idade?'
        stage='age'
      }
    }else if(stage==='age'){
      const m=message.match(/\b(\d{1,3})\b/);const age=m?Number(m[1]):0
      if(age<10||age>100)out='Me informe sua idade em anos para eu indicar a formação e o fluxo correto.'
      else{
        const patch:any={age,stage:'objective',lead_score:50,updated_at:new Date().toISOString()}
        await sb.from('commercial_chat_sessions').update(patch).eq('id',s.id)
        const ss={...s,...patch};await ensureLead(sb,ss)
        out='O que você busca agora: conseguir emprego, melhorar o currículo, mudar de área, empreender ou aprender uma habilidade específica?'
        stage='objective'
      }
    }else if(stage==='objective'){
      const {data:courses}=await sb.from('courses').select('id,name,type').eq('active',true).order('name').limit(120)
      const picks=rankCourses(courses||[],message)
      const patch:any={objective:message.slice(0,600),stage:'course',lead_score:65,metadata:{...(s.metadata||{}),suggested_courses:picks.map((c:any)=>c.name)},updated_at:new Date().toISOString()}
      await sb.from('commercial_chat_sessions').update(patch).eq('id',s.id)
      const list=picks.length?picks.map((c:any,i:number)=>`${i+1}. ${c.name}`).join('\n'):''
      out=picks.length?`Pelo que você me contou, estas opções fazem mais sentido:\n\n${list}\n\nQual delas mais te interessa? Se preferir, diga a área que quer estudar.`:'Qual área mais te interessa: Administrativo, Informática/Tecnologia, Saúde, Design/Marketing, Idiomas ou Beleza?'
      stage='course'
    }else if(stage==='course'){
      const {data:courses}=await sb.from('courses').select('id,name,type').eq('active',true).order('name').limit(150)
      const nm=norm(message)
      let course=(courses||[]).find((c:any)=>nm===norm(c.name)||nm.includes(norm(c.name))||norm(c.name).includes(nm))
      if(!course){
        const suggested=Array.isArray(s.metadata?.suggested_courses)?s.metadata.suggested_courses:[]
        const idx=Number(message.trim())-1
        if(Number.isInteger(idx)&&idx>=0&&idx<suggested.length)course=(courses||[]).find((c:any)=>c.name===suggested[idx])
      }
      if(!course){
        out='Ainda não consegui identificar o curso. Escreva o nome da formação ou uma área, como “Administrativo”, “Informática”, “Saúde” ou “Design”.'
      }else{
        const patch:any={course_interest:course.name,course_type:String(course.type),stage:'closing',status:'qualified',lead_score:80,updated_at:new Date().toISOString()}
        await sb.from('commercial_chat_sessions').update(patch).eq('id',s.id)
        const ss={...s,...patch};await saveInterest(sb,ss,course)
        const price=offerText(offer)
        out=`${course.name} é uma boa opção para o seu objetivo. ${price?price+' ':''}Quer iniciar sua matrícula agora? Se preferir, também posso chamar um consultor.`
        stage='closing'
      }
    }else if(stage==='closing'){
      if(yes(message)){
        const patch:any={status:'closing',lead_score:95,updated_at:new Date().toISOString()}
        await sb.from('commercial_chat_sessions').update(patch).eq('id',s.id)
        const ss={...s,...patch};const leadId=ss.lead_id||await ensureLead(sb,ss)
        if(leadId)await sb.from('lead_activities').insert({lead_id:leadId,activity_type:'chatbot_fechamento_iniciado',description:`Chatbot Comercial — fechamento iniciado — ${s.course_interest||'curso'}`,metadata:{chat_session_id:s.id}})
        const link=`https://www.liveconnect.com.br/cursos/${slugify(s.course_interest||'')}/?utm_source=chatbot&utm_medium=chat&utm_campaign=fechamento_chatbot&chat=${token}`
        out='Perfeito. Seu atendimento já está qualificado. Abra a matrícula para preencher os dados finais e escolher a condição disponível. Se precisar, um consultor consegue assumir a conversa no Admin.'
        await append(sb,s.id,'assistant',out,{cta_url:link,cta_label:'Iniciar matrícula',stage:'closing'})
        return reply(req,{ok:true,token,stage:'closing',message:out,cta:{label:'Iniciar matrícula',url:link},qualified:true,lead_score:95})
      }
      out='Sem problema. O que está impedindo você de avançar agora: valor, horário, escolha do curso ou alguma dúvida sobre a formação?'
    }else{
      out='Posso continuar sua qualificação ou chamar um consultor. O que você prefere?'
    }
    await append(sb,s.id,'assistant',out,{stage})
    return reply(req,{ok:true,token,stage,message:out,lead_score:s.lead_score||0})
  }catch(err){console.error('portal-commercial-chat',err);return reply(req,{ok:false,error:'internal_error'},500)}
})