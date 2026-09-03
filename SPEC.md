# ceph-container — SPEC

## Purpose

`ceph-container` provides a single-container Ceph image for **demo and
integration testing** (e.g. the `go-docker-testsuite`). It bootstraps a
minimal single-node Ceph cluster inside one container: one `mon`, one `mgr`,
one `osd` (bluestore on a plain directory) and one `rgw`, plus an RGW admin
user.

It is built on top of the official multi-arch `quay.io/ceph/ceph` release
image, so the same `Dockerfile` produces amd64 and arm64 images.

## Scope

* In scope: `mon`, `mgr`, `osd`, `rgw`, RGW admin user creation.
* Out of scope: `mds`, `nfs`, `rbd-mirror`, `crushmap` tuning, bucket
  pre-creation (modern Ceph only creates buckets via the S3 API, so clients
  create them).

## Runtime behavior

`entrypoint.sh` either bootstraps a fresh cluster (first run) or, when the
marker file `/var/lib/ceph/I_AM_A_DEMO` exists, only restarts the daemons.

Required environment (unset values cause the entrypoint to abort):

* `MON_IP`
* `CEPH_PUBLIC_NETWORK`
* `CEPH_DEMO_ACCESS_KEY`
* `CEPH_DEMO_SECRET_KEY`

Sensible defaults exist for `CLUSTER`, `MON_NAME`, `MGR_NAME`, `RGW_NAME`,
`MON_PORT`, `RGW_FRONTEND_IP`, `RGW_FRONTEND_PORT`, `CEPH_DEMO_UID`.

Readiness signal: the container prints `SUCCESS: RGW on <ip>:<port>, admin
user <uid>` after mon + mgr + osd + rgw are up and the RGW health check passed.

> **Performance**: bootstrap is very slow without a raised file limit. Always
> run with `--ulimit nofile=65536:65536`.

## Build model

The `Dockerfile` is parameterized by two `ARG`s:

* `CEPH_VERSION` (default `19.2.6`) — the semantic Ceph release, e.g. `19.2.6`
  (squid) or `20.2.4` (tentacle). The `quay.io/ceph/ceph` tag is `v<version>`.
* `CEPH_SOURCE_IMAGE` (default `quay.io/ceph/ceph`) — base image source,
  overridable so CI can pin a mirror.

```dockerfile
FROM ${CEPH_SOURCE_IMAGE}:v${CEPH_VERSION}
```

## Supported version matrix

CI builds an image for **every released version** of the Squid and Tentacle
release trains:

| Train    | Versions                                               |
| -------- | ------------------------------------------------------ |
| Squid    | 19.2.0, 19.2.1, 19.2.2, 19.2.3, 19.2.4, 19.2.5, 19.2.6 |
| Tentacle | 20.2.0, 20.2.1, 20.2.2, 20.2.3, 20.2.4                 |

## CI

Two GitHub Actions workflows, modelled on `runityru/cephctl`:

* `.github/workflows/verify.yml` — on push to `master` and on PRs. Runs
  `hadolint`, `markdownlint`, `shellcheck` and a matrix **build** (all 12
  versions, no push, image not run).
* `.github/workflows/release.yml` — on tag push `v*`. Runs the same linters as
  gates, then a matrix **build & push** of all 12 versions to
  `ghcr.io/<owner>/ceph`.

Publishing tags per version:

* `v<version>`
* `v<version>-<ref_name>`
* `v<version>-<ref_name>-<timestamp>` (immutable snapshot)

## Security

* Workflow-level `permissions: contents: read`; `packages: write` is granted
  only to the release publish job.
* Only GitHub-provided secrets are used (`secrets.GITHUB_TOKEN`); no secrets
  are hardcoded.
