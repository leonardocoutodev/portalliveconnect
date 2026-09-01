import { homePage, hydrateHome, coursesPage, hydrateCourses, courseCategoryPage, hydrateCourseCategory, coursePage, hydrateCourse, specialCatalogPage, hydrateSpecialCatalog, specialCoursePage, hydrateSpecialCourse, freePage, hydrateFree, youngPage, aboutPage, contactPage, hydrateContact, privacyPage, termsPage, studentPage, hydrateStudent, adminPage, hydrateAdmin, notFoundPage, metaFor } from './pages.js?v=550';
import { track } from './api.js?v=550';

const app=document.getElementById('app');
const DATA=window.LC_DATA||{courses:[]};
let lastTracked='';
history.scrollRestoration='manual';

const LEGACY_STYLE_URLS=['/assets/css/main.v360.css?v=530','/assets/css/responsive.v370.css?v=530'];
let formsPromise=null;
function loadForms(){return formsPromise||(formsPromise=import('./forms.js?v=520'));}
function styleLoaded(href){return [...document.querySelectorAll('link[rel="stylesheet"]')].some(l=>(l.getAttribute('href')||'').includes(href.split('?')[0]));}
function loadStyleBeforeHome(href){return new Promise(resolve=>{if(styleLoaded(href)){resolve();return;}const link=document.createElement('link');link.rel='stylesheet';link.href=href;link.dataset.legacyPortal='1';link.onload=resolve;link.onerror=resolve;const anchor=document.querySelector('link[data-v5-cards]')||document.querySelector('link[data-home-v5]');document.head.insertBefore(link,anchor||null);});}
async function ensureLegacyStyles(){await Promise.all(LEGACY_STYLE_URLS.map(loadStyleBeforeHome));}
function scheduleLegacyStyles(){const run=()=>LEGACY_STYLE_URLS.forEach(loadStyleBeforeHome);if('requestIdleCallback' in window)requestIdleCallback(run,{timeout:6500});else setTimeout(run,5000);}

function normalizePath(pathname){
  let p=pathname||'/';
  p=p.replace(/\/(?:index|default)\.(?:html?|HTML?)$/,'/');
  if(!p.startsWith('/'))p='/'+p;
  if(p!=='/'&&!p.endsWith('/'))p+='/';
  return p.replace(/\/{2,}/g,'/');
}

export function currentRoute(){
  const path=normalizePath(location.pathname);
  if(path==='/')return{name:'home',path};
  if(path==='/cursos/')return{name:'courses',path};
  const category=path.match(/^\/cursos\/area\/([^/]+)\/$/);if(category)return{name:'courseCategory',categorySlug:decodeURIComponent(category[1]),path};
  const course=path.match(/^\/cursos\/([^/]+)\/$/);if(course)return{name:'course',slug:decodeURIComponent(course[1]),path};
  if(path==='/nrs/')return{name:'nrs',path};
  if(path==='/nrs/curso/')return{name:'nrCourse',path};
  if(path==='/cursos-curtos/')return{name:'shortCourses',path};
  if(path==='/cursos-curtos/curso/')return{name:'shortCourse',path};
  if(path==='/gratuitos/')return{name:'free',path};
  if(path==='/jovem-aprendiz/')return{name:'young',path};
  if(path==='/sobre/')return{name:'about',path};
  if(path==='/contato/')return{name:'contact',path};
  if(path==='/privacidade/')return{name:'privacy',path};
  if(path==='/termos/')return{name:'terms',path};
  if(path==='/area-do-aluno/')return{name:'student',path};
  if(path==='/admin/')return{name:'admin',path};
  return{name:'notfound',path};
}

function renderRoute(route){
  if(route.name==='home')return homePage();
  if(route.name==='courses')return coursesPage();
  if(route.name==='courseCategory')return courseCategoryPage(route.categorySlug);
  if(route.name==='course')return coursePage(route.slug);
  if(route.name==='nrs')return specialCatalogPage('nr');
  if(route.name==='nrCourse')return specialCoursePage('nr');
  if(route.name==='shortCourses')return specialCatalogPage('short');
  if(route.name==='shortCourse')return specialCoursePage('short');
  if(route.name==='free')return freePage();
  if(route.name==='young')return youngPage();
  if(route.name==='about')return aboutPage();
  if(route.name==='contact')return contactPage();
  if(route.name==='privacy')return privacyPage();
  if(route.name==='terms')return termsPage();
  if(route.name==='student')return studentPage();
  if(route.name==='admin')return adminPage();
  return notFoundPage();
}

function updateMeta(route){
  const meta=metaFor(route);document.title=meta.title;
  let desc=document.querySelector('meta[name="description"]');if(desc)desc.content=meta.description;
  const canonical=document.querySelector('link[rel="canonical"]');if(canonical)canonical.href=location.origin+normalizePath(location.pathname);
  document.querySelector('meta[property="og:title"]')?.setAttribute('content',meta.title);
  document.querySelector('meta[property="og:description"]')?.setAttribute('content',meta.description);
  document.querySelector('meta[property="og:url"]')?.setAttribute('content',location.origin+normalizePath(location.pathname));
  const robots=document.querySelector('meta[name="robots"]');if(robots)robots.content=['admin','student','notfound'].includes(route.name)?'noindex,follow':'index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1';
  const ogImage=document.querySelector('meta[property="og:image"]');if(ogImage&&route.name==='course')ogImage.content=location.origin+`/assets/images/courses/${route.slug}.jpg`;else if(ogImage)ogImage.content=location.origin+'/assets/images/hero-main.jpg';
}

