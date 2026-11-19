#!/usr/bin/env bash
# The PR check: shellcheck, actionlint, and the structure of the JSON files.
set -euo pipefail

shellcheck ./*.sh
actionlint

jq -e '
  type == "array" and length > 0
  and all(.[]; type == "object" and (keys == ["dhi_tag", "image", "prefix"])
    and all(.[]; type == "string" and length > 0))
  and ([.[] | "\(.image):\(.prefix)"] | length == (unique | length))
' manifest.json >/dev/null || { echo "manifest.json: bad structure" >&2; exit 1; }

jq -e '
  type == "object"
  and all(to_entries[]; .key as $key | .value | type == "array"
    and all(.[]; type == "object"
      and keys == ["dhi_tag", "digest", "image", "prefix", "tag"]
      and "\(.image):\(.prefix)" == $key
      and (.digest | test("^sha256:[0-9a-f]{64}$"))
      and (.tag | startswith("\($key | split(":")[1])-")))
    and (map(.digest) | length == (unique | length))
    and (map(.tag) | length == (unique | length)))
' mirror.json >/dev/null || { echo "mirror.json: bad structure" >&2; exit 1; }
