import { createClient } from 'npm:@supabase/supabase-js@2.57.0'

const PORTAL_ORIGIN='https://portallc.netlify.app'
const allowedOrigins=new Set([PORTAL_ORIGIN,'https://liveconnect.com.br','https://www.liveconnect.com.br'])
const schoolStatuses=new Set(['fundamental','medio','medio_concluido','nao_estuda'])
const shifts=new Set(['manha','tarde','noite','indiferente'])
const selectedClasses=new Map([['terca_0900_1000','Terça-feira • 09:00 às 10:00'],['quinta_1400_1500','Quinta-feira • 14:00 às 15:00']])

function originAllowed(origin:string){
  return !origin||allowedOrigins.has(origin)||origin.startsWith('http://localhost:')||origin.startsWith('http://127.0.0.1:')||/^https:\/\/[a-z0-9-]+--portallc\.netlify\.app$/i.test(origin)
}
function cors(req:Request){
  const origin=req.headers.get('origin')||''
  return {
    'Content-Type':'application/json; charset=utf-8',
    'Access-Control-Allow-Origin':originAllowed(origin)&&origin?origin:PORTAL_ORIGIN,
    'Vary':'Origin',
    'Access-Control-Allow-Headers':'content-type, apikey, x-client-info',
    'Access-Control-Allow-Methods':'POST, OPTIONS',
    'Cache-Control':'no-store, max-age=0'
  }
}
const reply=(req:Request,body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:cors(req)})
const text=(v:unknown,max=300)=>String(v??'').trim().slice(0,max)
const digits=(v:unknown)=>String(v??'').replace(/\D/g,'')
const uuid=(v:unknown)=>/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(String(v||''))?String(v):''
function calcAge(value:string){
  if(!/^\d{4}-\d{2}-\d{2}$/.test(value))return null
  const [y,m,d]=value.split('-').map(Number)
  const dt=new Date(Date.UTC(y,m-1,d,12))
  if(dt.getUTCFullYear()!==y||dt.getUTCMonth()!==m-1||dt.getUTCDate()!==d)return null
  const now=new Date()
  if(dt>now)return null
  let age=now.getUTCFullYear()-y
  const md=now.getUTCMonth()+1-m
  if(md<0||(md===0&&now.getUTCDate()<d))age--
  return age
}
function validCpf(value:string){
  const cpf=digits(value)
  if(!cpf)return true
  if(cpf.length!==11||/^(\d)\1{10}$/.test(cpf))return false
  const calc=(base:number)=>{let sum=0;for(let i=0;i<base;i++)sum+=Number(cpf[i])*(base+1-i);const r=(sum*10)%11;return r===10?0:r}
  return calc(9)===Number(cpf[9])&&calc(10)===Number(cpf[10])
}
function normalizedPhone(value:string){
  const d=digits(value)
  if(d.length===10||d.length===11)return '55'+d
  return d
}

