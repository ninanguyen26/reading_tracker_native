import test from 'node:test';
import assert from 'node:assert/strict';
import {Catalog,validateInput} from './catalog.mjs';
import {createServer} from './server.mjs';
const book = {id:42,title:'Test Book',description:'A wizard explores an enchanted forest.',
  contributions:[{author:{name:'Test Author'}}],book_series:[{position:2.5,series:{name:'Wizard Series'}}],
  cached_tags:{Genre:[{tag:'Fantasy'}],Mood:[{tag:'Horror'}]}};
const input = {title:'Test Book',author:'Test Author'};
function setup(responder,options={}) {
  const requests=[];
  const catalog = new Catalog({token:'test-only-credential',interval:0,...options,fetcher:async (url,init)=>{
    const body=JSON.parse(init.body); requests.push({url,init,body});
    return responder(body,requests.length);
  }});
  return {catalog,requests};
}
const result = data => Response.json({data});
test('exact ISBN supplies edition pages and Genre only; credentials go only upstream',async()=>{
  const {catalog,requests}=setup(()=>result({editions:[{id:11,isbn_13:'9780140328721',pages:320,book}]}));
  const data=await catalog.lookup({...input,isbn:'9780140328721'});
  assert.equal(data.exactEdition.pages,320);assert.equal(data.exactEdition.isbn,'9780140328721');
  assert.equal(data.series[0].position,2.5);assert.deepEqual(data.genres,['Fantasy']);
  assert.equal(requests[0].init.headers.Authorization,'Bearer test-only-credential');
  assert.ok(!JSON.stringify(data).includes('test-only-credential'));
});
test('title and author match cannot supply pages; mismatched authors rejected',async()=>{
  const {catalog}=setup(()=>result({books:[{...book,pages:999}]}));
  assert.equal((await catalog.lookup(input)).exactEdition,null);
  assert.equal(await catalog.lookup({...input,author:'Different Author'}),null);
});
test('duplicate ISBNs and ambiguous title matches rejected',async()=>{
  const edition={id:11,isbn_13:'9780140328721',pages:320,book};
  const {catalog}=setup(body=>result(body.variables.isbn?{editions:[edition,edition]}:{books:[book,book]}));
  assert.equal(await catalog.lookup({...input,isbn:'9780140328721'}),null);
  assert.equal(await catalog.lookup(input),null);
});
test('missing ISBN falls back to title with no edition pages',async()=>{
  const {catalog,requests}=setup(body=>result(body.variables.isbn?{editions:[]}:{books:[book]}));
  assert.equal((await catalog.lookup({...input,isbn:'9780140328721'})).exactEdition,null);
  assert.equal(requests.length,2);
});
test('concurrent identical lookups coalesce; hits and misses are cached with expiry',async()=>{
  let now=0;
  const {catalog,requests}=setup(()=>result({books:[]}),{now:()=>now});
  const values=await Promise.all([catalog.lookup(input),catalog.lookup(input)]);
  assert.deepEqual(values,[null,null]);assert.equal(requests.length,1);
  await catalog.lookup(input); assert.equal(requests.length,1);
  now=3600001; await catalog.lookup(input);assert.equal(requests.length,2);
});
test('upstream quota reservation counts queries, resets next UTC day',async()=>{
  let now=0;
  const {catalog,requests}=setup(()=>result({books:[book]}),{dailyLimit:1,now:()=>now});
  await catalog.lookup(input);
  await assert.rejects(()=>catalog.lookup({...input,title:'Other'}),e=>e.code==='catalog_daily_limit');
  assert.equal(requests.length,1);
  now=86400000; await catalog.lookup({...input,title:'Other'});assert.equal(requests.length,2);
});
test('429 stops further upstream requests; GraphQL errors never become cached misses',async()=>{
  const {catalog,requests}=setup(()=>new Response('{}',{status:429,headers:{'retry-after':'120'}}));
  await assert.rejects(()=>catalog.lookup(input),e=>e.retryAfter===120);
  await assert.rejects(()=>catalog.lookup({...input,title:'Other'}),e=>e.status===429);
  assert.equal(requests.length,1);
  const failed=setup(()=>Response.json({errors:[{message:'secret upstream details'}]}));
  for(let i=0;i<2;i++) await assert.rejects(()=>failed.catalog.lookup(input),e=>e.code==='catalog_query_failed');
  assert.equal(failed.requests.length,2);
});
test('per-client limits bound repeated requests',()=>{
  const {catalog}=setup(()=>result({books:[]}));
  for(let i=0;i<30;i++)catalog.limitClient('example-client');
  assert.throws(()=>catalog.limitClient('example-client'),e=>e.status===429);
});
test('reject arbitrary GraphQL, invalid ISBNs, oversized fields, and insufficient identifiers',()=>{
  for(const value of [{query:'me { email }'}, {...input,isbn:'123'},{...input,title:'x'.repeat(501)},{title:'Book'}])
    assert.throws(()=>validateInput(value),e=>e.status===400);
});
test('health does not call Hardcover; public HTTP lookup returns sanitized metadata without auth',async()=>{
  const {catalog,requests}=setup(()=>result({books:[book]}));
  const server=createServer(catalog);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const url=`http://127.0.0.1:${server.address().port}`;
  try {
    const health=await fetch(url+'/health');assert.equal(health.status,200);assert.equal(requests.length,0);
    const response=await fetch(url+'/v1/metadata',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(input)});
    assert.equal(response.status,200);assert.equal((await response.json()).metadata.bookID,42);
    const bad=await fetch(url+'/v1/metadata',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"query":"anything"}'});
    assert.equal(bad.status,400);
  } finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});
