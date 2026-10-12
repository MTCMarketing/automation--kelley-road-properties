# automation — Kelley Road Properties

Keeps the website's content in step with the CMS.

The website is a set of static pages. That is what makes it fast and what
makes it indexable — a search engine reads the listings out of the HTML
without running any JavaScript. The cost is that the pages only change when
the site is rebuilt. This repository is what rebuilds it.

## Why this is a separate, public repository

**Public** because Actions minutes are free on public repositories. The
website repository is private, and private repositories get 2,000 minutes a
month. A build takes about five minutes, so that allowance is roughly 400
builds — thirteen a day. A build on every CMS save would exhaust it in under
a week.

**Separate** because the website should not know where its content comes
from. It builds from a `content.json` committed to its own repository. If
Supabase is replaced later, this repository changes and the website does not.

Nothing in here is secret. It references secrets by name and never prints
them, and the content it moves is the website's own public listings — the
same words and photographs any visitor can already read. Applicant
submissions are not touched and are not readable with the key used here.

## What happens

```
somebody saves in the CMS
   │
   ├─ a database trigger calls sync.yml, which is the only thing here that
   │  knows Supabase exists — it reads the CMS and writes content.json into
   │  .github/content/
   │
   ├─ that push starts .github/workflows/content.yml
   │     (a path filter — a commit anywhere else does not start it at all)
   │
   ├─ the file is checked: valid JSON, has a version, lists properties
   │
   └─ forwarded to the website, which publishes on push
```

The database writes a file to a repository and knows nothing else. It has
never heard of the website, what builds it, or where it is deployed.
Replacing Supabase later means teaching something else to write the same
file into the same folder.

Meanwhile the website itself re-reads the CMS in the visitor's browser, so a
change is visible within seconds. **That is for people; this is for search
engines.** Both are needed, and neither replaces the other.

## Configure

Settings → Secrets and variables → Actions.

**Variables** — read by `sync.yml`, which is the one workflow that talks to
the database. Neither is secret; both already appear in the website's own
page source.

| name | value |
|---|---|
| `SUPABASE_URL` | `https://ckfedtlwvbspubbauqvn.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | the `sb_publishable_…` key |
| `SETTLE_SECONDS` | optional, defaults to `90` |

**Secrets:**

| name | what it needs |
|---|---|
| `AUTOMATION_CONTENT_JSON` | a token with **contents: write** on `source--kelley-roads-property-management` |

That token must never be committed here. This repository is public; its
secrets are not, and are not exposed to pull requests from forks.

## Triggering it

The database calls `sync.yml` with a `cms-changed` dispatch. That is the
whole interface between Supabase and everything else:

```sql
select net.http_post(
  url     := 'https://api.github.com/repos/MTCMarketing/automation--kelley-road-properties/dispatches',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || current_setting('app.github_token'),
    'Accept',        'application/vnd.github+json',
    'User-Agent',    'kelley-road-cms',
    'Content-Type',  'application/json'
  ),
  body    := jsonb_build_object('event_type', 'cms-changed')
);
```

Writing `content.json` into `.github/content/` by hand works too, and skips
the database entirely — useful for replaying a publish or testing the second
half on its own.

By hand: Actions → content → Run workflow, which republishes whatever is
currently in the folder.

**Repeated saves do not mean repeated builds.** Each new commit cancels an
in-flight run, so editing a property through five wizard steps publishes
once, with the last version, rather than five times.

## When it goes wrong

**Nothing ran.** The workflow only starts when something under
`.github/content/` changes. A commit elsewhere in this repository will not
start it, by design.

**It refused to publish.** The file that arrived was empty, was not valid
JSON, had no version, or listed no properties at all. The log says which.
Refusing is deliberate: the website rebuilds from whatever lands in it, and a
truncated write would otherwise take the listings off a live site.

**It published but the site did not rebuild.** The website publishes on a
marker in the commit message, matched anywhere in the message. If that marker
appears twice the deploy is refused, so it must never be written in prose —
this is the single most common way to break the chain.

**The website has old content.** Check that the database trigger is actually
committing — if nothing has arrived in `.github/content/` there is nothing to
forward, and the problem is upstream of this repository.
