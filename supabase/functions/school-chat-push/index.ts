import { createClient } from 'npm:@supabase/supabase-js@2.57.0'
import webpush from 'npm:web-push@3.6.7'

const ALLOWED=new Set(['https://admin.liveconnectios.workers.dev'])
const cors=(req:Request)=>{
  const o=req.headers.get('origin')||''
  const ok=!o||ALLOWED.has(o)||o.startsWith('http://localhost:')||o.startsWith('http://127.0.0.1:')
  return {'Content-Type':'application/json; charset=utf-8','Access-Control-Allow-Origin':ok&&o?o:'https://admin.liveconnectios.workers.dev','Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store','Vary':'Origin'}
}
const reply=(req:Request,body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors(req)})
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
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors(req)})
  if(req.method!=='POST')return reply(req,{ok:false,error:'method_not_allowed'},405)
  try{
    const auth=req.headers.get('authorization')||''
    const token=auth.replace(/^Bearer\s+/i,'').trim()
    if(!token)return reply(req,{ok:false,error:'not_authenticated'},401)
    const url=Deno.env.get('SUPABASE_URL')!
    const raw=Deno.env.get('SUPABASE_SECRET_KEYS')
    const secret=raw?JSON.parse(raw)['default']:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    if(!secret)return reply(req,{ok:false,error:'service_key_unavailable'},500)
    const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})
    const actor=createClient(url,secret,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false,autoRefreshToken:false}})
    const {data:userData,error:userErr}=await service.auth.getUser(token)
    if(userErr||!userData?.user)return reply(req,{ok:false,error:'invalid_session'},401)
    const senderId=userData.user.id
    const {data:staff,error:staffErr}=await actor.rpc('is_staff')
    if(staffErr||staff!==true)return reply(req,{ok:false,error:'forbidden'},403)
    const body=await req.json().catch(()=>({}))
    const action=text(body.action,30)||'push'
    const vapid=await ensureVapid(service)
    if(action==='config')return reply(req,{ok:true,public_key:vapid.publicKey})

    const channelId=text(body.channel_id,80),message=text(body.message,220)
    if(!/^[0-9a-f-]{36}$/i.test(channelId)||!message)return reply(req,{ok:false,error:'invalid_request'},400)
    const {data:canWrite,error:accessErr}=await actor.rpc('school_chat_can_access',{p_channel_id:channelId,p_write:true})
    if(accessErr||canWrite!==true)return reply(req,{ok:false,error:'forbidden'},403)

    const [{data:channel,error:chErr},{data:profiles,error:prErr},{data:perms,error:pmErr},{data:subs,error:subErr}]=await Promise.all([
      service.from('school_chat_channels').select('id,name,channel_type,participant_roles').eq('id',channelId).maybeSingle(),
      service.from('profiles').select('id,full_name,role,active').eq('active',true),
      service.from('school_staff_permissions').select('user_id,can_manage_chat'),
      service.from('school_push_subscriptions').select('id,user_id,endpoint,p256dh,auth').eq('active',true)
    ])
    if(chErr||prErr||pmErr||subErr)throw chErr||prErr||pmErr||subErr
    if(!channel)return reply(req,{ok:false,error:'channel_not_found'},404)
    const pmap=new Map((perms||[]).map((x:any)=>[x.user_id,x]))
    const allowedUsers=new Set<string>()
    for(const p of profiles||[]){
      if(p.id===senderId)continue
      const chatAllowed=p.role==='master_admin'||p.role==='coadmin'||pmap.get(p.id)?.can_manage_chat===true
      if(!chatAllowed)continue
      if(channel.channel_type==='public'||p.role==='master_admin'||(channel.participant_roles||[]).includes(p.role))allowedUsers.add(p.id)
    }
    const sender=(profiles||[]).find((p:any)=>p.id===senderId)
    const payload=JSON.stringify({
      type:'school_chat_message',
      title:`Live Connect • ${channel.name}`,
      body:`${sender?.full_name||'Equipe'}: ${message}`,
      channel_id:channel.id,
      channel_name:channel.name,
      url:`/?lcchat=${encodeURIComponent(channel.id)}`,
      icon:'/assets/images/favicon.png',
      badge:'/assets/images/favicon.png'
    })
    webpush.setVapidDetails('https://liveconnect.com.br',vapid.publicKey,vapid.privateKey)
    let sent=0,failed=0
    for(const s of subs||[]){
      if(!allowedUsers.has(s.user_id))continue
      try{
        await webpush.sendNotification({endpoint:s.endpoint,keys:{p256dh:s.p256dh,auth:s.auth}},payload,{TTL:21600,urgency:'high'})
        sent++
      }catch(err:any){
        failed++
        const code=Number(err?.statusCode||err?.status||0)
        if(code===404||code===410)await service.from('school_push_subscriptions').update({active:false,updated_at:new Date().toISOString()}).eq('id',s.id)
        console.warn('push-failed',code,err?.message||String(err))
      }
    }
    return reply(req,{ok:true,sent,failed,recipients:allowedUsers.size})
  }catch(err){
    console.error('school-chat-push',err)
    return reply(req,{ok:false,error:'internal_error'},500)
  }
})