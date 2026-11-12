# sweagentd Agent API Documentation

This directory contains the documentation and OpenAPI specifications for the sweagentd Agent API.

## Overview

The sweagentd Agent API provides endpoints for GitHub Copilot agents to interact with the sweagentd service during job execution. The API enables agents to:

- Retrieve job metadata and configuration
- Report incremental progress updates
- Store and retrieve execution history
- Integrate with custom agents and tools

## Purpose

The Agent API serves as the primary interface between agent runtimes and the sweagentd service. It allows agents to:

1. **Access Job Details**: Retrieve the problem statement, custom agent configuration, and other metadata needed to execute a job
2. **Track Progress**: Report structured progress updates that can be displayed in various UIs (github.com mission control, VS Code, etc.)
3. **Maintain History**: Access progress from previous job executions to enable context-aware agent behavior
4. **Enable Extensibility**: Support both well-known (first-party) and custom (third-party) progress schemas

## Structure

```plaintext
api/
├── README.md              # This file - general API documentation
└── agent/
    ├── README.md          # Detailed Agent API documentation
    ├── openapi.yaml       # OpenAPI specification for the Agent API
    └── progress/
        ├── README.md      # Progress system documentation
        ├── copilot/       # Well-known progress schemas (copilot namespace)
        └── sessions-legacy/  # Deprecated legacy progress schemas
            ├── error.yaml
            └── log.yaml
```

## Key Concepts

### Jobs

A **job** represents a unit of work that an agent needs to execute. Jobs contain:

- A unique identifier
- A problem statement describing the task
- Custom agent configuration (if applicable)
- Organization-level instructions

### Progress

**Progress** represents incremental updates about a job's execution. Progress updates are polymorphic and support:

- Well-known schemas (first-party) that integrate with system UIs
- Custom schemas (third-party) for integrator-specific needs

Progress updates are identified by three properties:

- `namespace`: Groups related progress schemas (e.g., "copilot", "claude.code")
- `kind`: The specific type of update within a namespace (e.g., "error", "log")
- `version`: Schema version for the payload

### Authentication

All API endpoints require:

- A GitHub App installation token (Bearer authentication)
- A job-specific nonce (`X-GitHub-Job-Nonce` header) for request validation

## Documentation

- **[Agent API Reference](./agent/README.md)**: Detailed API documentation including endpoints, request/response formats, and usage examples
- **[Progress System](./agent/progress/README.md)**: In-depth documentation on the progress system, schemas, and extensibility

## API Version

Current version: **0.1.0**

## Base URL

```plaintext
https://api.githubcopilot.com/agent/swe
```

## Quick Start

1. Retrieve a job:

   ```bash
   GET /agent/jobs/{jobID}
   ```

2. Create a progress update:

   ```bash
   POST /agent/jobs/{jobID}/progress
   ```

3. List progress history:

   ```bash
   GET /agent/jobs/{jobID}/progress?namespace=copilot&history=true
   ```

See the [Agent API documentation](./agent/README.md) for complete details and examples.
