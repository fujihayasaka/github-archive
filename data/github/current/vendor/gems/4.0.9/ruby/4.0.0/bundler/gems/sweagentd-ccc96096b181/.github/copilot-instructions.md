# sweagentd Engineering Guidelines

These guidelines apply to all changes made to the sweagentd Go service.

## Go Code Changes

- We lint our Go code with `golangci-lint` to find problematic coding patterns.
   - Running `script/lint` from the repository root will check the code for linting errors.
   - You **MUST** run `script/lint` before finishing your work or using tools which commit changes/report progress (e.g. **report_progress**).
   - Changes that have lint errors will fail in CI.
- We enforce code formatting with `gofmt`.
   - Running `make format` from the repository root will automatically format the Go code.
   - You **MUST** run `make format` before finishing your work or using tools which commit changes/report progress (e.g. **report_progress**).
   - All Go code must be properly formatted or it will fail in CI.
- When running tests:
   - Use `script/test` to run the full test suite.
   - If being asked to make changes to a specific test, test file, or set of test files, **do not** run the full test suite unless you are specifically asked to do so. Instead run only the specific tests you are modifying using `go test ./path/to/package -run TestName`.

## Protocol Buffers (Proto) Changes

- We use Protocol Buffers for API definitions in the `proto/` directory.
- **ALWAYS** update the appropriate `VERSION` file when changing proto definitions:
   - `proto/jobs/VERSION` for changes to the Jobs API
   - `proto/sweagentd/VERSION` for changes to the sweagentd API
   - Follow semantic versioning: increment the patch version for backwards-compatible changes, minor version for backwards-compatible additions, major version for breaking changes.
- Use `make proto` to regenerate all proto code after making changes to `.proto` files.
- You **MUST** run `make proto` after any proto file changes to ensure generated code is up-to-date.
- Generated proto files in `proto/*/v1/*.pb.go` and `proto/*/v1/*.twirp.go` should be committed along with your proto definition changes.

## Runtime Changes (Node.js/TypeScript)

The `runtime/` directory is a git submodule pointing to the [copilot-agent-runtime](https://github.com/github/copilot-agent-runtime) repository.

- We lint runtime code with `eslint` to find problematic coding patterns.
   - Running `npm run lint` from within the `runtime` folder will check the code for `eslint` errors.
   - You **MUST** run `npm run lint` before finishing work on runtime changes.
- We enforce style guidelines with `prettier`.
   - Running `npm run format` from within the `runtime` folder will automatically format the code according to our style guidelines.
   - You **MUST** run `npm run format` before finishing work on runtime changes.

## Feature Flags

- When adding, removing, or updating feature flags, **ALWAYS** keep feature flag *definitions and lists* in alphabetical order by constant name.
- This ordering requirement applies only to feature flag definitions and lists (e.g., `const` blocks), **not** to arbitrary references to feature flags throughout the codebase.

## General Guidelines

- Follow Go naming conventions: use `ID` not `Id`, `API` not `Api`, `URL` not `Url` for acronyms in identifiers.
- Use `goerrors.New()` and `goerrors.Errorf()` instead of `errors.New()` and `fmt.Errorf()` to ensure stack traces are attached to errors.
- Keep changes minimal and focused on the specific issue being addressed.
- Test your changes thoroughly before committing.
