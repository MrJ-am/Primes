FROM rust:1.98.1-bookworm AS build
WORKDIR /app
COPY main.rs unrolled.rs run.sh author.txt ./
RUN ./run.sh check \
    && rustc --edition=2021 -O -C target-cpu=native -C target-feature=-avx512f main.rs -o sieve
FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /app/sieve ./
ENTRYPOINT ["./sieve"]
