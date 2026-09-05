#!/bin/bash
# Single-container Ceph for development and integration testing: one mon,
# one mgr, one OSD (bluestore on a plain directory) and one RGW, plus an
# RGW admin user.
#
# Adapted from /opt/ceph-container/bin/demo (quay.io/ceph/demo) so that it
# runs on the official multi-arch quay.io/ceph/ceph release image. Only the
# mon/mgr/osd/rgw daemons are bootstrapped (no mds, nfs, rbd-mirror, ...).
#
# Environment (same names as the demo image):
#   MON_IP, CEPH_PUBLIC_NETWORK           mon address and public network (required)
#   CEPH_DEMO_UID/ACCESS_KEY/SECRET_KEY   RGW admin user (access/secret required)
#   RGW_FRONTEND_PORT                     beast port (default 8080)
#   CLUSTER / MON_NAME / MGR_NAME / RGW_NAME / MON_PORT
#
# Buckets are NOT created here: modern Ceph (Reef+) only creates buckets via
# the S3 API, so tests/applications should create them through their client.
#
# State lives under /var/lib/ceph and /etc/ceph. A restart with the same
# volumes skips bootstrapping and only starts the daemons.
set -euo pipefail

: "${CLUSTER:=ceph}"
: "${MON_NAME:=demo}"
: "${MGR_NAME:=demo}"
: "${RGW_NAME:=localhost}"
: "${MON_IP:?MON_IP must be set}"
: "${CEPH_PUBLIC_NETWORK:?CEPH_PUBLIC_NETWORK must be set}"
: "${MON_PORT:=3300}"
: "${CEPH_DEMO_UID:=demo}"
: "${CEPH_DEMO_ACCESS_KEY:?CEPH_DEMO_ACCESS_KEY must be set}"
: "${CEPH_DEMO_SECRET_KEY:?CEPH_DEMO_SECRET_KEY must be set}"
: "${RGW_FRONTEND_IP:=0.0.0.0}"
: "${RGW_FRONTEND_PORT:=8080}"
# This image is for testing only and is not production-ready: SSE-C / S3
# crypto and TLS verification are disabled by default so tests can exercise
# them over plain HTTP. Override per-container if needed.
: "${RGW_CRYPT_REQUIRE_SSL:=false}"
: "${RGW_VERIFY_SSL:=false}"

CONF=/etc/ceph/${CLUSTER}.conf
ADMIN_KEYRING=/etc/ceph/${CLUSTER}.client.admin.keyring
MON_KEYRING=/etc/ceph/${CLUSTER}.mon.keyring
MONMAP=/etc/ceph/monmap-${CLUSTER}
MON_DATA_DIR=/var/lib/ceph/mon/${CLUSTER}-${MON_NAME}
MGR_PATH=/var/lib/ceph/mgr/${CLUSTER}-${MGR_NAME}
OSD_ID=0
OSD_PATH=/var/lib/ceph/osd/${CLUSTER}-${OSD_ID}
RGW_PATH=/var/lib/ceph/radosgw/${CLUSTER}-rgw.${RGW_NAME}
RGW_KEYRING=${RGW_PATH}/keyring
MARKER=/var/lib/ceph/I_AM_A_DEMO

# Daemons detach themselves (no -f); logs go to stderr, so `docker logs`
# shows everything.
DAEMON_OPTS=(--cluster "$CLUSTER" --setuser ceph --setgroup ceph \
  --default-log-to-stderr=true --err-to-stderr=true --default-log-to-file=false)
CLI_OPTS=(--cluster "$CLUSTER")

log() { echo "$(date '+%F %T')  ceph-demo: $*"; }

