# Caddy + plugin DNS Cloudflare (pour le challenge DNS-01 / certificat wildcard).
# L'image stock caddy:2 ne contient pas ce module → on le compile avec xcaddy.
FROM caddy:2-builder AS builder
RUN xcaddy build \
    --with github.com/caddy-dns/cloudflare

FROM caddy:2
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
