import { CONFIG } from './config.js?v=550';
import { getUTM, safeJSON, timeoutSignal } from './utils.js';

const { supabase } = CONFIG;
const SESSION_KEY = 'lc_auth_session_v2';
const STUDENT_SESSION_KEY = 'lc_student_session_v3';
const VISITOR_KEY = 'lc_portal_session_id_v2';
let visitorSession = sessionStorage.getItem(VISITOR_KEY);
if (!visitorSession) {
  visitorSession = crypto.randomUUID?.() || `lc-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  sessionStorage.setItem(VISITOR_KEY, visitorSession);
}

async function parse(res) {
  const text = await res.text();
  if (!text) return null;
  try { return JSON.parse(text); } catch { return text; }
}

function publicHeaders(extra={}) {
  return { apikey: supabase.publishableKey, 'Content-Type':'application/json', ...extra };
}

export function whatsappUrl(message='Olá! Vim pelo Portal Live Connect e gostaria de mais informações.') {
  return `https://api.whatsapp.com/send?phone=${CONFIG.brand.whatsapp}&text=${encodeURIComponent(message)}`;
}

export function track(event_type, metadata={}, course_name=null, lead_id=null) {
  const payload = {
    event_type,
    session_id: visitorSession,
    page_path: location.pathname + location.search,
    course_name,
    lead_id,
    referrer: document.referrer,
    ...getUTM(),
    metadata,
    website:''
  };
  fetch(supabase.analyticsEndpoint, {
    method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify(payload), keepalive:true
  }).catch(() => {});
}

