FROM crystallang/crystal:0.31.1

WORKDIR /app

# Install shards for caching
COPY shard.yml shard.yml
RUN shards install --production

# Add src
COPY ./src /app/src

# Build application
RUN crystal build --release /app/src/app.cr -o engine-triggers

# Run the app binding on port 3000
EXPOSE 3000
HEALTHCHECK CMD wget --spider localhost:3000/
CMD ["/app/engine-triggers", "-b", "0.0.0.0", "-p", "3000"]
