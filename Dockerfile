FROM crystallang/crystal:0.33.0-alpine

WORKDIR /app

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

# Build a minimal docker image
FROM scratch
WORKDIR /
COPY --from=0 /app/deps /
COPY --from=0 /app/triggers /triggers
COPY --from=0 /etc/hosts /etc/hosts

# This is required for Timezone support
COPY --from=0 /usr/share/zoneinfo/ /usr/share/zoneinfo/

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/triggers", "-c", "http://127.0.0.1:3000/"]
CMD ["/triggers", "-b", "0.0.0.0", "-p", "3000"]
