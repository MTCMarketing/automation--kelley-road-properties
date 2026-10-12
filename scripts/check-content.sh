#!/usr/bin/env bash
#
# Is the content that arrived actually publishable?
#
# Checked before anything is forwarded, because the website rebuilds from
# whatever lands in it. A truncated write, a half-finished upload or an empty
# document would otherwise take the listings off a live site, and the next
# anybody would hear of it is the client asking where their properties went.

set -euo pipefail

FILE=".github/content/content.json"

say() { echo "ok=false" >> "$GITHUB_OUTPUT"; echo "$1"; exit 1; }

[ -f "$FILE" ] || say "There is no $FILE. Nothing to publish."

# Valid JSON, with the shape the website expects, and not empty. Node rather
# than jq: it is already on every runner and needs no install step.
node --input-type=module -e '
import fs from "node:fs";

const raw = fs.readFileSync(".github/content/content.json", "utf8");

if (!raw.trim()) {
  console.error("The file is empty.");
  process.exit(1);
}

let content;
try {
  content = JSON.parse(raw);
} catch (error) {
  console.error("The file is not valid JSON: " + error.message);
  process.exit(1);
}

if (!content.version) {
  console.error("No version. The website uses it to tell new content from old.");
  process.exit(1);
}

const properties = content.properties;

if (properties !== null && !Array.isArray(properties)) {
  console.error("properties is present but is not a list.");
  process.exit(1);
}

/* An empty list is a real state - somebody may genuinely have unpublished
   everything - but it is far more often a broken write, and the cost of
   being wrong is a live site with no listings. It is refused here and can be
   published deliberately with a manual run. */
if (Array.isArray(properties) && properties.length === 0) {
  console.error(
    "The content lists no properties at all. Refusing automatically - " +
    "run the workflow by hand if that is genuinely intended."
  );
  process.exit(1);
}

const count = Array.isArray(properties) ? properties.length : 0;
console.log(`content.json looks sound: ${count} properties, version ${content.version}`);

fs.appendFileSync(process.env.GITHUB_OUTPUT, `version=${content.version}\n`);
fs.appendFileSync(process.env.GITHUB_OUTPUT, `count=${count}\n`);
' || say "The content that arrived is not publishable. Nothing was sent to the website."

echo "ok=true" >> "$GITHUB_OUTPUT"
