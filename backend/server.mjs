import http from 'node:http';
import { pathToFileURL } from 'node:url';
import { Catalog, CatalogError } from './catalog.mjs';

export function createServer(catalog = new Catalog({token:process.env.HARDCOVER_TOKEN})) {
  const server = http.createServer(async (req,res) => {
    const send = (status,data,headers={}) => {
      res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store',
        'X-Content-Type-Options':'nosniff',...headers}); res.end(JSON.stringify(data));
    };
    // The keep-alive endpoint does no catalog work and does not require the API credential.
    if ((req.method === 'GET' || req.method === 'HEAD') && req.url === '/health') {
      return send(200,{status:'ok',catalogConfigured:Boolean(catalog.token)});
    }
    if (req.method !== 'POST' || !['/v1/metadata','/v1/discovery','/v1/series','/v1/preview','/v1/mood-books','/v1/discover-picks'].includes(req.url))
      return send(404,{error:'not_found'});
    try {
      // Render appends its verified connecting IP; do not trust the leftmost caller-supplied value.
      const forwarded = String(req.headers['x-forwarded-for'] ?? '').split(',').map(v=>v.trim());
      catalog.limitClient(process.env.RENDER ? forwarded.at(-1) || req.socket.remoteAddress : req.socket.remoteAddress);
      if (!/^application\/json(?:;|$)/i.test(req.headers['content-type'] ?? '')) throw new CatalogError(415,'json_required');
      if (Number(req.headers['content-length']) > 4096) { req.resume(); throw new CatalogError(413,'lookup_too_large'); }
      let size = 0; const chunks = [];
      for await (const chunk of req) {
        size += chunk.length;
        if (size > 4096) throw new CatalogError(413,'lookup_too_large');
        chunks.push(chunk);
      }
      let input;
      try { input = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
      catch { throw new CatalogError(400,'invalid_json'); }
      if (req.url === '/v1/discovery') return send(200,{discovery:await catalog.discovery(input)});
      if (req.url === '/v1/series') return send(200,await catalog.seriesPage(input));
      if (req.url === '/v1/preview') return send(200,{preview:await catalog.preview(input)});
      if (req.url === '/v1/mood-books') return send(200,await catalog.moodBooks(input));
      if (req.url === '/v1/discover-picks') return send(200,await catalog.discoverPicks(input));
      send(200,{metadata:await catalog.lookup(input)});
    } catch (error) {
      const known = error instanceof CatalogError;
      const status = known ? error.status : 503;
      const code = known ? error.code : 'catalog_unavailable';
      // Log codes only: never ISBNs, titles, client addresses, credentials or upstream bodies.
      if (status >= 500) console.error(JSON.stringify({event:'metadata_failure',code}));
      send(status,{error:code},status === 429 || status === 503 ? {'Retry-After':String(error.retryAfter ?? 60)} : {});
    }
  });
  server.requestTimeout = 60000; server.headersTimeout = 10000;
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const port = Number(process.env.PORT ?? 10000);
  createServer().listen(port,'0.0.0.0',() => console.log(JSON.stringify({event:'listening',port})));
}
