Deno.serve(() => new Response('A entrega segura de primeiro acesso está temporariamente indisponível.', {
  status: 503,
  headers: {
    'Content-Type':'text/plain; charset=utf-8',
    'Cache-Control':'no-store, no-cache, must-revalidate, max-age=0',
    'Referrer-Policy':'no-referrer',
    'X-Content-Type-Options':'nosniff'
  }
}));