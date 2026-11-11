# Hierarchy Resolution

When resolving the effective configuration value for a target, the following hierarchy structures describe the prioritized paths for discovering configuration values:

## Repository

```mermaid

flowchart TD
  Repository --> User
  Repository --> Org
  User --> GHES?
  GHES? -->|no| global
  GHES? -->|yes| Business
  Business --> global
  Org --> Business
```

## Memex Project

```mermaid
flowchart TD
  MemexProject --> User/Org
  User/Org --> global
```

The following targets have no hierarchies defined:

- `Customer`
- `Gist`
- `RepositoryNetwork`
- `Team`
