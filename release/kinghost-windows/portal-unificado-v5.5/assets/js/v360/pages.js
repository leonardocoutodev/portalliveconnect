import { CONFIG } from './config.js?v=550';
import { icon } from './icons.js';
import { esc, debounce, digits, firstName, formatDate } from './utils.js';
import { pageShell, sectionHeader, courseCard, freeCourseCard, campaignCard, breadcrumbs, faq, categoryList, objectiveList, metricCard, moduleMosaic } from './components.js?v=520';
import { loadCampaigns, loadCommercialOfferCatalog, loadCurrentPricing, loadFreeCourseOuroCatalog, loadSpecialCourseCatalog, whatsappUrl, track, submitLead, login, logout, getSession, getMyProfile, getStudentSession, studentLogin, studentLogout, getStudentDashboard, getStudentCourseDetail, beginOuroBrowserSession, primeOuroBrowserSession } from './api.js?v=550';
import { openModal } from './modal.js';
import { toast } from './toast.js';
import { applyCommercialOffers, moneyBR } from './commercial-offer.js';

const DATA = window.LC_DATA || {courses:[], freeCourses:[]};
const ADMIN_ROLES = new Set(['master_admin','coadmin','diretoria','admin_comercial','secretaria','readonly']);
const CATEGORY_SLUGS={"Administrativo":"administrativo","Beleza":"beleza","Design":"design","Games":"games","Idiomas":"idiomas","Informática":"informatica","Kids":"kids","Marketing":"marketing","Saúde":"saude","Tecnologia":"tecnologia"};
const CATEGORY_BY_SLUG=Object.fromEntries(Object.entries(CATEGORY_SLUGS).map(([k,v])=>[v,k]));
function slugifyCategory(name){return CATEGORY_SLUGS[name]||String(name||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,'');}

function applyCurrentPricing(pricing){
  if(!pricing)return;
  DATA.courses.forEach(c=>{
    const beauty=(c.slug==='profissional-da-beleza'||String(c.name||'').toUpperCase().includes('BELEZA'));
    c.currentPricing={
      enrollmentFee:Number(pricing.enrollment_fee||0),
      monthlyFee:Number(pricing.monthly_fee||0)+(beauty?Number(pricing.beauty_surcharge||0):0),
      validFrom:pricing.valid_from||null,
      validUntil:pricing.valid_until||null
    };
  });
}
function investmentBlock(course){
  const o=course.commercialOffer;if(!o)return '<div class="course-investment-card loading"><span>Investimento</span><strong>Consultando condição vigente…</strong></div>';
  return `<div class="course-investment-card"><div><span class="eyebrow">INVESTIMENTO VIGENTE</span><h3>Escolha como quer avançar na sua formação.</h3></div><div class="investment-values"><div><small>Matrícula tradicional</small><strong>${o.enrollmentFee<=0?'GRÁTIS':moneyBR(o.enrollmentFee)}</strong><span>${o.billingMonths}x de ${moneyBR(o.monthlyPrice)}</span></div><div><small>Profissão Rápida</small><strong>MATRÍCULA GRÁTIS</strong><span>${o.billingMonths}x de ${moneyBR(o.monthlyPrice)} no cartão</span></div></div><p>Condição calculada automaticamente com os valores vigentes. Mudou a campanha, mudou a oferta.</p></div>`;
}
function fastTrackComparator(course){
  const o=course.commercialOffer;if(!o||!o.fastTrackEnabled)return '';
  let benefits=(o.fastTrackBenefits||[]).filter(b=>!String(b).toLowerCase().includes('farda')||(course.modalities||[]).includes('Presencial')).map(b=>String(b).toLowerCase().includes('farda')?'Farda inclusa para cursos presenciais':b);if(!benefits.some(b=>String(b).toLowerCase().includes('desconto')))benefits.push('Desconto nas parcelas conforme a condição vigente');
  return `<section class="section fast-track-section" id="profissao-rapida"><div class="container-wide">
    <div class="fast-track-heading"><span class="eyebrow">DUAS FORMAS DE COMEÇAR</span><h2>Você escolhe como quer investir na sua formação.</h2><p>O Tradicional mantém a praticidade do pagamento mensal. O Profissão Rápida fecha o valor da formação desde o início, acelera seus estudos e elimina matrícula e adicionais mensais por atraso.</p></div>
    <div class="offer-mobile-tabs" role="tablist" aria-label="Comparar modalidades"><button type="button" role="tab" data-offer-tab="tradicional" aria-selected="false">Tradicional</button><button type="button" role="tab" data-offer-tab="profissao_rapida" aria-selected="true">Profissão Rápida <span>Recomendado</span></button></div>
    <div class="offer-compare-grid mobile-fast-active">
      <article class="offer-plan standard">
        <span class="plan-kicker">MODALIDADE TRADICIONAL</span><h3>Flexibilidade para pagar mês a mês</h3>
        <ul class="plan-feature-list">
          <li>1 aula por semana, conforme organização da turma</li>
          <li>Pagamento recorrente por Pix/boleto</li>
          <li>Matrícula vigente: <strong>${o.enrollmentFee<=0?'Grátis':moneyBR(o.enrollmentFee)}</strong></li>
          <li>${o.billingMonths} mensalidades de <strong>${moneyBR(o.monthlyPrice)}</strong></li>
          ${o.lateFee>0?`<li>Parcela paga após o vencimento: <strong>+ ${moneyBR(o.lateFee)}</strong> de adicional</li>`:''}
        </ul>
        <div class="traditional-cost-stack">
          <div><small>Valor-base da formação</small><strong>${moneyBR(o.standardBaseTotal)}</strong></div>
          ${o.projectedLateFeeTotal>0?`<div class="projected-cost"><small>Adicionais possíveis em ${o.billingMonths} atrasos</small><strong>+ ${moneyBR(o.projectedLateFeeTotal)}</strong></div>`:''}
        </div>
        <div class="plan-total projected"><small>Valor que o curso pode atingir*</small><strong>${moneyBR(o.standardProjectedTotal)}</strong></div>
        ${o.lateFee>0?`<p class="projection-note">*Projeção considerando o adicional por atraso em todas as ${o.billingMonths} mensalidades. Quem paga em dia mantém o valor-base.</p>`:''}
        <button class="btn btn-secondary btn-wide" type="button" data-open-enroll="${esc(course.slug)}" data-commercial-mode="tradicional">Prefiro pagar mês a mês</button>
      </article>
      <article class="offer-plan fast">
        <span class="recommended-badge">MAIOR CUSTO-BENEFÍCIO</span><span class="plan-kicker">PROFISSÃO RÁPIDA</span>
        <h3>Formação acelerada para quem quer avançar mais rápido.</h3>
        <div class="fast-price"><small>Matrícula</small><strong>GRÁTIS</strong></div>
        <div class="fast-price"><small>Valor integral parcelado no cartão</small><strong>${o.billingMonths}x de ${moneyBR(o.monthlyPrice)}</strong></div>
        <div class="fast-price"><small>Adicional mensal por atraso</small><strong>NÃO SE APLICA</strong></div>
        <div class="plan-total"><small>Valor fechado da formação</small><strong>${moneyBR(o.fastTrackTotal)}</strong></div>
        <div class="saving-pair">
          ${o.guaranteedSavings>0?`<div><small>Economia imediata</small><strong>${moneyBR(o.guaranteedSavings)}</strong><span>pela matrícula isenta</span></div>`:''}
          ${o.potentialSavings>0?`<div class="potential"><small>Diferença potencial de até</small><strong>${moneyBR(o.potentialSavings)}</strong><span>comparando com o cenário tradicional com atrasos</span></div>`:''}
        </div>
        <p class="same-installment">O valor da formação é calculado pela duração do curso. A referência de cada parcela continua em <strong>${moneyBR(o.monthlyPrice)}</strong>. No Profissão Rápida, você não paga matrícula, fecha o valor da formação desde o início e não fica sujeito ao adicional mensal por atraso do modelo recorrente.</p>
        <div class="fast-benefit-title"><strong>Diferenciais do programa</strong><span>Mais ritmo, flexibilidade e benefícios para acelerar sua qualificação.</span></div>
        <ul class="fast-benefits">${benefits.map(b=>`<li>${icon('check')} ${esc(b)}</li>`).join('')}</ul>
        <button class="btn btn-primary btn-wide btn-lg" type="button" data-open-enroll="${esc(course.slug)}" data-commercial-mode="profissao_rapida">Quero o Profissão Rápida ${icon('arrow')}</button>
      </article>
    </div>
  </div></section>`;
}

function hero() {
  return `<section class="home-v5-hero">
    <div class="container-wide home-v5-hero-grid">
      <div class="home-v5-hero-copy">
        <span class="home-v5-kicker">CURSOS PROFISSIONALIZANTES EM ILHÉUS</span>
        <h1>Aprenda uma profissão. <span>Avance com mais preparo.</span></h1>
        <p>Formações presenciais e EAD para quem quer conquistar o primeiro emprego, evoluir na carreira ou desenvolver uma nova habilidade com aplicação prática.</p>
        <div class="home-v5-actions"><a class="btn btn-primary btn-lg" href="/cursos/" data-router>Encontrar meu curso ${icon('arrow')}</a><a class="btn btn-outline btn-lg" href="${whatsappUrl('Olá! Quero ajuda para escolher a melhor formação para o meu objetivo.')}" target="_blank" rel="noopener" data-whatsapp data-track-location="hero">${icon('whatsapp')} Falar com a equipe</a></div>
        <div class="home-v5-proof-row"><a href="https://www.google.com/maps/search/?api=1&query=Live+Connect+Escola+de+Profissoes+Ilheus" target="_blank" rel="noopener"><strong>5,0 ★</strong><span>mais de 200 avaliações no Google</span></a><div><strong>Desde 2016</strong><span>presença em Ilhéus</span></div></div>
      </div>
      <div class="home-v5-hero-media">
        <img class="home-v5-hero-photo" src="/assets/images/hero-main.jpg" width="1800" height="949" alt="Estudantes em ambiente de aprendizagem profissional" fetchpriority="high" decoding="async">
        <div class="home-v5-hero-badge"><span>${icon('award')}</span><div><strong>Presencial + EAD</strong><small>Escolha a modalidade disponível para sua formação.</small></div></div>
        <img class="home-v5-hero-mascot" src="/assets/images/mascotes/mascote-hero-v5.png" width="440" height="782" alt="Mascote Live Connect" loading="lazy" decoding="async">
      </div>
    </div>
  </section>`;
}

