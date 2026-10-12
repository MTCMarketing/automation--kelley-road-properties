#!/usr/bin/env bash
#
# Reads the CMS and writes content.json.
#
# The CMS keeps two documents — the property catalogue and the application
# form — and the website needs both at build time. This puts them in one file
# with one version number, so the website has a single thing to compare
# against and a single thing to fetch.
#
# Read with the PUBLISHABLE key over the ordinary public endpoint. No secret
# key is involved and none should be: this runs in a public repository, and a
# secret in a public build log is a secret that has leaked.

set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL is not set — add it under Settings, Variables}"
: "${SUPABASE_KEY:?SUPABASE_PUBLISHABLE_KEY is not set — add it under Settings, Variables}"

REST="${SUPABASE_URL}/rest/v1/cms_documents"

fetch() {
  curl -fsS \
    -H "apikey: ${SUPABASE_KEY}" \
    -H "Accept: application/json" \
    "${REST}?path=eq.$(printf '%s' "$1" | sed 's|/|%2F|g')&select=content,updated_at"
}

echo "Reading the CMS..."

properties=$(fetch "properties/properties.json")
applications=$(fetch "applications/applications.json")

# ── the version ───────────────────────────────────────────
# The newest updated_at across both documents, which the database maintains
# itself. Not a counter we increment: a counter would drift the first time a
# run failed halfway, and this cannot.
node --input-type=module -e '
import fs from "node:fs";

const read = (raw) => {
  const rows = JSON.parse(raw);
  return rows[0] ?? null;
};

const properties = read(process.argv[1]);
const applications = read(process.argv[2]);

if (!properties && !applications) {
  console.error("The CMS returned nothing at all. Refusing to publish an empty site.");
  process.exit(1);
}

const stamps = [properties?.updated_at, applications?.updated_at].filter(Boolean);
const version = stamps.sort().at(-1);

const content = {
  /* What this is, for anybody who opens the file in the website repository. */
  note: "Generated from the CMS by automation--kelley-road-properties. Do not edit by hand.",
  version,
  generatedAt: new Date().toISOString(),
  properties: properties?.content?.properties ?? null,
  applications: applications?.content ?? null,
};

fs.writeFileSync("content.json", JSON.stringify(content, null, 2) + "\n");

const count = content.properties?.length ?? 0;
console.log(`content.json written: ${count} properties, version ${version}`);

fs.appendFileSync(process.env.GITHUB_OUTPUT, `version=${version}\n`);
' "$properties" "$applications"

# ── has it actually changed? ──────────────────────────────
# Compared against what the website already has, so a dispatch that arrives
# after somebody saved and undid a change does not spend five minutes of
# build time republishing an identical file.
echo "Comparing with the website..."

live=$(curl -fsS \
  -H "Authorization: Bearer ${AUTOMATION_CONTENT_JSON:-${GITHUB_TOKEN:-}}" \
  -H "Accept: application/vnd.github.raw" \
  "https://api.github.com/repos/MTCMarketing/source--kelley-roads-property-management/contents/content.json" \
  2>/dev/null || echo "")

if [ -n "$live" ] && printf '%s' "$live" | node -e '
  let body = "";
  process.stdin.on("data", (c) => (body += c));
  process.stdin.on("end", () => {
    const fs = require("fs");
    try {
      const live = JSON.parse(body);
      const next = JSON.parse(fs.readFileSync("content.json", "utf8"));
      /* generatedAt changes on every run and means nothing; the version is
         the database own timestamp and is what actually matters. */
      process.exit(live.version === next.version ? 0 : 1);
    } catch {
      process.exit(1);
    }
  });
'; then
  echo "changed=false" >> "$GITHUB_OUTPUT"
  echo "Unchanged."
else
  echo "changed=true" >> "$GITHUB_OUTPUT"
  echo "Changed — will publish."
fi
