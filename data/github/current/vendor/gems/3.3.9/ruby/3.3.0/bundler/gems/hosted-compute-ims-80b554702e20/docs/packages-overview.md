# Packages overview

IMS consist of the following parts:
- Applications - these are service entry points which are located in the `/cmd` folder. Every application (service component) is separate binary which can be run and deployed independently from other components.
- Packages - these are located in `/internal` folder and are used to organize related Go source files together into a single unit, making them modular, reusable, and maintainable.

## Applications overview

- `twirp` - this app is responsible for all types of API (Admin API, Images API, Internal API)
- `worker` - this app is responsible for running aqueduct-based [worker jobs](./jobs.md#worker-jobs)
- `cronjobs` - this app is responsible for running Kubernetes-based [cron jobs](./jobs.md#cron-jobs)

## Packages overview

IMS consists of a large number of packages which are responsible for the different pieces of image management and image promotion functionality. All packages are located under `internal` folder.

During design of the packages architecture, we are trying to divide code following the "[Single-responsibility principle](https://en.wikipedia.org/wiki/Single-responsibility_principle)" to make package responsibilities clear and to simplify maintenance.

### Main packages

- `internal/azure`
    - Azure layer (wrapper for Azure SDK for Go)
    - Authentication & credentials
    - Provide methods for interacting with Azure resource groups, storage accounts and compute galleries
- `internal/promotion`
    - Provisioning image version, deleting image version, etc
    - Handle provisioning failures (retryable & non-retryable errors)
- `internal/cronjobs`
    - Replication job manages and controls gallery image version replications
- `internal/resources`
    - Manage Azure subscriptions capacity
    - Assign Azure subscriptions to image definitions
    - Define Azure resource layout for images
    - Provide Azure references for image versions
- `internal/twirp`
    - Configure HTTP server
    - Configure hooks and auth
    - Process API requests
    - Convert server models to API models and vice versa
- `internal/store`
    - Database layer
    - CRUD SQL operations for image definitions, image versions, image replications, etc
- `internal/store/mysql`
    - Configure SQL client
    - Setup read and write SQL connections
- `internal/worker`
    - Organize worker pool and create worker instances
    - Retrieve jobs from queue and assign to workers
    - Report job result to aqueduct and handle retries
- `internal/worker/aqueduct`
    - Wrap official aqueduct client
    - Simplify aqueduct client configuration and mocking aqueduct calls
- `internal/worker/queue`
    - Provide worker queue functionality
    - Submit jobs to queue
    - Handle job queues and job payloads
- `internal/vssf-clients/vssf_runner`
    - Client for Vssf Runner service
- `internal/vssf-clients/vssf_token`
    - Client for Vssf Token service


### Common packages

- `internal/config`
    - Main config of IMS service
- `internal/featureflags`
    - Provides functionality to check global feature flag state and feature flag state for owners
- `internal/models`
    - Data models and enums of server layer for image definitions, image versions, image replication, etc
- `internal/utils`
    - A collection of helpful utility functions which can be used by any other package