# apply_config_overrides appends any CONFIG_<SCOPE>_<SETTING>=<value> env vars
# to the ceph.conf as their own section blocks. Ceph merges duplicate
# sections, so appending works even when the section already exists above.
#
#   CONFIG_GLOBAL_<setting>  -> [global]
#   CONFIG_MON_<setting>     -> [mon]
#   CONFIG_OSD_<setting>     -> [osd]
#   CONFIG_MGR_<setting>     -> [mgr]
#   CONFIG_RGW_<setting>     -> [client.rgw.${RGW_NAME}]
#   CONFIG_CLIENT_<setting>  -> [client]
#
# <setting> is lowercased and its underscores become spaces to match the
# ceph.conf key syntax (e.g. CONFIG_RGW_CRYPT_REQUIRE_SSL -> "crypt require ssl").
apply_config_overrides() {
  local conf="$1" var value rest scope setting section

  for var in $(env | grep -E '^CONFIG_' | cut -d= -f1 || true); do
    value="${!var}"
    rest="${var#CONFIG_}"
    scope="${rest%%_*}"
    setting="${rest#*_}"
    setting=$(printf '%s' "$setting" | tr '[:upper:]' '[:lower:]' | tr '_' ' ')

    if [ -z "$setting" ]; then
      log "WARN: CONFIG_ env var $var has no setting; ignoring"
      continue
    fi

    case "$scope" in
      GLOBAL) section="global" ;;
      MON)    section="mon" ;;
      OSD)    section="osd" ;;
      MGR)    section="mgr" ;;
      RGW)    section="client.rgw.${RGW_NAME}" ;;
      CLIENT) section="client" ;;
      *)
        log "WARN: unknown CONFIG_ scope '$scope' in $var; ignoring"
        continue
        ;;
    esac

    log "applying config override: [$section] $setting = $value"
    cat >>"$conf" <<EOF

[$section]
$setting = $value
EOF
  done
}

write_conf() {
  mkdir -p /etc/ceph /var/lib/ceph
  local fsid
  fsid=$(cat /proc/sys/kernel/random/uuid)
  cat >"$CONF" <<EOF
[global]
fsid = $fsid
mon initial members = ${MON_NAME}
mon host = v2:${MON_IP}:${MON_PORT}/0
public network = ${CEPH_PUBLIC_NETWORK}
cluster network = ${CEPH_PUBLIC_NETWORK}
auth_allow_insecure_global_id_reclaim = false
osd crush chooseleaf type = 0
osd pool default size = 1
osd pool default min size = 1
osd objectstore = bluestore
bluestore block create = true
bluestore block size = 10737418240
osd max object name len = 256
osd max object namespace len = 64
mon allow pool size one = true
mon warn on pool no redundancy = false
mon data avail warn = 5

[osd.${OSD_ID}]
osd data = ${OSD_PATH}

[client.rgw.${RGW_NAME}]
rgw dns name = ${RGW_NAME}
rgw crypt require ssl = ${RGW_CRYPT_REQUIRE_SSL}
rgw verify ssl = ${RGW_VERIFY_SSL}
rgw frontends = beast endpoint=${RGW_FRONTEND_IP}:${RGW_FRONTEND_PORT}
EOF

  apply_config_overrides "$CONF"
}

bootstrap_mon() {
  write_conf
  local fsid
  fsid=$(awk '/^fsid/ {print $NF}' "$CONF")
  ceph-authtool "$ADMIN_KEYRING" --create-keyring --gen-key -n client.admin \
    --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
  ceph-authtool "$MON_KEYRING" --create-keyring --gen-key -n mon. --cap mon 'allow *'
  ceph-authtool "$MON_KEYRING" --import-keyring "$ADMIN_KEYRING"
  monmaptool --create --add "$MON_NAME" "${MON_IP}:${MON_PORT}" --fsid "$fsid" "$MONMAP"
  mkdir -p "$MON_DATA_DIR"
  chown -R ceph:ceph /etc/ceph "$MON_DATA_DIR"
  ceph-mon --setuser ceph --setgroup ceph --cluster "$CLUSTER" --mkfs -i "$MON_NAME" \
    --inject-monmap "$MONMAP" --keyring "$MON_KEYRING" --mon-data "$MON_DATA_DIR"
  rm -f "$MONMAP"
}

