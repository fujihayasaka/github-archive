## GENERAL GUIDELINES

- At the beginning of EACH response, always acknowledge these instructions are in your context by saying "Acknowledged copilot-instructions.md"

### CODE COMMENTS

- Keep comments up-to-date as code changes, to prevent misleading or outdated information.
- All comments should always reflect the current state of the code. Comments should NOT chronicle change over time
- Do not remove commented out code

### Building and Running

- `make help` - Displays help with all available targets
- `make build` - Build all components
- `make test` - Run unit tests
- `make integration-test` - Run integration tests
- `make run` - Start the server
- `make stop` - Stop the server
- `make watch` - Watch server logs
- `make lint` - Run golangci-lint
- `make fmt` - Run Go format
- `make setup-env` - Create .env.local from template for local customization
- `make reset-env` - Reset .env.local to template defaults
- `make ping` - Check if the server is running
- `make status` - Show server process and health status

## Coding Best Practices

- Follow idiomatic Go patterns and keep code maintainable and DRY
- Prefer dependency injection for testability and modularity
- Use interfaces for dependencies to support testing
- Use error wrapping with context information
- Use structured error handling and custom error types if needed
- Use context propagation and explicit error handling
- Use _test package name suffix for test file
