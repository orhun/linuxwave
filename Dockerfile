FROM euantorano/zig:0.10.1 as builder
RUN apk update
RUN apk add --no-cache git
WORKDIR /app
COPY . .
RUN git submodule update --init --recursive && \
  zig build -Drelease-safe

FROM alpine:3.8
WORKDIR /app
COPY --from=builder /app/zig-out/bin/linuxwave /usr/local/bin
RUN touch output.wav && \
  chown 1000:1000 output.wav
USER 1000:1000
ENTRYPOINT [ "linuxwave" ]
