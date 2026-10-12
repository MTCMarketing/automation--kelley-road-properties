#!/usr/bin/env bash
#
# Publishes content.json to the website repository, which builds on push.
#
# Over SSH, with a deploy key. An earlier version used the REST API with a
# bearer token and failed with curl exit 43 on every run: the credential is a
# key pair, 50 lines of it, and a newline in an Authorization header is not
# something curl will send. The shape of the credential decides the transport.
#
# The clone is deliberately minimal. The website repository carries its
# photography and is large; this needs to write one file. --filter=blob:none
# with a sparse checkout fetches the history shape and a single blob rather
# than the whole working tree.

set -euo pipefail

: "${DEPLOY_KEY:?AUTOMATION_CONTENT_JSON is not set}"
: "${TARGET_REPO:?TARGET_REPO is not set}"

SOURCE="${GITHUB_WORKSPACE:-$PWD}/.github/content/content.json"

[ -f "$SOURCE" ] || { echo "No content.json to publish."; exit 1; }

# ── the key ───────────────────────────────────────────────
# To a file, because ssh refuses a key readable by anyone else. Written under
# the runner's home rather than the workspace, so a later step that archives
# the checkout cannot pick it up.
key="$HOME/.ssh/content_deploy"
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# printf with an explicit newline: ssh rejects a key that does not end in one,
# and the stored secret does not carry it.
printf '%s\n' "$DEPLOY_KEY" > "$key"
chmod 600 "$key"

ssh-keyscan -t rsa,ecdsa,ed25519 github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null

export GIT_SSH_COMMAND="ssh -i $key -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

# ── the clone ─────────────────────────────────────────────
work="$(mktemp -d)"

echo "Fetching the website repository..."
git clone --quiet --depth 1 --filter=blob:none --sparse \
  "git@github.com:${TARGET_REPO}.git" "$work"

cd "$work"
git sparse-checkout set --no-cone content.json

# ── is there anything to publish? ─────────────────────────
# A build costs about five minutes of a fixed monthly allowance, so identical
# content must not spend one.
#
# Compared on `version` rather than by diffing the files. The version is the
# database's own updated_at, so equal versions mean identical content by
# definition - whereas a byte comparison is defeated by anything a writer
# stamps on the file per run. It was: an earlier content.json carried a
# generatedAt, which changed every time and made every trigger a build.
incoming=$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).version||"")' "$SOURCE")
existing=$(node -e 'try{console.log(JSON.parse(require("fs").readFileSync("content.json","utf8")).version||"")}catch{console.log("")}')

if [ -n "$existing" ] && [ "$incoming" = "$existing" ]; then
  echo "The website already has version $existing. Nothing published, no build spent."
  exit 0
fi

cp "$SOURCE" content.json
git add content.json

if git diff --cached --quiet; then
  echo "The file is byte-identical to what the website has. Nothing published."
  exit 0
fi

version=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("content.json","utf8")).version)')
count=$(node -e 'const c=JSON.parse(require("fs").readFileSync("content.json","utf8"));console.log(c.properties?c.properties.length:0)')

# The deployment marker appears here exactly once. It is matched anywhere in
# the message, so it must never be written again, not even in prose.
git -c user.name="Kelley Road automation" \
    -c user.email="automation@kelleyroadproperties.com" \
    commit --quiet -m "Content updated from the CMS [deploy:live]

${count} properties, version ${version}.

Published by automation--kelley-road-properties. The website builds from this
file rather than reading the database itself, so the database can be replaced
without the website knowing."

echo "Publishing ${count} properties (version ${version})..."
git push --quiet origin HEAD:main

echo "Published. The website is rebuilding."
