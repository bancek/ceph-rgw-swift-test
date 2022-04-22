#!/bin/bash

set -e

/setup-ceph.sh

echo
echo 'Ceph ready'

exec "$@"
