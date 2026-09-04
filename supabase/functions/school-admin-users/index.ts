import { createClient } from 'npm:@supabase/supabase-js@2.57.0'

const ALLOWED=new Set(['https://admin.liveconnectios.workers.dev'])
const cors=(req:Request)=>{
  const o=req.headers.get('origin')||''
  const ok=!o||ALLOWED.has(o)||o.startsWith('http://localhost:')||o.startsWith('http://127.0.0.1:')
  return {
    'Content-Type':'application/json; charset=utf-8',
    'Access-Control-Allow-Origin':ok&&o?o:'https://admin.liveconnectios.workers.dev',
    'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info',
    'Access-Control-Allow-Methods':'POST, OPTIONS',
    'Cache-Control':'no-store',
    'Vary':'Origin'
  }
}
const reply=(req:Request,body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors(req)})
const text=(v:unknown,max=200)=>String(v??'').trim().slice(0,max)
const validEmail=(v:string)=>/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)
const roles=new Set(['coadmin','diretoria','admin_comercial','secretaria','readonly'])
const defaults=(role:string)=>{
  const masterLike=role==='coadmin'
  return {
    can_view_students:['coadmin','diretoria','admin_comercial','secretaria'].includes(role),
    can_edit_students:['coadmin','secretaria'].includes(role),
    can_view_finance:['coadmin','diretoria','secretaria'].includes(role),
    can_edit_finance:['coadmin','secretaria'].includes(role),
    can_delete_finance:false,
    can_view_reports:['coadmin','diretoria'].includes(role),
    can_manage_campaigns:['coadmin','admin_comercial'].includes(role),
    can_manage_chat:role!=='readonly',
    can_manage_users:false,
    can_manage_integrations:masterLike
  }
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors(req)})
  if(req.method!=='POST')return reply(req,{ok:false,error:'method_not_allowed'},405)
  const origin=req.headers.get('origin')||''
  if(origin&&!ALLOWED.has(origin)&&!origin.startsWith('http://localhost:')&&!origin.startsWith('http://127.0.0.1:'))return reply(req,{ok:false,error:'origin_not_allowed'},403)
  try{
    const auth=req.headers.get('authorization')||''
    const token=auth.replace(/^Bearer\s+/i,'').trim()
    if(!token)return reply(req,{ok:false,error:'not_authenticated'},401)

    const url=Deno.env.get('SUPABASE_URL')!
    const raw=Deno.env.get('SUPABASE_SECRET_KEYS')
    const secret=raw?JSON.parse(raw)['default']:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    if(!secret)return reply(req,{ok:false,error:'service_key_unavailable'},500)

    const service=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})
    const actor=createClient(url,secret,{
      global:{headers:{Authorization:`Bearer ${token}`}},
      auth:{persistSession:false,autoRefreshToken:false}
    })

    const {data:userData,error:userError}=await service.auth.getUser(token)
    if(userError||!userData?.user)return reply(req,{ok:false,error:'invalid_session'},401)
    const actorId=userData.user.id

    const {data:isOwner,error:ownerErr}=await actor.rpc('is_owner')
    if(ownerErr||isOwner!==true)return reply(req,{ok:false,error:'forbidden'},403)

    const body=await req.json().catch(()=>({}))
    const action=text(body.action,40)||'list'

    if(action==='list'){
      const {data:authData,error:authErr}=await service.auth.admin.listUsers({page:1,perPage:1000})
      if(authErr)throw authErr
      const [{data:profiles,error:pe},{data:perms,error:pme}]=await Promise.all([
        service.from('profiles').select('id,full_name,role,active,last_seen_at,created_at').order('full_name'),
        service.from('school_staff_permissions').select('*')
      ])
      if(pe)throw pe;if(pme)throw pme
      const pmap=new Map((perms||[]).map((p:any)=>[p.user_id,p]))
      const amap=new Map((authData?.users||[]).map((u:any)=>[u.id,u]))
      const users=(profiles||[]).map((p:any)=>{
        const au=amap.get(p.id)
        const pm=pmap.get(p.id)||{}
        return {
          id:p.id,full_name:p.full_name,role:p.role,active:p.active,last_seen_at:p.last_seen_at,created_at:p.created_at,
          email:au?.email||null,email_confirmed_at:au?.email_confirmed_at||null,last_sign_in_at:au?.last_sign_in_at||null,
          owner:p.id===actorId,
          permissions:{
            view_students:p.id===actorId?true:!!pm.can_view_students,
            edit_students:p.id===actorId?true:!!pm.can_edit_students,
            view_finance:p.id===actorId?true:!!pm.can_view_finance,
            edit_finance:p.id===actorId?true:!!pm.can_edit_finance,
            delete_finance:p.id===actorId?true:!!pm.can_delete_finance,
            view_reports:p.id===actorId?true:!!pm.can_view_reports,
            manage_campaigns:p.id===actorId?true:!!pm.can_manage_campaigns,
            manage_chat:p.id===actorId?true:!!pm.can_manage_chat,
            manage_users:p.id===actorId?true:!!pm.can_manage_users,
            manage_integrations:p.id===actorId?true:!!pm.can_manage_integrations
          }
        }
      })
      return reply(req,{ok:true,users})
    }

    if(action==='create'){
      const fullName=text(body.full_name,140).replace(/\s+/g,' ')
      const email=text(body.email,180).toLowerCase()
      const password=String(body.password??'')
      const role=text(body.role,40)
      if(fullName.length<3)return reply(req,{ok:false,error:'invalid_name'},400)
      if(!validEmail(email))return reply(req,{ok:false,error:'invalid_email'},400)
      if(password.length<8)return reply(req,{ok:false,error:'password_too_short'},400)
      if(!roles.has(role))return reply(req,{ok:false,error:'invalid_role'},400)

      const {data:created,error:createErr}=await service.auth.admin.createUser({
        email,password,email_confirm:true,user_metadata:{full_name:fullName}
      })
      if(createErr)return reply(req,{ok:false,error:createErr.message||'create_user_failed'},400)
      const id=created.user?.id
      if(!id)return reply(req,{ok:false,error:'create_user_failed'},500)
      try{
        const {error:profileErr}=await service.from('profiles').upsert({id,full_name:fullName,role,active:true,updated_at:new Date().toISOString()},{onConflict:'id'})
        if(profileErr)throw profileErr
        const d=defaults(role)
        const {error:permErr}=await service.from('school_staff_permissions').upsert({user_id:id,...d,updated_by:actorId,updated_at:new Date().toISOString()},{onConflict:'user_id'})
        if(permErr)throw permErr
        await service.from('audit_logs').insert({
          user_id:actorId,action:'staff_user_created',entity_type:'profile',entity_id:id,
          metadata:{full_name:fullName,email,role}
        })
      }catch(e){
        await service.auth.admin.deleteUser(id).catch(()=>null)
        throw e
      }
      return reply(req,{ok:true,user_id:id})
    }

    if(action==='reset_password'){
      const userId=text(body.user_id,80)
      const password=String(body.password??'')
      if(!/^[0-9a-f-]{36}$/i.test(userId))return reply(req,{ok:false,error:'invalid_user'},400)
      if(password.length<8)return reply(req,{ok:false,error:'password_too_short'},400)
      if(userId===actorId)return reply(req,{ok:false,error:'owner_password_change_not_here'},400)
      const {data,error}=await service.auth.admin.updateUserById(userId,{password})
      if(error)return reply(req,{ok:false,error:error.message||'password_update_failed'},400)
      await service.from('audit_logs').insert({
        user_id:actorId,action:'staff_password_reset',entity_type:'profile',entity_id:userId,metadata:{}
      })
      return reply(req,{ok:true,user_id:data.user?.id||userId})
    }

    return reply(req,{ok:false,error:'invalid_action'},400)
  }catch(err){
    console.error('school-admin-users',err)
    return reply(req,{ok:false,error:'internal_error'},500)
  }
})