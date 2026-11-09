import { createHash } from 'node:crypto';

export class CatalogError extends Error {
  constructor(status, code, retryAfter = 60) { super(code); Object.assign(this, {status, code, retryAfter}); }
}
const normalize = value => String(value ?? '').normalize('NFD').replace(/\p{Diacritic}/gu, '')
  .toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim();
export function isbn(value) {
  const s = String(value ?? '').toUpperCase().replace(/^URN:ISBN:|^ISBN[: ]*/, '').replace(/[-\s]/g, '');
  if (/^\d{13}$/.test(s) && [...s].reduce((n,c,i) => n + Number(c)*(i%2 ? 3 : 1),0)%10 === 0) return s;
  if (/^\d{9}[\dX]$/.test(s) && [...s].reduce((n,c,i) => n + (c === 'X' ? 10 : Number(c))*(10-i),0)%11 === 0) return s;
  return null;
}
export function validateInput(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input) ||
      Object.keys(input).some(k => !['isbn','title','author'].includes(k))) throw new CatalogError(400,'invalid_lookup');
  const values = {};
  for (const [key, max] of [['isbn',40],['title',500],['author',300]]) {
    if (input[key] != null && (typeof input[key] !== 'string' || input[key].length > max)) throw new CatalogError(400,'invalid_lookup');
    values[key] = (input[key] ?? '').trim();
  }
  const identifier = isbn(values.isbn);
  if (values.isbn && !identifier) throw new CatalogError(400,'invalid_isbn');
  if (!identifier && (!normalize(values.title) || !normalize(values.author) || values.author === 'Unknown author'))
    throw new CatalogError(400,'insufficient_identifiers');
  return {isbn: identifier, title: values.title, author: values.author};
}
const fields = `id title description rating ratings_count cached_tags contributions { author { name } } book_series { position series { name } }`;
function tagNames(tags) {
  return Array.isArray(tags) ? [...new Set(tags.map(t => typeof t === 'string' ? t : t?.tag ?? t?.name)
    .filter(t => typeof t === 'string' && t.trim()).map(t => t.trim().slice(0,100)))].slice(0,30) : [];
}
function warningTags(categories) {
  return Object.entries(categories ?? {}).flatMap(([category, tags]) => {
    const name = normalize(category).replaceAll(' ', '');
    return (name === 'contentwarning' || name === 'contentwarnings') && Array.isArray(tags) ? tags : [];
  });
}
function metadata(record, edition = null, matchedISBN = null) {
  if (!Number.isInteger(record?.id) || record.id <= 0) throw new CatalogError(502,'invalid_catalog_response');
  const ratingsCount = Number.isSafeInteger(record.ratings_count) && record.ratings_count >= 0
    ? record.ratings_count : null;
  const rating = typeof record.rating === 'string' && record.rating.trim() ? Number(record.rating) : record.rating;
  return {
    bookID: record.id,
    description: typeof record.description === 'string' ? record.description.slice(0,30000) : null,
    series: (record.book_series ?? []).slice(0,20).filter(s => typeof s.series?.name === 'string')
      .map(s => ({name: s.series.name.slice(0,300), position: Number.isFinite(s.position) ? s.position : null})),
    genres: tagNames(record.cached_tags?.Genre),
    moods: tagNames(record.cached_tags?.Mood),
    contentWarnings: tagNames(warningTags(record.cached_tags)),
    rating: ratingsCount > 0 && Number.isFinite(rating) && rating >= 0 && rating <= 5 ? rating : null,
    ratingsCount,
    exactEdition: edition && Number.isInteger(edition.id) && edition.id > 0 && Number.isInteger(edition.pages) && edition.pages > 0
      ? {id: edition.id, isbn: matchedISBN, pages: edition.pages} : null
  };
}

