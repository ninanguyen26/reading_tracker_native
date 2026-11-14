import test from 'node:test';
import assert from 'node:assert/strict';
import {Catalog,validateInput} from './catalog.mjs';
import {createServer} from './server.mjs';
const book = {id:42,title:'Test Book',description:'A wizard explores an enchanted forest.',rating:'4.24',ratings_count:1283,
  contributions:[{author:{name:'Test Author'}}],book_series:[{position:2.5,series:{name:'Wizard Series'}}],
  cached_tags:{Genre:[{tag:'Fantasy'}],Mood:[{tag:'Dark'},{tag:'Dark'}],'Content Warning':[{tag:'Blood'}]}};
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
test('Discover pages the general catalog and taste matches without duplicate work IDs', async () => {
  const {catalog,requests} = setup(({variables:{offset}}) => result({
    general:Array.from({length:37},(_, index) => ({...book,id:100+offset+index})),
    tailored:[{...book,id:100+offset},{...book,id:900+offset}]
  }));
  const first = await catalog.discoverPicks({moods:['dark'],genres:['Fantasy']});
  assert.equal(first.candidates.length,37);
  assert.equal(first.nextOffset,36);
  assert.equal(first.candidates.at(-1).book.id,900);
  const next = await catalog.discoverPicks({moods:['dark'],genres:['Fantasy'],offset:first.nextOffset});
  assert.equal(next.candidates[0].book.id,136);
  assert.equal(requests[1].body.variables.offset,36);
  assert.ok(requests[0].body.variables.taste._or.some(filter => filter.cached_tags._contains.Genre));
  await assert.rejects(() => catalog.discoverPicks({moods:['%']}),{status:400});
});
test('mood catalog pages canonical Hardcover works and verifies mood tags before returning cards', async () => {
  const matching = {...book,cached_tags:{Genre:['Fantasy'],Mood:[{tag:'Funny'}]}};
  const {catalog,requests} = setup(() => result({books:[matching,book,
    ...Array.from({length:47},(_, index) => ({...matching,id:100+index}))]}));
  const page = await catalog.moodBooks({mood:'funny'});
  assert.equal(page.nextOffset,48);
  assert.equal(page.candidates.length,47);
  assert.deepEqual(page.candidates[0].moods,['Funny']);
  assert.equal(page.candidates[0].book.description,null);
  assert.deepEqual(requests[0].body.variables.filter.taggable_counts.tag,
    {tag:{_ilike:'funny'},tag_category:{category:{_ilike:'Mood'}}});
  assert.equal(requests[0].body.variables.offset,0);
  await catalog.moodBooks({mood:'funny'});
  assert.equal(requests.length,1);
  await assert.rejects(() => catalog.moodBooks({mood:'%'}),{status:400});
  await assert.rejects(() => catalog.moodBooks({mood:'funny',offset:1}),{status:400});
});
test('a forbidden mood relationship falls back to cached tags without blocking book lookups', async () => {
  const {catalog,requests} = setup((_, attempt) => attempt === 1 ? new Response(null,{status:403}) : result({books:[book]}));
  assert.equal((await catalog.moodBooks({mood:'dark'})).candidates[0].book.id,42);
  assert.deepEqual(requests[1].body.variables.filter._or[0],{cached_tags:{_contains:{Mood:[{tag:'dark'}]}}});
  assert.equal((await catalog.lookup(input)).bookID,42);
});
test('lookup and preview return the full catalog description', async () => {
  const description = 'A long synopsis. '.repeat(2100) + 'The final sentence.';
  const {catalog, requests} = setup(() => result({books: [{...book, description}]}));
  assert.equal((await catalog.lookup(input)).description, description);
  assert.equal((await catalog.preview({bookID: book.id})).description, description);
  assert.match(requests[1].body.query, /\bid description\b/);
});
test('exact ISBN supplies edition pages and separate tag categories; credentials go only upstream',async()=>{
  const {catalog,requests}=setup(()=>result({editions:[{id:11,isbn_13:'9780140328721',pages:320,book}]}));
  const data=await catalog.lookup({...input,isbn:'9780140328721'});
  assert.equal(data.exactEdition.pages,320);assert.equal(data.exactEdition.isbn,'9780140328721');
  assert.equal(data.series[0].position,2.5);assert.deepEqual(data.genres,['Fantasy']);
  assert.deepEqual(data.moods,['Dark']);assert.deepEqual(data.contentWarnings,['Blood']);
  assert.equal(data.rating,4.24);assert.equal(data.ratingsCount,1283);
  assert.equal(requests[0].init.headers.Authorization,'Bearer test-only-credential');
  assert.ok(!JSON.stringify(data).includes('test-only-credential'));
});
test('zero ratings do not produce an average',async()=>{
  const {catalog}=setup(()=>result({books:[{...book,rating:0,ratings_count:0}]}));
  const data=await catalog.lookup(input);
  assert.equal(data.rating,null);assert.equal(data.ratingsCount,0);
});
test('lookup and preview remove array fragments from Hardcover mood tags', async () => {
  const cached_tags = {Mood: [{tag: 'mysterious'}, {tag: '"mysterious"]'}, {tag: '["reflective"'}]};
  const {catalog} = setup(() => result({books: [{...book, cached_tags}]}));
  assert.deepEqual((await catalog.lookup(input)).moods, ['mysterious', 'reflective']);
  assert.deepEqual((await catalog.preview({bookID: book.id})).moods, ['mysterious', 'reflective']);
});
test('book and ISBN edition years are independent of each other and of page count',async()=>{
  const edition = {id:11,isbn_13:'9780140328721',release_year:2018,book:{...book,release_year:1980}};
  const {catalog,requests}=setup(body=>result(body.variables.isbn ? {editions:[edition]} : {books:[edition.book]}));
  const data=await catalog.lookup({...input,isbn:edition.isbn_13});
  assert.equal(data.exactEdition,null);
  assert.deepEqual(data.publicationYears,{releaseYear:1980,exactEdition:{id:11,isbn:edition.isbn_13,year:2018}});
  assert.deepEqual((await catalog.lookup(input)).publicationYears,{releaseYear:1980,exactEdition:null});
  assert.match(requests[0].body.query,/pages release_year book \{[^}]*release_year/);
  const missing=setup(()=>result({editions:[{...edition,book:{...book,release_year:0}}]}));
  assert.equal((await missing.catalog.lookup({...input,isbn:edition.isbn_13})).publicationYears.releaseYear,null);
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
test('discovery preserves series order and uses exact author and series IDs', async () => {
  const members = Array.from({length: 7}, (_, index) => ({
    position: index === 2 ? 2.5 : index + 1,
    book: {
      id: index === 2 ? 42 : 50 + index,
      title: `Series book ${index + 1}`,
      cached_image: {url: index ? 'https://assets.hardcover.app/cover.jpg' : 'https://untrusted.example/cover.jpg'},
      default_cover_edition: {isbn_13:'9780140328721'},
      contributions: [{author:{name:'Test Author'}}]
    }
  }));
  const standalone = {id:100,title:'Standalone',description:'A long synopsis. '.repeat(300) + 'The final sentence.'};
  const {catalog,requests} = setup(({query}) => {
    if (query.includes('query Book(')) return result({books:[book]});
    if (query.includes('query AuthorBooks')) return result({books:[standalone]});
    return result({books:[{id:42,contributions:[{author_id:17},{author_id:17}],
      book_series:[{position:2.5,series:{id:9,name:'Wizard Series',book_series:members}}]}]});
  });
  const discovery = await catalog.discovery(input);
  assert.equal(discovery.bookID,42);
  assert.equal(discovery.series[0].currentPosition,2.5);
  assert.deepEqual(discovery.series[0].entries.map(entry => entry.position),[1,2,2.5,4,5,6]);
  assert.equal(discovery.series[0].entries[2].book.id,42);
  assert.equal(discovery.series[0].entries[0].book.coverURL,null);
  assert.equal(discovery.series[0].entries[1].book.coverURL,'https://assets.hardcover.app/cover.jpg');
  assert.deepEqual(discovery.series[0].entries[0].book.isbns,['9780140328721']);
  assert.equal(discovery.series[0].nextOffset,6);
  assert.deepEqual(discovery.authorBooks.map(book => book.id),[100]);
  assert.equal(discovery.authorBooks[0].description,standalone.description);
  assert.deepEqual(requests[2].body.variables,{id:42,authors:[17],series:[9],bookLanguage:{},editionFilter:{canonical_id:{_is_null:true}}});
  assert.match(requests[2].body.query,/contributions:\{author_id:\{_in:\$authors\}/);
  assert.match(requests[2].body.query,/_not:\{book_series:\{series_id:\{_in:\$series\}/);
  assert.deepEqual(await catalog.discovery({bookID:42}),discovery);
  assert.equal(requests.length,3);
});
test('author discovery filters by the current language and recovers covers and ISBNs from matching editions', async () => {
  const english = {code2:'en',code3:'eng'};
  const french = {code2:'fr',code3:'fra'};
  const current = {id:42,default_cover_edition:{language:english},contributions:[{author_id:17}]};
  const {catalog,requests} = setup(({query}) => result(query.includes('AuthorBooks') ? {books:[
    {id:101,title:'No cover on the work',matching_editions:[{title:'English edition',language:english,isbn_13:'9780140328721'}],
      cover_editions:[{language:english,image:{url:'https://assets.hardcover.app/cover.jpg'},isbn_10:'0140328726'},
        {language:english,cached_image:{url:'https://assets.hardcover.app/alternate.jpg'}}]},
    {id:102,title:'French only',default_cover_edition:{language:french}},
    {id:103,title:'English without cover',default_cover_edition:{language:english}},
    {id:104,title:'French default title',cached_image:{url:'https://assets.hardcover.app/french.jpg'},
      default_cover_edition:{language:french},matching_editions:[{title:'Localized title',language:english,
        cached_image:{url:'https://assets.hardcover.app/english.jpg'}}]}
  ]} : {books:[current]}));

  const {authorBooks} = await catalog.discovery({bookID:42});
  assert.deepEqual(authorBooks.map(book => book.id),[101,103,104]);
  assert.ok(authorBooks.every(book => book.language === 'en'));
  assert.equal(authorBooks[0].coverURL,'https://assets.hardcover.app/cover.jpg');
  assert.deepEqual(authorBooks[0].alternateCoverURLs,['https://assets.hardcover.app/alternate.jpg']);
  assert.deepEqual(authorBooks[0].isbns,['9780140328721','0140328726']);
  assert.equal(authorBooks[1].coverURL,null);
  assert.equal(authorBooks[2].title,'Localized title');
  assert.equal(authorBooks[2].coverURL,'https://assets.hardcover.app/english.jpg');
  const language = {language:{_or:[{code2:{_eq:'en'}},{code3:{_eq:'en'}}]}};
  assert.deepEqual(requests[1].body.variables.bookLanguage,{_or:[{default_cover_edition:language},
    {editions:{...language,canonical_id:{_is_null:true}}}]});
  assert.match(requests[1].body.query,/_and:\[\$bookLanguage\]/);

  await catalog.discovery({bookID:42,language:'fr'});
  assert.deepEqual(requests[3].body.variables.editionFilter.language._or,[{code2:{_eq:'fr'}},{code3:{_eq:'fr'}}]);
});
test('series paging uses the same order and has no next page at the end', async () => {
  const {catalog,requests} = setup(({query}) => result(query.includes('SeriesPage')
    ? {series:[{book_series:Array.from({length:7},(_, i) => ({position:i+1,book:{id:i+1,title:`Book ${i+1}`}}))}]}
    : {books:[{id:42,book_series:[{series:{id:9,name:'Short Series',book_series:[{position:1,book}]}}]}]}));
  const discovery = await catalog.discovery({bookID:42});
  assert.equal(discovery.series[0].nextOffset,null);
  const page = await catalog.seriesPage({seriesID:9,offset:6});
  assert.equal(page.entries[0].book.id,7);
  assert.equal(page.nextOffset,null);
  assert.deepEqual(requests[1].body.variables,{id:9,offset:0,language:'',currentID:0});
  for (const request of requests) assert.match(request.body.query,/position:asc_nulls_last/);
  await assert.rejects(() => catalog.seriesPage({seriesID:9,offset:-1}), {status:400});
  await assert.rejects(() => catalog.discovery({bookID:42,query:'ignored'}), {status:400});
});
test('series chooses one version per work before preview and page limits, using the current language', async () => {
  const member = (position, id, title, code2, extra = {}) => ({position, book:{
    id, title, default_cover_edition:{language:{code2}}, ...extra
  }});
  const members = [
    member(1, 1, 'Book 1', 'en'),
    member(2, 2, 'Book 2', 'en'),
    member(3, 3, 'Current book', 'en'),
    member(3, 30, 'Translation of current book', 'uk', {canonical_id:3}),
    member(4, 4, 'Закон про шлюб', 'uk'),
    member(4, 40, 'The Marriage Act', 'en'),
    member(5, 5, 'Only available in French', 'fr'),
    member(6, 6, 'Book 6', 'en'),
    member(6, 60, 'Translation of book 6', 'uk', {canonical_id:6}),
    member(7, 7, 'English title', 'en'),
    member(7, 70, 'Ukrainian title', 'uk', {canonical_id:7}),
    member(8, 8, 'Default title', 'fr', {description:'Book-level synopsis', preferred:[{title:'English edition', isbn_13:'9780140328721',
      cached_image:{url:'https://assets.hardcover.app/english.jpg'}}]}),
    member(null, 80, 'Unnumbered translation of book 6', 'uk', {canonical_id:6}),
    member(null, 90, 'Unnumbered standalone entry', 'uk')
  ];
  const {catalog} = setup(({query,variables}) => {
    // Hardcover exposes the synopsis on books, and omits it from the editions schema.
    assert.match(query, /preferred: editions\([\s\S]*?limit:1\)\s*\{\s*title isbn_13 isbn_10 cached_image\s*\}/);
    // The preferred edition field only returns editions in the requested language.
    const records = variables.language === 'en' ? members : members.map(({position,book}) => ({position,book:{...book,preferred:[]}}));
    const current = {id:3, default_cover_edition:{language:{code2:'en'}}};
    return result(query.includes('SeriesPage')
      ? {books:[current], series:[{book_series:records}]}
      : {books:[{...current,book_series:[{position:3,series:{id:9,name:'Dark Future',book_series:records}}]}]});
  });
  const english = (await catalog.discovery({bookID:3,language:'en'})).series[0];
  assert.deepEqual(english.entries.map(entry => entry.book.id), [1,2,3,40,5,6]);
  assert.equal(english.nextOffset,6);
  const englishPage = await catalog.seriesPage({seriesID:9,offset:english.nextOffset,bookID:3,language:'en'});
  assert.deepEqual(englishPage.entries.map(entry => entry.book.id), [7,8,90]);
  assert.equal(englishPage.entries[1].book.title,'English edition');
  assert.equal(englishPage.entries[1].book.description,'Book-level synopsis');
  assert.equal(englishPage.entries[1].book.coverURL,'https://assets.hardcover.app/english.jpg');
  assert.equal(englishPage.nextOffset,null);
  const ukrainian = (await catalog.discovery({bookID:3,language:'uk'})).series[0];
  assert.deepEqual(ukrainian.entries.map(entry => entry.book.id), [1,2,3,4,5,60]);
  const ukrainianPage = await catalog.seriesPage({seriesID:9,offset:ukrainian.nextOffset,bookID:3,language:'uk'});
  assert.deepEqual(ukrainianPage.entries.map(entry => entry.book.id), [70,8,90]);
  const fallback = (await catalog.discovery({bookID:3})).series[0];
  assert.deepEqual(fallback.entries,english.entries);
  const fallbackPage = await catalog.seriesPage({seriesID:9,offset:fallback.nextOffset,bookID:3});
  assert.equal(fallbackPage.entries[1].book.title,'Default title');
});
test('translations across catalog batches do not consume another series slot', async () => {
  const members = Array.from({length:101},(_,i) => ({position:Math.min(i+1,100),book:{
    id:i+1,title:`Book ${i+1}`,default_cover_edition:{language:{code2:i === 99 ? 'uk' : 'en'}}
  }}));
  const {catalog,requests} = setup(({variables:{offset}}) => result({series:[{book_series:members.slice(offset,offset+100)}]}));
  const page = await catalog.seriesPage({seriesID:9,offset:99,language:'en'});
  assert.deepEqual(page.entries.map(entry => [entry.position,entry.book.id]),[[100,101]]);
  assert.equal(page.nextOffset,null);
  assert.deepEqual(requests.map(request => request.body.variables.offset),[0,100]);
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
    const oversized=await fetch(url+'/v1/metadata',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({...input,title:'x'.repeat(5000)})});
    assert.equal(oversized.status,413);
    const discovery=await fetch(url+'/v1/discovery',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"bookID":42}'});
    assert.equal(discovery.status,200);assert.equal((await discovery.json()).discovery.bookID,42);
    const preview=await fetch(url+'/v1/preview',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"bookID":42}'});
    assert.equal(preview.status,200);
    assert.deepEqual((await preview.json()).preview,{description:book.description,genres:['Fantasy'],moods:['Dark'],releaseYear:null,
      rating:4.24,ratingsCount:1283,language:null});
    const invalidPreview=await fetch(url+'/v1/preview',{method:'POST',headers:{'Content-Type':'application/json'},
      body:'{"bookID":42,"query":"arbitrary"}'});
    assert.equal(invalidPreview.status,400);
    const invalidPage=await fetch(url+'/v1/series',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"seriesID":5,"offset":-1}'});
    assert.equal(invalidPage.status,400);
    const mood=await fetch(url+'/v1/mood-books',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"mood":"dark"}'});
    assert.equal(mood.status,200);
    assert.equal((await mood.json()).candidates[0].book.id,42);
  } finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
});
