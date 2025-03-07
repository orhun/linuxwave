FROM eloitor/zig:0.14.0 as builder
RUN apk update
RUN apk add --no-cache git
WORKDIR /app
COPY . .
RUN zig build --release=safe

FROM alpine:3.8
WORKDIR /app
COPY --from=builder /app/zig-out/bin/linuxwave /usr/local/bin
RUN touch output.wav && \
  chown 1000:1000 output.wav
USER 1000:1000
ENTRYPOINT [ "linuxwave" ]