export function homePage() {
  const featured = DATA.courses.filter(c=>c.featured).slice(0,6);
  const free = DATA.freeCourses.slice(0,6);
  const homeFaq=[
    {q:'Qual curso combina mais com o meu objetivo?',a:'Você pode explorar por área ou falar com a equipe da Live Connect. O atendimento ajuda a comparar conteúdo, modalidade e rotina antes da matrícula.'},
    {q:'Existem cursos presenciais e EAD?',a:'Sim. A modalidade disponível depende de cada formação. Essa informação aparece no card e na página do curso.'},
    {q:'Como funciona o Profissão Rápida?',a:'É uma forma acelerada de fazer formações elegíveis, com benefícios comerciais e mais flexibilidade de ritmo. As condições vigentes aparecem na página de cada curso.'},
    {q:'A Live Connect oferece cursos gratuitos?',a:'Sim. Há um catálogo de cursos gratuitos presenciais e também o Projeto Jovem Aprendiz. As vagas dependem da disponibilidade de turma.'},
    {q:'Os cursos têm certificado?',a:'Sim. Ao concluir a formação conforme as regras aplicáveis, o aluno recebe certificado de conclusão.'}
  ];
  const content = `<div class="lc-home-v5">${hero()}
    <section class="home-v5-trust"><div class="container-wide home-v5-trust-grid"><div>${icon('location')}<strong>Unidade no Centro de Ilhéus</strong><span>Rua Sá Oliveira, 18 • Fraga Center</span></div><div>${icon('graduation')}<strong>${DATA.courses.length} formações profissionais</strong><span>Áreas para diferentes objetivos de carreira</span></div><div>${icon('monitor')}<strong>Presencial e EAD</strong><span>Modalidades conforme cada formação</span></div><div>${icon('award')}<strong>Certificado de conclusão</strong><span>Formação para fortalecer o currículo</span></div></div></section>
    <section class="campaign-zone home-v5-campaign" id="campaignZone" hidden><div class="container-wide"><div id="campaignMount"></div></div></section>
    <section class="section home-v5-objectives"><div class="container-wide">${sectionHeader('COMECE PELO SEU OBJETIVO','O que você quer conquistar agora?','Escolha um caminho e veja formações que fazem sentido para o seu momento.')}
      <div class="home-v5-objective-grid">
        <a href="/jovem-aprendiz/" data-router><span>${icon('briefcase')}</span><div><strong>Quero meu primeiro emprego</strong><small>Preparação e Projeto Jovem Aprendiz</small></div>${icon('arrow')}</a>
        <a href="/cursos/area/administrativo/" data-router><span>${icon('layers')}</span><div><strong>Quero trabalhar em escritório</strong><small>Administração, financeiro e gestão</small></div>${icon('arrow')}</a>
        <a href="/cursos/area/tecnologia/" data-router><span>${icon('monitor')}</span><div><strong>Quero entrar na tecnologia</strong><small>Programação, IA e desenvolvimento</small></div>${icon('arrow')}</a>
        <a href="/cursos/area/marketing/" data-router><span>${icon('spark')}</span><div><strong>Quero trabalhar com internet</strong><small>Marketing, vendas e mídias digitais</small></div>${icon('arrow')}</a>
        <a href="/cursos/area/saude/" data-router><span>${icon('users')}</span><div><strong>Quero atuar com atendimento</strong><small>Saúde, farmácia e serviços</small></div>${icon('arrow')}</a>
      </div>
    </div></section>
    <section class="section home-v5-featured"><div class="container-wide">${sectionHeader('FORMAÇÕES EM DESTAQUE','Cursos para transformar interesse em habilidade.','Conheça algumas das formações mais completas do catálogo Live Connect.')}
      <div class="course-grid home-course-grid">${featured.map(c=>courseCard(c)).join('')}</div>
      <div class="center-action"><a class="btn btn-secondary btn-lg" href="/cursos/" data-router>Explorar todas as formações ${icon('arrow')}</a></div>
    </div></section>
    <section class="home-v5-fast"><div class="container-wide home-v5-fast-grid"><div class="home-v5-fast-copy"><span class="eyebrow yellow">PROFISSÃO RÁPIDA</span><h2>Duas formas de estudar. Escolha a que combina com seu momento.</h2><p>Compare o modelo tradicional com o Profissão Rápida e entenda, de forma simples, o que muda no ritmo e na forma de pagamento.</p><ul><li>${icon('check')} Matrícula grátis no Profissão Rápida</li><li>${icon('check')} Ritmo de estudo acelerado</li><li>${icon('check')} Mais opções de dias e horários</li><li>${icon('check')} Valor da formação fechado no cartão</li></ul><a class="btn btn-yellow btn-lg" href="/cursos/" data-router>Comparar nas formações ${icon('arrow')}</a></div><div class="home-v5-fast-panel home-v6-fast-panel"><article class="home-v6-plan"><small>TRADICIONAL</small><strong>Pagamento mensal</strong><ul><li><b>Ritmo</b><span>Padrão da turma</span></li><li><b>Pagamento</b><span>Mês a mês</span></li><li><b>Flexibilidade</b><span>Conforme turma disponível</span></li></ul></article><article class="home-v6-plan featured"><span class="home-v6-recommended">RECOMENDADO</span><small>PROFISSÃO RÁPIDA</small><strong>Formação acelerada</strong><ul><li><b>Matrícula</b><span>Grátis</span></li><li><b>Ritmo</b><span>Acelerado</span></li><li><b>Horários</b><span>Mais flexíveis</span></li><li><b>Pagamento</b><span>Valor fechado da formação</span></li></ul></article></div></div></section>
    <section class="section home-v5-confidence"><div class="container-wide home-v5-confidence-grid"><div class="home-v5-confidence-copy"><span class="eyebrow">CONFIANÇA LOCAL</span><h2>Uma escola de profissões que você pode visitar, conhecer e acompanhar de perto.</h2><p>A Live Connect atende em Ilhéus desde 2016 e mantém uma unidade física no Centro, além das opções online disponíveis em parte das formações.</p><div class="home-v5-rating"><strong>5,0</strong><span>★★★★★</span><p>mais de 200 avaliações no Google</p></div><div class="home-v5-actions"><a class="btn btn-primary" href="/sobre/" data-router>Conhecer a Live Connect</a><a class="btn btn-secondary" href="https://www.google.com/maps/search/?api=1&query=Rua+Sa+Oliveira+18+Fraga+Center+Ilheus+BA" target="_blank" rel="noopener">Como chegar ${icon('arrow')}</a></div></div><div class="home-v5-location-card"><span>${icon('location')}</span><div><small>UNIDADE LIVE CONNECT</small><h3>Centro de Ilhéus</h3><p>Rua Sá Oliveira, 18 • Ed. Empresarial Fraga Center • Sala 01</p><hr><div><b>${icon('phone')} (73) 3223-7593</b><b>${icon('clock')} Atendimento de segunda a sábado</b></div></div></div></div></section>
    <section class="section home-v5-free"><div class="container-wide home-v5-split"><div class="home-v5-free-copy"><span class="eyebrow">OPORTUNIDADE DE COMEÇAR</span><h2>Cursos gratuitos para desenvolver uma habilidade e conhecer a Live Connect.</h2><p>Opções presenciais para quem quer começar sem custo de curso. Consulte vagas e turmas disponíveis.</p><div class="home-v5-free-list">${free.map(c=>`<button type="button" data-open-free="${esc(c.slug)}"><img src="/${c.icon}" width="42" height="42" alt="" loading="lazy"><span>${esc(c.name)}</span>${icon('arrow')}</button>`).join('')}</div><a class="btn btn-primary" href="/gratuitos/" data-router>Ver todos os cursos gratuitos ${icon('arrow')}</a></div><div class="home-v5-young-card"><img src="/assets/images/mascotes/mascote-jovem-v5.png" width="430" height="764" alt="Mascote Live Connect estudando" loading="lazy" decoding="async"><div><span class="eyebrow yellow">JOVEM APRENDIZ</span><h2>Primeiro emprego exige preparo.</h2><p>Projeto gratuito para desenvolver postura profissional, comunicação, currículo e preparação para processos seletivos.</p><a class="btn btn-yellow" href="/jovem-aprendiz/" data-router>Conhecer o projeto ${icon('arrow')}</a></div></div></div></section>
    <section class="section home-v5-why"><div class="container-wide">${sectionHeader('POR QUE LIVE CONNECT','Formação prática, atendimento próximo e escolhas mais claras.','Uma experiência pensada para ajudar você a sair da dúvida e avançar com segurança.')}
      <div class="home-v5-why-grid"><article><span>${icon('graduation')}</span><h3>Formações completas</h3><p>Módulos conectados em uma única jornada, evitando conteúdos soltos e sem direção.</p></article><article><span>${icon('users')}</span><h3>Atendimento humano</h3><p>Equipe local para orientar modalidade, matrícula, turma e próximos passos.</p></article><article><span>${icon('briefcase')}</span><h3>Conteúdo para uso real</h3><p>Habilidades aplicáveis ao trabalho, aos estudos, ao negócio próprio e à rotina digital.</p></article></div>
    </div></section>
    <section class="section home-v5-faq"><div class="container-narrow">${sectionHeader('DÚVIDAS FREQUENTES','Antes de escolher, entenda como funciona.','')}${faq(homeFaq)}</div></section>
    <section class="home-v5-final"><div class="container-wide home-v5-final-grid"><div><span class="eyebrow yellow">SEU PRÓXIMO PASSO</span><h2>Não sabe qual curso escolher? A gente ajuda.</h2><p>Conte seu objetivo e receba orientação para encontrar a formação que combina com sua rotina.</p></div><div class="home-v5-actions"><a class="btn btn-yellow btn-lg" href="${whatsappUrl('Olá! Quero ajuda para escolher uma formação na Live Connect.')}" target="_blank" rel="noopener" data-whatsapp data-track-location="final_cta">${icon('whatsapp')} Falar com a equipe</a><a class="btn btn-white btn-lg" href="/cursos/" data-router>Ver cursos ${icon('arrow')}</a></div></div></section>
  </div>`;
  return pageShell(content,'home');
}

export async function hydrateHome() {
  const [campaigns,offers]=await Promise.all([loadCampaigns(),loadCommercialOfferCatalog()]);
  applyCommercialOffers(DATA.courses,offers);
  const homeGrid=document.querySelector('.home-course-grid');
  if(homeGrid){const featured=DATA.courses.filter(c=>c.featured).slice(0,6);homeGrid.innerHTML=featured.map(c=>courseCard(c)).join('');}
  const zone=document.getElementById('campaignZone'), mount=document.getElementById('campaignMount');
  if(campaigns.length && zone && mount){
    const primary=campaigns.filter(c=>c.show_home!==false).sort((a,b)=>(b.priority||0)-(a.priority||0))[0];
    if(primary){zone.hidden=false;mount.innerHTML=`${sectionHeader('CONDIÇÃO EM DESTAQUE','Uma oportunidade para facilitar seu começo.','Campanhas são atualizadas automaticamente pela Live Connect.','left')}${campaignCard(primary,{hero:true})}`;}
    const popup=campaigns.find(c=>c.show_popup);
    const key=popup?`lc_campaign_seen_${popup.id}`:'';
    if(popup && !sessionStorage.getItem(key)){
      let shown=false;
      const showPopup=()=>{
        if(shown||sessionStorage.getItem(key))return;
        shown=true;sessionStorage.setItem(key,'1');
        openModal({title:'Condição especial',eyebrow:popup.public_badge||'OPORTUNIDADE',size:'lg',content:`<div class="campaign-modal">${campaignCard(popup,{hero:true,popup:true})}</div>`});
        track('campaign_popup_view',{campaign_code:popup.code||null});
        window.removeEventListener('scroll',onScroll);
      };
      const onScroll=()=>{const total=Math.max(1,document.documentElement.scrollHeight-innerHeight);if(scrollY/total>=0.42)showPopup();};
      window.addEventListener('scroll',onScroll,{passive:true});
      setTimeout(showPopup,12000);
    }
  }
}

