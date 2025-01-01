# Keeping GHEX containers up to date

## Updating Docker Images

The Dependency Graph API Docker images use the [GitHub base images](https://thehub.github.com/epd/engineering/dev-practicals/containers/container-development/adopt-base-images-for-service/#staying-up-to-date-with-the-latest-base-images)
and are configured to automatically update to the latest version of the base images on a monthly basis using Dependabot.

When a new Enterprise release branch is created, make sure to update `.github/dependabot.yml` to include the new branch.

### Example Dependabot config

```yaml
- package-ecosystem: "docker"
  target-branch: "enterprise-3.7-release"
  directory: "/"
  registries:
    - ghcr
  schedule:
    interval: "monthly"
    time: "21:00"
  labels:
    - "ern:not-customer-facing"
```
