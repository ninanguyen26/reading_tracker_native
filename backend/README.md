# Metadata backend (Render Free)

Run `npm start`; run tests with `npm test` (Node 22). No package dependencies.

Set `HARDCOVER_TOKEN` as a secret environment variable in Render. Use an app-owned
Hardcover token limited to `read:catalog:data`. Never put a token in this repository,
mobile app, cron job, URL, or logs. `PORT` is supplied by Render.

- `GET /health`: minimal health response; never calls Hardcover.
- `POST /v1/metadata`: JSON with `isbn`, `title`, `author`; returns `{metadata: ...}`
  or `{metadata: null}` when there is no unique match. No user sign-in.
- `POST /v1/mood-books`: JSON with a supported lowercase `mood` and optional
  `offset`. Returns up to 48 canonical Hardcover books and the next offset.
  The app filters and ranks these results locally.
- `/v1/metadata` accepts only those identifiers and runs fixed catalog queries.
  Arbitrary GraphQL, user data access, and uploads are unsupported.

An exact ISBN match is required for pages. A unique exact title and author match
can supply description, series, genre tags, moods, and content warnings.
The iOS client also validates the returned edition ISBN before accepting its pages.

Matched results cache for 24 hours, misses for 1 hour, up to 1,000 entries. Duplicate
in-flight requests coalesce. The single process reserves a 50-query/minute and
4,500-query/UTC-day budget and spaces upstream calls 1.1 seconds apart. At most 12
lookups can be in flight; per-client requests are capped at 30/minute. Upstream 429s
trigger backoff. Errors are not cached as misses and never expose upstream bodies.

Cache, budgets and client limits are **in memory**, reset on Render restart/deploy,
and are not a durable guarantee of Hardcover's account-wide quota. Hardcover's own
limits still apply across restarts and any other uses of the same account. This
service is public and rate limited, not authenticated; stronger client attestation
can be added separately when needed. No permanent library or book files are stored.

Deploy the backend directory as a Render **Free Web Service**, build
`npm ci --omit=dev`, start `npm start`, health path `/health`. `render.yaml` describes
the same settings. Do not add a database or disk for this version.

Automatic deploys require `reading_tracker_native` in the Render GitHub App's
repository access. The service watches `main` with Auto-Deploy set to On Commit
and triggers a build for pushes that change files under `backend/`.

The deployed service is `https://reading-tracker-metadata.onrender.com`.
Configure cron-job.org to GET `https://reading-tracker-metadata.onrender.com/health` every 10 minutes
with response-body storage disabled. No Hardcover token is needed in the job.
The cron keeps activity below Render's 15-minute idle interval but cannot prevent
platform restarts, quota suspension or cold starts. The mobile lookup retries one
transient failure in the background; imports remain usable immediately.
