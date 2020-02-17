FROM crystallang/crystal:0.33.0-alpine

WORKDIR /app

# Install shards for caching
COPY shard.yml shard.yml
RUN shards install --production

# Add src
COPY ./src /app/src

# Build application
RUN crystal build --error-trace --release /app/src/engine-triggers.cr

# Extract dependencies
RUN ldd /app/engine-triggers | tr -s '[:blank:]' '\n' | grep '^/' | \
    xargs -I % sh -c 'mkdir -p $(dirname deps%); cp % deps%;'

# Build a minimal docker image
FROM scratch
WORKDIR /
COPY --from=0 /app/deps /
COPY --from=0 /app/engine-triggers /engine-triggers
COPY --from=0 /etc/hosts /etc/hosts

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/engine-triggers", "-c", "http://127.0.0.1:3000/"]
CMD ["/engine-triggers", "-b", "0.0.0.0", "-p", "3000"]
