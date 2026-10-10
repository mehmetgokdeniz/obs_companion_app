# Saf Dart runtime + tesseract (CAPTCHA OCR) ile tek aşamalı imaj.
# Taban sürüm, server/pubspec.lock'ın istediği Dart SDK (>=3.11) ile uyumlu
# olmalı; lock, pub get'den ÖNCE kopyalanır ki çözümleme tekrarlanabilir olsun.
FROM dart:3.13 AS build

WORKDIR /app
COPY packages/obs_core ./packages/obs_core
COPY server/pubspec.yaml server/pubspec.lock ./server/
RUN dart pub get --directory ./server

COPY server ./server
RUN dart compile exe server/bin/server.dart -o /app/obs_api

# --- çalışma imajı ---
FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/obs_api /app/obs_api

# Oturum çerezi ve .env bu dizinde saklanır; kalıcı disk olarak bağlayın.
ENV DATA_DIR=/app/data \
    PORT=8080

EXPOSE 8080

# .env dosyası /app/.env konumundan okunur.
ENTRYPOINT ["/app/obs_api"]
