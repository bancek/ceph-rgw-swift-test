# Ceph RGW Swift test image

Usage:

```sh
docker run --rm -it -p 8080:8080 bancek/ceph-rgw-swift-test

curl -i -H "X-Auth-User: test:test" -H "X-Auth-Key: test" http://localhost:8080/auth/v1.0

curl -i -H "X-Auth-Token: YOURTOKEN" http://localhost:8080/swift/v1/test -X PUT

curl -i -H "X-Auth-Token: YOURTOKEN" http://localhost:8080/swift/v1/test/test -X PUT -d 'test'

# persist data (needs privileged mode to create a loop back device)
docker run --privileged=true -it -p 8080:8080 -e CEPH_PERSISTENT=true -v `pwd`/cephdata:/tmp/ceph bancek/ceph-rgw-swift-test
```

Build:

```sh
docker build -t bancek/ceph-rgw-swift-test .
```
