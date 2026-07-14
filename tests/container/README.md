# Container Acceptance Tests

Contract tests for the Observatory MediaWiki Docker image
(`ghcr.io/phosphene/observatory-mediawiki`).

## What These Test

**Not the code.** The code is tested by 108 PHPUnit tests in `book-decompose/`.

**The runtime environment.** These tests prove the built Docker image has the
binaries, files, and configuration the code needs to run.

| Test | What it proves |
|------|---------------|
| Pandoc installed | DownloadBook can export PDF/EPUB/MD |
| Pandoc converts HTML→PDF | Not just present but functional |
| Pandoc converts HTML→EPUB | EPUB export works |
| wkhtmltopdf installed | PdfBook can export page PDFs |
| PHP 8.3 available | Runtime matches our code target |
| Lua sandbox available | Scribunto/Lua modules work |
| ImageMagick available | Thumbnail generation works |
| MediaWiki files present | Core install intact |
| DownloadBook extension present | Export extension installed |

## Running

```bash
# Using Google Container Structure Tests
container-structure-test test \
  --image ghcr.io/phosphene/observatory-mediawiki:TAG \
  --config tests/container/observatory-image-tests.yaml

# Or manually (sidecar probe pattern)
CONTAINER_ID=$(docker run -d ghcr.io/phosphene/observatory-mediawiki:TAG)
docker exec $CONTAINER_ID pandoc --version
docker exec $CONTAINER_ID wkhtmltopdf --version
docker exec $CONTAINER_ID sh -c "echo '<h1>Test</h1>' | pandoc -o /tmp/test.pdf && test -s /tmp/test.pdf && echo OK"
docker kill $CONTAINER_ID && docker rm $CONTAINER_ID
```

## Integration with CI

Add to `phosphene/observatory-mediawiki/.github/workflows/build-push.yml`
after the image build step:

```yaml
- name: Container Acceptance Tests
  run: |
    container-structure-test test \
      --image ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.meta.outputs.version }} \
      --config tests/container/observatory-image-tests.yaml
```

## Origin

Created 2026-07-14 after Reynard Loki reported PDF download failure.
Root cause: pandoc not in V2 image (was in Anton's V1 Taqasta image).

Testing philosophy: acceptance tests prove the contract, smoke tests
verify the environment. These are acceptance tests for the container.
See `team/platform/testing-philosophy.md`.
