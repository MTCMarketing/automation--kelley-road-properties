# content

What the CMS writes. Everything here is an input, not a build artifact.

A change in Supabase fires a database trigger, which commits `content.json`
into this folder using a token with write access to this repository. That
commit is a push, and that push is what starts `.github/workflows/content.yml`
— which checks the file and forwards it to the website, where it is built
into the static pages a search engine reads.

The workflow is triggered by a path filter on this folder, so a commit
anywhere else in this repository does not start it at all.

## content.json

```json
{
  "version": "2026-10-12T00:45:43.610133+00:00",
  "properties": [ ... ],
  "applications": { ... }
}
```

**Do not stamp anything on this file that changes per write** — a "generated
at" time, a run id, a nonce. The pipeline skips a rebuild when the version is
unchanged, and a field that moves every time defeats that: every write
becomes a five-minute build, which is the cost this whole arrangement exists
to avoid.

`version` is the database's own `updated_at`, not a counter. A counter would
drift the first time a run failed halfway through; a timestamp the database
maintains cannot. The website compares it against the version it was built
with to decide whether what it already holds is stale.

Nothing private belongs here. This repository is public, and these are the
listings and the application questions already published on the website.
Applicant submissions are a different table, readable only by signed-in
staff, and must never be written into this folder.
