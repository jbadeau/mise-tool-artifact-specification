
# Mise Tool Artifact (MTA) Specification v1.0

## Overview

The **Mise Tool Artifact (MTA)** specification defines a standardized, multi-platform format for distributing development tools and binaries using [OCI-compatible](https://github.com/opencontainers/image-spec) registries. It extends the tool stub format used by [mise](https://mise.jdx.dev/), but is **tool-agnostic** and can be integrated into any tool version manager, package manager, or provisioning system.

## Goals

- **Multi-platform**: Distribute binaries for Linux, macOS, and Windows using OCI Image Index
- **Registry-native**: Built on OCI Image Spec, Distribution Spec, and standard annotations
- **Tool-agnostic**: Can be used with mise, nix, brew, or any provisioning system
- **Secure**: Leverages OCI referrers for provenance, SBOM, and signature attestations
- **Minimal**: No duplication between layers — metadata lives in annotations, install behavior lives in config

## Design Principles

1. **Single source of truth** — each piece of data lives in exactly one place
2. **OCI standard first** — use existing OCI fields and annotations before introducing custom ones
3. **Separation of concerns** — annotations carry metadata, config carries install behavior, Image Index carries platform routing

## Specification

### Media Types

| Component | Media Type |
|-----------|------------|
| Image Index | `application/vnd.oci.image.index.v1+json` |
| Platform Manifest | `application/vnd.oci.image.manifest.v1+json` |
| Artifact Type | `application/vnd.mise.tool.v1` |
| Config | `application/vnd.mise.tool.config.v1+json` |
| Layer | `application/vnd.oci.image.layer.v1.tar+gzip` |

## Artifact Layout

An MTA artifact is a standard **OCI Image Index** pointing to one **platform manifest** per supported OS/architecture combination. Each platform manifest contains a single config blob and a single payload layer.

A single artifact version MUST be published as one OCI Image Index. That index MUST contain one manifest for each supported platform variant of that version. MTA artifacts MUST use an OCI Image Index even when only one platform is supported.

```
OCI Image Index
  ├── platform: linux/amd64   → Manifest → [config, layer.tar.gz]
  ├── platform: linux/arm64   → Manifest → [config, layer.tar.gz]
  ├── platform: darwin/amd64  → Manifest → [config, layer.tar.gz]
  ├── platform: darwin/arm64  → Manifest → [config, layer.tar.gz]
  └── platform: windows/amd64 → Manifest → [config, layer.tar.gz]
```

```mermaid
flowchart LR
    TAG["Tag<br/>registry.example.com/tools/kubectl:1.34.1"]
    IDX["OCI Image Index<br/>mediaType: application/vnd.oci.image.index.v1+json<br/>artifactType: application/vnd.mise.tool.v1<br/><br/>annotations:<br/>org.opencontainers.image.title: kubectl<br/>org.opencontainers.image.version: 1.34.1<br/>org.opencontainers.image.description: Kubernetes CLI<br/>org.opencontainers.image.url: kubernetes.io<br/>org.opencontainers.image.source: github.com/kubernetes/kubernetes<br/>org.opencontainers.image.licenses: Apache-2.0"]

    M1["Platform Manifest<br/>mediaType: application/vnd.oci.image.manifest.v1+json<br/>platform.os: linux<br/>platform.architecture: amd64"]
    M2["Platform Manifest<br/>mediaType: application/vnd.oci.image.manifest.v1+json<br/>platform.os: darwin<br/>platform.architecture: arm64"]

    C1["Config Blob<br/>mediaType: application/vnd.mise.tool.config.v1+json<br/><br/>fields:<br/>mtaSpecVersion: 1.0<br/>bin: ['kubectl']<br/>env: {}"]
    C2["Config Blob<br/>mediaType: application/vnd.mise.tool.config.v1+json<br/><br/>fields:<br/>mtaSpecVersion: 1.0<br/>bin: ['kubectl']<br/>env: {}"]

    L1["Payload Layer<br/>mediaType: application/vnd.oci.image.layer.v1.tar+gzip<br/><br/>archive contents:<br/>kubectl"]
    L2["Payload Layer<br/>mediaType: application/vnd.oci.image.layer.v1.tar+gzip<br/><br/>archive contents:<br/>kubectl"]

    R1["Referrer Manifest<br/>artifactType: application/spdx+json"]
    R2["Referrer Manifest<br/>artifactType: application/vnd.in-toto+json"]
    R3["Referrer Manifest<br/>artifactType: application/vnd.cncf.notary.signature"]

    TAG -->|"resolves to"| IDX

    IDX -->|"choose matching platform"| M1
    IDX -->|"choose matching platform"| M2

    M1 -->|"read install config"| C1
    M1 -->|"download payload"| L1
    M2 -->|"read install config"| C2
    M2 -->|"download payload"| L2

    R1 -. "subject: describes this artifact" .-> IDX
    R2 -. "subject: describes this artifact" .-> IDX
    R3 -. "subject: describes this artifact" .-> IDX
```

Read the diagram from left to right:

1. A user or client resolves a tag such as `registry/repo/tool:version`.
2. That tag points to an OCI Image Index, which carries shared metadata and the list of supported platforms.
3. The client chooses the matching platform manifest for the current machine.
4. The platform manifest points to two blobs:
   - a config blob that tells the installer how to wire up the tool
   - a payload layer that contains the files to extract
5. Optional referrers can point back to the artifact for signatures, SBOMs, and provenance.

### OCI Image Index

The top-level artifact. Platform resolution uses the standard OCI `platform` descriptor on each manifest entry.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.index.v1+json",
  "artifactType": "application/vnd.mise.tool.v1",
  "manifests": [
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:aaa...",
      "size": 1024,
      "platform": {
        "os": "linux",
        "architecture": "amd64"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:bbb...",
      "size": 1024,
      "platform": {
        "os": "linux",
        "architecture": "arm64"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:ccc...",
      "size": 1024,
      "platform": {
        "os": "darwin",
        "architecture": "arm64"
      }
    },
    {
      "mediaType": "application/vnd.oci.image.manifest.v1+json",
      "digest": "sha256:ddd...",
      "size": 1024,
      "platform": {
        "os": "windows",
        "architecture": "amd64"
      }
    }
  ],
  "annotations": {
    "org.opencontainers.image.title": "Azul Zulu JDK",
    "org.opencontainers.image.version": "17.60.17",
    "org.opencontainers.image.description": "Azul Zulu OpenJDK distribution",
    "org.opencontainers.image.url": "https://azul.com/zulu",
    "org.opencontainers.image.documentation": "https://docs.azul.com/core/zulu-openjdk",
    "org.opencontainers.image.source": "https://github.com/zulu-openjdk/zulu-openjdk",
    "org.opencontainers.image.licenses": "GPL-2.0-with-classpath-exception",
    "org.opencontainers.image.vendor": "Azul Systems",
    "org.opencontainers.image.authors": "Azul Systems <support@azul.com>",
    "org.opencontainers.image.created": "2025-08-06T05:08:34Z"
  }
}
```

### Platform Manifest

One per OS/architecture. Contains a config blob (install behavior) and a single layer (the installation payload). The `artifactType` identifies this as an MTA tool artifact.

Platform manifests MAY repeat a subset of Index annotations for convenience, but the Image Index is authoritative when the same annotation appears in both places.

If multiple platform manifests reference byte-identical config blobs, registries will naturally deduplicate those blobs by digest. Publishers do not need to optimize for this explicitly.

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/vnd.mise.tool.v1",
  "config": {
    "mediaType": "application/vnd.mise.tool.config.v1+json",
    "digest": "sha256:eee...",
    "size": 512
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:fff...",
      "size": 198700362
    }
  ],
  "annotations": {
    "org.opencontainers.image.title": "Azul Zulu JDK",
    "org.opencontainers.image.version": "17.60.17"
  }
}
```

### Payload Layer Semantics

The payload layer MUST be a gzip-compressed tar archive using the standard OCI layer media type `application/vnd.oci.image.layer.v1.tar+gzip`.

For installation, clients MUST treat the layer as a regular archive payload, not as a container root filesystem diff. To keep behavior deterministic across clients, publishers and clients MUST follow these rules:

- The archive MUST unpack into a fresh installation directory chosen by the client.
- Archive entry paths MUST be relative, normalized POSIX-style paths as stored in the tar archive.
- Archive entries MUST NOT use absolute paths or contain `..` path traversal segments.
- Archive entries MUST NOT use OCI whiteout semantics.
- Archive entries MUST NOT include device nodes.
- Symbolic links MAY be used. Clients SHOULD preserve them when the host platform supports them.
- Clients MUST NOT strip a leading directory automatically. Paths are interpreted exactly as stored in the archive.

This keeps the payload OCI-native at the transport layer while avoiding container-specific filesystem semantics that do not map cleanly to installer behavior.

### Config Object (`application/vnd.mise.tool.config.v1+json`)

The config blob defines **installation behavior only**. Metadata (name, version, description, license, etc.) is carried by OCI annotations on the Index and is not duplicated here.

Clients MUST ignore unknown fields in the config object.

```json
{
  "mtaSpecVersion": "1.0",
  "bin": [
    "bin/java",
    "bin/javac",
    "bin/jar"
  ],
  "env": {
    "JAVA_HOME": "{{ install_path }}",
    "PATH": "{{ install_path }}/bin{{ path_list_sep }}{{ PATH }}"
  }
}
```

#### Config Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mtaSpecVersion` | string | yes | Spec version (e.g. `"1.0"`) |
| `bin` | string[] | yes | Relative POSIX-style paths to executables within the installation directory after extraction |
| `env` | object | no | Environment variables to set using the templating variables defined below |

#### Config Templating

The `env` object supports simple string substitution only. Clients MUST NOT evaluate shell expressions.

| Variable | Description |
|----------|-------------|
| `{{ install_path }}` | Absolute installation directory selected by the client |
| `{{ PATH }}` | Existing `PATH` value in the target environment |
| `{{ path_list_sep }}` | Host path list separator (`:` on POSIX, `;` on Windows) |

Template variables are resolved against the host environment before the new `env` map is applied. Clients SHOULD normalize expanded paths for the host platform. Publishers SHOULD keep `bin` entries and archive paths POSIX-style inside the artifact.

## Annotations

### OCI Standard Annotations (on Image Index)

OCI pre-defined annotations SHOULD be used wherever their semantics match the artifact metadata. Canonical package identity is derived from the OCI reference used to resolve the artifact, not from annotations.

| Annotation | Required | Description |
|------------|----------|-------------|
| `org.opencontainers.image.title` | recommended | Human-readable title |
| `org.opencontainers.image.version` | yes | Tool version |
| `org.opencontainers.image.description` | yes | Human-readable description |
| `org.opencontainers.image.url` | recommended | Homepage URL |
| `org.opencontainers.image.documentation` | recommended | Documentation URL |
| `org.opencontainers.image.source` | recommended | Source code URL |
| `org.opencontainers.image.licenses` | recommended | SPDX license expression |
| `org.opencontainers.image.vendor` | recommended | Vendor / distributing entity |
| `org.opencontainers.image.authors` | recommended | Contact details of maintainers |
| `org.opencontainers.image.created` | recommended | Build timestamp (RFC 3339) |

Clients SHOULD treat the OCI reference as the canonical package identity. In practice, this means the repository identifies the tool and the tag identifies the version, for example `registry.example.com/tools/kubectl:1.34.1`. Clients MAY additionally resolve and record the digest for reproducibility.

## Platform Resolution

Platform selection follows the standard OCI Image Index resolution. Clients match the `platform` descriptor on each manifest entry against the host system:

| Field | Description | Examples |
|-------|-------------|---------|
| `os` | Operating system | `linux`, `darwin`, `windows` |
| `architecture` | CPU architecture | `amd64`, `arm64`, `arm`, `386` |
| `os.version` | OS version constraint (optional) | `10.0.17763` |
| `variant` | Architecture variant (optional) | `v7`, `v8` |

These are standard OCI platform descriptor fields per the [OCI Image Index specification](https://github.com/opencontainers/image-spec/blob/main/image-index.md).

Because the config blob is platform-specific, `bin` entries MUST name the executable as it exists in that platform payload. For example, a Windows manifest SHOULD list `kubectl.exe`, while a Linux or macOS manifest SHOULD list `kubectl`. Clients MUST NOT append platform-specific executable suffixes automatically.

If multiple manifests match, clients SHOULD prefer the most specific match, for example a matching `variant` over an entry that omits it.

## Installation Semantics

After selecting a platform manifest, clients SHOULD:

1. Download and verify the selected manifest, config, and payload layer descriptors.
2. Extract the payload into a newly created installation directory.
3. Resolve `bin` entries relative to that installation directory exactly as listed.
4. Apply `env` templating using host-specific path normalization.

Clients MUST fail installation if any `bin` entry resolves outside the installation directory or does not exist after extraction.

## ORAS Interoperability

MTA is designed to work well with [ORAS](https://oras.land/) for publishing, discovery, and pulling.

- Publishers SHOULD tag the top-level OCI Image Index for each released version.
- Clients SHOULD resolve the platform from the tagged index, then fetch the selected manifest, config, and payload blobs.
- Installation MUST NOT depend on the Referrers API. A client using `oras` SHOULD be able to install an artifact using only standard manifest and blob retrieval.
- Signatures, SBOMs, and provenance SHOULD be treated as optional verification data layered on top of the core install flow.

In practice, an MTA client built on `oras` is expected to:

1. Resolve a reference such as `<registry>/<repo>/<tool>:<version>` to an OCI Image Index.
2. Select the best matching manifest from `manifests[]` using the host platform.
3. Fetch the selected manifest, config blob, and payload layer.
4. Extract and install according to the rules in this specification.

This keeps the install path compatible with registries and clients that support OCI artifacts and image indexes, even when newer registry features such as referrers are unavailable.

Clients that need to discover available versions MAY use the standard registry tags API, for example `GET /v2/<name>/tags/list`, and treat tags as candidate artifact versions.

## Security Attestations

MTA leverages the **OCI Referrers API** ([OCI Distribution Spec v1.1](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#listing-referrers)) for supply chain security. Attestations are stored as separate OCI artifacts that reference the MTA artifact via the `subject` field.

### Supported Attestation Types

| Attestation | Artifact Type | Media Type | Description |
|------------|---------------|------------|-------------|
| Provenance | `application/vnd.in-toto+json` | `application/vnd.in-toto+json` | [SLSA Provenance](https://slsa.dev) build attestation |
| SBOM | `application/spdx+json` | `application/spdx+json` | [SPDX](https://spdx.dev/) software bill of materials |
| SBOM | `application/vnd.cyclonedx+json` | `application/vnd.cyclonedx+json` | [CycloneDX](https://cyclonedx.org/) software bill of materials |
| Signature | `application/vnd.cncf.notary.signature` | `application/jose+json` | [Notary v2](https://github.com/notaryproject/specifications) signature |

### Referrer Structure

Attestation artifacts use the standard OCI manifest `subject` field to reference the MTA artifact they describe:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "artifactType": "application/spdx+json",
  "config": {
    "mediaType": "application/vnd.oci.empty.v1+json",
    "digest": "sha256:44136fa...",
    "size": 2
  },
  "layers": [
    {
      "mediaType": "application/spdx+json",
      "digest": "sha256:ggg...",
      "size": 4096
    }
  ],
  "subject": {
    "mediaType": "application/vnd.oci.image.index.v1+json",
    "digest": "sha256:hhh...",
    "size": 2048
  }
}
```

Clients discover attestations by querying the [Referrers API](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#listing-referrers):

```
GET /v2/<name>/referrers/<digest>?artifactType=application/spdx+json
```

### Verification

Clients SHOULD:

1. **Verify descriptor integrity** for the image index, selected manifest, config blob, and payload layer using both `digest` and `size`
2. **Verify extraction safety** by rejecting invalid archive entries such as path traversal, absolute paths, whiteouts, and device nodes
3. **Discover and verify signatures** via the Referrers API before installation when signatures are available
4. **Check provenance** attestations to validate the build origin when available

Clients MAY proceed with installation when referrers are unsupported or absent, as long as the core artifact descriptors verify successfully and local policy permits unsigned installs.

## Inspirations

- [**Helm**](https://helm.sh): For pioneering the use of OCI registries as general-purpose artifact distribution systems
- [**OCI Image Spec**](https://github.com/opencontainers/image-spec): For the Image Index, manifest, and annotation standards
- [**OCI Distribution Spec**](https://github.com/opencontainers/distribution-spec): For the Referrers API used by security attestations
- [**SLSA**](https://slsa.dev): For the provenance attestation model
