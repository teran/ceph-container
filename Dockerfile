# syntax=docker/dockerfile:1
#
# Ceph single-container demo image (mon, mgr, osd, rgw) for integration
# testing in go-docker-testsuite.
#
# Built on top of the official multi-arch quay.io/ceph/ceph release image, so
# the SAME Dockerfile produces amd64 and arm64 images (both are published for
# every Ceph release tag).
#
# Build (single arch):
#   docker build -t ceph-demo:squid    --build-arg CEPH_VERSION=19.2.6 contrib/ceph
#   docker build -t ceph-demo:tentacle --build-arg CEPH_VERSION=20.2.4 contrib/ceph
#
# Build (multi-arch amd64 + arm64):
#   docker buildx build --platform linux/amd64,linux/arm64 \
#       -t ceph-demo:19.2.6 --build-arg CEPH_VERSION=19.2.6 contrib/ceph
#
# Run (mon 3300, rgw 8080; ulimit is required, otherwise bootstrap is very slow):
#   docker run --rm -p 8080:8080 -p 3300:3300 \
#     -e MON_IP=127.0.0.1 \
#     -e CEPH_PUBLIC_NETWORK=0.0.0.0/0 \
#     -e CEPH_DEMO_UID=demo \
#     -e CEPH_DEMO_ACCESS_KEY=access \
#     -e CEPH_DEMO_SECRET_KEY=secret \
#     --ulimit nofile=65536:65536 \
#     ceph-demo:squid
#
# Wait for readiness in the logs:  "SUCCESS: RGW on ..."

# Semantic Ceph version, e.g. 19.2.6 (squid) or 20.2.4 (tentacle).
# The published quay.io/ceph/ceph tags are prefixed with "v".
ARG CEPH_VERSION=20.2.4
# Base image source (defaults to the official quay.io image; CI overrides it
# via build-arg CEPH_SOURCE_IMAGE, mirroring runityru/cephctl).
ARG CEPH_SOURCE_IMAGE=quay.io/ceph/ceph
FROM ${CEPH_SOURCE_IMAGE}:v${CEPH_VERSION}

# Demo bootstrap entrypoint (mon, mgr, osd, rgw only).
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Sensible demo defaults; every one can be overridden at runtime.
ENV CLUSTER=ceph \
    MON_NAME=demo \
    MGR_NAME=demo \
    RGW_NAME=localhost \
    MON_PORT=3300 \
    RGW_FRONTEND_IP=0.0.0.0 \
    RGW_FRONTEND_PORT=8080 \
    CEPH_DEMO_UID=demo

# Override the base image entrypoint with our demo bootstrap script.
ENTRYPOINT ["/entrypoint.sh"]
