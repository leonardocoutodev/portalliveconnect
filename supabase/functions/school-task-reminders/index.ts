import { createClient } from 'npm:@supabase/supabase-js@2.57.0'
import webpush from 'npm:web-push@3.6.7'

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{
  status,
  headers:{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store'}
})
const text=(v:unknown,max=500)=>String(v??'').trim().slice(0,max)
const b64u=(buf:ArrayBuffer)=>btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,'')

async function ensureVapid(service:any){
  const {data:cfg,error}=await service.rpc('school_push_service_get_vapid')
  if(error)throw error
  if(cfg?.public_key&&cfg?.private_key)return {publicKey:cfg.public_key,privateKey:cfg.private_key}
  const pair=await crypto.subtle.generateKey({name:'ECDSA',namedCurve:'P-256'},true,['sign','verify'])
  const pubRaw=await crypto.subtle.exportKey('raw',pair.publicKey)
  const privJwk:any=await crypto.subtle.exportKey('jwk',pair.privateKey)
  const publicKey=b64u(pubRaw),privateKey=String(privJwk.d||'')
  if(!privateKey)throw new Error('vapid_generation_failed')
  const {error:storeErr}=await service.rpc('school_push_service_store_vapid',{p_public_key:publicKey,p_private_key:privateKey})
  if(storeErr)throw storeErr
  return {publicKey,privateKey}
}

Deno.serve(async(req:Request)=>{
  if(req.method!=='POST')return reply({ok:false,error:'method_not_allowed'},405)
  try{
    const supplied=text(req.headers.get('x-cron-secret'),200)
    if(!supplied)return reply({ok:false,error:'missing_secret'},401)

    const url=Deno.env.get('SUPABASE_URL')!
    const raw=Deno.env.get('SUPABASE_SECRET_KEYS')
    const secret=raw?JSON.parse(raw)['default']:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    if(!secret)return reply({ok:false,error:'service_key_unavailable'},500)
    const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})

    const {data:secretOk,error:secretErr}=await service.rpc('school_task_reminder_secret_matches',{p_secret:supplied})
    if(secretErr||secretOk!==true)return reply({ok:false,error:'forbidden'},403)

    const {data:tasks,error:taskErr}=await service.rpc('school_chat_task_claim_push_reminders',{p_limit:100})
    if(taskErr)throw taskErr
    if(!Array.isArray(tasks)||tasks.length===0)return reply({ok:true,claimed:0,sent:0,failed:0})

    const userIds=[...new Set(tasks.map((t:any)=>t.assigned_to).filter(Boolean))]
    const {data:subs,error:subErr}=await service
      .from('school_push_subscriptions')
      .select('id,user_id,endpoint,p256dh,auth')
      .eq('active',true)
      .in('user_id',userIds)
    if(subErr)throw subErr

    const vapid=await ensureVapid(service)
    webpush.setVapidDetails('https://liveconnect.com.br',vapid.publicKey,vapid.privateKey)

    const byUser=new Map<string,any[]>()
    for(const s of subs||[]){
      const list=byUser.get(s.user_id)||[]
      list.push(s)
      byUser.set(s.user_id,list)
    }

    let sent=0,failed=0
    for(const task of tasks){
      const overdue=task.is_overdue===true
      const due=task.due_at?new Intl.DateTimeFormat('pt-BR',{
        timeZone:'America/Bahia',day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'
      }).format(new Date(task.due_at)):'sem prazo'
      const priority=String(task.priority||'normal')
      const payload=JSON.stringify({
        type:'school_chat_task',
        title:overdue?'⚠️ Tarefa atrasada • Live Connect':'⏰ Lembrete de tarefa • Live Connect',
        body:`${task.title} • prazo ${due}${priority==='urgente'?' • URGENTE':''}`,
        task_id:task.task_id,
        channel_id:task.channel_id,
        source_message_id:task.source_message_id,
        url:`/?lctask=${encodeURIComponent(task.task_id)}`,
        icon:'/assets/images/favicon.png',
        badge:'/assets/images/favicon.png',
        require_interaction:true
      })
      for(const s of byUser.get(task.assigned_to)||[]){
        try{
          await webpush.sendNotification(
            {endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},
            payload,
            {TTL:86400,urgency:'high'}
          )
          sent++
        }catch(err:any){
          failed++
          const code=Number(err?.statusCode||err?.status||0)
          if(code===404||code===410){
            await service.from('school_push_subscriptions')
              .update({active:false,updated_at:new Date().toISOString()})
              .eq('id',s.id)
          }
          console.warn('task-push-failed',task.task_id,code,err?.message||String(err))
        }
      }
    }

    return reply({ok:true,claimed:tasks.length,sent,failed})
  }catch(err){
    console.error('school-task-reminders',err)
    return reply({ok:false,error:'internal_error'},500)
  }
})