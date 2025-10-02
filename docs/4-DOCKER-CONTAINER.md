# Docker Container for Liquibase CI/CD

The pipeline uses a custom Docker container with all database tools pre-installed. This eliminates the need to install database clients during each workflow run.

## Container Details

**Image Location**: `ghcr.io/{your-org}/{your-repo}/liquibase-tools:latest`

**Base Image**: `ubuntu:24.04`

## What's Included

### Database Tools

- **PostgreSQL Client**: `psql` (postgresql-client package)
- **MySQL Client**: `mysql` (mysql-client package)
- **Oracle Instant Client**: `sqlplus` (basiclite 23.4.0.24.05)
- **SQL Server Tools**: `sqlcmd` (mssql-tools18)

### Development Tools

- **Java**: OpenJDK 17 JRE Headless
- **Liquibase**: Version 4.33.0
- **AWS CLI**: Version 2
- **Utilities**: curl, wget, jq, git, unzip

### JDBC Drivers

All drivers are pre-installed in `/opt/liquibase/lib/`:

- **PostgreSQL**: postgresql-42.7.4.jar
- **MySQL**: mysql-connector-j-9.1.0.jar
- **Oracle**: ojdbc11-23.6.0.24.10.jar
- **SQL Server**: mssql-jdbc-12.8.1.jre11.jar

## Environment Configuration

The container sets up the following environment:

```dockerfile
# Oracle environment
PATH="/opt/oracle/instantclient_23_4:${PATH}"
LD_LIBRARY_PATH="/opt/oracle/instantclient_23_4"

# SQL Server tools
PATH="/opt/mssql-tools18/bin:${PATH}"

# Liquibase
PATH="/opt/liquibase:${PATH}"

# Working directory
WORKDIR /workspace
```

## Building the Container

The container is automatically built when the `Dockerfile` is modified:

```yaml
# Triggers:
on:
  push:
    branches: [main]
    paths:
      - 'Dockerfile'
      - '.github/workflows/build-docker-image.yml'
  workflow_dispatch:
```

### Manual Build

To manually trigger a container build:

```bash
gh workflow run build-docker-image.yml
```

### Build Workflow

Located at `.github/workflows/build-docker-image.yml`, the build:

1. Checks out the repository
2. Sets up Docker Buildx
3. Logs in to GitHub Container Registry
4. Builds and tags the image
5. Pushes to GHCR

**Build time**: ~5-7 minutes

**Image size**: Optimized (~800MB compressed)

## Size Optimizations

The Dockerfile uses several techniques to minimize image size:

1. **Single-layer package installation**: All apt packages installed in one RUN command
2. **Minimal packages**: Uses `--no-install-recommends` flag
3. **Headless JRE**: Uses `openjdk-17-jre-headless` instead of full JDK
4. **Oracle basiclite**: Uses smaller basiclite package instead of full basic client
5. **Aggressive cleanup**: Removes unnecessary files after installation
6. **No development files**: Removes .sym files and other debug symbols

## Using the Container in GitHub Actions

The workflow uses the container via the `container` directive:

```yaml
jobs:
  liquibase:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/${{ github.repository }}/liquibase-tools:latest
      credentials:
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}
```

**Benefits:**
- All tools available immediately (no setup time)
- Consistent environment across all runs
- No need to download/install database clients
- Faster workflow execution

## Troubleshooting

### Container build fails with package errors

**Cause**: Ubuntu package repository changes or network issues.

**Solution**:
- Check Dockerfile for correct package names
- Ensure package repositories are accessible
- Try rebuilding after a few minutes

### Shell syntax errors in workflow

**Cause**: Container uses `/bin/sh` (not bash) by default.

**Solution**: Avoid bash-specific syntax like:
- Here-strings (`<<<`)
- Arrays
- Bash-specific operators

Use POSIX-compliant shell syntax instead.

### Driver not found errors

**Cause**: Liquibase looking for drivers in wrong location.

**Solution**: Set `DRIVER_PATH=""` in configure-database.sh - drivers are automatically loaded from `/opt/liquibase/lib/`.

### Image pull fails with authentication error

**Cause**: GitHub token doesn't have package read permissions.

**Solution**: Ensure GITHUB_TOKEN has `packages: read` permission:
```yaml
permissions:
  contents: read
  packages: read
```

## Customizing the Container

To add additional tools or modify the container:

1. **Edit Dockerfile**:
   ```dockerfile
   # Add your custom tools
   RUN apt-get update && apt-get install -y your-tool \
       && rm -rf /var/lib/apt/lists/*
   ```

2. **Commit and push**:
   ```bash
   git add Dockerfile
   git commit -m "Add custom tool to Docker image"
   git push
   ```

3. **Build automatically triggers** when Dockerfile changes

4. **New workflows use updated image** automatically

## Dockerfile Location

The Dockerfile is located at the repository root: `/Dockerfile`

Key sections:
- **Line 7-20**: Base packages and dependencies
- **Line 23-31**: Oracle Instant Client
- **Line 36-42**: SQL Server tools
- **Line 47-53**: Liquibase installation
- **Line 58-63**: JDBC drivers
- **Line 66-69**: AWS CLI

## Local Development

To use the same environment locally:

```bash
# Build the image locally
docker build -t liquibase-tools .

# Run with mounted workspace
docker run -it --rm \
  -v $(pwd):/workspace \
  -w /workspace \
  liquibase-tools /bin/bash

# Now you have access to all tools
liquibase --version
psql --version
mysql --version
sqlcmd -?
sqlplus -V
```

## Version Management

The container image is tagged with:
- `latest`: Most recent build from main branch
- SHA tags: Specific commit builds (optional)

To use a specific version in workflows:
```yaml
container:
  image: ghcr.io/${{ github.repository }}/liquibase-tools:sha-abc123
```

## Performance Impact

**Before Docker container** (installing tools each run):
- Setup time: ~2-3 minutes
- Multiple downloads and installations
- Variable based on network speed

**After Docker container** (tools pre-installed):
- Pull time: ~30 seconds (cached after first pull)
- No installation needed
- Consistent performance

**Net improvement**: ~2 minutes saved per workflow run

## Security Considerations

- ✅ Image built from official Ubuntu base
- ✅ Packages from official repositories
- ✅ Image stored in GitHub Container Registry (private)
- ✅ Automatic security updates when Dockerfile rebuilt
- ✅ Minimal attack surface (only required tools)

## Future Improvements

Potential optimizations:
- Multi-stage build to further reduce size
- Alpine Linux base (much smaller, but requires musl compatibility)
- Layer caching optimization
- Version pinning for all tools
