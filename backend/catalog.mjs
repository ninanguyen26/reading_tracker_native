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
const fields = `id title description release_year rating ratings_count cached_tags contributions { author { name } } book_series { position series { name } }`;
function publicationYear(value) {
  return Number.isInteger(value) && value >= 1 && value <= 9999 ? value : null;
}
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
  const editionID = Number.isInteger(edition?.id) && edition.id > 0 ? edition.id : null;
  const editionYear = publicationYear(edition?.release_year);
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
    exactEdition: editionID && Number.isInteger(edition.pages) && edition.pages > 0
      ? {id: editionID, isbn: matchedISBN, pages: edition.pages} : null,
    publicationYears: {
      releaseYear: publicationYear(record.release_year),
      exactEdition: editionID && editionYear ? {id: editionID, isbn: matchedISBN, year: editionYear} : null
    }
  };
}

const previewCount = 6;
const seriesPageSize = 24;
const seriesBatchSize = 100;
const authorRole = '_or:[{contribution:{_is_null:true}},{contribution:{_eq:"Author"}},{contribution:{_eq:"author"}}]';
const cardFields = 'id title description cached_image default_cover_edition { isbn_13 isbn_10 } ' +
  'contributions(where:{' + authorRole + '},limit:4) { author { name } }';
const seriesOrder = 'order_by:[{position:asc_nulls_last},{book_id:asc},{id:asc}]';
const editionLanguage = 'language { code2 code3 }';
const seriesFields = `position book {
  ${cardFields} canonical_id users_count
  default_cover_edition { ${editionLanguage} }
  preferred: editions(where:{language:{_or:[{code2:{_eq:$language}},{code3:{_eq:$language}}]},
    canonical_id:{_is_null:true}},order_by:[{users_count:desc_nulls_last},{id:asc}],limit:1) {
    title description isbn_13 isbn_10 cached_image
  }
}`;

function coverURL(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && url.hostname.endsWith('.hardcover.app') &&
      !url.username && !url.password && !url.port ? url.href : null;
  } catch { return null; }
}

function discoveryCard(book, preferred) {
  if (!Number.isInteger(book?.id) || book.id <= 0 || typeof book.title !== 'string' || !book.title.trim()) return null;
  const edition = preferred ?? book.default_cover_edition;
  const title = preferred?.title?.trim() || book.title;
  const description = preferred?.description?.trim() || book.description;
  return {
    id: book.id,
    title: title.slice(0,500),
    author: [...new Set((book.contributions ?? []).map(item => item.author?.name).filter(Boolean))]
      .join(', ').slice(0,300),
    description: typeof description === 'string' ? description.slice(0,4000) : null,
    coverURL: coverURL(preferred ? preferred.cached_image?.url : book.cached_image?.url),
    isbns: [...new Set([isbn(edition?.isbn_13), isbn(edition?.isbn_10)].filter(Boolean))]
  };
}

function seriesLanguage(value) {
  return typeof value === 'string' && /^[a-z]{2,3}$/.test(value) && !['und','mul','zxx'].includes(value)
    ? value : '';
}

function seriesEntries(members, currentID, language) {
  const works = new Map();
  const positions = new Map();
  const rank = entry => [entry.book.id === currentID, entry.languageRank,
    entry.canonicalID === entry.book.id, entry.usersCount];
  function keepPreferred(groups, key, entry) {
    const previous = groups.get(key);
    if (!previous) {
      groups.set(key, entry);
      return;
    }
    const previousRank = rank(previous);
    const nextRank = rank(entry);
    const difference = nextRank.findIndex((value, index) => value !== previousRank[index]);
    if (difference !== -1 && nextRank[difference] > previousRank[difference]) {
      groups.set(key, {...entry, position: previous.position});
    }
  }

  for (const {book, position} of members) {
    const defaultLanguage = book?.default_cover_edition?.language;
    const defaultMatches = Boolean(language && [defaultLanguage?.code2, defaultLanguage?.code3].includes(language));
    const preferred = language && !defaultMatches ? book?.preferred?.[0] : null;
    const card = discoveryCard(book, preferred);
    if (!card) continue;
    card.language = (preferred ? language : seriesLanguage(defaultLanguage?.code2) || seriesLanguage(defaultLanguage?.code3)) || null;
    const canonicalID = validCatalogID(book.canonical_id) ? book.canonical_id : book.id;
    keepPreferred(works, canonicalID, {book:card, canonicalID, position:Number.isFinite(position) ? position : null,
      languageRank:defaultMatches ? 2 : preferred ? 1 : 0, usersCount:book.users_count ?? 0});
  }

  // Hardcover also lists unlinked translations at the same numbered position.
  // Unnumbered entries have no such slot and stay separate by work ID.
  for (const entry of works.values()) {
    const key = entry.position ?? `work:${entry.canonicalID}`;
    keepPreferred(positions, key, entry);
  }
  return [...positions.values()].map(({book, position}) => ({book, position}));
}

