#!/usr/bin/env bash
#
# Reads the CMS documents and writes .github/content/content.json.
#
# The only file in this repository that knows what a Supabase is. Everything
# downstream reads content.json and would not notice if this were rewritten
# to read something else entirely.
#
# Read with the PUBLISHABLE key over the ordinary public endpoint — the same
# request a visitor's browser makes. No secret key is involved and none
# should be: this runs in a public repository, and a secret in a public build
# log is a secret that has leaked.

set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL is empty. The workflow passes a default, so an empty value here means someone set the SUPABASE_URL variable to nothing.}"
: "${SUPABASE_KEY:?SUPABASE_KEY is empty. The workflow passes a default, so an empty value here means someone set the SUPABASE_PUBLISHABLE_KEY variable to nothing.}"

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

node --input-type=module -e '
import fs from "node:fs";

const row = (raw) => {
  const rows = JSON.parse(raw);
  return rows[0] ?? null;
};

const properties = row(process.argv[1]);
const applications = row(process.argv[2]);

if (!properties && !applications) {
  console.error(
    "The CMS returned nothing at all. Refusing to write an empty content.json — " +
    "publishing a site with no properties over a working one is the worst " +
    "available outcome."
  );
  process.exit(1);
}

/* The newest change across both documents, as the database recorded it.
   NOT a counter: a counter drifts the first time a run fails halfway, and
   nothing would ever notice. */
const version = [properties?.updated_at, applications?.updated_at]
  .filter(Boolean)
  .sort()
  .at(-1);

/* Nothing per-write belongs in here. The pipeline skips a rebuild when the
   version is unchanged, and a field that moves every time — a generated-at,
   a run id — defeats that and turns every save into a five-minute build.
   That has already happened once. */
const content = {
  note: "Written from the CMS by automation--kelley-road-properties. Do not edit by hand.",
  version,
  properties: properties?.content?.properties ?? null,
  applications: applications?.content ?? null,
};

fs.mkdirSync(".github/content", { recursive: true });
fs.writeFileSync(".github/content/content.json", JSON.stringify(content, null, 2) + "\n");

const count = content.properties?.length ?? 0;
console.log(`Read ${count} properties. Version ${version}.`);
' "$properties" "$applications"
