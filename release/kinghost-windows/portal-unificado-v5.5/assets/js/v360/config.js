export const CONFIG = Object.freeze({
  brand: {
    name: 'Live Connect Escola de Profissões',
    shortName: 'Live Connect',
    city: 'Ilhéus - BA',
    address: 'Rua Sá Oliveira, 18 - Ed. Empresarial Fraga Center, Sala 01 - Centro, Ilhéus - BA',
    email: 'contato@liveconnect.com.br',
    phoneDisplay: '(73) 3223-7593',
    whatsapp: '557332237593',
    canonicalOrigin: 'https://www.liveconnect.com.br'
  },
  supabase: {
    url: 'https://utfxjadpntvbrhnkghbf.supabase.co',
    publishableKey: 'sb_publishable_ZsaxQ9DDaeQ9JOSPpxO20Q_l0XwyiyC',
    enrollmentEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=enrollment',
    leadEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=lead',
    youngApprenticeEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=young',
    analyticsEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=analytics',
    paymentEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=payment',
    enrollmentPreferencesEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-enrollment-preferences',
    ouroStudentEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=ouro',
    dkwebStudentEndpoint: 'https://utfxjadpntvbrhnkghbf.supabase.co/functions/v1/portal-gateway?service=dkweb'
  },
  integrationStatus: {
    supabase: 'connected',
    ouroWebhook: 'connected',
    ouroApi: 'connected',
    mercadoPago: 'backend_ready'
  },
  dueDays: [5, 10, 15, 20, 25, 30],
  schedules: [
    '08h - 10h Segunda a Sexta-Feira',
    '10h - 12h (Sexta-feira)',
    '14h - 16h Segunda a Sexta-Feira',
    '16h - 18h Segunda a Sexta-Feira',
    '18h - 20h (Somente nas quartas-feiras)'
  ]
});