export function coursesPage() {
  const cats=categoryList(), objectives=objectiveList();
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Cursos',href:'/cursos/'}])}<div class="container-wide course-family-tabs" role="navigation" aria-label="Tipos de cursos"><a class="active" href="/cursos/" data-router>Formações completas</a><a href="/nrs/" data-router>NRs</a><a href="/cursos-curtos/" data-router>Cursos Curtos</a></div><section class="page-hero compact"><div class="container-wide"><span class="eyebrow">CATÁLOGO LIVE CONNECT</span><h1>Encontre a formação que combina com <span>seu próximo objetivo.</span></h1><p>Filtre por objetivo, área e modalidade. Cada formação reúne vários módulos em uma jornada única.</p></div></section><section class="section catalog-section"><div class="container-wide"><div class="catalog-tools"><label class="search-box" for="courseSearch">${icon('search')}<span class="sr-only">Pesquisar cursos</span><input id="courseSearch" type="search" placeholder="Busque por curso, módulo ou área…" autocomplete="off"></label>
    <div class="catalog-filter-group"><strong>Por objetivo</strong><div class="filter-row" id="objectiveFilters">${objectives.map((o,i)=>`<button type="button" class="filter-pill ${i===0?'active':''}" data-course-objective="${esc(o)}">${esc(o)}</button>`).join('')}</div></div>
    <div class="catalog-filter-group"><strong>Por área</strong><div class="filter-row" id="categoryFilters">${cats.map((c,i)=>`<button type="button" class="filter-pill ${i===0?'active':''}" data-course-category="${esc(c)}">${esc(c)}</button>`).join('')}</div></div>
    <div class="catalog-filter-group"><strong>Modalidade</strong><div class="filter-row small" id="modalityFilters"><button type="button" class="filter-pill active" data-course-modality="Todos">Todas</button><button type="button" class="filter-pill" data-course-modality="Presencial">Presencial</button><button type="button" class="filter-pill" data-course-modality="EAD">EAD</button></div></div>
    </div><div class="catalog-result-head"><strong id="courseCount">${DATA.courses.length} formações</strong><span>Use os filtros para encontrar uma opção compatível com seu objetivo.</span></div><div class="course-grid" id="courseGrid">${DATA.courses.map(c=>courseCard(c)).join('')}</div><div class="empty-state" id="courseEmpty" hidden>${icon('search')}<h3>Nenhuma formação encontrada.</h3><p>Tente outro termo ou remova alguns filtros.</p></div></div></section>`,'courses');
}

export async function hydrateCourses() {
  const offers=await loadCommercialOfferCatalog();applyCommercialOffers(DATA.courses,offers);
  const input=document.getElementById('courseSearch'), grid=document.getElementById('courseGrid'), count=document.getElementById('courseCount'), empty=document.getElementById('courseEmpty');
  if(!grid)return;
  let cat=new URL(location.href).searchParams.get('categoria')||'Todos',mod='Todos',objective='Todos',query='';
  const valid=categoryList();if(!valid.includes(cat))cat='Todos';
  function courseObjectiveLocal(c){
    const n=(c.name||'').toLowerCase(), k=(c.category||'').toLowerCase();
    if(k.includes('administrativo')||n.includes('contábil')||n.includes('logística')||n.includes('excel'))return 'Carreira e escritório';
    if(k.includes('tecnologia')||k.includes('informática')||k.includes('games'))return 'Tecnologia';
    if(k.includes('marketing')||k.includes('design')||n.includes('vendedor'))return 'Criatividade e negócios';
    if(k.includes('saúde')||k.includes('beleza'))return 'Serviços e atendimento';
    if(k.includes('kids')||n.includes('kids'))return 'Desenvolvimento jovem';
    if(k.includes('idiomas'))return 'Idiomas';
    return 'Qualificação profissional';
  }
  function draw(){
    const q=query.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
    const list=DATA.courses.filter(c=>{
      const hay=[c.name,c.category,c.description,c.commercialHeadline,c.commercialSubheadline,...(c.modules||[])].join(' ').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
      return (cat==='Todos'||c.category===cat)&&(mod==='Todos'||(c.modalities||[]).includes(mod))&&(objective==='Todos'||courseObjectiveLocal(c)===objective)&&(!q||hay.includes(q));
    });
    grid.innerHTML=list.map(c=>courseCard(c)).join('');count.textContent=`${list.length} ${list.length===1?'formação':'formações'}`;empty.hidden=list.length>0;
  }
  const debounced=debounce(()=>{query=input.value.trim();draw();},100);
  input?.addEventListener('input',debounced);
  document.querySelectorAll('[data-course-category]').forEach(btn=>{btn.classList.toggle('active',btn.dataset.courseCategory===cat);btn.addEventListener('click',()=>{cat=btn.dataset.courseCategory;document.querySelectorAll('[data-course-category]').forEach(b=>b.classList.toggle('active',b===btn));draw();});});
  document.querySelectorAll('[data-course-modality]').forEach(btn=>btn.addEventListener('click',()=>{mod=btn.dataset.courseModality;document.querySelectorAll('[data-course-modality]').forEach(b=>b.classList.toggle('active',b===btn));draw();}));
  document.querySelectorAll('[data-course-objective]').forEach(btn=>btn.addEventListener('click',()=>{objective=btn.dataset.courseObjective;document.querySelectorAll('[data-course-objective]').forEach(b=>b.classList.toggle('active',b===btn));draw();}));
  draw();
}


export function courseCategoryPage(slug){
  const category=CATEGORY_BY_SLUG[slug];
  if(!category)return notFoundPage();
  const list=DATA.courses.filter(c=>c.category===category);
  const descriptions={
    'Administrativo':'Desenvolva competências para escritórios, atendimento, gestão, finanças e rotinas administrativas.',
    'Tecnologia':'Aprenda programação, desenvolvimento, inteligência artificial e competências digitais aplicáveis.',
    'Marketing':'Desenvolva vendas, comunicação, mídias sociais, tráfego e estratégias digitais.',
    'Saúde':'Conheça formações voltadas a atendimento, rotinas e serviços na área da saúde.',
    'Informática':'Desenvolva domínio de computador, ferramentas de escritório, internet e recursos digitais.',
    'Kids':'Tecnologia e criatividade para crianças e jovens desenvolverem novas habilidades.',
    'Design':'Ferramentas criativas, produção visual e competências para design gráfico.',
    'Games':'Desenvolvimento de games, criação 3D e competências digitais ligadas a jogos.',
    'Idiomas':'Desenvolva comunicação em outros idiomas e amplie suas possibilidades.',
    'Beleza':'Formação presencial com prática, técnica e desenvolvimento profissional em beleza.'
  };
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Cursos',href:'/cursos/'},{label:category,href:`/cursos/area/${slug}/`}])}<section class="page-hero compact category-seo-hero"><div class="container-wide"><span class="eyebrow">CURSOS EM ${esc(category.toUpperCase())}</span><h1>Cursos de ${esc(category)} em <span>Ilhéus.</span></h1><p>${esc(descriptions[category]||'Explore as formações profissionais da Live Connect nesta área.')}</p></div></section><section class="section catalog-section"><div class="container-wide"><div class="category-seo-intro"><h2>${list.length} ${list.length===1?'formação disponível':'formações disponíveis'} em ${esc(category)}</h2><p>Compare conteúdo, duração e modalidades. O investimento e as condições comerciais são apresentados somente dentro da página de cada formação.</p></div><div class="course-grid">${list.map(c=>courseCard(c)).join('')}</div><div class="center-action"><a class="btn btn-secondary" href="/cursos/" data-router>Ver todas as áreas ${icon('arrow')}</a></div></div></section>`,'courses');
}
export async function hydrateCourseCategory(){return;}

export function coursePage(slug) {
  const c=DATA.courses.find(x=>x.slug===slug);
  if(!c)return notFoundPage();
  const benefits=(c.commercialBenefits||[]).slice(0,4);
  const faqs=[
    {q:'Essa formação é um único curso ou vários cursos separados?',a:`É uma formação Live Connect composta por ${c.modules.length} módulos integrados. Você realiza uma única formação.`},
    {q:'Quais modalidades estão disponíveis?',a:`Esta formação está disponível em: ${(c.modalities||[]).join(' e ')}.`},
    {q:'Como funciona a matrícula?',a:'Você inicia a ficha pelo portal. Quando a matrícula online estiver disponível para a sua condição, o próprio portal apresenta a etapa de pagamento; casos que precisam de confirmação de turma ou atendimento seguem para a equipe da escola.'},
    {q:'Quando posso começar?',a:'O início depende da modalidade e, no presencial, da disponibilidade da turma escolhida. A confirmação aparece durante o processo de matrícula ou é orientada pela equipe.'},
    {q:'Há certificado?',a:'Ao concluir a formação conforme as regras aplicáveis, o aluno recebe certificado de conclusão.'}
  ];
  const content=`${breadcrumbs([{label:'Início',href:'/'},{label:'Cursos',href:'/cursos/'},{label:c.category,href:`/cursos/area/${slugifyCategory(c.category)}/`},{label:c.name,href:`/cursos/${c.slug}/`}])}<section class="course-hero" id="visao-geral"><div class="container-wide course-hero-grid"><div class="course-hero-copy"><span class="eyebrow">${esc(c.category)} • CURSO PROFISSIONALIZANTE EM ILHÉUS</span><h1>${esc(c.name)}</h1><p>${esc(c.description)}</p><div class="course-fact-cards ${c.teacherInRoomAvailable?'has-four':''}"><span>${icon('clock')}<b>${esc(c.hours)}</b><small>Carga horária da formação</small></span><span>${icon('calendar')}<b>${esc(c.duration)}</b><small>Duração</small></span><span>${icon('monitor')}<b>${esc((c.modalities||[]).join(' + '))}</b><small>Modalidade</small></span>${c.teacherInRoomAvailable?`<span>${icon('users')}<b>Disponível</b><small>Professor em sala</small></span>`:''}</div><div class="hero-actions"><button class="btn btn-primary btn-lg" type="button" data-open-enroll="${esc(c.slug)}">Quero iniciar minha matrícula ${icon('arrow')}</button><a class="btn btn-whatsapp btn-lg" href="${whatsappUrl(`Olá! Quero informações sobre a formação ${c.name}.`)}" target="_blank" rel="noopener" data-whatsapp data-track-location="course_detail">${icon('whatsapp')} Tirar uma dúvida</a></div><small class="course-disclaimer">Preencha a ficha pelo portal. Disponibilidade de turma, modalidade e etapa de pagamento são apresentadas conforme o fluxo da matrícula.</small></div><div class="course-showcase course-showcase-hd"><img class="course-showcase-cover" src="/assets/images/courses-hd/${esc(c.slug)}.jpg" srcset="/assets/images/courses/${esc(c.slug)}.jpg 720w, /assets/images/courses-hd/${esc(c.slug)}.jpg 1440w" sizes="(max-width: 900px) 92vw, 48vw" width="1440" height="810" alt="Imagem representativa da formação ${esc(c.name)}" decoding="async" fetchpriority="high"><div class="course-showcase-top"><span>${esc(c.category)}</span><small>LIVE CONNECT • FORMAÇÃO</small></div><div class="course-showcase-title"><strong>${esc(c.name)}</strong><span>${c.modules.length} módulos em uma única formação</span></div></div></div></section>
    <nav class="course-anchor-nav" aria-label="Atalhos desta formação"><div class="container-wide"><a href="#visao-geral">Visão geral</a><a href="#profissao-rapida">Modalidades e investimento</a><a href="#resultados">Você vai desenvolver</a><a href="#modulos">Módulos</a><a href="#para-quem">Para quem é</a><a href="#duvidas">Dúvidas</a><button type="button" data-open-enroll="${esc(c.slug)}">Matrícula</button></div></nav>
    <div id="fastTrackMount"></div>
    <section class="course-campaign-slot" id="courseCampaignSlot" hidden><div class="container-wide" id="courseCampaignMount"></div></section>
    <section class="section course-commercial" id="resultados"><div class="container-wide">${sectionHeader('VOCÊ VAI DESENVOLVER',esc(c.commercialHeadline||`Desenvolva habilidades para avançar em ${c.name}.`),c.commercialSubheadline||c.description)}
      <div class="why-grid course-benefit-grid">${benefits.map((b,i)=>`<article><span>${icon(['briefcase','layers','star','graduation'][i%4])}</span><h3>${esc(b.title)}</h3><p>${esc(b.text)}</p></article>`).join('')}</div>
    </div></section>
    <section class="section course-modules-section" id="modulos"><div class="container-wide"><div class="split-heading"><div>${sectionHeader('CONTEÚDO PROGRAMÁTICO','Veja os módulos que fazem parte desta formação.','Cada módulo contribui para construir uma habilidade diferente dentro do mesmo curso Live Connect.','left')}</div><div class="module-count-badge"><strong>${c.modules.length}</strong><span>módulos</span></div></div><div class="module-grid">${c.modules.map((m,i)=>`<article class="module-card"><span class="module-number">${String(i+1).padStart(2,'0')}</span><span class="module-card-icon"><img src="/${c.moduleIcons[i]}" width="82" height="82" alt="Ícone do módulo ${esc(m)}" loading="lazy"></span><h3>${esc(m)}</h3></article>`).join('')}</div></div></section>
    <section class="section course-fit" id="para-quem"><div class="container-wide two-column-info"><article><span class="info-icon">${icon('users')}</span><span class="eyebrow">PARA QUEM É</span><h2>Veja se esta formação combina com seu objetivo.</h2><p>${esc(c.audience)}</p></article><article><span class="info-icon">${icon('briefcase')}</span><span class="eyebrow">ONDE ESSE CONHECIMENTO É ÚTIL</span><h2>Leve o aprendizado para situações reais.</h2><p>${esc(c.workplace)}</p></article></div></section>
    <section class="section course-faq" id="duvidas"><div class="container-narrow">${sectionHeader('DÚVIDAS FREQUENTES','Antes de escolher, entenda como funciona.','')}${faq(faqs)}</div></section>
    <section class="course-bottom-cta"><div class="container-wide"><div><span class="eyebrow yellow">DÊ O PRÓXIMO PASSO</span><h2>Comece sua matrícula em ${esc(c.name)}.</h2><p>Preencha seus dados pelo portal e avance para as próximas etapas disponíveis para a sua modalidade.</p></div><button class="btn btn-yellow btn-lg" type="button" data-open-enroll="${esc(c.slug)}">Quero iniciar agora ${icon('arrow')}</button></div></section>`;
  return pageShell(content,'courses');
}

