FROM alpine:3.12 AS base

MAINTAINER Paul Talbot <prolixalias@gmail.com>

# https://github.com/sgerrand/alpine-pkg-glibc
ARG GLIBC_VERSION=2.31-r0

RUN \
    # apk cache -v sync && \
    apk add certbot certbot-nginx
    # apk -v cache clean && \
    # mkdir /etc/letsencrypt

COPY secret-patch-template.json /
COPY entrypoint.sh /

FROM base AS glibc

RUN \
    set -x && \
    apk add --no-cache -t .deps ca-certificates && \
    # Install glibc on Alpine (required by docker-compose)
    # See also https://github.com/gliderlabs/docker-alpine/issues/11
    wget -q -O /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub && \
    wget https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk && \
    apk add glibc-${GLIBC_VERSION}.apk && \
    rm glibc-${GLIBC_VERSION}.apk && \
    apk del --purge .deps

FROM glibc as ngrok

RUN \
    set -x && \
    # Install ngrok (latest official stable from https://ngrok.com/download).
    apk add --no-cache curl && \
    APKARCH="$(apk --print-arch)" && \
    case "$APKARCH" in \
        aarch64) NGROKARCH="arm64" ;; \
        armhf)   NGROKARCH="arm" ;; \ 
        armv7)   NGROKARCH="arm" ;; \
        armel)   NGROKARCH="arm" ;; \
        x86)     NGROKARCH="386" ;; \
        x86_64)  NGROKARCH="amd64" ;; \
    esac && \
    curl -Lo /ngrok.tgz https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-$NGROKARCH.tgz && \
    tar xvfz /ngrok.tgz && \
    mv ngrok /bin && \
    rm -f /ngrok.tgz && \
    adduser -h /home/ngrok -D -u 6737 ngrok

# Add config script.
COPY --chown=ngrok ngrok.yml /home/ngrok/.ngrok2/
COPY secret-patch-template.json /
# COPY deployment-patch-template.json /
COPY entrypoint.sh /

USER ngrok
ENV USER=ngrok

# Basic sanity check.
RUN ngrok --version

EXPOSE 4040

CMD ["/entrypoint.sh"]
