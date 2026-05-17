# docker build -t moshix/bricks;latest .
# docker run --name bricks_ts -d -ti -p 23:2300/tcp  \
# -e BRICKS_dns_host=mainframe.ibmexample.com \
# -v ${PWD}/data:/srv/bricks/data:rw \
# -v ${PWD}/runtime:/srv/bricks/runtime:ro \
# moshix/bricks:latest
#
# uses m4 template in entrypoint.sh to configure
# entrypoint.sh bootstraps
# volumes are availble to bind mount
#
# admin: (e.g add users/acls) docker exec -ti bricks_ti ./add_brick_user.bash

FROM alpine:latest

RUN apk add --no-cache m4 acme.sh openssl coreutils libc6-compat && \
    addgroup -S -g 1001 bricksgroup && \
    adduser -S -u 1001 -G bricksgroup -h /srv/bricks -s /sbin/nologin bricksuser
ENV TZ=Etc/UTC
WORKDIR /srv/bricks
COPY --chown=bricksuser:bricksgroup . .
RUN rm -Rf .git && \
    chmod -R 755 /srv/bricks/entrypoint.sh && \
    mkdir -p data runtime logs && \
    chmod 770 data runtime
VOLUME ["/srv/bricks/data", "/srv/bricks/runtime"]
EXPOSE 2300 2023 9000
USER bricksuser
ENTRYPOINT ["./entrypoint.sh"]
CMD ["-no-console"]
