FROM ubuntu:20.04

RUN apt-get update \
  && apt-get install -y apt-transport-https wget curl gnupg uuid-runtime \
  && wget -q -O- 'https://download.ceph.com/keys/release.asc' | apt-key add -

ARG CEPH_VERSION=nautilus

RUN echo "deb https://download.ceph.com/debian-${CEPH_VERSION}/ focal main" > /etc/apt/sources.list.d/ceph.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends ceph-mgr ceph-mon ceph-osd radosgw

COPY setup-ceph.sh /
COPY entrypoint.sh /

ENV CEPH_ROOT=/tmp/ceph
ENV CEPH_CONF=/tmp/ceph/ceph.conf
ENV CEPH_PERSISTENT=false
ENV CEPH_SWIFT_TENANT=test
ENV CEPH_SWIFT_USERNAME=test
ENV CEPH_SWIFT_PASSWORD=test

ENTRYPOINT [ "/entrypoint.sh" ]

EXPOSE 8080

CMD [ "bash", "-c", "trap : TERM INT; sleep infinity & wait" ]
