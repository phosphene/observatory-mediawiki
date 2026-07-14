#!/usr/bin/env bash
set -eo pipefail

# Sidecar-Driven Probe for Observatory MediaWiki Image
#
# Spins up the built image, waits for the health endpoint,
# verifies PDF export capability, tears down.
#
# Usage: ./sidecar-probe.sh ghcr.io/phosphene/observatory-mediawiki:TAG
#
# Exit 0 = image is deployable
# Exit 1 = image fails contract

IMAGE="${1:?Usage: $0 IMAGE_TAG}"
CONTAINER_NAME="observatory-probe-$$"
PROBE_PORT=18080
TIMEOUT=60

echo "=== Observatory Image Sidecar Probe ==="
echo "Image: $IMAGE"
echo ""

# 1. Start the container
echo "[1] Starting container..."
CONTAINER_ID=$(docker run -d \
  --name "$CONTAINER_NAME" \
  -p "$PROBE_PORT:80" \
  -e MW_DB_SERVER=localhost \
  -e MW_DB_NAME=test \
  "$IMAGE")

cleanup() {
  echo "[cleanup] Stopping and removing container..."
  docker kill "$CONTAINER_NAME" 2>/dev/null || true
  docker rm "$CONTAINER_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# 2. Wait for Apache to respond
echo "[2] Waiting for Apache (${TIMEOUT}s timeout)..."
SECONDS=0
until curl --output /dev/null --silent --head --fail "http://localhost:$PROBE_PORT/"; do
  if [ "$SECONDS" -ge "$TIMEOUT" ]; then
    echo "FAIL: Apache did not respond within ${TIMEOUT}s"
    docker logs "$CONTAINER_NAME" 2>&1 | tail -20
    exit 1
  fi
  sleep 2
done
echo "    Apache responded in ${SECONDS}s"

# 3. Verify Pandoc inside the container
echo "[3] Verifying Pandoc..."
PANDOC_VERSION=$(docker exec "$CONTAINER_NAME" pandoc --version | head -1)
if [ -z "$PANDOC_VERSION" ]; then
  echo "FAIL: Pandoc not found in container"
  exit 1
fi
echo "    $PANDOC_VERSION"

# 4. Verify Pandoc can convert
echo "[4] Testing HTML→PDF conversion..."
docker exec "$CONTAINER_NAME" sh -c \
  "echo '<h1>Probe Test</h1><p>PDF export contract.</p>' > /tmp/probe.html && \
   pandoc /tmp/probe.html -o /tmp/probe.pdf && \
   test -s /tmp/probe.pdf"
if [ $? -ne 0 ]; then
  echo "FAIL: Pandoc conversion failed"
  exit 1
fi
echo "    HTML→PDF: OK"

# 5. Verify wkhtmltopdf
echo "[5] Verifying wkhtmltopdf..."
WKHTML_VERSION=$(docker exec "$CONTAINER_NAME" wkhtmltopdf --version 2>&1 | head -1)
if [ -z "$WKHTML_VERSION" ]; then
  echo "FAIL: wkhtmltopdf not found in container"
  exit 1
fi
echo "    $WKHTML_VERSION"

# 6. Verify PHP + extensions
echo "[6] Verifying PHP..."
PHP_VERSION=$(docker exec "$CONTAINER_NAME" php -v | head -1)
echo "    $PHP_VERSION"
docker exec "$CONTAINER_NAME" php -m | grep -q luasandbox || { echo "FAIL: luasandbox missing"; exit 1; }
echo "    luasandbox: OK"

echo ""
echo "=== ALL PROBES PASSED ==="
echo "Image $IMAGE is deployable."
exit 0
