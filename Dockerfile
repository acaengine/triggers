FROM crystallang/crystal:0.32.1

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

# These are required for communicating with external services
COPY --from=0 /lib/x86_64-linux-gnu/libnss_dns.so.2 /lib/x86_64-linux-gnu/libnss_dns.so.2
COPY --from=0 /lib/x86_64-linux-gnu/libresolv.so.2 /lib/x86_64-linux-gnu/libresolv.so.2
COPY --from=0 /etc/hosts /etc/hosts

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD ["/engine-triggers", "-c", "http://127.0.0.1:3000/"]
CMD ["/engine-triggers", "-b", "0.0.0.0", "-p", "3000"]