function validCatalogID(id) {
  return Number.isInteger(id) && id > 0 && id <= 2147483647;
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
    return this.cached(key, () => this.match(value));
  }
  async cached(key, load) {
    const cached = this.cache.get(key);
    if (cached && cached.until > this.now()) return cached.value;
    if (this.inflight.has(key)) return this.inflight.get(key);
    if (!this.token) throw new CatalogError(503,'catalog_not_configured');
    if (this.inflight.size >= 12) throw new CatalogError(503,'catalog_busy',15);
    const job = load().then(result => {
      if (this.cache.size >= 1000) this.cache.delete(this.cache.keys().next().value);
      this.cache.set(key,{value: result, until: this.now() + (result ? 86400000 : 3600000)});
      return result;
    }).finally(() => this.inflight.delete(key));
    this.inflight.set(key,job);
    return job;
  }
  async discovery(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input)) throw new CatalogError(400,'invalid_discovery');
    const {language: requestedLanguage, ...lookup} = input;
    const language = seriesLanguage(requestedLanguage);
    if (requestedLanguage != null && !language) throw new CatalogError(400,'invalid_discovery');
    let bookID;
    if (Object.hasOwn(lookup, 'bookID')) {
      if (Object.keys(lookup).length !== 1 || !validCatalogID(lookup.bookID)) throw new CatalogError(400,'invalid_discovery');
      bookID = lookup.bookID;
    } else {
      bookID = (await this.lookup(lookup))?.bookID;
    }
    return bookID ? this.cached(`discovery:${bookID}:${language}`, () => this.relatedBooks(bookID, language)) : null;
  }
  async relatedBooks(bookID, language) {
    const result = await this.query(`query Discovery($id:Int!,$language:String!) {
      books(where:{id:{_eq:$id}},limit:1) {
        id
        default_cover_edition { ${editionLanguage} }
        contributions(where:{${authorRole}},order_by:{id:asc},limit:5) { author_id }
        book_series(order_by:[{featured:desc},{id:asc}],limit:5) {
          position
          series {
            id name
            book_series(${seriesOrder},limit:${seriesBatchSize}) { ${seriesFields} }
          }
        }
      }
    }`, {id:bookID, language});
    const current = result.books?.[0];
    if (!current) return null;

    const seenSeries = new Set();
    const series = [];
    const currentLanguage = current.default_cover_edition?.language;
    const preferredLanguage = language || seriesLanguage(currentLanguage?.code2) || seriesLanguage(currentLanguage?.code3);
    for (const {series: group, position} of current.book_series ?? []) {
      if (!validCatalogID(group?.id) || typeof group.name !== 'string' || !group.name.trim() ||
          seenSeries.has(group.id)) continue;
      seenSeries.add(group.id);
      const {members} = await this.loadSeriesMembers(group.id, bookID, language, group.book_series ?? []);
      const entries = seriesEntries(members, bookID, preferredLanguage);
      series.push({
        id: group.id,
        name: group.name.slice(0,300),
        currentPosition: Number.isFinite(position) ? position : null,
        entries: entries.slice(0,previewCount),
        nextOffset: entries.length > previewCount ? previewCount : null
      });
    }
    const authors = [...new Set((current.contributions ?? []).map(item => item.author_id).filter(validCatalogID))];
    let authorBooks = [];
    if (authors.length) {
      const result = await this.query(`query AuthorBooks($id:Int!,$authors:[Int!]!,$series:[Int!]!) {
        books(where:{
          id:{_neq:$id},canonical_id:{_is_null:true},
          contributions:{author_id:{_in:$authors},${authorRole}},
          _not:{book_series:{series_id:{_in:$series}}}
        },order_by:[{users_count:desc_nulls_last},{id:asc}],limit:${previewCount}) {
          ${cardFields}
        }
      }`, {id:bookID, authors, series:[...seenSeries]});
      authorBooks = (result.books ?? []).map(discoveryCard).filter(Boolean);
    }
    return {bookID:current.id, series, authorBooks};
  }
  async seriesPage(input) {
    if (!input || typeof input !== 'object' || Array.isArray(input) ||
        Object.keys(input).some(key => !['seriesID','offset','bookID','language'].includes(key)) ||
        !validCatalogID(input.seriesID) || !Number.isInteger(input.offset) ||
        input.offset < 0 || input.offset > 10000 ||
        (input.bookID != null && !validCatalogID(input.bookID)) ||
        (input.language != null && !seriesLanguage(input.language))) throw new CatalogError(400,'invalid_series_page');
    const {seriesID, offset, bookID = null} = input;
    const language = seriesLanguage(input.language);
    const entries = await this.cached(`series:${seriesID}:${bookID}:${language}`, async () => {
      const {members, currentLanguage} = await this.loadSeriesMembers(seriesID, bookID, language);
      const preferredLanguage = language || seriesLanguage(currentLanguage?.code2) || seriesLanguage(currentLanguage?.code3);
      return seriesEntries(members, bookID, preferredLanguage);
    });
    const end = offset + seriesPageSize;
    return {entries:entries.slice(offset,end), nextOffset:entries.length > end && end <= 10000 ? end : null};
  }
  async loadSeriesMembers(seriesID, bookID, language, initial) {
    const members = [...(initial ?? [])];
    let currentLanguage;
    let batch = initial;
    while (!batch || batch.length === seriesBatchSize) {
      const offset = members.length;
      const result = await this.query(`query SeriesPage($id:Int!,$offset:Int!,$language:String!,$currentID:Int!) {
        books(where:{id:{_eq:$currentID}},limit:1) { default_cover_edition { ${editionLanguage} } }
        series(where:{id:{_eq:$id}},limit:1) {
          book_series(${seriesOrder},offset:$offset,limit:${seriesBatchSize}) { ${seriesFields} }
        }
      }`, {id:seriesID, offset, language, currentID:!initial && offset === 0 && !language ? bookID ?? 0 : 0});
      batch = result.series?.[0]?.book_series ?? [];
      currentLanguage ??= result.books?.[0]?.default_cover_edition?.language;
      members.push(...batch);
    }
    return {members, currentLanguage};
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
          id isbn_10 isbn_13 pages release_year book { ${fields} }
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
