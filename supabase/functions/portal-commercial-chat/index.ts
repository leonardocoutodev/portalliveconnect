import { createClient } from 'npm:@supabase/supabase-js@2.57.0'

const BOT_VERSION = 'liveconnect-basic-sales-1.2'
const ALLOWED = new Set(['https://www.liveconnect.com.br','https://liveconnect.com.br','https://portallc.netlify.app'])

const text = (v,max=1000) => String(v ?? '').trim().slice(0,max)
const digits = v => String(v ?? '').replace(/\D/g,'')
const norm = v => String(v ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().replace(/\s+/g,' ').trim()
const reply = (req,body,status=200) => new Response(JSON.stringify(body),{status,headers:cors(req)})

function cors(req){
  const o=req.headers.get('origin')||''
  const ok=!o||ALLOWED.has(o)||o.startsWith('http://localhost:')||o.startsWith('http://127.0.0.1:')
  return {
    'Content-Type':'application/json; charset=utf-8',
    'Access-Control-Allow-Origin':ok&&o?o:'https://www.liveconnect.com.br',
    'Vary':'Origin',
    'Access-Control-Allow-Headers':'content-type, apikey, x-client-info',
    'Access-Control-Allow-Methods':'POST, OPTIONS',
    'Cache-Control':'no-store'
  }
}

function isGreeting(v){
  const n=norm(v).replace(/[!?.,;:]+/g,' ').replace(/\s+/g,' ').trim()
  return /^(oi|ola|bom dia|boa tarde|boa noite|e ai|opa|salve|tudo bem|como vai)$/.test(n)
}
function wantsHuman(v){ return /\b(atendente|humano|pessoa|consultor|vendedor|comercial|equipe|falar com alguem)\b/.test(norm(v)) }
function wantsPrice(v){ return /\b(preco|valor|mensalidade|matricula|quanto custa|investimento|parcela)\b/.test(norm(v)) }
function wantsAddress(v){ return /\b(endereco|onde fica|localizacao|local da escola)\b/.test(norm(v)) }
function wantsFree(v){ return /\b(gratis|gratuito|gratuita|de graca|sem pagar)\b/.test(norm(v)) }
function wantsEnroll(v){ return /\b(matricula|matricular|inscrever|inscricao|fechar|garantir vaga)\b/.test(norm(v)) }
function yes(v){ return /^(sim|s|quero|tenho interesse|pode|vamos|claro|ok|beleza|fechado|gostei)\b/.test(norm(v)) }
function no(v){ return /^(nao|n|agora nao|depois|sem interesse)\b/.test(norm(v)) }

function parseName(v){
  let s=text(v,100).replace(/\s+/g,' ').trim()
  s=s.replace(/^(me chamo|meu nome e|meu nome é|sou)\s+/i,'').trim()
  if(!s||isGreeting(s)||/\d/.test(s)) return null
  const words=s.split(' ').filter(Boolean)
  if(words.length<1||words.length>5) return null
  if(words.some(w=>w.length<2||!/^[\p{L}'’\-]+$/u.test(w))) return null
  return words.map(w=>w.charAt(0).toLocaleUpperCase('pt-BR')+w.slice(1).toLocaleLowerCase('pt-BR')).join(' ')
}
function parsePhone(v){
  let raw=digits(v)
  if(raw.startsWith('55')&&(raw.length===12||raw.length===13)) raw=raw.slice(2)
  if(raw.length!==10&&raw.length!==11) return null
  const ddd=Number(raw.slice(0,2)),local=raw.slice(2)
  if(ddd<11||ddd>99||/^0+$/.test(local)||/^(.)\1+$/.test(local)) return null
  if(raw.length===11&&local[0]!=='9') return null
  if(raw.length===10&&!/[2-5]/.test(local[0])) return null
  return '55'+raw
}
function negativeAvailability(v){
  const n=norm(v)
  if(!/\b(nao|sem)\b/.test(n)) return null
  if(/\bmanha\b/.test(n)) return 'manhã'
  if(/\btarde\b/.test(n)) return 'tarde'
  if(/\b(noite|noturno)\b/.test(n)) return 'noite'
  if(/\b(ead|online|a distancia)\b/.test(n)) return 'EAD'
  if(/\bpresencial\b/.test(n)) return 'presencial'
  return null
}
function parseAvailability(v){
  const n=norm(v)
  if(negativeAvailability(v)) return null
  let mode=null,period=null
  if(/\b(ead|online|a distancia)\b/.test(n)) mode='ead'
  if(/\b(presencial|na escola)\b/.test(n)) mode='presencial'
  if(/\b(manha)\b/.test(n)) period='manha'
  if(/\b(tarde)\b/.test(n)) period='tarde'
  if(/\b(noite|noturno)\b/.test(n)) period='noite'
  if(/\b(flexivel|qualquer horario)\b/.test(n)) period='flexivel'
  if(!mode&&!period) return null
  return {mode:mode||'presencial',period:period||null,raw:text(v,180)}
}
function openStatus(v){ return ['qualifying','qualified','closing','handoff'].includes(String(v||'')) }

async function client(){
  const url=Deno.env.get('SUPABASE_URL')
  const secret=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if(!url||!secret) throw new Error('supabase_config_missing')
  return createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})
}
async function append(sb,sessionId,sender,body,metadata={}){
  const {error}=await sb.from('commercial_chat_messages').insert({session_id:sessionId,sender_type:sender,body,metadata})
  if(error) throw error
  await sb.from('commercial_chat_sessions').update({last_message_at:new Date().toISOString(),updated_at:new Date().toISOString()}).eq('id',sessionId)
}
async function patchSession(sb,id,patch){
  const {error}=await sb.from('commercial_chat_sessions').update(Object.assign({},patch,{updated_at:new Date().toISOString()})).eq('id',id)
  if(error) throw error
}
async function history(sb,id,limit=80){
  const {data,error}=await sb.from('commercial_chat_messages').select('id,sender_type,body,metadata,created_at').eq('session_id',id).order('created_at',{ascending:false}).limit(limit)
  if(error) throw error
  return [...(data||[])].reverse()
}
async function createSession(sb,meta={}){
  const row={
    status:'qualifying',
    stage:'discovery',
    lead_score:0,
    source:'portal_chatbot',
    landing_page:text(meta.landing_page,300)||null,
    referrer:text(meta.referrer,300)||null,
    utm_source:text(meta.utm_source,120)||null,
    utm_medium:text(meta.utm_medium,120)||null,
    utm_campaign:text(meta.utm_campaign,120)||null,
    utm_content:text(meta.utm_content,120)||null,
    metadata:{
      bot_version:BOT_VERSION,
      architecture:'standalone_liveconnect',
      course_slug:text(meta.course_slug,160)||null
    }
  }
  const {data,error}=await sb.from('commercial_chat_sessions').insert(row).select('*').single()
  if(error) throw error
  return data
}
async function getCourses(sb,type=null){
  let q=sb.from('courses').select('id,name,type,description,duration_months_1x_week,workload_hours').eq('active',true).order('name')
  if(type) q=q.eq('type',type)
  const {data,error}=await q.limit(180)
  if(error) throw error
  return data||[]
}
function courseScore(course,message){
  const q=norm(message)
  const n=norm(course.name)
  const d=norm(course.description||'')
  let score=0
  if(q===n) score+=100
  if(n.includes(q)&&q.length>2) score+=40
  if(q.includes(n)&&n.length>2) score+=35
  const stop=new Set(['quero','curso','cursos','fazer','para','trabalhar','area','profissional','formacao','gratuito','gratuita','gratis','apenas','somente'])
  const nt=new Set(n.split(' ')),dt=new Set(d.split(' '))
  for(const w of q.split(' ').filter(x=>x.length>=4&&!stop.has(x))){
    if(nt.has(w)) score+=8
    if(dt.has(w)) score+=2
  }
  const groups=[
    [/administrat|empresa|gestao|escritorio|contab|finance/,/administrat|gestao|escritorio|contab|finance/],
    [/informat|comput|excel|office|program|tecnolog|web|games/,/informat|excel|office|program|tecnolog|web|games|comput/],
    [/saude|farmac/,/saude|farmac/],
    [/marketing|social|midia|design|trafego/,/marketing|social|midia|design|trafego/],
    [/ingles|idioma/,/ingles|idioma/],
    [/beleza/,/beleza/],
    [/vendas|atendimento|comercial/,/vendas|atendimento|comercial/]
  ]
  for(const pair of groups) if(pair[0].test(q)&&pair[1].test(n+' '+d)) score+=18
  if(/administrat/.test(q)&&/auxiliar administrat/.test(n)) score+=14
  return score
}
async function matchCourse(sb,message,onlyFree=false){
  const list=await getCourses(sb,onlyFree?'gratuito':'pago')
  const ranked=list.map(c=>({c,s:courseScore(c,message)})).sort((a,b)=>b.s-a.s)
  return ranked[0]&&ranked[0].s>=30?ranked[0].c:null
}
async function recommend(sb,message,onlyFree=false){
  const list=await getCourses(sb,onlyFree?'gratuito':'pago')
  return list.map(c=>({c,s:courseScore(c,message)}))
    .filter(x=>x.s>0)
    .sort((a,b)=>b.s-a.s||String(a.c.name).localeCompare(String(b.c.name),'pt-BR'))
    .slice(0,3).map(x=>x.c)
}
function safeDescription(c){
  const d=String(c.description||'').replace(/\s+/g,' ').trim()
  if(!d||/curso presente no cat[aá]logo de cursos live connect 2026/i.test(d)) return 'Formação profissional voltada ao desenvolvimento de habilidades práticas para o mercado de trabalho.'
  return d
}
function courseList(list){
  return list.map((c,i)=>(i+1)+'. '+c.name+' — '+safeDescription(c).slice(0,120)).join('\n')
}
function coursePitch(c){
  const parts=[c.name+'.',safeDescription(c)]
  if(Number(c.duration_months_1x_week)>0) parts.push('Duração de referência: cerca de '+c.duration_months_1x_week+' '+(Number(c.duration_months_1x_week)===1?'mês':'meses')+'.')
  if(Number(c.workload_hours)>0) parts.push('Carga horária: '+c.workload_hours+' horas.')
  return parts.join('\n')
}
async function currentOffer(sb){
  try{
    const today=new Date().toISOString().slice(0,10)
    const {data}=await sb.from('campaigns').select('title,offer_text,enrollment_fee,monthly_fee,start_date,end_date,priority').eq('active',true).eq('highlight_public',true).order('priority',{ascending:false}).limit(20)
    return (data||[]).find(x=>(!x.start_date||String(x.start_date)<=today)&&(!x.end_date||String(x.end_date)>=today))||null
  }catch{return null}
}
function offerText(o){
  if(!o) return ''
  if(o.offer_text) return text(o.offer_text,500)
  const br=n=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})
  if(o.enrollment_fee!=null&&o.monthly_fee!=null) return 'Condição vigente: matrícula '+br(o.enrollment_fee)+' + mensalidades de '+br(o.monthly_fee)+'.'
  return text(o.title,300)
}
async function courseOffer(sb,courseName){
  try{
    const {data,error}=await sb.rpc('public_portal_commercial_offer',{p_course_name:courseName})
    if(error) return ''
    const o=Array.isArray(data)?data[0]||null:data
    if(!o) return ''
    const br=n=>Number(n||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'})
    const lines=[]
    if(o.monthly_price!=null) lines.push('Tradicional: mensalidades de '+br(o.monthly_price)+(Number(o.enrollment_fee||0)>0?' + matrícula de '+br(o.enrollment_fee):' com matrícula grátis')+'.')
    if(o.fast_track_total!=null) lines.push('Profissão Rápida: '+br(o.fast_track_total)+' no cartão, com parcelamento conforme as opções disponíveis.')
    return lines.join('\n')
  }catch{return ''}
}
async function presentOffer(sb,course){
  const direct=await courseOffer(sb,course.name)
  if(direct) return direct
  return offerText(await currentOffer(sb))
}
async function ensureLead(sb,s){
  if(!s.full_name||!s.whatsapp) return null
  const phone=parsePhone(s.whatsapp)
  if(!phone) return null
  const candidates=[phone,phone.replace(/^55/,'')].filter(Boolean)
  const {data:rows}=await sb.from('leads').select('id,lead_score').or('whatsapp.in.('+candidates.join(',')+'),whatsapp_normalized.in.('+candidates.join(',')+')').is('deleted_at',null).order('updated_at',{ascending:false}).limit(1)
  const payload={
    full_name:s.full_name,
    whatsapp:phone,
    professional_goal:s.objective||s.course_interest||'Qualificação profissional',
    landing_page:s.landing_page||null,
    referrer:s.referrer||null,
    utm_source:s.utm_source||null,
    utm_medium:s.utm_medium||null,
    utm_campaign:s.utm_campaign||null,
    utm_content:s.utm_content||null,
    updated_at:new Date().toISOString()
  }
  if(rows&&rows[0]){
    await sb.from('leads').update(Object.assign({},payload,{lead_score:Math.max(Number(rows[0].lead_score||0),Number(s.lead_score||90))})).eq('id',rows[0].id)
    await patchSession(sb,s.id,{lead_id:rows[0].id})
    return rows[0].id
  }
  const {data,error}=await sb.from('leads').insert(Object.assign({},payload,{source:'portal_chatbot',status:'pre_inscricao',lead_score:s.lead_score||90})).select('id').single()
  if(error) return null
  await patchSession(sb,s.id,{lead_id:data.id})
  return data.id
}

function hello(){
  return 'Olá! Eu sou o Lico, assistente da Live Connect. Posso te ajudar a escolher um curso, consultar valores e horários ou entender como funciona a matrícula. O que você procura hoje?'
}
function askName(){
  return 'Ótimo. Para eu registrar seu interesse para a equipe, como posso te chamar? Pode informar só o seu primeiro nome.'
}
function askPhone(name){
  return 'Perfeito'+(name?', '+name:'')+'. Qual é o seu WhatsApp com DDD para a equipe conseguir continuar seu atendimento, se necessário?'
}

Deno.serve(async req=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:cors(req)})
  if(req.method!=='POST') return reply(req,{ok:false,error:'method_not_allowed'},405)
  const origin=req.headers.get('origin')||''
  if(origin&&!ALLOWED.has(origin)&&!origin.startsWith('http://localhost:')&&!origin.startsWith('http://127.0.0.1:')) return reply(req,{ok:false,error:'origin_not_allowed'},403)

  try{
    const body=await req.json()
    if(text(body.website,100)) return reply(req,{ok:true})
    const sb=await client()
    const action=text(body.action,30)||'message'

    if(action==='start'){
      const token=text(body.token,80)
      let current=null
      if(/^[0-9a-f-]{36}$/i.test(token)){
        const {data}=await sb.from('commercial_chat_sessions').select('*').eq('public_token',token).maybeSingle()
        current=data||null
      }
      if(current&&openStatus(current.status)&&current.metadata&&current.metadata.bot_version===BOT_VERSION){
        return reply(req,{ok:true,token:current.public_token,session_id:current.id,stage:current.stage,status:current.status,resumed:true,new_session:false,messages:await history(sb,current.id)})
      }
      if(current) await patchSession(sb,current.id,{status:'closed',metadata:Object.assign({},current.metadata||{},{closed_reason:'bot_version_upgrade'})})
      const fresh=await createSession(sb,body.context&&typeof body.context==='object'?body.context:{})
      const out=hello()
      await append(sb,fresh.id,'assistant',out,{assistant:'Lico',stage:'discovery',bot_version:BOT_VERSION})
      return reply(req,{ok:true,token:fresh.public_token,session_id:fresh.id,stage:'discovery',status:'qualifying',new_session:true,message:out,messages:await history(sb,fresh.id)})
    }

    const token=text(body.token,80)
    if(!/^[0-9a-f-]{36}$/i.test(token)) return reply(req,{ok:false,error:'invalid_request'},400)
    const {data:s,error}=await sb.from('commercial_chat_sessions').select('*').eq('public_token',token).maybeSingle()
    if(error) throw error
    if(!s) return reply(req,{ok:false,error:'session_not_found'},404)

    if(action==='restart'){
      await patchSession(sb,s.id,{status:'closed',metadata:Object.assign({},s.metadata||{},{closed_reason:'user_restart'})})
      const fresh=await createSession(sb,body.context&&typeof body.context==='object'?body.context:{})
      const out=hello()
      await append(sb,fresh.id,'assistant',out,{assistant:'Lico',stage:'discovery',bot_version:BOT_VERSION})
      return reply(req,{ok:true,token:fresh.public_token,session_id:fresh.id,stage:'discovery',status:'qualifying',new_session:true,restarted:true,message:out,messages:await history(sb,fresh.id)})
    }
    if(action==='resume') return reply(req,{ok:true,token:s.public_token,stage:s.stage,status:s.status,resumed:true,messages:await history(sb,s.id)})
    if(action==='poll'){
      const {data:staff}=await sb.from('commercial_chat_messages').select('id,body,created_at').eq('session_id',s.id).eq('sender_type','staff').order('created_at',{ascending:false}).limit(40)
      return reply(req,{ok:true,token,status:s.status,handoff:!!s.assigned_to||s.status==='handoff',messages:[...(staff||[])].reverse()})
    }
    if(action==='prefill') return reply(req,{ok:true,token,contact_name:s.full_name||null,student_name:s.full_name||null,whatsapp:s.whatsapp||null,course_interest:s.course_interest||null,qualified:Number(s.lead_score||0)>=80})

    const message=text(body.message,1000)
    if(!message) return reply(req,{ok:false,error:'empty_message'},400)
    await append(sb,s.id,'visitor',message)

    if(s.assigned_to||s.status==='handoff') return reply(req,{ok:true,token,stage:'handoff',handoff:true,message:'Recebi sua mensagem. A equipe da Live Connect continuará o atendimento por aqui.'})

    if(wantsHuman(message)){
      await patchSession(sb,s.id,{status:'handoff',stage:'handoff'})
      const out='Claro. Vou encaminhar seu atendimento para a equipe da Live Connect. Você pode continuar escrevendo por aqui.'
      await append(sb,s.id,'assistant',out,{assistant:'Lico',stage:'handoff'})
      return reply(req,{ok:true,token,stage:'handoff',handoff:true,message:out})
    }

    if(wantsAddress(message)){
      const out='A Live Connect fica na Rua Sá Oliveira, 18, Ed. Empresarial Fraga Center, Sala 01, Centro, Ilhéus - BA. Se quiser, também posso te ajudar com cursos, valores e matrícula.'
      await append(sb,s.id,'assistant',out,{assistant:'Lico',kind:'address',stage:s.stage})
      return reply(req,{ok:true,token,stage:s.stage,message:out})
    }

    if(wantsPrice(message)&&s.course_interest){
      const {data:course}=await sb.from('courses').select('id,name,type,description,duration_months_1x_week,workload_hours').eq('active',true).eq('type',s.course_type||'pago').ilike('name',s.course_interest).limit(1).maybeSingle()
      const price=course&&course.type==='gratuito'?'Essa formação está cadastrada como gratuita. A equipe confirma apenas turma, horário e disponibilidade de vaga.':course?await presentOffer(sb,course):offerText(await currentOffer(sb))
      const out=price?price+'\n\nSe essa condição fizer sentido para você, posso registrar seu interesse e deixar o atendimento pronto para a equipe.':'Os valores dependem da formação e da modalidade. Posso confirmar a condição da sua escolha antes de você avançar.'
      await append(sb,s.id,'assistant',out,{assistant:'Lico',kind:'pricing',stage:s.stage})
      return reply(req,{ok:true,token,stage:s.stage,message:out})
    }

    let stage=s.stage||'discovery'
    let next=stage
    let patch={}
    let out=''

    if(isGreeting(message)){
      out='Olá! Tudo bem? Me diga o que você procura: um curso específico, uma área profissional, valores, horários ou matrícula.'
    }else if(stage==='discovery'){
      if(wantsPrice(message)&&!s.course_interest){
        out='Consigo te passar os valores, sim. Qual curso ou área você está procurando?'
      }else{
        const onlyFree=wantsFree(message)
        const direct=await matchCourse(sb,message,onlyFree)
        if(direct){
          next='availability'
          patch={course_interest:direct.name,course_type:direct.type,objective:text(message,400),stage:next,lead_score:35,metadata:Object.assign({},s.metadata||{},{bot_version:BOT_VERSION,architecture:'standalone_liveconnect',free_only:onlyFree})}
          out=coursePitch(direct)+'\n\n'+(direct.type==='gratuito'?'Os cursos gratuitos são presenciais. Qual período funciona melhor para você — manhã, tarde ou noite?':'Qual modalidade você prefere para eu registrar sua preferência: presencial ou EAD? Se for presencial, qual período funciona melhor — manhã, tarde ou noite?')
        }else{
          const picks=await recommend(sb,message,onlyFree)
          next='course'
          patch={objective:text(message,500),stage:next,lead_score:20,metadata:Object.assign({},s.metadata||{},{bot_version:BOT_VERSION,architecture:'standalone_liveconnect',free_only:onlyFree,suggestions:picks.map(x=>({id:x.id,name:x.name,type:x.type}))})}
          out=picks.length?(onlyFree?'Separei algumas opções gratuitas que podem fazer sentido:':'Pelo que você me contou, estas opções podem combinar com o que você procura:')+'\n\n'+courseList(picks)+'\n\nQual delas te interessa mais? Se nenhuma, me diga a área que você prefere.':(onlyFree?'Temos opções gratuitas, sim. Qual área mais te interessa — Administrativo, Tecnologia, Saúde, Marketing ou outra?':'Para eu não te indicar um curso aleatório, qual área mais te interessa — Administrativo, Tecnologia, Saúde, Marketing, Idiomas, Beleza ou outra?')
        }
      }
    }else if(stage==='course'){
      const suggestions=Array.isArray(s.metadata&&s.metadata.suggestions)?s.metadata.suggestions:[]
      const idx=Number(message.trim())-1
      let selected=Number.isInteger(idx)&&idx>=0&&idx<suggestions.length?suggestions[idx]:null
      if(selected){
        const all=await getCourses(sb,null)
        selected=all.find(x=>x.id===selected.id)||selected
      }else selected=await matchCourse(sb,message,!!(s.metadata&&s.metadata.free_only))
      if(!selected){
        const picks=await recommend(sb,message,!!(s.metadata&&s.metadata.free_only))
        patch={metadata:Object.assign({},s.metadata||{},{suggestions:picks.map(x=>({id:x.id,name:x.name,type:x.type}))})}
        out=picks.length?'Encontrei estas opções:\n\n'+courseList(picks)+'\n\nQual delas você quer conhecer melhor?':'Ainda não identifiquei uma formação. Pode me dizer a área ou o nome do curso?'
      }else{
        next='availability'
        patch={course_interest:selected.name,course_type:selected.type,stage:next,lead_score:40}
        out=coursePitch(selected)+'\n\n'+(selected.type==='gratuito'?'Os cursos gratuitos são presenciais. Qual período funciona melhor para você — manhã, tarde ou noite?':'Qual modalidade você prefere para eu registrar sua preferência: presencial ou EAD? Se for presencial, qual período funciona melhor — manhã, tarde ou noite?')
      }
    }else if(stage==='availability'){
      const neg=negativeAvailability(message)
      const av=parseAvailability(message)
      if(neg) out='Entendi que '+neg+' não funciona para você. Qual opção funciona melhor? '+(s.course_type==='gratuito'?'Os gratuitos são presenciais; pode ser manhã, tarde ou noite.':'Pode ser presencial de manhã, tarde ou noite, ou EAD.')
      else if(!av) out=s.course_type==='gratuito'?'Só preciso entender seu período disponível para o presencial: manhã, tarde ou noite.':'Só preciso entender sua preferência: presencial ou EAD? Se presencial, qual período — manhã, tarde ou noite?'
      else{
        const {data:course}=await sb.from('courses').select('id,name,type,description,duration_months_1x_week,workload_hours').eq('active',true).eq('type',s.course_type||'pago').ilike('name',s.course_interest||'').limit(1).maybeSingle()
        const isFree=(s.course_type==='gratuito'||course?.type==='gratuito')
        const offer=isFree?'':course?await presentOffer(sb,course):''
        next='offer'
        patch={stage:next,lead_score:65,metadata:Object.assign({},s.metadata||{},{availability:av,bot_version:BOT_VERSION,architecture:'standalone_liveconnect'})}
        out=(course?coursePitch(course):(s.course_interest||'Essa formação'))+'\n\n'+(isFree?'Essa opção é gratuita e presencial. A equipe confirma a turma, o horário e a disponibilidade de vaga antes da inscrição.\n\n':offer?offer+'\n\n':'')+'Se fizer sentido para você, posso registrar seu interesse e deixar seu atendimento pronto para a equipe. Quer avançar?'
      }
    }else if(stage==='offer'){
      const offerN=norm(message)
      if(/\b(caro|pesado|valor alto|nao cabe|sem dinheiro|nao consigo pagar|nao tenho como pagar)\b/.test(offerN)){
        out=s.course_type==='gratuito'?'Essa opção é gratuita. Se a preocupação for algum custo adicional, a equipe pode confirmar exatamente o que está incluído antes da inscrição.':'Entendo. Se o valor total ficou pesado, o Tradicional permite organizar o investimento mês a mês; a Profissão Rápida é a alternativa para quem prioriza acelerar a formação. Qual formato fica mais viável para você?'
      }else if(yes(message)||wantsEnroll(message)){
        next='contact_name'
        patch={stage:next,status:'qualified',lead_score:78}
        out=askName()
      }else if(no(message)) out='Sem problema. O que pesou mais para você: valor, horário, modalidade ou o próprio curso? Posso tentar te orientar sem compromisso.'
      else out='Pode me dizer sua dúvida. Se preferir avançar, basta responder “quero”.'
    }else if(stage==='contact_name'){
      const name=parseName(message)
      if(!name) out='Pode me dizer só o seu primeiro nome? Por exemplo: Leonardo.'
      else{
        next='contact_whatsapp'
        patch={full_name:name,stage:next,lead_score:84}
        out=askPhone(name.split(' ')[0])
      }
    }else if(stage==='contact_whatsapp'){
      const phone=parsePhone(message)
      if(!phone) out='Não consegui validar o número. Envie com DDD, por exemplo: (73) 99999-9999.'
      else{
        next='closing'
        patch={whatsapp:phone,stage:next,status:'qualified',lead_score:92}
        await patchSession(sb,s.id,patch)
        const fresh=Object.assign({},s,patch)
        await ensureLead(sb,fresh).catch(()=>null)
        const first=(s.full_name||'').split(' ')[0]
        out='Perfeito'+(first?', '+first:'')+'. Registrei seu interesse em '+(s.course_interest||'uma formação da Live Connect')+' e seu contato. A equipe já pode continuar a partir daqui. Se quiser, ainda posso esclarecer alguma dúvida sobre curso, valor ou horário.'
        await append(sb,s.id,'assistant',out,{assistant:'Lico',stage:next,qualified:true,bot_version:BOT_VERSION})
        return reply(req,{ok:true,token,stage:next,message:out,qualified:true,lead_score:92})
      }
    }else if(stage==='closing'){
      if(wantsEnroll(message)){
        patch={status:'closing',lead_score:96}
        out='Seu interesse já está registrado. A equipe da Live Connect pode finalizar a matrícula com você e confirmar os dados necessários.'
      }else out='Claro. Pode perguntar sobre curso, valor, horário ou matrícula. Se preferir falar com uma pessoa, é só pedir “atendente”.'
    }else{
      next='discovery'
      patch={stage:'discovery'}
      out=hello()
    }

    if(Object.keys(patch).length) await patchSession(sb,s.id,patch)
    await append(sb,s.id,'assistant',out,{assistant:'Lico',stage:next,bot_version:BOT_VERSION})
    return reply(req,{ok:true,token,stage:next,message:out,lead_score:Number(patch.lead_score??s.lead_score??0),handoff:next==='handoff'})
  }catch(err){
    console.error('portal-commercial-chat',err)
    return reply(req,{ok:false,error:'internal_error'},500)
  }
})