export async function hydrateCourse(slug) {
  const [campaigns,offers]=await Promise.all([loadCampaigns(),loadCommercialOfferCatalog()]);
  applyCommercialOffers(DATA.courses,offers);
  const c=DATA.courses.find(x=>x.slug===slug);
  const ft=document.getElementById('fastTrackMount');if(ft&&c){
    ft.innerHTML=fastTrackComparator(c);
    const grid=ft.querySelector('.offer-compare-grid');
    ft.querySelectorAll('[data-offer-tab]').forEach(btn=>btn.addEventListener('click',()=>{
      const mode=btn.dataset.offerTab;
      grid?.classList.toggle('mobile-standard-active',mode==='tradicional');
      grid?.classList.toggle('mobile-fast-active',mode==='profissao_rapida');
      ft.querySelectorAll('[data-offer-tab]').forEach(x=>x.setAttribute('aria-selected',String(x===btn)));
      grid?.querySelector(`.offer-plan.${mode==='tradicional'?'standard':'fast'}`)?.scrollIntoView({block:'nearest',behavior:'smooth'});
    }));
  }
  const slot=document.getElementById('courseCampaignSlot'),mount=document.getElementById('courseCampaignMount');
  if(slot&&mount&&campaigns.length){
    const broad=campaigns.filter(ca=>ca.show_course_pages!==false && (!Array.isArray(ca.course_ids)||ca.course_ids.length===0||ca.course_ids.length>=Math.max(1,DATA.courses.length-2))).sort((a,b)=>(b.priority||0)-(a.priority||0))[0];
    if(broad){slot.hidden=false;mount.innerHTML=campaignCard(broad);}
  }
}


function specialKindMeta(kind){
  return kind==='nr'
    ? {active:'courses',label:'NORMAS REGULAMENTADORAS',title:'Cursos de NR para ampliar sua qualificação profissional.',desc:'Conheça as NRs disponíveis no catálogo acadêmico da Live Connect. Carga horária e duração vêm da Ouro Moderno; o investimento acompanha automaticamente a condição comercial vigente.',path:'/nrs/'}
    : {active:'courses',label:'CURSOS CURTOS',title:'Qualificações rápidas para aprender uma habilidade específica.',desc:'Cursos de curta duração com até 18 horas de carga horária. O investimento é calculado automaticamente pela quantidade de meses necessários e pelo valor vigente da mensalidade.',path:'/cursos-curtos/'};
}
function specialCard(c,kind){
  const href=`${kind==='nr'?'/nrs/curso/':'/cursos-curtos/curso/'}?id=${encodeURIComponent(c.ouro_course_id)}`;
  return `<article class="special-course-card"><div class="special-course-icon">${icon(kind==='nr'?'shield':'clock')}</div><div class="special-course-copy"><span class="eyebrow">${kind==='nr'?'NORMA REGULAMENTADORA':'CURSO CURTO'}</span><h3>${esc(c.name)}</h3><p>${esc(c.description||'Qualificação profissional de curta duração.')}</p><div class="special-course-facts"><span>${icon('clock')} ${String(c.workload_hours).replace('.',',')}h</span><span>${icon('book')} ${c.lessons||'—'} aulas</span><span>${icon('calendar')} ${c.billing_months} ${c.billing_months===1?'mês':'meses'} no ritmo padrão</span></div><a class="btn btn-primary btn-wide" href="${href}" data-router>Ver curso e investimento ${icon('arrow')}</a></div></article>`;
}
export function specialCatalogPage(kind='short'){
  const m=specialKindMeta(kind);
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:kind==='nr'?'NRs':'Cursos Curtos',href:m.path}])}
    <div class="container-wide course-family-tabs" role="navigation" aria-label="Tipos de cursos"><a href="/cursos/" data-router>Formações completas</a><a class="${kind==='nr'?'active':''}" href="/nrs/" data-router>NRs</a><a class="${kind==='short'?'active':''}" href="/cursos-curtos/" data-router>Cursos Curtos</a></div>
    <section class="page-hero compact special-catalog-hero"><div class="container-wide"><span class="eyebrow">${m.label}</span><h1>${m.title}</h1><p>${m.desc}</p><div class="hero-actions"><a class="btn btn-secondary" href="${kind==='nr'?'/cursos-curtos/':'/nrs/'}" data-router>${kind==='nr'?'Ver Cursos Curtos':'Ver NRs'}</a></div></div></section>
    <section class="section"><div class="container-wide"><div class="catalog-tools single"><label class="search-box">${icon('search')}<span class="sr-only">Pesquisar</span><input id="specialSearch" type="search" placeholder="Pesquisar ${kind==='nr'?'NR':'curso curto'}…" autocomplete="off"></label></div><div class="catalog-result-head"><strong id="specialCount">Carregando catálogo…</strong><span>Os cards não exibem preço. Entre no curso para consultar o investimento vigente.</span></div><div class="special-course-grid" id="specialGrid"><div class="portal-loading inline"><span class="loader"></span><p>Carregando cursos…</p></div></div><div class="empty-state" id="specialEmpty" hidden>${icon('search')}<h3>Nenhum curso encontrado.</h3></div></div></section>`,m.active);
}
export async function hydrateSpecialCatalog(kind='short'){
  const rows=await loadSpecialCourseCatalog(kind);
  const grid=document.getElementById('specialGrid'),count=document.getElementById('specialCount'),input=document.getElementById('specialSearch'),empty=document.getElementById('specialEmpty');
  const render=()=>{
    const q=(input?.value||'').trim().toLowerCase();
    const filtered=rows.filter(c=>!q||`${c.name} ${c.description||''}`.toLowerCase().includes(q));
    if(grid)grid.innerHTML=filtered.map(c=>specialCard(c,kind)).join('');
    if(count)count.textContent=`${filtered.length} ${kind==='nr'?(filtered.length===1?'NR':'NRs'):(filtered.length===1?'curso curto':'cursos curtos')}`;
    if(empty)empty.hidden=filtered.length>0;
  };
  input?.addEventListener('input',debounce(render,150));render();
}
export function specialCoursePage(kind='short'){
  const m=specialKindMeta(kind);
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:kind==='nr'?'NRs':'Cursos Curtos',href:m.path},{label:'Detalhes',href:location.pathname+location.search}])}<section class="section special-course-detail"><div class="container-narrow" id="specialCourseMount"><div class="portal-loading"><span class="loader"></span><p>Carregando curso e condição vigente…</p></div></div></section>`,m.active);
}
export async function hydrateSpecialCourse(kind='short'){
  const id=new URLSearchParams(location.search).get('id');
  const mount=document.getElementById('specialCourseMount');if(!mount)return;
  const rows=await loadSpecialCourseCatalog(kind),c=rows.find(x=>String(x.ouro_course_id)===String(id));
  if(!c){mount.innerHTML=`<div class="empty-state">${icon('info')}<h2>Curso não encontrado.</h2><a class="btn btn-primary" href="${kind==='nr'?'/nrs/':'/cursos-curtos/'}" data-router>Voltar ao catálogo</a></div>`;return;}
  const monthly=Number(c.monthly_price||0),enrollment=Number(c.enrollment_fee||0),training=Number(c.training_total||0),traditional=Number(c.traditional_total||0);
  const message=`Olá! Tenho interesse no curso ${c.name}. Quero saber sobre horários e matrícula.`;
  mount.innerHTML=`<article class="special-detail-card"><div class="special-detail-head"><span class="eyebrow">${kind==='nr'?'NORMA REGULAMENTADORA':'CURSO CURTO'}</span><h1>${esc(c.name)}</h1><p>${esc(c.description||'Qualificação profissional Live Connect.')}</p><div class="special-course-facts large"><span>${icon('clock')} <strong>${String(c.workload_hours).replace('.',',')}h</strong><small>Carga horária</small></span><span>${icon('book')} <strong>${c.lessons||'—'}</strong><small>Aulas acadêmicas</small></span><span>${icon('calendar')} <strong>${c.billing_months} ${c.billing_months===1?'mês':'meses'}</strong><small>Estimativa no ritmo padrão</small></span></div></div>
    <div class="special-pricing-explainer"><span>${icon('info')}</span><div><strong>Como calculamos o investimento</strong><p>Consideramos aulas de 2 horas, 1 vez por semana. A quantidade de meses é calculada pela carga horária e multiplicada pela mensalidade vigente. Se a campanha mudar, esta página recalcula automaticamente.</p></div></div>
    <div class="offer-compare-grid special-offer-grid">
      <article class="offer-plan standard"><span class="plan-kicker">TRADICIONAL</span><h3>Pagamento mês a mês</h3><ul class="plan-feature-list"><li>Matrícula vigente: <strong>${enrollment<=0?'Grátis':moneyBR(enrollment)}</strong></li><li><strong>${c.billing_months} ${c.billing_months===1?'mensalidade':'mensalidades'} de ${moneyBR(monthly)}</strong></li><li>Ritmo padrão: aproximadamente 1 encontro semanal</li></ul><div class="plan-total"><small>Investimento total</small><strong>${moneyBR(traditional)}</strong></div><a class="btn btn-secondary btn-wide" href="${whatsappUrl(message+' Prefiro o pagamento mensal.')}" target="_blank" rel="noopener" data-whatsapp>Quero pagar mês a mês</a></article>
      <article class="offer-plan fast"><span class="recommended-badge">FORMAÇÃO ACELERADA</span><span class="plan-kicker">PROFISSÃO RÁPIDA</span><h3>Avance mais rápido na sua qualificação.</h3><ul class="plan-feature-list"><li>Matrícula: <strong>GRÁTIS</strong></li><li>Valor integral da formação: <strong>${moneyBR(training)}</strong></li><li>Pagamento do valor total no cartão, com parcelamento conforme disponibilidade</li><li>Mais possibilidades de estudo durante a semana e aos sábados, conforme vagas</li><li>Horários mais flexíveis e formação acelerada</li></ul><div class="plan-total"><small>Valor fechado da formação</small><strong>${moneyBR(training)}</strong></div><div class="savings-badge">Economia imediata de ${moneyBR(Math.max(0,traditional-training))}</div><a class="btn btn-primary btn-wide" href="${whatsappUrl(message+' Quero fazer pelo Profissão Rápida e concluir mais rápido.')}" target="_blank" rel="noopener" data-whatsapp>Quero o Profissão Rápida ${icon('arrow')}</a></article>
    </div>
    ${c.campaign_name?`<p class="projection-note special-campaign-note">Condição baseada em “${esc(c.campaign_name)}”${c.campaign_expiration?`, válida até ${formatDate(c.campaign_expiration+'T12:00:00')}`:''}. Valores atualizados automaticamente pelo sistema.</p>`:''}
    </article>`;
  document.title=`${c.name} | Live Connect`;
  document.querySelector('meta[name="description"]')?.setAttribute('content',`${c.name}: ${String(c.workload_hours).replace('.',',')} horas, duração estimada de ${c.billing_months} ${c.billing_months===1?'mês':'meses'} e investimento atualizado conforme a condição vigente da Live Connect.`);
  track('special_course_view',{kind,ouro_course_id:c.ouro_course_id},c.name);
}

