#!/usr/bin/env bash
set -euo pipefail

TOOL_YAML="${1:?Usage: publish.sh <tool.yaml> [registry]}"
REGISTRY="${2:-localhost:5000}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# --- Parse tool metadata ---
name=$(yq -r '.tool.name' "$TOOL_YAML")
version=$(yq -r '.tool.version' "$TOOL_YAML")
description=$(yq -r '.tool.description // ""' "$TOOL_YAML")
url=$(yq -r '.tool.url // ""' "$TOOL_YAML")
documentation=$(yq -r '.tool.documentation // ""' "$TOOL_YAML")
source=$(yq -r '.tool.source // ""' "$TOOL_YAML")
license=$(yq -r '.tool.license // ""' "$TOOL_YAML")
vendor=$(yq -r '.tool.vendor // ""' "$TOOL_YAML")
authors=$(yq -r '.tool.authors // ""' "$TOOL_YAML")

repo=$(basename "$(dirname "$(realpath "$TOOL_YAML")")")
ref="${REGISTRY}/tools/${repo}:${version}"

echo "Publishing ${name} ${version} -> ${ref}"

# --- Build config blob from tool.yaml ---
config_file="$WORK_DIR/config.json"
yq -o json '{"mtaSpecVersion": "1.0", "stripComponents": (.config.stripComponents // 0), "bin": .config.bin, "env": .config.env // {}}' "$TOOL_YAML" > "$config_file"

# --- Push each platform manifest ---
platform_count=$(yq '.platforms | length' "$TOOL_YAML")
manifests_json="[]"

for i in $(seq 0 $((platform_count - 1))); do
  os=$(yq -r ".platforms[$i].os" "$TOOL_YAML")
  arch=$(yq -r ".platforms[$i].arch" "$TOOL_YAML")
  asset=$(yq -r ".platforms[$i].asset" "$TOOL_YAML")

  platform_dir="$WORK_DIR/${os}-${arch}"
  mkdir -p "$platform_dir"

  echo "==> [${os}/${arch}] Downloading asset..."
  curl -sSL -o "$platform_dir/asset" "$asset"

  layer="$platform_dir/asset"

  # Detect media type from file format (preserve original, no repackaging)
  layer_media_type="application/octet-stream"
  if file "$layer" | grep -qi "gzip"; then
    layer_media_type="application/vnd.oci.image.layer.v1.tar+gzip"
  elif file "$layer" | grep -qi "xz"; then
    layer_media_type="application/vnd.oci.image.layer.v1.tar+zstd"
  elif file "$layer" | grep -qi "zip archive"; then
    layer_media_type="application/zip"
  fi

  # Push platform manifest with a temporary platform-specific tag
  platform_tag="${version}-${os}-${arch}"
  platform_ref="${REGISTRY}/tools/${repo}:${platform_tag}"

  echo "==> [${os}/${arch}] Pushing manifest (${layer_media_type})..."
  oras push --insecure --disable-path-validation "$platform_ref" \
    --config "$config_file:application/vnd.mise.tool.config.v1+json" \
    --artifact-type "application/vnd.mise.tool.v1" \
    "${layer}:${layer_media_type}"

  # Capture the pushed manifest descriptor
  descriptor=$(oras manifest fetch --insecure "$platform_ref" --descriptor)
  digest=$(echo "$descriptor" | jq -r '.digest')
  size=$(echo "$descriptor" | jq -r '.size')

  # Append to manifests array with platform info
  manifests_json=$(echo "$manifests_json" | jq \
    --arg digest "$digest" \
    --arg size "$size" \
    --arg os "$os" \
    --arg arch "$arch" \
    '. += [{
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": $digest,
      "size": ($size | tonumber),
      "platform": {"os": $os, "architecture": $arch}
    }]')
done

# --- Build OCI annotations ---
annotations=$(jq -n \
  --arg title "$name" \
  --arg version "$version" \
  --arg desc "$description" \
  --arg url "$url" \
  --arg docs "$documentation" \
  --arg src "$source" \
  --arg lic "$license" \
  --arg vendor "$vendor" \
  --arg authors "$authors" \
  --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{
    "org.opencontainers.image.title": $title,
    "org.opencontainers.image.version": $version,
    "org.opencontainers.image.description": $desc,
    "org.opencontainers.image.url": $url,
    "org.opencontainers.image.documentation": $docs,
    "org.opencontainers.image.source": $src,
    "org.opencontainers.image.licenses": $lic,
    "org.opencontainers.image.vendor": $vendor,
    "org.opencontainers.image.authors": $authors,
    "org.opencontainers.image.created": $created
  } | with_entries(select(.value != ""))')

# --- Build and push OCI Image Index ---
index_file="$WORK_DIR/index.json"
jq -n \
  --argjson manifests "$manifests_json" \
  --argjson annotations "$annotations" \
  '{
    "schemaVersion": 2,
    "mediaType": "application/vnd.oci.image.index.v1+json",
    "artifactType": "application/vnd.mise.tool.v1",
    "manifests": $manifests,
    "annotations": $annotations
  }' > "$index_file"

echo "==> Pushing image index..."
oras manifest push --insecure "$ref" "$index_file" \
  --media-type "application/vnd.oci.image.index.v1+json"

echo "==> Published ${ref}"
