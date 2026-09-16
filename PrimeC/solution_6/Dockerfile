FROM ubuntu:24.04 AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY sieve.c run.sh author.txt ./
RUN ./run.sh check
FROM ubuntu:24.04
WORKDIR /app
COPY --from=build /app/sieve /app/author.txt ./
ENTRYPOINT ["./sieve"]
