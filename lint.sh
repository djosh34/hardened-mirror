#!/usr/bin/env bash
# The PR check: shellcheck, actionlint, and the structure of the JSON files.
set -euo pipefail

shellcheck ./*.sh
actionlint

# -s reads the whole file as one array, so an empty file fails too.
jq -se '
  length == 1 and (.[0]
  | type == "array" and length > 0
  and all(.[]; type == "object" and keys == ["dhi_tag", "image", "prefix"]
    and all(.[]; type == "string" and test("^[a-z0-9][a-z0-9._-]*$")))
  and (map("\(.image):\(.prefix)") | length == (unique | length)))
' manifest.json >/dev/null || { echo "manifest.json: bad structure" >&2; exit 1; }

jq -se '
  length == 1 and (.[0]
  | type == "object"
  and all(to_entries[]; .key as $key | .value | type == "array" and length > 0
    and all(.[]; type == "object"
      and keys == ["dhi_tag", "digest", "image", "prefix", "tag"]
      and all(.[]; type == "string")
      and "\(.image):\(.prefix)" == $key
      and (.digest | test("^sha256:[0-9a-f]{64}$"))
      and (.tag | ltrimstr($key | split(":")[1]) | test("^-[0-9]{8}(\\.[0-9]+)?$")))
    and (map(.digest) | length == (unique | length))
    and (map(.tag) | length == (unique | length))))
' mirror.json >/dev/null || { echo "mirror.json: bad structure" >&2; exit 1; }
