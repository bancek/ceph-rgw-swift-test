#!/bin/bash
# from https://github.com/ceph/go-ceph/blob/master/micro-osd.sh
#
#    Copyright (C) 2013,2014 Loic Dachary <loic@dachary.org>
#    Copyright (C) 2022 Luka Zakrajsek <luka@bancek.net>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU Affero General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU Affero General Public License for more details.
#
#    You should have received a copy of the GNU Affero General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
set -e
set -x
set -u

LOG_DIR=$CEPH_ROOT/log
MON_DATA=$CEPH_ROOT/mon
MDS_DATA=$CEPH_ROOT/mds
MOUNTPT=$MDS_DATA/mnt
OSD_DATA=$CEPH_ROOT/osd
RGW_DATA=$CEPH_ROOT/radosgw
MDS_NAME="Z"
MON_NAME="a"
MGR_NAME="x"
RGW_ID="r"

CEPH_LOOPBACK=`losetup -f`

if [ ! -f "$CEPH_ROOT/initialized" ] || [ "$CEPH_PERSISTENT" != "true" ]; then
  rm -Rf $CEPH_ROOT/*
  mkdir -p "${LOG_DIR}" "${MON_DATA}" "${OSD_DATA}" "${MDS_DATA}" "${MOUNTPT}" "${RGW_DATA}"

  set +e

  if [ "$CEPH_PERSISTENT" == "true" ]; then
    read -r -d '' OST_STORE_CONFIG <<EOF
osd objectstore = bluestore
bluestore = true
bluestore block path = ${CEPH_LOOPBACK}
EOF
  else
    read -r -d '' OST_STORE_CONFIG <<EOF
osd objectstore = memstore
EOF
  fi

  set -e

  # cluster wide parameters
  cat > "$CEPH_ROOT/ceph.conf" <<EOF
[global]
fsid = $(uuidgen)
osd crush chooseleaf type = 0
run dir = ${CEPH_ROOT}/run
auth cluster required = none
auth service required = none
auth client required = none
osd pool default size = 1
mon host = 127.0.0.1
[mds.${MDS_NAME}]
host = 127.0.0.1
[mon.${MON_NAME}]
log file = ${LOG_DIR}/mon.log
chdir = ""
mon cluster log file = ${LOG_DIR}/mon-cluster.log
mon data = ${MON_DATA}
mon data avail crit = 0
mon addr = 127.0.0.1
mon allow pool delete = true
[osd.0]
log file = ${LOG_DIR}/osd.log
chdir = ""
osd data = ${OSD_DATA}
osd journal = ${OSD_DATA}.journal
osd journal size = 100
${OST_STORE_CONFIG}
osd class load list = *
osd class default list = *
[client.rgw.${RGW_ID}]
rgw enable usage log = true
rgw usage log tick interval = 1
rgw usage log flush threshold = 1
rgw usage max shards = 32
rgw usage max user shards = 1
log file = /var/log/ceph/client.rgw.${RGW_ID}.log
rgw frontends = civetweb port=8080
EOF

  # start an osd
  ceph-mon --id "${MON_NAME}" --mkfs --keyring /dev/null
  touch "${MON_DATA}/keyring"
  ceph-mon --id "${MON_NAME}"

  # start an osd
  if [ "$CEPH_PERSISTENT" == "true" ]; then
    truncate -s 1G "$OSD_DATA/loopback"
    losetup -d "${CEPH_LOOPBACK}" || true
    losetup -P "${CEPH_LOOPBACK}" "$OSD_DATA/loopback"
  fi
  OSD_ID=$(ceph osd create)
  ceph osd crush add "osd.${OSD_ID}" 1 root=default
  ceph-osd --id "${OSD_ID}" --mkjournal --mkfs
  ceph-osd --id "${OSD_ID}" || ceph-osd --id "${OSD_ID}" || ceph-osd --id "${OSD_ID}"

  # start a manager
  ceph-mgr --id ${MGR_NAME}

  # start an rgw
  ceph auth get-or-create client.rgw."${RGW_ID}" osd 'allow rwx' mon 'allow rw' -o "${RGW_DATA}/keyring"
  radosgw -n "client.rgw.${RGW_ID}" -k "${RGW_DATA}/keyring"
  timeout 60 sh -c 'until [ $(ceph -s | grep -c "rgw:") -eq 1 ]; do echo "waiting for rgw to show up" && sleep 1; done'
  radosgw-admin user create --uid="$CEPH_SWIFT_TENANT" --display-name="$CEPH_SWIFT_TENANT"
  radosgw-admin subuser create --uid="$CEPH_SWIFT_TENANT" --subuser="$CEPH_SWIFT_TENANT:$CEPH_SWIFT_USERNAME" --access=full
  radosgw-admin key create --subuser="$CEPH_SWIFT_TENANT:$CEPH_SWIFT_USERNAME" --key-type=swift --secret-key "$CEPH_SWIFT_PASSWORD"

  touch "$CEPH_ROOT/initialized"
else
  rm -Rf "${CEPH_ROOT}/run"

  if [ "$CEPH_PERSISTENT" == "true" ]; then
    losetup -d "${CEPH_LOOPBACK}" || true
    losetup -P "${CEPH_LOOPBACK}" "$OSD_DATA/loopback"
  fi

  # start an osd
  ceph-mon --id "${MON_NAME}"

  # start an osd
  OSD_ID=0
  ceph-osd --id "${OSD_ID}"

  # start a manager
  ceph-mgr --id ${MGR_NAME}

  # start an rgw
  radosgw -n client.rgw."${RGW_ID}" -k "${RGW_DATA}/keyring"
  timeout 60 sh -c 'until [ $(ceph -s | grep -c "rgw:") -eq 1 ]; do echo "waiting for rgw to show up" && sleep 1; done'
fi

# test the setup
ceph --version
ceph status

# wait for rgw
timeout 60 sh -c 'while ! curl http://localhost:8080 2>/dev/null; do echo "waiting for rgw web server to start" && sleep 1; done; echo'
