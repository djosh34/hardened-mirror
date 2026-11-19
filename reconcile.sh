#!/usr/bin/env bash
# Makes GHCR and the releases match mirror.json for one <image>:<prefix> key.
# Copies each entry whose tag is missing, with its referrers. For each entry
# without a release, checks the DHI signature on the copy, then makes the
# release. Points <prefix>-latest at the last entry. A dated tag is never
# written twice.
# Needs a docker login to dhi.io and ghcr.io, regctl, cosign, gh with GH_TOKEN,
# GITHUB_REPOSITORY, and a checkout with the full history of mirror.json.
set -euo pipefail

key=$1
image=${key%%:*}
prefix=${key#*:}
dest="ghcr.io/$GITHUB_REPOSITORY/$image"

# A rerun of an old job can name a key that main no longer tracks.
tracked=$(jq --arg key "$key" 'any(.[]; "\(.image):\(.prefix)" == $key)' manifest.json)
if [[ $tracked != true ]]; then
  echo "$key is not in manifest.json; dispatch a new run instead" >&2
  exit 1
fi

entries=$(jq -ec --arg key "$key" '.[$key][]' mirror.json)
releases=$(gh api --paginate "repos/$GITHUB_REPOSITORY/releases" --jq '.[].tag_name')

errors=$(mktemp)

# Prints the digest of a GHCR tag, or nothing when the tag does not exist.
ghcr_digest() {
  local digest
  if digest=$(regctl manifest head "$dest:$1" 2>"$errors"); then
    echo "$digest"
  elif ! grep -qF "[http 404]" "$errors"; then
    cat "$errors" >&2
    return 1
  fi
}

while read -r entry; do
  digest=$(jq -r .digest <<<"$entry")
  tag=$(jq -r .tag <<<"$entry")
  release="$image-$tag"

  current=$(ghcr_digest "$tag")
  if [[ -z $current ]]; then
    echo "$dest:$tag: copying dhi.io/$image@$digest" >&2
    regctl image copy --referrers --force-recursive "dhi.io/$image@$digest" "$dest:$tag"
  elif [[ $current != "$digest" ]]; then
    echo "$dest:$tag is $current, but mirror.json says $digest" >&2
    exit 1
  fi

  # The release is made last, after the signature on the copy checks out.
  if grep -qxF -- "$release" <<<"$releases"; then
    continue
  fi
  if [[ ! -f dhi.pub ]]; then
    curl -fsSL -o dhi.pub https://registry.scout.docker.com/keyring/dhi/latest.pub
  fi
  cosign verify --key dhi.pub --insecure-ignore-tlog=true --experimental-oci11 \
    "$dest@$digest" >/dev/null
  echo "$dest@$digest: DHI signature verified" >&2

  # The release's git tag points at the commit that added this entry.
  commits=$(git log --reverse --format=%H -- mirror.json)
  commit=""
  for c in $commits; do
    found=$(git show "$c:mirror.json" |
      jq --arg key "$key" --arg tag "$tag" --arg digest "$digest" \
        '(.[$key] // []) | any(.tag == $tag and .digest == $digest)')
    if [[ $found == true ]]; then
      commit=$c
      break
    fi
  done
  if [[ -z $commit ]]; then
    echo "no commit adds $key $tag to mirror.json" >&2
    exit 1
  fi
  gh release create "$release" --repo "$GITHUB_REPOSITORY" --target "$commit" \
    --title "$release" --notes "\
docker pull $dest:$tag
docker pull $dest@$digest

Copied from dhi.io/$image@$digest."
done <<<"$entries"

last_digest=$(jq -r --arg key "$key" '.[$key][-1].digest' mirror.json)
last_tag=$(jq -r --arg key "$key" '.[$key][-1].tag' mirror.json)
latest_digest=$(ghcr_digest "$prefix-latest")
if [[ $latest_digest != "$last_digest" ]]; then
  regctl image copy "$dest@$last_digest" "$dest:$prefix-latest"
  echo "$dest:$prefix-latest now points at $last_tag" >&2
fi