export function freePage() {
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Cursos Gratuitos',href:'/gratuitos/'}])}
  <section class="page-hero free-hero"><div class="container-wide free-hero-grid"><div><span class="eyebrow yellow">PROJETO SOCIAL LIVE CONNECT</span><h1>Começar a aprender pode custar <span>zero.</span></h1><p>Escolha uma habilidade para desenvolver presencialmente, conheça a rotina da escola e dê um primeiro passo sem custo de curso.</p><div class="inline-badges"><span class="pill pill-green">100% gratuito</span><span class="pill pill-blue">Somente presencial</span><span class="pill pill-blue">Vagas por turma</span></div><div class="hero-actions"><a class="btn btn-primary btn-lg" href="#cursos-gratuitos">Ver cursos disponíveis ${icon('arrow')}</a><a class="btn btn-whatsapp btn-lg" href="${whatsappUrl('Olá! Quero saber como funcionam os cursos gratuitos da Live Connect.')}" target="_blank" rel="noopener" data-whatsapp>${icon('whatsapp')} Tirar uma dúvida</a></div></div><img class="mascot-official" src="/assets/images/mascotes/mascote-comemorando.png" alt="Mascote Live Connect comemorando"></div></section>
  <section class="section free-explainer"><div class="container-wide">${sectionHeader('COMO FUNCIONA','Um projeto gratuito, simples de entender e com vagas organizadas por turma.','A inscrição registra seu interesse. A equipe confirma a disponibilidade antes do início.')}
    <div class="journey-grid"><article>${icon('search')}<h3>1. Escolha o curso</h3><p>Veja as opções gratuitas disponíveis e encontre uma habilidade que faça sentido para você.</p></article><article>${icon('user')}<h3>2. Registre seu interesse</h3><p>Envie nome e WhatsApp pelo portal para entrar na fila de atendimento.</p></article><article>${icon('calendar')}<h3>3. Aguarde a confirmação</h3><p>A equipe informa disponibilidade, horário e orientações da turma presencial.</p></article><article>${icon('graduation')}<h3>4. Participe</h3><p>Compareça no horário confirmado e aproveite a experiência para desenvolver uma nova habilidade.</p></article></div>
  </div></section>
  <section class="section" id="cursos-gratuitos"><div class="container-wide">${sectionHeader('CURSOS GRATUITOS','Escolha por onde você quer começar.','As opções podem variar conforme disponibilidade de turma.')}
    <div class="catalog-tools single"><label class="search-box" for="freeSearch">${icon('search')}<span class="sr-only">Pesquisar cursos gratuitos</span><input id="freeSearch" type="search" placeholder="Pesquisar curso gratuito…"></label></div>
    <div class="free-course-grid" id="freeGrid">${DATA.freeCourses.map(f=>freeCourseCard(f)).join('')}</div><div class="empty-state" id="freeEmpty" hidden>${icon('search')}<h3>Nenhum curso encontrado.</h3></div></div></section>
  <section class="info-band"><div class="container-wide"><span>${icon('info')}</span><div><strong>Importante</strong><p>Os cursos gratuitos são presenciais e dependem de disponibilidade de turma. Registrar interesse não reserva automaticamente uma vaga; a confirmação é feita pela equipe da Live Connect.</p></div></div></section>
  <section class="section free-value"><div class="container-wide">${sectionHeader('POR QUE PARTICIPAR','Use o curso gratuito como ponto de partida.','Uma oportunidade para conhecer uma área, desenvolver uma habilidade e decidir seus próximos passos com mais informação.')}
    <div class="why-grid"><article><span>${icon('star')}</span><h3>Experimente uma área</h3><p>Tenha contato com um conteúdo antes de decidir se quer aprofundar seus estudos.</p></article><article><span>${icon('users')}</span><h3>Aprenda presencialmente</h3><p>Participe de uma experiência em sala e tenha contato direto com a escola.</p></article><article><span>${icon('briefcase')}</span><h3>Amplie seu repertório</h3><p>Adicione uma nova habilidade à sua rotina de estudos, trabalho ou projetos pessoais.</p></article><article><span>${icon('arrow')}</span><h3>Continue evoluindo</h3><p>Depois do curso, conheça outras formações e monte uma trajetória de aprendizado maior.</p></article></div>
  </div></section>`,'free');
}

export async function hydrateFree() {
  const input=document.getElementById('freeSearch'),grid=document.getElementById('freeGrid'),empty=document.getElementById('freeEmpty');
  if(!grid)return;

  const official=await loadFreeCourseOuroCatalog();
  if(official.length){
    const map=Object.fromEntries(official.map(x=>[x.free_slug,x]));
    DATA.freeCourses.forEach(c=>{
      const o=map[c.slug];if(!o)return;
      c.ouroCourseId=o.ouro_course_id;
      c.ouroName=o.ouro_name;
      c.lessons=Number(o.lessons||0)||null;
      c.workloadHours=Number(o.ouro_reported_workload_hours||0)||null;
      c.classHours=Number(o.class_hours||0)||null;
      c.durationWeeks=Number(o.duration_weeks||0)||null;
      c.durationMonths=Number(o.duration_months||0)||null;
      c.ouroDescription=o.ouro_description||null;
      c.ouroVersion=o.ouro_version||null;
      c.ouroSyncedAt=o.synced_at||null;
    });
  }

  const draw=()=>{
    const q=(input?.value||'').trim().toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
    const list=DATA.freeCourses.filter(c=>c.name.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'').includes(q));
    grid.innerHTML=list.map(f=>freeCourseCard(f)).join('');
    empty.hidden=list.length>0;
  };
  input?.addEventListener('input',debounce(draw,90));
  draw();
}

export function youngPage() {
  return pageShell(`<section class="young-page-hero"><div class="container-wide young-page-grid"><div><span class="eyebrow yellow">PROJETO GRATUITO</span><h1>Seu primeiro emprego começa <span>antes da entrevista.</span></h1><p>Prepare currículo, comunicação, postura e estratégia de candidatura para chegar às oportunidades com mais clareza sobre o que fazer.</p><div class="hero-actions"><button class="btn btn-yellow btn-lg" type="button" data-open-lead="young">Preencher ficha ${icon('arrow')}</button><a class="btn btn-white btn-lg" href="${whatsappUrl('Olá! Quero informações sobre o Projeto Jovem Aprendiz gratuito da Live Connect.')}" target="_blank" rel="noopener" data-whatsapp data-track-location="young_hero">${icon('whatsapp')} Falar com a equipe</a></div><div class="young-points"><span>${icon('check')} Projeto gratuito</span><span>${icon('check')} Encontros presenciais</span><span>${icon('check')} Preparação para o primeiro emprego</span></div></div><img class="mascot-official" src="/assets/images/mascotes/mascote-estudando.png" alt="Mascote Live Connect estudando"></div></section>
  <section class="section"><div class="container-wide">${sectionHeader('O QUE VOCÊ VAI TRABALHAR','Preparação prática para entrar no mercado com mais segurança.','Não é promessa de vaga: é preparação para você se apresentar melhor quando a oportunidade aparecer.')}
    <div class="journey-grid"><article>${icon('user')}<h3>Apresentação profissional</h3><p>Postura, comunicação, comportamento e cuidados importantes no primeiro contato com empresas.</p></article><article>${icon('briefcase')}<h3>Currículo e candidatura</h3><p>Como organizar suas informações, identificar vagas e enviar uma candidatura mais clara.</p></article><article>${icon('users')}<h3>Entrevistas e processos seletivos</h3><p>Entenda perguntas comuns, dinâmicas e atitudes que ajudam a demonstrar preparo.</p></article><article>${icon('star')}<h3>Confiança com preparação</h3><p>Reduza o improviso e aprenda a comunicar melhor seus pontos fortes e objetivos.</p></article></div>
  </div></section>
  <section class="section young-how"><div class="container-wide two-column-info"><article><span class="info-icon">${icon('briefcase')}</span><span class="eyebrow">PARA QUEM É</span><h2>Para quem está se preparando para começar.</h2><p>Jovens em busca do primeiro emprego, de oportunidades como aprendiz ou de mais segurança para participar de processos seletivos.</p></article><article><span class="info-icon">${icon('calendar')}</span><span class="eyebrow">COMO FUNCIONA</span><h2>Encontros presenciais com foco em prática.</h2><p>As turmas são organizadas conforme disponibilidade. Ao registrar interesse, a equipe informa datas, horários, critérios e orientações para participação.</p></article></div></section>
  <section class="section young-checklist"><div class="container-wide">${sectionHeader('SAIA COM UM PLANO','O objetivo é saber o que fazer antes, durante e depois de uma candidatura.','')}${`<div class="why-grid"><article><span>${icon('search')}</span><h3>Onde procurar</h3><p>Organize sua busca e aprenda a identificar oportunidades compatíveis com seu momento.</p></article><article><span>${icon('book')}</span><h3>O que colocar no currículo</h3><p>Entenda como apresentar formação, cursos, habilidades e experiências de forma clara.</p></article><article><span>${icon('users')}</span><h3>Como se comunicar</h3><p>Trabalhe linguagem, postura e respostas para contatos e entrevistas.</p></article><article><span>${icon('arrow')}</span><h3>Como acompanhar</h3><p>Aprenda a manter organização das candidaturas e continuar buscando novas oportunidades.</p></article></div>`}</div></section>
  <section class="young-callout"><div class="container-wide"><div><span class="eyebrow yellow">É GRATUITO</span><h2>Quer participar da próxima turma?</h2><p>Preencha a ficha de inscrição com seus dados, situação escolar e disponibilidade. Quando houver turma, a equipe informa datas e orientações.</p></div><button class="btn btn-yellow btn-lg" type="button" data-open-lead="young">Preencher ficha de inscrição ${icon('arrow')}</button></div></section>`,'young');
}

export function aboutPage() {
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Sobre',href:'/sobre/'}])}<section class="page-hero about-hero"><div class="container-wide"><span class="eyebrow">LIVE CONNECT • ILHÉUS</span><h1>Conhecimento que aproxima você do <span>próximo passo.</span></h1><p>A Live Connect Escola de Profissões atua com qualificação profissional, formações presenciais e EAD, projetos gratuitos e atendimento voltado a quem quer desenvolver novas habilidades.</p></div></section><section class="section"><div class="container-wide story-grid"><div><span class="eyebrow">NOSSA PROPOSTA</span><h2>Ensino profissional precisa ser claro, acessível e conectado à vida real.</h2><p>Nosso catálogo reúne formações em áreas administrativas, tecnologia, marketing, saúde, design e outras frentes. Em cada formação, diferentes módulos trabalham juntos para construir um repertório mais completo.</p><p>Também desenvolvemos iniciativas gratuitas, como cursos presenciais e o Projeto Jovem Aprendiz, ampliando o acesso à qualificação.</p></div><div class="story-card"><img class="mascot-official" src="/assets/images/mascotes/mascote-boas-vindas.png" alt="Mascote Live Connect dando boas-vindas"><div class="story-brand"><img class="story-brand-logo" src="/assets/images/logo.png?v=2216" alt="Live Connect Escola de Profissões"><p>${esc(CONFIG.brand.address)}</p></div></div></div></section><section class="values-section"><div class="container-wide why-grid"><article><span>${icon('shield')}</span><h3>Comunicação responsável</h3><p>Sem promessas irreais. Nosso foco é qualificação e desenvolvimento.</p></article><article><span>${icon('book')}</span><h3>Formações completas</h3><p>Módulos complementares organizados em jornadas profissionais.</p></article><article><span>${icon('users')}</span><h3>Atendimento humano</h3><p>Orientação para entender opções, modalidades e próximos passos.</p></article><article><span>${icon('briefcase')}</span><h3>Visão profissional</h3><p>Conteúdo pensado para desenvolver habilidades aplicáveis.</p></article></div></section>`,'about');
}

export function contactPage() {
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Contato',href:'/contato/'}])}<section class="page-hero contact-hero"><div class="container-wide"><span class="eyebrow">FALE COM A LIVE CONNECT</span><h1>Uma dúvida não deve impedir <span>seu próximo passo.</span></h1><p>Converse com a equipe sobre cursos, modalidades, matrícula, projetos gratuitos ou atendimento ao aluno.</p></div></section><section class="section"><div class="container-wide contact-layout"><div class="contact-cards"><article>${icon('whatsapp')}<div><small>WhatsApp</small><strong>${esc(CONFIG.brand.phoneDisplay)}</strong><p>Para informações, cursos e matrícula.</p><a href="${whatsappUrl()}" target="_blank" rel="noopener" data-whatsapp data-track-location="contact">Abrir WhatsApp ${icon('arrow')}</a></div></article><article>${icon('location')}<div><small>Endereço</small><strong>Centro • Ilhéus</strong><p>${esc(CONFIG.brand.address)}</p></div></article><article>${icon('clock')}<div><small>Horário</small><strong>Segunda a sábado</strong><p>Seg–Sex: 8h às 18h<br>Sábado: 8h às 12h</p></div></article><article>${icon('mail')}<div><small>E-mail</small><strong>${esc(CONFIG.brand.email)}</strong><p>Contato institucional.</p></div></article></div><form class="contact-form" id="contactForm"><span class="eyebrow">ENVIE UMA MENSAGEM</span><h2>Deixe seu contato.</h2><p>A solicitação entra diretamente no CRM da Live Connect.</p><div class="form-grid"><div class="field full"><label for="contactName">Nome completo *</label><input class="input" id="contactName" name="name" required autocomplete="name"></div><div class="field full"><label for="contactPhone">WhatsApp *</label><input class="input" id="contactPhone" name="phone" required inputmode="tel" autocomplete="tel"></div><div class="field full"><label for="contactSubject">Assunto</label><select class="select" id="contactSubject" name="subject"><option>Informações sobre cursos</option><option>Matrícula</option><option>Cursos gratuitos</option><option>Jovem Aprendiz</option><option>Área do aluno</option><option>Outro assunto</option></select></div><div class="field full"><label for="contactMessage">Mensagem</label><textarea class="textarea" id="contactMessage" name="message" rows="5" placeholder="Como podemos ajudar?"></textarea></div></div><button class="btn btn-primary btn-wide" type="submit">Enviar para a equipe ${icon('arrow')}</button></form></div></section>`,'contact');
}

export function hydrateContact() {
  document.getElementById('contactForm')?.addEventListener('submit',async e=>{e.preventDefault();const f=e.currentTarget,name=f.querySelector('#contactName').value.trim(),phone=digits(f.querySelector('#contactPhone').value),subject=f.querySelector('#contactSubject').value,message=f.querySelector('#contactMessage').value.trim();if(name.length<3||phone.length<10){toast('Preencha nome e WhatsApp.','error');return;}const btn=e.submitter;btn.disabled=true;btn.textContent='Enviando…';try{const json=await submitLead({type:'contato',full_name:name,whatsapp:phone,message:`${subject}${message?`: ${message}`:''}`});track('contact_submit',{subject},null,json.lead_id||null);toast('Mensagem recebida. A equipe poderá continuar o atendimento com você.');f.reset();}catch{toast('Não foi possível enviar agora. Tente novamente.','error');}finally{btn.disabled=false;btn.innerHTML=`Enviar para a equipe ${icon('arrow')}`;}});
}

