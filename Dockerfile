FROM scratch

LABEL org.opencontainers.image.title="K1OS"
LABEL org.opencontainers.image.description="K1OS minimal development OS image"
LABEL org.opencontainers.image.source="https://github.com/KEYTRON/K1OS"
LABEL org.opencontainers.image.licenses="Apache-2.0"

COPY rootfs/ /

ENV PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin
ENV HOME=/root
ENV TERM=xterm-256color
ENV LANG=C.UTF-8

WORKDIR /root

CMD ["/usr/bin/fish", "--login"]