async function hydrate(route){
  if(route.name==='home')await hydrateHome();
  if(route.name==='courses')await hydrateCourses();
  if(route.name==='courseCategory')await hydrateCourseCategory(route.categorySlug);
  if(route.name==='nrs')await hydrateSpecialCatalog('nr');
  if(route.name==='nrCourse')await hydrateSpecialCourse('nr');
  if(route.name==='shortCourses')await hydrateSpecialCatalog('short');
  if(route.name==='shortCourse')await hydrateSpecialCourse('short');
  if(route.name==='free')hydrateFree();
  if(route.name==='contact')hydrateContact();
  if(route.name==='student')await hydrateStudent(navigate);
  if(route.name==='admin')await hydrateAdmin(navigate);
  if(route.name==='course'){const c=DATA.courses.find(x=>x.slug===route.slug);if(c)track('course_view',{},c.name);await hydrateCourse(route.slug);}
}

export async function render({replace=false}={}){
  const route=currentRoute();document.body.dataset.route=route.name;updateMeta(route);if(route.name!=='home')await ensureLegacyStyles();app.innerHTML=renderRoute(route);
  if(replace)history.replaceState({},'',location.href);
  closeMobileMenu();
  requestAnimationFrame(()=>window.scrollTo({top:0,left:0,behavior:'instant'}));
  const key=route.path+location.search;if(lastTracked!==key){lastTracked=key;track('page_view',{title:document.title,route:route.name});}
  await hydrate(route);
  setupScrollUI();
}

export function navigate(url,replace=false){
  const target=new URL(url,location.origin);
  if(target.origin!==location.origin){location.href=target.href;return;}
  if(replace)history.replaceState({},'',target.pathname+target.search+target.hash);else history.pushState({},'',target.pathname+target.search+target.hash);
  render();
}

function openMobileMenu(){const drawer=document.getElementById('mobileMenu'),btn=document.getElementById('mobileMenuButton');if(!drawer)return;drawer.classList.add('open');drawer.setAttribute('aria-hidden','false');btn?.setAttribute('aria-expanded','true');document.documentElement.classList.add('menu-open');drawer.querySelector('.mobile-nav a')?.focus();}
function closeMobileMenu(){const drawer=document.getElementById('mobileMenu'),btn=document.getElementById('mobileMenuButton');if(!drawer)return;drawer.classList.remove('open');drawer.setAttribute('aria-hidden','true');btn?.setAttribute('aria-expanded','false');document.documentElement.classList.remove('menu-open');}

function setupScrollUI(){const header=document.getElementById('siteHeader'),top=document.getElementById('backToTop');const apply=()=>{header?.classList.toggle('scrolled',scrollY>12);top?.classList.toggle('visible',scrollY>520);};apply();window.removeEventListener('scroll',window.__lcScrollHandler);window.__lcScrollHandler=apply;window.addEventListener('scroll',apply,{passive:true});}

async function globalClick(e){
  const router=e.target.closest('a[data-router]');if(router){const u=new URL(router.href,location.origin);if(u.origin===location.origin){e.preventDefault();if(router.closest('#mobileMenu'))closeMobileMenu();navigate(u.pathname+u.search+u.hash);return;}}
  if(e.target.closest('#mobileMenuButton')){openMobileMenu();return;}
  if(e.target.closest('[data-menu-close]')){closeMobileMenu();return;}
  const enroll=e.target.closest('[data-open-enroll]');if(enroll){await ensureLegacyStyles();const {openEnrollment}=await loadForms();const c=DATA.courses.find(x=>x.slug===enroll.dataset.openEnroll);if(c){c._selectedCommercialMode=enroll.dataset.commercialMode||'tradicional';openEnrollment(c);delete c._selectedCommercialMode;}return;}
  const free=e.target.closest('[data-open-free]');if(free){await ensureLegacyStyles();const {openFreeCourse}=await loadForms();openFreeCourse(free.dataset.openFree);return;}
  const lead=e.target.closest('[data-open-lead]');if(lead){await ensureLegacyStyles();const {openYoungApprenticeForm,openLeadCapture}=await loadForms();if(lead.dataset.openLead==='young')openYoungApprenticeForm();else openLeadCapture({title:'Quero saber mais',type:'contato',message:'Quero mais informações sobre a Live Connect.'});return;}
  const faq=e.target.closest('.faq-button');if(faq){const expanded=faq.getAttribute('aria-expanded')==='true',answer=document.getElementById(faq.getAttribute('aria-controls'));faq.setAttribute('aria-expanded',String(!expanded));if(answer)answer.hidden=expanded;faq.closest('.faq-item')?.classList.toggle('open',!expanded);return;}
  const wa=e.target.closest('[data-whatsapp]');if(wa){track('whatsapp_click',{location:wa.dataset.trackLocation||'unknown'});return;}
  const cwa=e.target.closest('[data-campaign-whatsapp]');if(cwa){track('campaign_cta_click',{campaign_code:cwa.dataset.campaignWhatsapp});return;}
  if(e.target.closest('#backToTop')){window.scrollTo({top:0,behavior:'smooth'});return;}
}

document.addEventListener('click',globalClick);
document.addEventListener('keydown',e=>{if(e.key==='Escape')closeMobileMenu();});
window.addEventListener('popstate',()=>render());
render({replace:true});
scheduleLegacyStyles();
