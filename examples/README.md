# Examples

End-to-end workflow for publishing MTA artifacts to a local Nexus OCI registry.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [mise](https://mise.jdx.dev/)

## Quick Start

Install tools (oras, yq, jq):

```sh
mise install
```

Start Nexus and provision the OCI registry:

```sh
mise run dev
```

This starts a Nexus container, accepts the EULA, enables the Docker Bearer Token realm, creates a Docker hosted repository (`oci-registry`) on port 5000, and sets the admin password to `admin123`.

Publish all tool artifacts:

```sh
mise run publish
```

This logs into the registry and runs `publish:java`, which downloads the Azul Zulu JDK assets for all platforms, pushes per-platform manifests, and creates the OCI Image Index at `localhost:5000/tools/java:17.60.17`.

## Tasks

| Task | Description |
|------|-------------|
| `mise run dev` | Start Nexus and provision the OCI registry |
| `mise run publish` | Publish all tool artifacts |
| `mise run publish:java` | Publish only the Java artifact |
| `mise run catalog` | List repositories in the registry |
| `mise run nexus:logs` | Tail Nexus logs |
| `mise run nexus:stop` | Stop Nexus |
| `mise run nuke` | Stop Nexus and delete all data |

## Verifying

Inspect the published image index:

```sh
oras manifest fetch --insecure localhost:5000/tools/java:17.60.17 | jq .
```

Inspect a platform manifest:

```sh
oras manifest fetch --insecure localhost:5000/tools/java:17.60.17-darwin-arm64 | jq .
```

## Services

| Service | URL | Credentials |
|---------|-----|-------------|
| Nexus UI | http://localhost:8081 | admin / admin123 |
| OCI Registry | http://localhost:5000 | admin / admin123 |

## Adding a New Tool

1. Create a directory under `examples/` (e.g. `examples/node/`)
2. Add a `tool.yaml` following the format in `examples/java/tool.yaml`
3. Add a `publish:<tool>` task to `mise.toml` that calls `publish.sh` with the new tool.yaml
4. Add the new task to the `publish` task's `depends` list

## ORAS Interoperability

This example uses [ORAS](https://oras.land/) for publishing, discovery, and pulling.

- Publishers SHOULD tag the top-level OCI Image Index for each released version.
- Clients SHOULD resolve the platform from the tagged index, then fetch the selected manifest, config, and payload blobs.
- Installation MUST NOT depend on the Referrers API. A client using `oras` SHOULD be able to install an artifact using only standard manifest and blob retrieval.
- Signatures, SBOMs, and provenance SHOULD be treated as optional verification data layered on top of the core install flow.

In practice, an MTA client built on `oras` is expected to:

1. Resolve a reference such as `localhost:5000/tools/java:17.60.17` to an OCI Image Index.
2. Select the best matching manifest from `manifests[]` using the host platform.
3. Fetch the selected manifest, config blob, and payload layer.
4. Extract and install according to the rules in the specification.

Clients that need to discover available versions MAY use the standard registry tags API, for example `GET /v2/<name>/tags/list`, and treat tags as candidate artifact versions.

## TODO

- [ ] Attach a CycloneDX SBOM using Cosign
- [ ] Sign the artifact using Cosign/Sigstore
- [ ] Verify artifact digest integrity after publish