/// One Render process, with bounded memory and no persisted user/library data.
export class Catalog {
  constructor({token, fetcher = fetch, now = Date.now, dailyLimit = 4500, minuteLimit = 50, interval = 1100} = {}) {
    Object.assign(this, {token, fetcher, now, dailyLimit, minuteLimit, interval});
    this.cache = new Map(); this.inflight = new Map(); this.clients = new Map();
    this.day = ''; this.used = 0; this.minute = []; this.next = 0; this.blockedUntil = 0;
  }
  limitClient(address) {
    const time = this.now();
    // Never retain raw client IPs, and bound this map even under many distinct callers.
    const key = createHash('sha256').update(address ?? 'unknown').digest('hex');
    let client = this.clients.get(key);
    if (!client || client.until <= time) client = {used: 0, until: time + 60000};
    if (client.used >= 30) throw new CatalogError(429,'client_rate_limit',Math.ceil((client.until-time)/1000));
    client.used += 1;
    if (this.clients.size >= 2000) {
      for (const [k,v] of this.clients) if (v.until <= time) this.clients.delete(k);
      if (this.clients.size >= 2000) this.clients.delete(this.clients.keys().next().value);
    }
    this.clients.set(key,client);
  }
  async lookup(input) {
    const value = validateInput(input);
    // Include fallback identifiers: the same missing ISBN can accompany different title/author pairs.
    const key = createHash('sha256').update(JSON.stringify(value)).digest('hex');
    const cached = this.cache.get(key);
    if (cached && cached.until > this.now()) return cached.value;
    if (this.inflight.has(key)) return this.inflight.get(key);
    if (!this.token) throw new CatalogError(503,'catalog_not_configured');
    if (this.inflight.size >= 12) throw new CatalogError(503,'catalog_busy',15);
    const job = this.match(value).then(result => {
      if (this.cache.size >= 1000) this.cache.delete(this.cache.keys().next().value);
      this.cache.set(key,{value: result, until: this.now() + (result ? 86400000 : 3600000)});
      return result;
    }).finally(() => this.inflight.delete(key));
    this.inflight.set(key,job);
    return job;
  }
  async query(query, variables) {
    const time = this.now();
    if (time < this.blockedUntil) throw new CatalogError(429,'catalog_rate_limit',Math.ceil((this.blockedUntil-time)/1000));
    const day = new Date(time).toISOString().slice(0,10);
    if (this.day !== day) { this.day = day; this.used = 0; }
    this.minute = this.minute.filter(t => t > time-60000);
    if (this.used >= this.dailyLimit) throw new CatalogError(429,'catalog_daily_limit',3600);
    if (this.minute.length >= this.minuteLimit) throw new CatalogError(429,'catalog_rate_limit',60);
    // Reserve before awaiting, so simultaneous requests cannot exceed the process budget.
    this.used += 1; this.minute.push(time);
    const slot = Math.max(time,this.next); this.next = slot+this.interval;
    if (slot > time) await new Promise(resolve => setTimeout(resolve,slot-time));
    if (this.now() < this.blockedUntil) throw new CatalogError(429,'catalog_rate_limit',60);
    let response;
    try {
      response = await this.fetcher('https://api.hardcover.app/v1/graphql', {
        method:'POST', signal:AbortSignal.timeout(20000),
        headers:{'Content-Type':'application/json','Authorization':`Bearer ${this.token.replace(/^Bearer\s+/i,'')}`,
          'User-Agent':'ReadingTrackerMetadata/1.0 (github.com/ninanguyen26/reading_tracker_native)'},
        body:JSON.stringify({query,variables})
      });
    } catch { throw new CatalogError(503,'catalog_unavailable'); }
    if (response.status === 429) {
      const delay = Math.min(86400,Math.max(60,Number(response.headers.get('retry-after')) || 60));
      this.blockedUntil = this.now()+delay*1000;
      throw new CatalogError(429,'catalog_rate_limit',delay);
    }
    if (response.status === 401 || response.status === 403) {
      this.blockedUntil = this.now()+900000;
      throw new CatalogError(503,'catalog_authentication');
    }
    if (!response.ok) throw new CatalogError(503,'catalog_unavailable');
    let envelope;
    try { envelope = await response.json(); } catch { throw new CatalogError(502,'invalid_catalog_response'); }
    if (envelope.errors?.length || !envelope.data) throw new CatalogError(502,'catalog_query_failed');
    return envelope.data;
  }
  async match(value) {
    if (value.isbn) {
      const result = await this.query(`query Edition($isbn:String!) {
        editions(where:{_or:[{isbn_10:{_eq:$isbn}},{isbn_13:{_eq:$isbn}}]},limit:2) {
          id isbn_10 isbn_13 pages book { ${fields} }
        }
      }`,{isbn:value.isbn});
      if (!Array.isArray(result.editions)) throw new CatalogError(502,'invalid_catalog_response');
      const matches = result.editions.filter(e => isbn(e.isbn_10) === value.isbn || isbn(e.isbn_13) === value.isbn);
      if (matches.length > 1) return null;
      if (matches.length === 1) return metadata(matches[0].book,matches[0],value.isbn);
    }
    if (!value.title || !value.author || value.author === 'Unknown author') return null;
    const result = await this.query(`query Book($title:String!) {
      books(where:{title:{_eq:$title}},limit:11) { ${fields} }
    }`,{title:value.title});
    if (!Array.isArray(result.books)) throw new CatalogError(502,'invalid_catalog_response');
    if (result.books.length >= 11) return null;
    const authors = value.author.split(',').map(normalize);
    const matches = result.books.filter(b => normalize(b.title) === normalize(value.title) &&
      b.contributions?.some(c => authors.includes(normalize(c.author?.name))));
    return matches.length === 1 ? metadata(matches[0]) : null;
  }
}
