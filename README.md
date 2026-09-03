# ceph-container

Ceph container image for demo & testing purposes. It bootstraps a single-node
Ceph cluster (one mon, one mgr, one OSD, one RGW) inside one container, built
on top of the official multi-arch `quay.io/ceph/ceph` release image. This makes
it handy for integration testing (e.g. the `go-docker-testsuite`).

## Supported Ceph versions (CI build matrix)

The CI builds an image for every released version of the **Squid** and
**Tentacle** release trains:

| Train    | Versions                                               |
| -------- | ------------------------------------------------------ |
| Squid    | 19.2.0, 19.2.1, 19.2.2, 19.2.3, 19.2.4, 19.2.5, 19.2.6 |
| Tentacle | 20.2.0, 20.2.1, 20.2.2, 20.2.3, 20.2.4                 |

Images are tagged as `v<version>` and published to
[`ghcr.io/teran/ceph-container/ceph`](https://ghcr.io/teran/ceph-container/ceph).

## Building locally

Pick a Ceph version and build:

```sh
# Squid
docker build -t ghcr.io/teran/ceph-container/ceph:v19.2.6 --build-arg CEPH_VERSION=19.2.6 .

# Tentacle
docker build -t ghcr.io/teran/ceph-container/ceph:v20.2.4 --build-arg CEPH_VERSION=20.2.4 .
```

To build from a different base image source (the default is
`quay.io/ceph/ceph`):

```sh
docker build -t ghcr.io/teran/ceph-container/ceph:v19.2.6 \
  --build-arg CEPH_SOURCE_IMAGE=quay.io/ceph/ceph \
  --build-arg CEPH_VERSION=19.2.6 .
```

## Running

```sh
docker run --rm -p 8080:8080 -p 3300:3300 \
  -e MON_IP=127.0.0.1 \
  -e CEPH_PUBLIC_NETWORK=0.0.0.0/0 \
  -e CEPH_DEMO_UID=demo \
  -e CEPH_DEMO_ACCESS_KEY=access \
  -e CEPH_DEMO_SECRET_KEY=secret \
  --ulimit nofile=65536:65536 \
  ghcr.io/teran/ceph-container/ceph:v19.2.6
```

The container is ready when the logs print `SUCCESS: RGW on ...`.
