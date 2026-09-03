# AGENTS.md — guidance for AI agents

Working notes for agents contributing to this repository.

## Repository layout

* `Dockerfile` — single-stage image built on `quay.io/ceph/ceph:v<version>`.
  Build args: `CEPH_VERSION` (semantic version) and `CEPH_SOURCE_IMAGE`
  (base source).
* `entrypoint.sh` — demo bootstrap (mon/mgr/osd/rgw). Read it before changing
  runtime behavior.
* `.github/workflows/verify.yml` — PR / push-to-master checks.
* `.github/workflows/release.yml` — tag-push (`v*`) matrix build & publish.
* `README.md` — user-facing build/run docs.
* `SPEC.md` — project specification.

## Language

`SPEC.md`, `AGENTS.md` and all agent-facing prompts are **English**. The
`README.md` is English.

## Version matrix

CI builds every released **Squid** (19.2.0..19.2.6) and **Tentacle**
(20.2.0..20.2.4) version. **Keep `verify.yml` and `release.yml` matrices in
sync** — if you add or remove a version, update both.

## Build & run (local)

```sh
docker build -t ghcr.io/teran/ceph-container/ceph:v19.2.6 --build-arg CEPH_VERSION=19.2.6 .
docker run --rm -p 8080:8080 -p 3300:3300 \
  -e MON_IP=127.0.0.1 -e CEPH_PUBLIC_NETWORK=0.0.0.0/0 \
  -e CEPH_DEMO_UID=demo -e CEPH_DEMO_ACCESS_KEY=access \
  -e CEPH_DEMO_SECRET_KEY=secret \
  --ulimit nofile=65536:65536 \
  ghcr.io/teran/ceph-container/ceph:v19.2.6
```

Ready when logs print `SUCCESS: RGW on ...`.

## CI gotchas

* **Do not run the image in `verify.yml`** — it only builds (no push, no
  `docker run`).
* The `build-container-images` job pushes to GHCR only on tag push `v*`.
* Three tags are published per version (see `SPEC.md`): the immutable
  timestamp tag is produced from the `timestamp` step output.
* `ludeeus/action-shellcheck` has **no short `@2` tag** — only full tags such
  as `2.0.0`. Reference it by the full version.
* Keep GitHub Actions pinned to current major versions.

## Conventions

* Minimal workflow permissions (see `SPEC.md` → Security).
* No hardcoded secrets; use `${{ secrets.GITHUB_TOKEN }}` / `${{ github.token }}`.
* Validate workflow YAML after editing (e.g. `ruby -e 'require "yaml";
  YAML.load_file("...")'`).
