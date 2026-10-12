#!/usr/bin/env bash
#
# Commits content.json to the website repository, which publishes on push.
#
# Done through the GitHub API rather than by cloning: the website repository
# is private and several hundred megabytes, and this needs to write one file.
# A clone would spend most of the run downloading things it will not read.
#
# The commit message carries the deployment marker exactly once. It is matched
# anywhere in the message, so it must not appear a second time, even in prose.

set -euo pipefail

: "${GITHUB_TOKEN:?AUTOMATION_CONTENT_JSON is not set — add it under Settings, Secrets}"
: "${TARGET_REPO:?TARGET_REPO is not set}"

API="https://api.github.com/repos/${TARGET_REPO}/contents/content.json"

auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}"
      -H "Accept: application/vnd.github+json"
      -H "X-GitHub-Api-Version: 2022-11-28")

# The file's current sha, which the API needs in order to replace it. Absent
# the first time, which is a create rather than an update.
sha=$(curl -fsS "${auth[@]}" "$API" 2>/dev/null \
  | node -e 'let b="";process.stdin.on("data",c=>b+=c);process.stdin.on("end",()=>{try{console.log(JSON.parse(b).sha||"")}catch{console.log("")}})' \
  || echo "")

version=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("content.json","utf8")).version)')
count=$(node -e 'const c=JSON.parse(require("fs").readFileSync("content.json","utf8"));console.log(c.properties?c.properties.length:0)')

message="Content updated from the CMS [deploy:live]

${count} properties, version ${version}.

Written by automation--kelley-road-properties. The website builds from this
file rather than reading the CMS directly, so the database can be replaced
without the website knowing."

payload=$(node --input-type=module -e '
import fs from "node:fs";
const body = {
  message: process.argv[1],
  content: fs.readFileSync("content.json").toString("base64"),
  committer: { name: "Kelley Road automation", email: "automation@kelleyroadproperties.com" },
};
if (process.argv[2]) body.sha = process.argv[2];
console.log(JSON.stringify(body));
' "$message" "$sha")

echo "Publishing ${count} properties (version ${version}) to ${TARGET_REPO}..."

response=$(curl -fsS -X PUT "${auth[@]}" -d "$payload" "$API")

printf '%s' "$response" | node -e '
let b = "";
process.stdin.on("data", (c) => (b += c));
process.stdin.on("end", () => {
  const r = JSON.parse(b);
  if (r.commit && r.commit.sha) {
    console.log("Committed " + r.commit.sha.slice(0, 7) + " — the website is rebuilding.");
  } else {
    console.error("The API did not report a commit. Nothing was published.");
    process.exit(1);
  }
});
'