function loginForm(roleHint='student') {
  const student = roleHint === 'student';
  return `<div class="auth-card">
    <div class="auth-brand"><img src="/assets/images/logo.png?v=2216" width="150" height="67" alt="Live Connect"><span class="auth-lock">${icon('lock')}</span></div>
    <span class="eyebrow">ACESSO SEGURO</span>
    <h1>${student?'Área do Aluno':'Área Administrativa'}</h1>
    <p>${student?'Use seu usuário e senha da Ouro Moderno para acessar cursos presenciais e EAD no mesmo portal.':'Entre com sua conta administrativa autorizada.'}</p>
    <form id="authForm" class="stack-form">
      <div class="field"><label for="${student?'authUsername':'authEmail'}">${student?'Usuário':'E-mail'}</label>
        <input class="input" id="${student?'authUsername':'authEmail'}" type="${student?'text':'email'}" autocomplete="username" ${student?'autocapitalize="none" spellcheck="false"':''} required placeholder="${student?'Seu usuário da Ouro Moderno':'seu@email.com'}">
      </div>
      <div class="field"><label for="authPassword">Senha</label><input class="input" id="authPassword" type="password" autocomplete="current-password" required placeholder="${student?'Sua senha da Ouro Moderno':'Sua senha'}"></div>
      <button class="btn btn-primary btn-wide" type="submit">${student?'Entrar no Portal':'Entrar com segurança'} ${icon('arrow')}</button>
    </form>
    <div class="auth-help">${icon('shield')} ${student?'Suas credenciais são validadas pela Ouro Moderno e a senha não é armazenada pela Live Connect. Depois do acesso, o portal reúne automaticamente seus dados EAD e presenciais.':'A autenticação administrativa é processada pelo ambiente seguro da Live Connect.'}</div>
    <a href="${student?'https://ead.ouromoderno.com.br/':'/contato/'}" ${student?'target="_blank" rel="noopener"':'data-router'}>${student?'Esqueci minha senha / acessar o EAD':'Precisa de ajuda para acessar?'}</a>
    <a class="auth-role-switch" href="${student?'/admin/':'/area-do-aluno/'}" data-router>${student?'Sou administrador':'Voltar para Área do Aluno'} ${icon('arrow')}</a>
  </div>`;
}

export function studentPage() {
  const session=getStudentSession();
  const content=session
    ? `<section class="portal-page"><div class="container-wide"><div id="studentPortalMount" class="portal-loading"><span class="loader"></span><p>Sincronizando seus dados presenciais e EAD…</p></div></div></section>`
    : `<section class="auth-page"><div class="auth-visual"><div><span class="eyebrow yellow">PORTAL LIVE CONNECT</span><h2>Presencial e EAD em um só lugar.</h2><p>Use o mesmo acesso da Ouro Moderno para acompanhar toda a sua jornada na Live Connect.</p></div><img class="mascot-official" src="/assets/images/mascotes/mascote-comemorando.png" alt="Mascote oficial Live Connect com notebook"></div>${loginForm('student')}</section>`;
  return pageShell(content,'',{noFloatingWhatsapp:true});
}

function progressOf(course){return Math.max(0,Math.min(100,Number(course?.progresso?.percentual||0)));}
function presencialOf(data){return data?.presencial?.ok===true?data.presencial:null;}
function presencialCourses(data){const p=presencialOf(data);return Array.isArray(p?.courses)?p.courses:[];}
function presencialCourse(data,id=''){const list=presencialCourses(data);return list.find(c=>String(c.id_aluno_curso)===String(id))||list[0]||null;}
function presencialAttendance(data,id){const list=Array.isArray(presencialOf(data)?.attendance)?presencialOf(data).attendance:[];return list.find(a=>String(a.id_aluno_curso)===String(id))||null;}
function attendancePercent(item){const total=Number(item?.aulas_registradas||0),present=Number(item?.presencas||0);return total?Math.round(present/total*100):0;}

function presencialNotice(data){
  if(presencialOf(data)||!data?.presencial_error)return '';
  const identity=['identity_not_linked','dkweb_student_not_found','ambiguous_identity','ouro_identity_incomplete'].includes(data.presencial_error);
  return `<div class="student-honest-note student-presential-notice">${icon('info')}<div><strong>${identity?'Cadastro presencial ainda não vinculado.':'Dados presenciais temporariamente indisponíveis.'}</strong><p>${identity?'O acesso Ouro está correto. A Secretaria precisa conferir o CPF cadastrado nos dois sistemas.':'Os cursos EAD continuam disponíveis normalmente. Tente novamente mais tarde.'}</p></div></div>`;
}

function studentOverview(data){
  const c=data.primary_course,d=data.primary_detail;
  const lessons=Array.isArray(d?.aulas)?d.aulas:[];
  const total=Number(c?.progresso?.total_aulas||lessons.length||0);
  const done=Number(c?.progresso?.aulas_concluidas||lessons.filter(a=>a.situacao==='concluido').length||0);
  const eadGrades=lessons.map(a=>Number(a.nota)).filter(Number.isFinite);
  const pct=progressOf(c);
  const p=presencialOf(data),pc=presencialCourse(data),pa=pc?presencialAttendance(data,pc.id_aluno_curso):null;
  const pModules=Array.isArray(p?.modules)?p.modules.filter(m=>String(m.id_aluno_curso)===String(pc?.id_aluno_curso)):[];
  const pGrades=Array.isArray(p?.grades)?p.grades.filter(g=>String(g.id_aluno_curso)===String(pc?.id_aluno_curso)):[];
  const cards=[];
  if(c)cards.push(`<section class="student-course-spotlight student-modality-card student-modality-card--ead"><div class="spotlight-copy"><span class="modality-chip">EAD • OURO MODERNO</span><span class="course-status-pill">${esc(c.situacao||'cursando')}</span><h2>${esc(c.curso||'Curso')}</h2><p>${done} de ${total} aulas concluídas</p><div class="student-progress"><span style="width:${pct}%"></span></div><div class="student-progress-label"><strong>${pct}% concluído</strong><span>Continue de onde parou.</span></div><div class="spotlight-actions"><a class="btn btn-yellow" href="https://ead.ouromoderno.com.br/" target="_blank" rel="noopener" data-study-link>Continuar no EAD ${icon('external')}</a><button class="btn btn-white" type="button" data-student-view="lessons">Aulas e notas ${icon('arrow')}</button></div></div><div class="spotlight-mascot"><img class="mascot-official" src="/assets/images/mascotes/mascote-comemorando.png" alt="Mascote Live Connect"></div></section>`);
  if(pc)cards.push(`<section class="student-modality-card student-modality-card--presencial"><div class="modality-card-head"><div><span class="modality-chip">PRESENCIAL • LIVE CONNECT</span><span class="course-status-pill">${esc(pc.situacao||'matriculado')}</span></div>${icon('location')}</div><h2>${esc(pc.curso||'Curso presencial')}</h2><p>Matrícula ${esc(p?.student?.matricula||'—')} • início ${legacyDate(pc.data_inicial||pc.data_matricula)}</p><div class="presential-kpis"><span><small>Frequência</small><strong>${pa?`${attendancePercent(pa)}%`:'—'}</strong></span><span><small>Módulos</small><strong>${pModules.length}</strong></span><span><small>Última nota</small><strong>${pGrades[0]?.nota??'—'}</strong></span></div><div class="spotlight-actions"><button class="btn btn-primary" type="button" data-student-view="lessons">Aulas e notas ${icon('arrow')}</button><button class="btn btn-secondary" type="button" data-student-view="finance">Financeiro</button></div></section>`);
  if(!cards.length)return `<section class="student-empty-state">${icon('book')}<h2>Nenhum curso disponível</h2><p>Seu login foi confirmado, mas ainda não localizamos uma matrícula acadêmica vinculada.</p><a class="btn btn-primary" href="${whatsappUrl('Olá! Preciso de ajuda para vincular meu curso ao Portal Live Connect.')}" target="_blank" rel="noopener">${icon('whatsapp')} Falar com a equipe</a></section>${presencialNotice(data)}`;
  return `<div class="student-dashboard-grid"><div class="student-journey-grid">${cards.join('')}</div>${c?`<div class="student-kpis"><article>${icon('book')}<small>Aulas EAD</small><strong>${total}</strong></article><article>${icon('check')}<small>Concluídas</small><strong>${done}</strong></article><article>${icon('award')}<small>Última nota EAD</small><strong>${eadGrades.length?eadGrades[eadGrades.length-1]:'—'}</strong></article></div>`:''}${data.local?.linked?`<section class="student-local-summary"><div><span class="eyebrow">LIVE CONNECT</span><h3>Informações da sua matrícula</h3></div><div class="student-local-grid"><span><small>Horário</small><strong>${esc(data.local.schedule_text||'A confirmar')}</strong></span><span><small>Vencimento</small><strong>${data.local.due_day?`Dia ${data.local.due_day}`:'A confirmar'}</strong></span><span><small>Situação</small><strong>${esc(data.local.enrollment_payment_status||'—')}</strong></span></div></section>`:''}${presencialNotice(data)}</div>`;
}

function studentCourses(data){
  const ead=Array.isArray(data.courses)?data.courses:[],presencial=presencialCourses(data);
  if(!ead.length&&!presencial.length)return `<div class="student-empty-state"><h2>Nenhum curso disponível.</h2></div>${presencialNotice(data)}`;
  const eadHtml=ead.length?`<section class="unified-course-group"><div class="unified-group-title"><span class="modality-chip">EAD</span><h2>Cursos Ouro Moderno</h2></div><div class="student-course-list">${ead.map(c=>{const pct=progressOf(c),contract=c.contrato||{};return `<article><div class="student-course-icon">${icon('book')}</div><div class="student-course-main"><span class="course-status-pill">${esc(c.situacao||'')}</span><h3>${esc(c.curso||'Curso')}</h3><p>Matrícula: ${contract.data_matricula?esc(formatDate(contract.data_matricula+'T12:00:00')):'—'} ${contract.data_fim?`• acesso até ${esc(formatDate(contract.data_fim+'T12:00:00'))}`:''}</p><div class="student-progress compact"><span style="width:${pct}%"></span></div><small>${pct}% • ${esc(c.progresso?.aulas_concluidas||'0')} de ${esc(c.progresso?.total_aulas||'0')} aulas</small></div><button class="btn btn-ghost btn-compact" type="button" data-open-student-course="${esc(c.id)}" data-contract="${esc(contract.id||'')}">Aulas e notas ${icon('arrow')}</button></article>`}).join('')}</div></section>`:'';
  const presencialHtml=presencial.length?`<section class="unified-course-group"><div class="unified-group-title"><span class="modality-chip modality-chip--presencial">PRESENCIAL</span><h2>Cursos Live Connect</h2></div><div class="student-course-list">${presencial.map(c=>{const modules=Array.isArray(data.presencial?.modules)?data.presencial.modules.filter(m=>String(m.id_aluno_curso)===String(c.id_aluno_curso)):[];const attendance=presencialAttendance(data,c.id_aluno_curso);return `<article><div class="student-course-icon student-course-icon--presencial">${icon('location')}</div><div class="student-course-main"><span class="course-status-pill">${esc(c.situacao||'')}</span><h3>${esc(c.curso||'Curso presencial')}</h3><p>Matrícula: ${legacyDate(c.data_matricula)} ${c.previsao_termino?`• previsão ${legacyDate(c.previsao_termino)}`:''}</p><small>${modules.length} módulos${attendance?` • ${attendancePercent(attendance)}% de frequência`:''}</small></div><button class="btn btn-ghost btn-compact" type="button" data-open-presential-course="${esc(c.id_aluno_curso)}">Aulas e notas ${icon('arrow')}</button></article>`}).join('')}</div></section>`:'';
  return `<div class="unified-course-stack">${presencialHtml}${eadHtml}${presencialNotice(data)}</div>`;
}

