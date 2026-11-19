#!/usr/bin/env bash
# Appends each new upstream build of the manifest.json entries to mirror.json.
# Prints one line per added entry: <image>:<tag>.
# Needs regctl logged in to dhi.io.
set -euo pipefail

entries=$(jq -c '.[]' manifest.json)
while read -r entry; do
  image=$(jq -r .image <<<"$entry")
  dhi_tag=$(jq -r .dhi_tag <<<"$entry")
  prefix=$(jq -r .prefix <<<"$entry")
  key="$image:$prefix"

  digest=$(regctl image digest "dhi.io/$image:$dhi_tag")
  known=$(jq --arg key "$key" --arg digest "$digest" \
    '(.[$key] // []) | any(.digest == $digest)' mirror.json)
  if [[ $known == true ]]; then
    echo "$key: $digest already recorded" >&2
    continue
  fi

  # The build date in UTC. fromdate accepts only YYYY-MM-DDTHH:MM:SSZ.
  created=$(regctl manifest get "dhi.io/$image@$digest" --format raw-body |
    jq -r '.annotations["com.docker.dhi.created"]')
  base="$prefix-$(jq -nr --arg created "$created" '$created | fromdate | strftime("%Y%m%d")')"
  tags=$(jq -r --arg key "$key" '(.[$key] // [])[].tag' mirror.json)
  tag=$base
  n=0
  while grep -qxF -- "$tag" <<<"$tags"; do
    n=$((n + 1))
    tag="$base.$n"
  done

  jq --arg key "$key" --arg image "$image" --arg dhi_tag "$dhi_tag" \
    --arg prefix "$prefix" --arg digest "$digest" --arg tag "$tag" \
    '.[$key] += [{image: $image, dhi_tag: $dhi_tag, prefix: $prefix, digest: $digest, tag: $tag}]' \
    mirror.json >mirror.json.new
  mv mirror.json.new mirror.json
  echo "$key: added $tag ($digest, created $created)" >&2
  echo "$image:$tag"
done <<<"$entries"