start_mon() {
  ceph-mon "${DAEMON_OPTS[@]}" -i "$MON_NAME" --mon-data "$MON_DATA_DIR" --public-addr "$MON_IP"
  for _ in $(seq 1 60); do
    if ceph "${CLI_OPTS[@]}" -s >/dev/null 2>&1; then return; fi
    sleep 1
  done
  log "ERROR: mon did not come up"
  exit 1
}

bootstrap_mgr() {
  mkdir -p "$MGR_PATH"
  ceph "${CLI_OPTS[@]}" auth get-or-create mgr."$MGR_NAME" \
    mon 'allow profile mgr' mds 'allow *' osd 'allow *' -o "$MGR_PATH"/keyring
  chown -R ceph:ceph "$MGR_PATH"
}

start_mgr() {
  ceph-mgr "${DAEMON_OPTS[@]}" -i "$MGR_NAME"
}

bootstrap_osd() {
  mkdir -p "$OSD_PATH"
  ceph "${CLI_OPTS[@]}" auth get-or-create osd."$OSD_ID" \
    mon 'allow profile osd' osd 'allow *' mgr 'allow profile osd' -o "$OSD_PATH"/keyring
  chown -R ceph:ceph "$OSD_PATH"
  ceph-osd --cluster "$CLUSTER" --setuser ceph --setgroup ceph --osd-data "$OSD_PATH" --mkfs -i "$OSD_ID"
  chown -R ceph:ceph "$OSD_PATH"
}

start_osd() {
  ceph-osd "${DAEMON_OPTS[@]}" -i "$OSD_ID"
  for _ in $(seq 1 120); do
    if ceph "${CLI_OPTS[@]}" osd stat 2>/dev/null | grep -q '1 up'; then return; fi
    sleep 1
  done
  log "ERROR: osd.${OSD_ID} did not come up"
  exit 1
}

bootstrap_rgw() {
  mkdir -p "$RGW_PATH"
  ceph "${CLI_OPTS[@]}" auth get-or-create client.rgw."$RGW_NAME" \
    osd 'allow rwx' mon 'allow rw' -o "$RGW_KEYRING"
  chown -R ceph:ceph "$RGW_PATH"
}

start_rgw() {
  radosgw "${DAEMON_OPTS[@]}" -n client.rgw."$RGW_NAME" -k "$RGW_KEYRING"
  for _ in $(seq 1 120); do
    if curl -sf "http://127.0.0.1:${RGW_FRONTEND_PORT}/" >/dev/null 2>&1; then return; fi
    sleep 1
  done
  log "ERROR: rgw did not answer on port ${RGW_FRONTEND_PORT}"
  exit 1
}

bootstrap_demo_user() {
  radosgw-admin "${CLI_OPTS[@]}" user create --uid="$CEPH_DEMO_UID" \
    --display-name="Ceph demo user" \
    --access-key="$CEPH_DEMO_ACCESS_KEY" --secret-key="$CEPH_DEMO_SECRET_KEY" >/dev/null
  radosgw-admin "${CLI_OPTS[@]}" caps add --uid="$CEPH_DEMO_UID" \
    --caps="buckets=*;users=*;usage=*;metadata=*" >/dev/null
}

if [ -e "$MARKER" ]; then
  log "existing demo cluster found, starting daemons"
  start_mon; start_mgr; start_osd; start_rgw
else
  log "bootstrapping a new demo cluster"
  bootstrap_mon; start_mon
  bootstrap_mgr; start_mgr
  bootstrap_osd; start_osd
  bootstrap_rgw; start_rgw
  bootstrap_demo_user
  touch "$MARKER"
fi
log "SUCCESS: RGW on ${RGW_FRONTEND_IP}:${RGW_FRONTEND_PORT}, admin user ${CEPH_DEMO_UID}"

# Stay in the foreground and forward the stop signal to the daemons.
stop() { local d; for d in radosgw ceph-osd ceph-mgr ceph-mon; do pkill -TERM -x "$d" 2>/dev/null || true; done; exit 0; }
trap stop TERM INT
while true; do
  sleep 3600 &
  wait $!
done