function studentLessons(course,data,presentialCourseId=''){
  const sections=[];
  const lessons=Array.isArray(course?.aulas)?course.aulas:[];
  if(course)sections.push(`<section class="student-lessons-panel"><div class="panel-head"><div><span class="modality-chip">EAD • AULAS E NOTAS</span><h2>${esc(course.curso||'Curso')}</h2><p>${esc(course.progresso?.aulas_concluidas||'0')} de ${esc(course.progresso?.total_aulas||lessons.length)} aulas concluídas • ${esc(course.progresso?.percentual||'0')}%</p></div><a class="btn btn-yellow btn-compact" href="https://ead.ouromoderno.com.br/" target="_blank" rel="noopener" data-study-link>Continuar no EAD ${icon('external')}</a></div><div class="lesson-list">${lessons.map(a=>{const done=a.situacao==='concluido',current=a.situacao==='cursando';return `<article class="${done?'done':current?'current':''}"><span class="lesson-state">${done?icon('check'):current?icon('arrow'):icon('clock')}</span><div><strong>${esc(a.aula)}. ${esc(a.descricao||'Aula')}</strong><small>${done?'Concluída':current?'Em andamento':'Não iniciada'}${a.data?` • ${esc(formatDate(a.data))}`:''}</small></div><div class="lesson-grade"><small>Nota</small><strong>${a.nota??'—'}</strong></div></article>`}).join('')}</div></section>`);
  const pc=presencialCourse(data,presentialCourseId),p=presencialOf(data);
  if(pc){const modules=Array.isArray(p.modules)?p.modules.filter(m=>String(m.id_aluno_curso)===String(pc.id_aluno_curso)):[];const grades=Array.isArray(p.grades)?p.grades.filter(g=>String(g.id_aluno_curso)===String(pc.id_aluno_curso)):[];sections.unshift(`<section class="student-lessons-panel presencial-lessons-panel"><div class="panel-head"><div><span class="modality-chip modality-chip--presencial">PRESENCIAL • AULAS E NOTAS</span><h2>${esc(pc.curso||'Curso presencial')}</h2><p>${modules.length} módulos vinculados à matrícula ${esc(p.student?.matricula||'—')}</p></div></div><div class="presential-academic-grid"><div><h3>Módulos</h3>${modules.length?`<div class="dk-table">${modules.map(m=>`<div class="dk-table__row"><div><strong>${esc(m.modulo||'Módulo')}</strong><small>${Number(m.carga_horaria||0)}h • ${esc(m.situacao||'—')}</small></div><span>${legacyDate(m.data_final||m.data_inicial)}</span></div>`).join('')}</div>`:'<p class="dk-empty">Nenhum módulo registrado.</p>'}</div><div><h3>Notas</h3>${grades.length?`<div class="dk-table">${grades.map(g=>`<div class="dk-table__row"><div><strong>${esc(g.avaliacao||'Avaliação')}</strong><small>${esc(g.modulo||'Módulo')} • ${legacyDate(g.data)}</small></div><strong class="dk-grade">${esc(g.nota??'—')}</strong></div>`).join('')}</div>`:'<p class="dk-empty">Nenhuma avaliação registrada.</p>'}</div></div></section>`)}
  return sections.length?`<div class="unified-panel-stack">${sections.join('')}</div>`:`<div class="student-empty-state"><h2>Nenhuma aula disponível.</h2></div>${presencialNotice(data)}`;
}

function studentSchedule(data){
  const l=data.local||{},pc=presencialCourse(data),p=presencialOf(data);
  const local=l.linked?`<div class="info-detail-grid"><article>${icon('calendar')}<small>Horário registrado</small><strong>${esc(l.schedule_text||'A confirmar')}</strong></article><article>${icon('location')}<small>Sala</small><strong>${esc(l.room_name||l.class_label||'A confirmar')}</strong></article><article>${icon('clock')}<small>Início</small><strong>${l.start_date?esc(formatDate(l.start_date+'T12:00:00')):'A confirmar'}</strong></article></div>`:'';
  const presencial=pc?`<div class="info-detail-grid presential-schedule"><article>${icon('book')}<small>Curso presencial</small><strong>${esc(pc.curso||'Curso')}</strong></article><article>${icon('user')}<small>Matrícula</small><strong>${esc(p?.student?.matricula||'—')}</strong></article><article>${icon('clock')}<small>Previsão de conclusão</small><strong>${legacyDate(pc.previsao_termino||pc.data_termino)}</strong></article></div>`:'';
  return `<section class="student-info-panel"><span class="eyebrow">TURMA E HORÁRIO</span><h2>Sua rotina de estudos</h2>${local}${presencial}${!local&&!presencial?`<div class="student-honest-note">${icon('info')}<div><strong>Ainda não encontramos informações de turma.</strong><p>Fale com a Secretaria para confirmar dias e horários.</p></div></div>`:''}${presencialNotice(data)}</section>`;
}

function studentFinance(data){
  const l=data.local||{},localPayments=Array.isArray(l.payments)?l.payments:[];
  const finance=Array.isArray(presencialOf(data)?.finance)?presencialOf(data).finance:[];
  const summary=l.linked?`<div class="info-detail-grid"><article>${icon('calendar')}<small>Dia de vencimento</small><strong>${l.due_day?`Dia ${l.due_day}`:'A confirmar'}</strong></article><article>${icon('check')}<small>Matrícula</small><strong>${esc(l.enrollment_payment_status||'—')}</strong></article><article>${icon('check')}<small>Primeira mensalidade</small><strong>${esc(l.first_month_payment_status||'—')}</strong></article></div>`:'';
  const entries=finance.length?`<div class="finance-section-title"><span class="modality-chip modality-chip--presencial">PRESENCIAL</span><h3>Movimentações registradas no DKOnline</h3></div><div class="dk-table">${finance.map(entry=>{const paid=entry.quitado==='S';return `<div class="dk-table__row"><div><strong>${esc(entry.historico||'Parcela')}</strong><small>Vencimento: ${legacyDate(entry.vencimento)}</small></div><div class="dk-finance"><strong>${legacyMoney(paid?entry.valor_pago:entry.valor)}</strong><span class="dk-badge${paid?' dk-badge--paid':''}">${paid?'Pago':'Em aberto'}</span></div></div>`}).join('')}</div>`:localPayments.length?`<div class="student-payment-list">${localPayments.map(p=>`<div><span>${esc(p.kind||'Pagamento')}</span><strong>R$ ${Number(p.amount||0).toLocaleString('pt-BR',{minimumFractionDigits:2})}</strong><em class="payment-${esc(p.status||'pendente')}">${esc(p.status||'pendente')}</em></div>`).join('')}</div>`:'';
  return `<section class="student-info-panel"><span class="eyebrow">FINANCEIRO</span><h2>Informações da sua matrícula</h2>${summary}${entries||`<div class="student-honest-note">${icon('info')}<div><strong>Nenhuma movimentação disponível.</strong><p>Isso não significa que exista pendência. Consulte a Secretaria para confirmação.</p></div></div>`}${presencialNotice(data)}</section>`;
}

function studentCertificates(data){
  const presencial=presencialCourses(data);
  const presencialHtml=presencial.length?`<div class="finance-section-title"><span class="modality-chip modality-chip--presencial">PRESENCIAL</span><h3>Situação no DKOnline</h3></div><div class="dk-table">${presencial.map(course=>{const ready=course.certificado==='S',delivered=course.certificado_entregue==='S';return `<div class="dk-table__row"><div><strong>${esc(course.curso||'Curso presencial')}</strong><small>${delivered?'Certificado entregue':ready?'Certificado registrado; confirme a disponibilidade com a Secretaria':'Ainda não liberado no sistema'}</small></div><span class="dk-badge${ready?' dk-badge--paid':''}">${delivered?'Entregue':ready?'Disponível':'Pendente'}</span></div>`}).join('')}</div>`:'';
  return `<section class="student-info-panel"><span class="eyebrow">CERTIFICADOS</span><h2>Seus certificados</h2>${presencialHtml}<div class="student-honest-note">${icon('award')}<div><strong>O portal mostra a situação registrada no sistema presencial.</strong><p>Para emissão, segunda via ou certificado EAD, solicite diretamente à equipe Live Connect.</p></div></div><a class="btn btn-primary" href="${whatsappUrl('Olá! Preciso de ajuda com meu certificado na Live Connect.')}" target="_blank" rel="noopener">${icon('whatsapp')} Solicitar atendimento</a></section>`;
}

function legacyDate(value){
  const raw=String(value||'').slice(0,10);
  if(!/^\d{4}-\d{2}-\d{2}$/.test(raw)||raw.startsWith('0000-')||raw.startsWith('1899-'))return '—';
  const [year,month,day]=raw.split('-');return `${day}/${month}/${year}`;
}

function legacyMoney(value){
  return Number(value||0).toLocaleString('pt-BR',{style:'currency',currency:'BRL'});
}

function studentSupport(){
  return `<section class="student-support-panel"><img class="mascot-official" src="/assets/images/mascotes/mascote-boas-vindas.png" alt="Mascote Live Connect acenando"><div><span class="eyebrow yellow">SUPORTE AO ALUNO</span><h2>Precisa de ajuda?</h2><p>Fale com a equipe sobre acesso ao EAD, turma, pagamentos, certificado ou qualquer dificuldade na sua jornada.</p><a class="btn btn-yellow" href="${whatsappUrl('Olá! Sou aluno da Live Connect e preciso de suporte com meu acesso/curso.')}" target="_blank" rel="noopener">${icon('whatsapp')} Falar com a Live Connect</a></div></section>`;
}

export async function hydrateStudent(navigate) {
  const form=document.getElementById('authForm');
  if(form){
    form.addEventListener('submit',async e=>{
      e.preventDefault();
      const loginValue=form.querySelector('#authUsername').value.trim();
      const passwordInput=form.querySelector('#authPassword');
      const password=passwordInput.value;
      // A janela precisa nascer diretamente do clique do usuário para não ser bloqueada.
      const ouroBridge=beginOuroBrowserSession();
      const btn=e.submitter;btn.disabled=true;btn.textContent='Validando no EAD…';
      try{
        await studentLogin(loginValue,password);
        const primed=primeOuroBrowserSession(loginValue,password,ouroBridge);
        if(!primed) toast('Login confirmado. Para acesso automático ao EAD, permita pop-ups deste site.','error');
        passwordInput.value='';
        track('student_login_success',{provider:'ouro_moderno'});
        toast('Acesso confirmado. Bem-vindo ao Portal Live Connect.');
        navigate('/area-do-aluno/',true);
      }catch(err){
        try{ouroBridge?.popup?.close();}catch{}
        const code=String(err?.message||'');
        const msg=code==='too_many_attempts'?'Muitas tentativas. Aguarde alguns minutos e tente novamente.':code==='student_inactive'?'Seu acesso na Ouro Moderno está inativo. Fale com a Live Connect.':code==='student_not_resolved'?'Credenciais válidas, mas não foi possível localizar seu cadastro acadêmico. Fale com a equipe.':'Usuário ou senha da Ouro Moderno inválidos.';
        toast(msg,'error');btn.disabled=false;btn.innerHTML=`Entrar no Portal ${icon('arrow')}`;
      }finally{passwordInput.value='';}
    });
    return;
  }

  const mount=document.getElementById('studentPortalMount');if(!mount)return;
  let data;
  try{data=await getStudentDashboard();}
  catch(err){await studentLogout();toast('Sua sessão expirou. Entre novamente.','error');navigate('/area-do-aluno/',true);return;}

  const name=data?.student?.name||getStudentSession()?.student?.name||'Aluno';
  mount.className='student-portal';
  mount.innerHTML=`<div class="portal-mobile-bar"><button class="icon-button" type="button" data-portal-menu aria-label="Abrir navegação" aria-expanded="false">${icon('menu')}</button><strong>Área do Aluno</strong><button class="icon-button" type="button" data-student-logout aria-label="Sair">${icon('logout')}</button></div>
    <aside class="portal-side student-side" id="studentSide"><img src="/assets/images/logo.png?v=2216" width="145" height="64" alt="Live Connect"><div class="student-side-profile"><span>${icon('user')}</span><div><strong>${esc(firstName(name))}</strong><small>${esc(data?.student?.login||'Aluno')}</small></div></div><nav>
      <button class="active" data-student-view="overview">${icon('home')} Visão geral</button>
      <button data-student-view="courses">${icon('book')} Meus cursos</button>
      <button data-student-view="lessons">${icon('chart')} Aulas e notas</button>
      <button data-student-view="schedule">${icon('calendar')} Turma e horário</button>
      <button data-student-view="finance">${icon('briefcase')} Financeiro</button>
      <button data-student-view="certificates">${icon('award')} Certificados</button>
      <button data-student-view="support">${icon('mail')} Suporte</button>
    </nav><button class="portal-logout" type="button" data-student-logout>${icon('logout')} Sair</button></aside>
    <button class="portal-menu-backdrop" type="button" data-portal-close aria-label="Fechar navegação"></button>
    <div class="portal-content"><div class="portal-welcome"><div><span class="eyebrow">ÁREA DO ALUNO</span><h1>Olá, ${esc(firstName(name))}.</h1><p>Acompanhe seus cursos presenciais e EAD no mesmo ambiente.</p></div><span class="status-chip status-online">${icon('wifi')} ${presencialOf(data)&&data.primary_course?'EAD + presencial':presencialOf(data)?'Presencial sincronizado':'EAD sincronizado'}</span></div><div id="studentView"></div></div>`;

  bindPortalMenu();
  const target=document.getElementById('studentView');
  let selectedCourse=data.primary_detail||null;
  let selectedPresentialCourseId=presencialCourse(data)?.id_aluno_curso||'';

  async function renderView(view){
    document.querySelectorAll('[data-student-view]').forEach(b=>b.classList.toggle('active',b.dataset.studentView===view));
    if(view==='overview') target.innerHTML=studentOverview(data);
    if(view==='courses') target.innerHTML=studentCourses(data);
    if(view==='lessons') target.innerHTML=studentLessons(selectedCourse||data.primary_detail,data,selectedPresentialCourseId);
    if(view==='schedule') target.innerHTML=studentSchedule(data);
    if(view==='finance') target.innerHTML=studentFinance(data);
    if(view==='certificates') target.innerHTML=studentCertificates(data);
    if(view==='support') target.innerHTML=studentSupport();

    target.querySelectorAll('[data-student-view]').forEach(b=>b.addEventListener('click',()=>renderView(b.dataset.studentView)));
    target.querySelectorAll('[data-open-student-course]').forEach(b=>b.addEventListener('click',async()=>{
      const original=b.innerHTML;b.disabled=true;b.textContent='Carregando…';
      try{const detail=await getStudentCourseDetail(b.dataset.openStudentCourse,b.dataset.contract);selectedCourse=detail.course;renderView('lessons');}
      catch{toast('Não foi possível carregar as aulas deste curso.','error');b.disabled=false;b.innerHTML=original;}
    }));
    target.querySelectorAll('[data-open-presential-course]').forEach(b=>b.addEventListener('click',()=>{selectedPresentialCourseId=b.dataset.openPresentialCourse;renderView('lessons');}));
  }

  document.querySelectorAll('[data-student-view]').forEach(b=>b.addEventListener('click',()=>renderView(b.dataset.studentView)));
  document.querySelectorAll('[data-student-logout]').forEach(b=>b.addEventListener('click',async()=>{await studentLogout();track('student_logout',{provider:'ouro_moderno'});navigate('/area-do-aluno/',true);}));
  renderView('overview');
}