export async function submitLead(payload) {
  const res = await fetch(supabase.leadEndpoint, {
    method:'POST', headers:{'Content-Type':'application/json'},
    body:JSON.stringify({...payload, landing_page:location.href, referrer:document.referrer, website:''})
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.ok) throw new Error(json.error || 'lead_submit_failed');
  return json;
}

export async function submitEnrollment(payload) {
  const res = await fetch(supabase.enrollmentEndpoint, {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.ok) throw new Error(json.error || 'enrollment_submit_failed');
  return json;
}


export async function submitYoungApprentice(payload) {
  const res = await fetch(supabase.youngApprenticeEndpoint, {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({...payload, landing_page:location.href, referrer:document.referrer, ...getUTM(), website:''})
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.ok) {
    const err = new Error(json.error || 'young_apprentice_submit_failed');
    err.payload = json;
    throw err;
  }
  return json;
}


export async function saveEnrollmentPreferences(payload) {
  const res=await fetch(supabase.enrollmentPreferencesEndpoint,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(payload)});
  const json=await parse(res)||{};
  if(!res.ok||!json.ok)throw new Error(json.error||'preferences_save_failed');
  return json;
}

export async function paymentRequest(payload) {
  const res = await fetch(supabase.paymentEndpoint, {
    method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.ok) {
    const err = new Error(json.error || 'payment_request_failed');
    err.payload = json;
    throw err;
  }
  return json;
}


export async function loadSpecialCourseCatalog(kind='') {
  try {
    const res=await fetch(`${supabase.url}/rest/v1/rpc/public_portal_special_course_catalog`,{
      method:'POST',headers:publicHeaders(),body:JSON.stringify({p_kind:kind||null}),signal:timeoutSignal(4500)
    });
    if(!res.ok)return [];
    const json=await parse(res);
    return Array.isArray(json)?json:[];
  } catch { return []; }
}

export async function loadCommercialOfferCatalog() {
  try {
    const res=await fetch(`${supabase.url}/rest/v1/rpc/public_portal_commercial_offer_catalog`,{
      method:'POST',headers:publicHeaders(),body:'{}',signal:timeoutSignal(3000)
    });
    if(!res.ok)return [];
    const json=await parse(res);
    return Array.isArray(json)?json:[];
  } catch { return []; }
}

export async function loadCommercialOffer(courseName) {
  try {
    const res=await fetch(`${supabase.url}/rest/v1/rpc/public_portal_commercial_offer`,{
      method:'POST',headers:publicHeaders(),body:JSON.stringify({p_course_name:courseName||null}),signal:timeoutSignal(3000)
    });
    if(!res.ok)return null;
    const json=await parse(res);return Array.isArray(json)?json[0]||null:json||null;
  } catch { return null; }
}

export async function loadCurrentPricing() {
  try {
    const res = await fetch(`${supabase.url}/rest/v1/rpc/public_portal_current_pricing`, {
      method:'POST', headers:publicHeaders(), body:'{}', signal:timeoutSignal(2600)
    });
    if (!res.ok) return null;
    const json=await parse(res);
    const row=Array.isArray(json)?json[0]:json;
    if(!row)return null;
    return {
      enrollment_fee:Number(row.enrollment_fee||0),
      monthly_fee:Number(row.monthly_fee||0),
      beauty_surcharge:Number(row.beauty_surcharge||0),
      valid_from:row.valid_from||null,
      valid_until:row.valid_until||null
    };
  } catch { return null; }
}

export async function loadCampaigns() {
  try {
    const res = await fetch(`${supabase.url}/rest/v1/rpc/public_active_campaigns`, {
      method:'POST', headers:publicHeaders(), body:'{}', signal:timeoutSignal(2800)
    });
    if (!res.ok) return [];
    const json = await parse(res);
    if (Array.isArray(json)) {
      if (json.length === 1 && Array.isArray(json[0]?.public_active_campaigns)) return json[0].public_active_campaigns;
      return json;
    }
    if (Array.isArray(json?.public_active_campaigns)) return json.public_active_campaigns;
    return [];
  } catch { return []; }
}


export async function loadFreeCourseOuroCatalog() {
  try {
    const res = await fetch(`${supabase.url}/rest/v1/rpc/portal_free_course_ouro_catalog`, {
      method:'POST',
      headers:publicHeaders(),
      body:'{}',
      signal:timeoutSignal(3500)
    });
    if (!res.ok) return [];
    const json = await parse(res);
    return Array.isArray(json) ? json : [];
  } catch {
    return [];
  }
}


export async function loadPaidCourseAcademicCatalog() {
  try {
    const res = await fetch(`${supabase.url}/rest/v1/rpc/portal_paid_course_academic_catalog`, {
      method:'POST',
      headers:publicHeaders(),
      body:'{}',
      signal:timeoutSignal(3500)
    });
    if (!res.ok) return [];
    const json = await parse(res);
    return Array.isArray(json) ? json : [];
  } catch {
    return [];
  }
}


export async function loadClassPreferences() {
  try {
    const res = await fetch(`${supabase.url}/rest/v1/rpc/public_portal_class_preferences`, {
      method:'POST',
      headers:publicHeaders(),
      body:'{}',
      signal:timeoutSignal(3000)
    });
    if (!res.ok) return [];
    const json=await parse(res);
    return Array.isArray(json)?json:[];
  } catch {
    return [];
  }
}


export function getStudentSession() {
  const session = safeJSON(sessionStorage.getItem(STUDENT_SESSION_KEY), null);
  if (!session?.token) return null;
  if (session.expires_at && Date.parse(session.expires_at) <= Date.now()) {
    sessionStorage.removeItem(STUDENT_SESSION_KEY);
    localStorage.removeItem(STUDENT_SESSION_KEY);
    return null;
  }
  return session;
}

function saveStudentSession(session) {
  const safe = {
    token: session.token,
    expires_at: session.expires_at,
    student: session.student || null
  };
  sessionStorage.setItem(STUDENT_SESSION_KEY, JSON.stringify(safe));
  localStorage.removeItem(STUDENT_SESSION_KEY);
  return safe;
}

export async function studentLogin(username, password) {
  const res = await fetch(supabase.ouroStudentEndpoint, {
    method:'POST',
    headers:{'Content-Type':'application/json'},
    body:JSON.stringify({ action:'login', username, password })
  });
  const data = await parse(res) || {};
  if (!res.ok || !data.ok || !data.token) {
    const known = ['too_many_attempts','student_inactive','student_not_resolved','invalid_credentials'];
    throw new Error(known.includes(data.error) ? data.error : 'invalid_credentials');
  }
  return saveStudentSession(data);
}

export function beginOuroBrowserSession() {
  try {
    const name = `lc_ouro_session_${Date.now()}`;
    const width = 460, height = 680;
    const left = Math.max(0, Math.round((window.screen.width - width) / 2));
    const top = Math.max(0, Math.round((window.screen.height - height) / 2));
    const popup = window.open('', name, `popup=yes,width=${width},height=${height},left=${left},top=${top}`);
    if (!popup) return null;
    popup.document.write(`<!doctype html><html lang="pt-BR"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Conectando ao EAD</title><style>body{margin:0;font-family:system-ui,-apple-system,Segoe UI,sans-serif;background:#f5f8ff;color:#08298f;display:grid;place-items:center;min-height:100vh}.box{text-align:center;padding:32px}.dot{width:46px;height:46px;border:5px solid #dce7ff;border-top-color:#1049c6;border-radius:50%;margin:0 auto 18px;animation:s .8s linear infinite}@keyframes s{to{transform:rotate(360deg)}}p{color:#51637e;line-height:1.5}</style></head><body><div class="box"><div class="dot"></div><strong>Conectando ao ambiente de aulas…</strong><p>Esta janela será fechada automaticamente.</p></div></body></html>`);
    popup.document.close();
    return { popup, name };
  } catch {
    return null;
  }
}

export function primeOuroBrowserSession(username, password, bridge = null) {
  try {
    const popup = bridge?.popup && !bridge.popup.closed ? bridge.popup : null;
    const target = bridge?.name || `lc_ouro_session_${Date.now()}`;
    if (!popup) return false;

    const form = document.createElement('form');
    form.method = 'POST';
    form.action = 'https://ead.ouromoderno.com.br/index.php?pag=entrar';
    form.target = target;
    form.style.display = 'none';

    const loginInput = document.createElement('input');
    loginInput.type = 'hidden';
    loginInput.name = 'login';
    loginInput.value = username;

    const passwordInput = document.createElement('input');
    passwordInput.type = 'hidden';
    passwordInput.name = 'senha';
    passwordInput.value = password;

    form.append(loginInput, passwordInput);
    document.body.appendChild(form);
    form.submit();

    // Remove a senha do DOM imediatamente após o POST.
    passwordInput.value = '';
    form.remove();

    // O POST acontece numa janela top-level da Ouro, permitindo que o domínio
    // ead.ouromoderno.com.br grave seu próprio cookie de sessão como first-party.
    setTimeout(() => {
      try { if (!popup.closed) popup.close(); } catch {}
    }, 4500);
    return true;
  } catch {
    try { bridge?.popup?.close(); } catch {}
    return false;
  }
}

export async function studentRequest(action, payload={}) {
  const session = getStudentSession();
  if (!session?.token) throw new Error('student_not_authenticated');
  const res = await fetch(supabase.ouroStudentEndpoint, {
    method:'POST',
    headers:{ 'Content-Type':'application/json', Authorization:`Bearer ${session.token}` },
    body:JSON.stringify({ action, ...payload })
  });
  const data = await parse(res) || {};
  if (res.status === 401) {
    sessionStorage.removeItem(STUDENT_SESSION_KEY);
    localStorage.removeItem(STUDENT_SESSION_KEY);
    throw new Error('student_session_expired');
  }
  if (!res.ok || !data.ok) throw new Error(data.error || 'student_request_failed');
  return data;
}

export async function getStudentDashboard() {
  const academic = await studentRequest('snapshot');
  try {
    const presencial = await getDkwebHistory();
    return { ...academic, presencial, presencial_error:null };
  } catch (error) {
    const code = String(error?.message || 'presencial_unavailable');
    if (code === 'student_session_expired') throw error;
    return { ...academic, presencial:null, presencial_error:code };
  }
}

export function getStudentCourseDetail(courseId, contractId) {
  return studentRequest('course_detail', { course_id:String(courseId), contract_id:String(contractId) });
}

export async function getDkwebHistory() {
  const session = getStudentSession();
  if (!session?.token) throw new Error('student_not_authenticated');
  const res = await fetch(supabase.dkwebStudentEndpoint, {
    method:'POST',
    headers:{ 'Content-Type':'application/json', Authorization:`Bearer ${session.token}` },
    body:JSON.stringify({ action:'summary' })
  });
  const data = await parse(res) || {};
  if (res.status === 401) {
    sessionStorage.removeItem(STUDENT_SESSION_KEY);
    localStorage.removeItem(STUDENT_SESSION_KEY);
    throw new Error('student_session_expired');
  }
  if (!res.ok || !data.ok) throw new Error(data.error || 'dkweb_request_failed');
  return data;
}

export function getStudentStudyLaunch() {
  return studentRequest('study_launch');
}

export async function studentLogout() {
  const session = getStudentSession();
  try {
    if (session?.token) await fetch(supabase.ouroStudentEndpoint, {
      method:'POST',
      headers:{ 'Content-Type':'application/json', Authorization:`Bearer ${session.token}` },
      body:JSON.stringify({ action:'logout' })
    });
  } catch {}
  sessionStorage.removeItem(STUDENT_SESSION_KEY);
  localStorage.removeItem(STUDENT_SESSION_KEY);
}

export function getSession() {
  const s = safeJSON(localStorage.getItem(SESSION_KEY), null);
  if (!s?.access_token) return null;
  return s;
}

function saveSession(session) {
  localStorage.setItem(SESSION_KEY, JSON.stringify(session));
  return session;
}

export async function login(email, password) {
  const res = await fetch(`${supabase.url}/auth/v1/token?grant_type=password`, {
    method:'POST', headers:publicHeaders(), body:JSON.stringify({email,password})
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.access_token) throw new Error(json.error_description || json.msg || 'invalid_login');
  return saveSession(json);
}

export async function refreshSession() {
  const current = getSession();
  if (!current?.refresh_token) return null;
  const res = await fetch(`${supabase.url}/auth/v1/token?grant_type=refresh_token`, {
    method:'POST', headers:publicHeaders(), body:JSON.stringify({refresh_token:current.refresh_token})
  });
  const json = await parse(res) || {};
  if (!res.ok || !json.access_token) { localStorage.removeItem(SESSION_KEY); return null; }
  return saveSession(json);
}

export async function authFetch(path, options={}) {
  let session = getSession();
  if (!session) throw new Error('not_authenticated');
  const exp = session.expires_at || (session.expires_in && session.created_at ? session.created_at + session.expires_in : null);
  if (exp && Date.now()/1000 > Number(exp)-60) session = await refreshSession();
  if (!session?.access_token) throw new Error('not_authenticated');
  const res = await fetch(`${supabase.url}${path}`, {
    ...options,
    headers: { ...publicHeaders(), Authorization:`Bearer ${session.access_token}`, ...(options.headers || {}) }
  });
  if (res.status === 401) {
    session = await refreshSession();
    if (!session) throw new Error('not_authenticated');
    return fetch(`${supabase.url}${path}`, {
      ...options,
      headers: { ...publicHeaders(), Authorization:`Bearer ${session.access_token}`, ...(options.headers || {}) }
    });
  }
  return res;
}

export async function getMyProfile() {
  const session = getSession();
  const userId = session?.user?.id;
  if (!userId) return null;
  const res = await authFetch(`/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=id,full_name,role,active,last_seen_at&limit=1`, {method:'GET'});
  if (!res.ok) return null;
  const data = await parse(res);
  return Array.isArray(data) ? data[0] || null : null;
}

export async function logout() {
  const session = getSession();
  try {
    if (session?.access_token) await fetch(`${supabase.url}/auth/v1/logout`, {method:'POST', headers:publicHeaders({Authorization:`Bearer ${session.access_token}`})});
  } catch {}
  localStorage.removeItem(SESSION_KEY);
}

function countFromRange(value='') {
  const m = String(value).match(/\/(\d+)$/);
  return m ? Number(m[1]) : 0;
}

export async function adminCount(table, query='') {
  const q = query ? `&${query}` : '';
  const res = await authFetch(`/rest/v1/${table}?select=id&limit=1${q}`, {method:'GET', headers:{Prefer:'count=exact'}});
  if (!res.ok) return 0;
  return countFromRange(res.headers.get('content-range'));
}

export async function adminList(table, select='*', order='created_at.desc', limit=8) {
  const res = await authFetch(`/rest/v1/${table}?select=${encodeURIComponent(select)}&order=${encodeURIComponent(order)}&limit=${limit}`, {method:'GET'});
  if (!res.ok) return [];
  const data = await parse(res);
  return Array.isArray(data) ? data : [];
}

export async function adminRpc(name, payload={}) {
  const res = await authFetch(`/rest/v1/rpc/${encodeURIComponent(name)}`, {method:'POST', body:JSON.stringify(payload)});
  if (!res.ok) return [];
  const data = await parse(res);
  return Array.isArray(data) ? data : (data ? [data] : []);
}

export async function getIntegrationSnapshot() {
  const [events, students] = await Promise.all([
    adminList('ouro_webhook_events','event_name,status,received_at,external_event_id','received_at.desc',6).catch(() => []),
    adminList('ouro_student_links','ouro_student_id,student_name,login,last_event_name,last_event_at,last_login_at,last_logout_at,lead_id','last_event_at.desc',6).catch(() => [])
  ]);
  return {events, students};
}

export async function adminRpcStrict(name, payload={}) {
  const res = await authFetch(`/rest/v1/rpc/${encodeURIComponent(name)}`, {method:'POST', body:JSON.stringify(payload)});
  const data = await parse(res);
  if (!res.ok) {
    const err = new Error(data?.message || data?.hint || data?.error || `rpc_${name}_failed`);
    err.payload = data;
    throw err;
  }
  return data;
}

export async function adminInsert(table, payload, select='*') {
  const res = await authFetch(`/rest/v1/${encodeURIComponent(table)}?select=${encodeURIComponent(select)}`, {
    method:'POST', headers:{Prefer:'return=representation'}, body:JSON.stringify(payload)
  });
  const data = await parse(res);
  if (!res.ok) throw new Error(data?.message || data?.error || `insert_${table}_failed`);
  return Array.isArray(data) ? data[0] || null : data;
}

export async function adminUpdate(table, id, payload, select='*') {
  const res = await authFetch(`/rest/v1/${encodeURIComponent(table)}?id=eq.${encodeURIComponent(id)}&select=${encodeURIComponent(select)}`, {
    method:'PATCH', headers:{Prefer:'return=representation'}, body:JSON.stringify(payload)
  });
  const data = await parse(res);
  if (!res.ok) throw new Error(data?.message || data?.error || `update_${table}_failed`);
  return Array.isArray(data) ? data[0] || null : data;
}

export async function adminDelete(table, id) {
  const res = await authFetch(`/rest/v1/${encodeURIComponent(table)}?id=eq.${encodeURIComponent(id)}`, {
    method:'DELETE', headers:{Prefer:'return=minimal'}
  });
  if (!res.ok) {
    const data = await parse(res);
    throw new Error(data?.message || data?.error || `delete_${table}_failed`);
  }
  return true;
}
