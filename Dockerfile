FROM crystallang/crystal:0.35.0-alpine

WORKDIR /app

# Add trusted CAs for communicating with external services
RUN apk update && apk add --no-cache ca-certificates tzdata && update-ca-certificates

# Install shards for caching
COPY shard.yml shard.yml
COPY shard.lock shard.lock

RUN shards install --production

# Add src
COPY ./src /app/src

# Build application
ENV UNAME_AT_COMPILE_TIME=true
RUN crystal build --release --debug --error-trace /app/src/app.cr -o triggers

# Extract dependencies
RUN ldd /app/triggers | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Create a non-privileged user, defaults are appuser:10001
ARG IMAGE_UID="10001"
ENV UID=$IMAGE_UID
ENV USER=appuser

# See https://stackoverflow.com/a/55757473/12429735RUN
RUN adduser \
    --disabled-password \
    --gecos "" \
    --home "/nonexistent" \
    --shell "/sbin/nologin" \
    --no-create-home \
    --uid "${UID}" \
    "${USER}"

# Build a minimal docker image
FROM scratch
WORKDIR /
COPY --from=0 /app/deps /
COPY --from=0 /app/triggers /triggers
COPY --from=0 /etc/hosts /etc/hosts

# These provide certificate chain validation where communicating with external services over TLS
COPY --from=0 /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Copy the user information over
COPY --from=0 /etc/passwd /etc/passwd
COPY --from=0 /etc/group /etc/group

# Use an unprivileged user.
USER appuser:appuser

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/triggers", "-c", "http://127.0.0.1:3000/"]
CMD ["/triggers", "-b", "0.0.0.0", "-p", "3000"]