Deno.serve(async(req:Request)=>{
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors(req)})
  if(req.method!=='POST')return reply(req,{ok:false,error:'method_not_allowed'},405)

  const origin=req.headers.get('origin')||''
  if(!originAllowed(origin))return reply(req,{ok:false,error:'origin_not_allowed'},403)

  try{
    const body=await req.json()
    if(text(body.website,200))return reply(req,{ok:true})

    const fullName=text(body.full_name,160)
    const rawPhone=digits(body.whatsapp)
    const phone=normalizedPhone(rawPhone)
    const birthDate=text(body.birth_date,10)
    const age=calcAge(birthDate)
    const schoolStatus=text(body.school_status,40)
    const availableShift=text(body.available_shift,30)
    const selectedClass=text(body.selected_class,40)

    if(fullName.split(/\s+/).length<2)return reply(req,{ok:false,error:'invalid_name'},400)
    if(rawPhone.length<10||rawPhone.length>13)return reply(req,{ok:false,error:'invalid_whatsapp'},400)
    if(age===null||age<10||age>40)return reply(req,{ok:false,error:'invalid_birth_date'},400)
    if(!schoolStatuses.has(schoolStatus))return reply(req,{ok:false,error:'invalid_school_status'},400)
    if(!shifts.has(availableShift))return reply(req,{ok:false,error:'invalid_available_shift'},400)
    if(!selectedClasses.has(selectedClass))return reply(req,{ok:false,error:'invalid_selected_class'},400)

    const zipCode=digits(body.zip_code)
    const street=text(body.street,180)
    const number=text(body.number,30)
    const neighborhood=text(body.neighborhood,120)
    const city=text(body.city,120)
    const stateCode=text(body.state,2).toUpperCase()
    if(zipCode.length!==8||!street||!number||!neighborhood||!city||!/^[A-Z]{2}$/.test(stateCode)){
      return reply(req,{ok:false,error:'invalid_address'},400)
    }

    const studentRg=text(body.rg,20).replace(/[^0-9A-Za-z.-]/g,'')||null
    const studentCpf=digits(body.cpf)||null
    if(studentCpf&&!validCpf(studentCpf))return reply(req,{ok:false,error:'invalid_cpf'},400)

    const isMinor=age<18
    const guardianName=text(body.guardian_name,160)
    const guardianPhoneRaw=digits(body.guardian_whatsapp)
    const guardianPhone=guardianPhoneRaw?normalizedPhone(guardianPhoneRaw):''
    const guardianRg=text(body.guardian_rg,20).replace(/[^0-9A-Za-z.-]/g,'')||null
    const guardianCpf=digits(body.guardian_cpf)||null
    const guardianBirthDate=text(body.guardian_birth_date,10)||null

    if(isMinor){
      if(guardianName.split(/\s+/).length<2||guardianPhoneRaw.length<10)return reply(req,{ok:false,error:'guardian_required'},400)
      if(guardianCpf&&!validCpf(guardianCpf))return reply(req,{ok:false,error:'invalid_guardian_cpf'},400)
      if(guardianBirthDate){
        const guardianAge=calcAge(guardianBirthDate)
        if(guardianAge===null||guardianAge<18)return reply(req,{ok:false,error:'invalid_guardian_birth_date'},400)
      }
    }

    const currentlyStudying=schoolStatus!=='medio_concluido'&&schoolStatus!=='nao_estuda'
    const submittedAt=new Date().toISOString()

    const url=Deno.env.get('SUPABASE_URL')!
    const raw=Deno.env.get('SUPABASE_SECRET_KEYS')
    const secret=raw?JSON.parse(raw)['default']:Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase=createClient(url,secret,{auth:{persistSession:false,autoRefreshToken:false}})

    const candidates=[rawPhone,phone].filter((x,i,a)=>x&&a.indexOf(x)===i)
    const {data:existingRows,error:lookupError}=await supabase
      .from('leads')
      .select('id,status')
      .in('whatsapp_normalized',candidates)
      .is('deleted_at',null)
      .order('updated_at',{ascending:false})
      .limit(1)
    if(lookupError)throw lookupError

    const leadPayload:Record<string,unknown>={
      full_name:fullName,
      whatsapp:phone,
      age,
      birth_date:birthDate,
      address:`${street}, ${number} - ${city}/${stateCode}`,
      neighborhood,
      zip_code:zipCode,
      is_minor:isMinor,
      rg:studentRg,
      cpf:studentCpf,
      guardian_name:isMinor?guardianName:null,
      guardian_whatsapp:isMinor?guardianPhone:null,
      guardian_rg:isMinor?guardianRg:null,
      guardian_cpf:isMinor?guardianCpf:null,
      guardian_birth_date:isMinor&&guardianBirthDate?guardianBirthDate:null,
      currently_studying:currentlyStudying,
      professional_goal:'Projeto Jovem Aprendiz',
      landing_page:text(body.landing_page,300),
      referrer:text(body.referrer,300),
      utm_source:text(body.utm_source,120)||null,
      utm_medium:text(body.utm_medium,120)||null,
      utm_campaign:text(body.utm_campaign,120)||null,
      utm_content:text(body.utm_content,120)||null,
      updated_at:submittedAt
    }

    let leadId:string
    const existing=existingRows?.[0]
    if(existing?.id){
      const {error}=await supabase.from('leads').update(leadPayload).eq('id',existing.id)
      if(error)throw error
      leadId=existing.id
    }else{
      const {data,error}=await supabase.from('leads').insert({
        ...leadPayload,
        status:'pre_inscricao',
        source:'portal_jovem_aprendiz',
        lead_score:80
      }).select('id').single()
      if(error)throw error
      leadId=data.id
    }

    const cutoff=new Date(Date.now()-45000).toISOString()
    const {data:recent,error:recentError}=await supabase
      .from('lead_interests')
      .select('id')
      .eq('lead_id',leadId)
      .eq('interest_type','jovem_aprendiz')
      .gte('created_at',cutoff)
      .order('created_at',{ascending:false})
      .limit(1)
    if(recentError)throw recentError

    if(recent?.length){
      const {data:existingForm}=await supabase
        .from('young_apprentice_registration_forms')
        .select('id')
        .eq('interest_id',recent[0].id)
        .maybeSingle()
      return reply(req,{ok:true,lead_id:leadId,interest_id:recent[0].id,form_id:existingForm?.id||null,duplicate:true})
    }

    const metadata={
      form_version:1,
      project:'jovem_aprendiz',
      school_status:schoolStatus,
      available_shift:availableShift,
      selected_class:selectedClass,
      selected_class_label:selectedClasses.get(selectedClass),
      currently_studying:currentlyStudying,
      student:{
        full_name:fullName,
        age,
        birth_date:birthDate,
        whatsapp:phone,
        rg:studentRg,
        cpf:studentCpf,
        address:{zip_code:zipCode,street,number,neighborhood,city,state:stateCode}
      },
      guardian:isMinor?{
        full_name:guardianName,
        whatsapp:guardianPhone,
        rg:guardianRg,
        cpf:guardianCpf,
        birth_date:guardianBirthDate
      }:null,
      submitted_at:submittedAt
    }

    const {data:interest,error:interestError}=await supabase.from('lead_interests').insert({
      lead_id:leadId,
      course_id:null,
      interest_type:'jovem_aprendiz',
      source:'portal_jovem_aprendiz',
      metadata
    }).select('id').single()
    if(interestError)throw interestError

    const snapshot={
      student_name:fullName,
      age,
      birth_date:birthDate,
      whatsapp:phone,
      rg:studentRg,
      cpf:studentCpf,
      address:`${street}, ${number} - ${city}/${stateCode}`,
      street,
      number,
      neighborhood,
      city,
      state:stateCode,
      zip_code:zipCode,
      guardian_name:isMinor?guardianName:null,
      guardian_whatsapp:isMinor?guardianPhone:null,
      guardian_rg:isMinor?guardianRg:null,
      guardian_cpf:isMinor?guardianCpf:null,
      guardian_birth_date:isMinor?guardianBirthDate:null,
      currently_studying:currentlyStudying,
      school_status:schoolStatus,
      available_shift:availableShift,
      selected_class:selectedClass,
      selected_class_label:selectedClasses.get(selectedClass),
      project:'Projeto Jovem Aprendiz',
      submitted_at:submittedAt
    }

    const {data:form,error:formError}=await supabase.from('young_apprentice_registration_forms').insert({
      lead_id:leadId,
      interest_id:interest.id,
      data_snapshot:snapshot
    }).select('id').single()
    if(formError)throw formError

    const {error:activityError}=await supabase.from('lead_activities').insert({
      lead_id:leadId,
      activity_type:'inscricao_jovem_aprendiz_portal',
      description:`Projeto Jovem Aprendiz — ficha recebida — turma: ${selectedClasses.get(selectedClass)}`,
      metadata:{interest_id:interest.id,form_id:form.id,school_status:schoolStatus,available_shift:availableShift,selected_class:selectedClass,selected_class_label:selectedClasses.get(selectedClass)}
    })
    if(activityError)throw activityError

    return reply(req,{ok:true,lead_id:leadId,interest_id:interest.id,form_id:form.id})
  }catch(error){
    console.error('portal-young-apprentice-submit',error)
    return reply(req,{ok:false,error:'internal_error'},500)
  }
})