function bindPortalMenu(){
  const side=document.querySelector('.portal-side'),toggle=document.querySelector('[data-portal-menu]'),backdrop=document.querySelector('[data-portal-close]');
  const onEsc=e=>{if(e.key==='Escape')close();};
  const close=()=>{side?.classList.remove('mobile-open');document.documentElement.classList.remove('portal-menu-open');toggle?.setAttribute('aria-expanded','false');document.removeEventListener('keydown',onEsc);};
  toggle?.addEventListener('click',()=>{const open=!side?.classList.contains('mobile-open');side?.classList.toggle('mobile-open',open);document.documentElement.classList.toggle('portal-menu-open',open);toggle?.setAttribute('aria-expanded',String(open));if(open)document.addEventListener('keydown',onEsc);else document.removeEventListener('keydown',onEsc);});
  backdrop?.addEventListener('click',close);
  side?.querySelectorAll('nav button').forEach(btn=>btn.addEventListener('click',()=>{if(matchMedia('(max-width:1020px)').matches)close();}));
}

export function adminPage() {
  const session=getSession();
  const content=session?`<section class="portal-page admin-bg"><div class="container-wide"><div id="adminMount" class="portal-loading"><span class="loader"></span><p>Validando acesso à Central da Escola…</p></div></div></section>`:`<section class="auth-page"><div class="auth-visual admin-auth"><div><span class="eyebrow yellow">CENTRAL LIVE CONNECT</span><h2>Secretaria, Comercial e Diretoria em um só ambiente.</h2><p>O acesso é liberado de acordo com o perfil administrativo de cada usuário.</p></div><img class="mascot-official" src="/assets/images/mascotes/mascote-estudando.png" alt="Mascote oficial Live Connect"></div>${loginForm('admin')}</section>`;
  return pageShell(content,'admin');
}

export async function hydrateAdmin(navigate) {
  const form=document.getElementById('authForm');
  if(form){form.addEventListener('submit',async e=>{e.preventDefault();const btn=e.submitter;btn.disabled=true;btn.textContent='Entrando…';try{await login(form.querySelector('#authEmail').value.trim(),form.querySelector('#authPassword').value);navigate('/admin/',true);}catch{toast('E-mail ou senha inválidos.','error');btn.disabled=false;btn.innerHTML=`Entrar com segurança ${icon('arrow')}`;}});return;}
  const mount=document.getElementById('adminMount');if(!mount)return;
  const profile=await getMyProfile().catch(()=>null);
  if(!profile||!profile.active||!ADMIN_ROLES.has(profile.role)){
    mount.className='access-denied';
    mount.innerHTML=`${icon('shield')}<h1>Acesso não autorizado</h1><p>Esta conta não possui perfil administrativo ativo.</p><button class="btn btn-primary" type="button" data-auth-logout>Sair</button>`;
    mount.querySelector('[data-auth-logout]')?.addEventListener('click',async()=>{await logout();navigate('/admin/',true);});return;
  }
  const {mountAdminCentral}=await import('./admin-central.js');
  await mountAdminCentral(mount,profile,navigate);
}


export function privacyPage() {
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Privacidade',href:'/privacidade/'}])}<section class="page-hero compact"><div class="container-wide"><span class="eyebrow">PRIVACIDADE</span><h1>Seus dados merecem <span>clareza e cuidado.</span></h1><p>Esta página resume como os dados enviados pelo Portal Live Connect são usados no atendimento e na operação escolar.</p></div></section><section class="section"><div class="container-narrow legal-content"><h2>Dados que podem ser coletados</h2><p>Nos formulários de contato, cursos gratuitos, Projeto Jovem Aprendiz e pré-inscrição, podem ser solicitados dados de identificação, contato, endereço e, quando aplicável, dados do responsável legal.</p><h2>Para que usamos essas informações</h2><p>Os dados são utilizados para responder solicitações, registrar interesses no CRM, processar pré-inscrições, organizar o atendimento e manter registros necessários à operação escolar.</p><h2>Integrações</h2><p>O portal utiliza serviços de infraestrutura e gestão para processar formulários, autenticação, analytics, integrações acadêmicas e, quando o usuário escolhe pagar online, o Mercado Pago como processador de pagamentos. Credenciais privadas de backend não são expostas no navegador.</p><h2>Contato</h2><p>Para dúvidas sobre seus dados, entre em contato pelo e-mail ${esc(CONFIG.brand.email)} ou pelos canais oficiais da Live Connect.</p></div></section>`,'');
}

export function termsPage() {
  return pageShell(`${breadcrumbs([{label:'Início',href:'/'},{label:'Termos de uso',href:'/termos/'}])}<section class="page-hero compact"><div class="container-wide"><span class="eyebrow">TERMOS DE USO</span><h1>Informação clara antes de <span>qualquer decisão.</span></h1><p>O portal apresenta informações institucionais, cursos, campanhas e canais de pré-atendimento da Live Connect.</p></div></section><section class="section"><div class="container-narrow legal-content"><h2>Pré-inscrição e pagamento</h2><p>O envio de uma ficha pelo portal registra uma pré-inscrição e não gera cobrança automática. Após o envio, o usuário pode optar por iniciar um pagamento online. O valor apresentado é calculado pelo backend conforme a condição financeira vigente e o pagamento é processado em ambiente seguro do Mercado Pago.</p><h2>Campanhas</h2><p>Ofertas e campanhas podem ter período, disponibilidade e condições específicas. As condições válidas são as confirmadas no atendimento da Live Connect.</p><h2>Cursos gratuitos</h2><p>O registro de interesse em curso gratuito não garante vaga. A disponibilidade depende das turmas e critérios comunicados pela equipe.</p><h2>Empregabilidade</h2><p>A Live Connect oferece qualificação e iniciativas voltadas ao desenvolvimento profissional. Não há garantia de contratação, renda ou resultado profissional específico.</p></div></section>`,'');
}
export function notFoundPage(){return pageShell(`<section class="not-found"><div class="container-narrow"><span class="error-code">404</span><h1>Essa página saiu da rota.</h1><p>Use o menu para continuar explorando a Live Connect.</p><a class="btn btn-primary" href="/" data-router>Voltar ao início ${icon('arrow')}</a></div></section>`,'');}

export function metaFor(route){
  if(route.name==='course'){
    const c=DATA.courses.find(x=>x.slug===route.slug);
    if(!c)return{title:'Cursos Profissionalizantes em Ilhéus | Live Connect',description:'Conheça as formações profissionais da Live Connect em Ilhéus.'};
    const modes=(c.modalities||[]).join(' e ');
    const courseTitle=c.slug==='montagem-e-configuracao-de-computadores'?'Montagem de Computadores em Ilhéus | Live Connect':`Curso de ${c.name} em Ilhéus | Live Connect`;return{title:courseTitle,description:`Curso de ${c.name} em Ilhéus: ${c.duration}, ${c.modules.length} módulos e modalidade ${modes}. Veja conteúdo, formas de estudo e condições de matrícula.`};
  }
  if(route.name==='courseCategory'){
    const c=CATEGORY_BY_SLUG[route.categorySlug]||'Profissionalizantes';
    return{title:`Cursos de ${c} em Ilhéus | Live Connect`,description:`Conheça os cursos de ${c} da Live Connect em Ilhéus. Compare formações, conteúdos, duração e modalidades disponíveis.`};
  }
  const map={home:['Live Connect | Cursos Profissionalizantes em Ilhéus','Cursos profissionalizantes em Ilhéus, formações presenciais e EAD, cursos gratuitos e Projeto Jovem Aprendiz na Live Connect Escola de Profissões.'],nrs:['Cursos de NR em Ilhéus | Live Connect','Conheça os cursos de Normas Regulamentadoras disponíveis na Live Connect, com carga horária, duração e investimento atualizados automaticamente.'],nrCourse:['Curso NR | Live Connect','Veja carga horária, duração estimada e investimento vigente para este curso de Norma Regulamentadora.'],shortCourses:['Cursos Curtos em Ilhéus | Live Connect','Qualificações de curta duração com investimento calculado automaticamente pela duração e condição comercial vigente da Live Connect.'],shortCourse:['Curso Curto | Live Connect','Veja carga horária, duração estimada e investimento vigente deste curso curto da Live Connect.'],courses:['Cursos Profissionalizantes em Ilhéus | Live Connect','Explore cursos profissionalizantes em Ilhéus por área e modalidade. Conheça conteúdos, duração e formas de matrícula na Live Connect.'],free:['Cursos Gratuitos em Ilhéus | Live Connect','Conheça os cursos gratuitos presenciais da Live Connect em Ilhéus, veja duração, aulas e registre seu interesse nas próximas turmas.'],young:['Jovem Aprendiz Gratuito em Ilhéus | Live Connect','Conheça o Projeto Jovem Aprendiz gratuito da Live Connect em Ilhéus e registre seu interesse nas próximas turmas.'],about:['Live Connect Escola de Profissões em Ilhéus | Sobre','Conheça a Live Connect Escola de Profissões, sua proposta de qualificação profissional e atuação com cursos presenciais e EAD em Ilhéus.'],contact:['Contato Live Connect em Ilhéus | Cursos e Matrículas','Fale com a Live Connect em Ilhéus sobre cursos profissionalizantes, matrícula, projetos gratuitos, horários e atendimento ao aluno.'],privacy:['Privacidade | Live Connect','Política de privacidade e tratamento de dados do Portal Live Connect.'],terms:['Termos de Uso | Live Connect','Termos de uso, matrícula, campanhas e condições do Portal Live Connect.'],student:['Área do Aluno | Live Connect','Acesso seguro à Área do Aluno Live Connect.'],admin:['Área Administrativa | Live Connect','Acesso administrativo seguro da Live Connect.'],notfound:['Página não encontrada | Live Connect','A página solicitada não foi encontrada.']};
  const [title,description]=map[route.name]||map.notfound;return{title,description};
}
