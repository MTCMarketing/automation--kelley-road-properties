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
   ├─ a database trigger calls this repository
   │
   ├─ this waits a couple of minutes, so five saves are one build
   │
   ├─ reads the CMS, writes content.json, and compares it with the website's
   │  copy — if nothing actually changed, it stops here
   │
   └─ commits content.json to the website, which publishes on push
```

Meanwhile the website itself re-reads the CMS in the visitor's browser, so a
change is visible within seconds. **That is for people; this is for search
engines.** Both are needed, and neither replaces the other.

## Configure

Settings → Secrets and variables → Actions.

**Variables** (not secret — these already appear in the website's page source):

| name | value |
|---|---|
| `SUPABASE_URL` | `https://ckfedtlwvbspubbauqvn.supabase.co` |
| `SUPABASE_PUBLISHABLE_KEY` | the `sb_publishable_…` key |
| `DEBOUNCE_SECONDS` | optional, defaults to `120` |

**Secrets:**

| name | what it needs |
|---|---|
| `AUTOMATION_CONTENT_JSON` | a token with **contents: write** on `source--kelley-roads-property-management` |

That token must never be committed here. This repository is public; its
secrets are not, and are not exposed to pull requests from forks.

## Triggering it

From the database, on change:

```sql
select net.http_post(
  url     := 'https://api.github.com/repos/MTCMarketing/automation--kelley-road-properties/dispatches',
  headers := jsonb_build_object(
    'Authorization', 'Bearer ' || current_setting('app.automation_token'),
    'Accept',        'application/vnd.github+json',
    'User-Agent',    'kelley-road-cms'
  ),
  body    := jsonb_build_object('event_type', 'content-changed')
);
```

Or by hand: Actions → process → Run workflow. Use **force** to republish
content that has not changed, which is occasionally what you want after
changing something about the build itself.

## When it goes wrong

**It published nothing.** Expected when the CMS has not changed since the
last build — the log says so. Use *Run workflow* with **force** to override.

**It published but the site did not rebuild.** The website publishes on a
marker in the commit message, matched anywhere in the message. If that marker
appears twice the deploy is refused, so it must never be written in prose —
this is the single most common way to break the chain.

**It could not read the CMS.** Check `SUPABASE_URL` and the publishable key.
The script fails rather than writing an empty `content.json`: publishing a
site with no properties would be worse than publishing nothing.
