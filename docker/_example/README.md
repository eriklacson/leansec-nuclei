# Local Docker Deployment — Template

This folder is a **template**. Copy it to `deployments/<your-client>/` inside
the repo checkout to set up a local Docker scan.

## What you need

- Docker installed
- This repo cloned locally
- The scanner image built (see below)

## Setup

1. **Copy this folder** to your deployment folder:
   ```bash
   cp -r docker/_example/ deployments/<your-client>/
   cd deployments/<your-client>/
   ```
   The `deployments/<client>/` folder is gitignored.

2. **Populate `targets.txt`** with real external URLs (one per line).

3. **Copy `.env.example` to `.env`** and set `CLIENT=<your-client>`.

4. **Build the image** (build context is repo root, not `docker/`):
   ```bash
   docker build -f docker/Dockerfile.local -t leansecurity/leansec-nuclei:local .
   ```

5. **Run the scan** from the repo root:
   ```bash
   docker run --rm \
     --env-file deployments/<your-client>/.env \
     -v "$(pwd)/deployments:/app/deployments:ro" \
     -v "$(pwd)/results:/app/results" \
     leansecurity/leansec-nuclei:local
   ```

Results land in `results/<your-client>/YYYY-MM/` on the host.

## Options

**Skip template updates** (faster for repeated local runs):
```bash
docker run --rm \
  --env-file deployments/<your-client>/.env \
  -e UPDATE_TEMPLATES=false \
  -v "$(pwd)/deployments:/app/deployments:ro" \
  -v "$(pwd)/results:/app/results" \
  leansecurity/leansec-nuclei:local
```

**Pin the Nuclei version** at build time:
```bash
docker build -f docker/Dockerfile.local \
  --build-arg NUCLEI_VERSION=vX.Y.Z \
  -t leansecurity/leansec-nuclei:local .
```

## See also

- [`docs/setup-guide.md`](../../docs/setup-guide.md)
- [`docker/Dockerfile.local`](../Dockerfile.local) — image definition
- [`docker/entrypoint.sh`](../entrypoint.sh) — container entry point
