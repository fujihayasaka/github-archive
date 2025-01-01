// Package process exposes utilities to manage running processes, like trigger an exit with predefined status codes
package process

import "os"

// ExitCode represents the exit code of a process
type ExitCode int

// NOTE: These enum values are not initialized with `iota` so the exit code value is explicit
const (
	RuntimeError      ExitCode = 1
	ConfigLoadError   ExitCode = 2
	ReporterInitError ExitCode = 3
	APIServerError    ExitCode = 4
	DBConnectionError ExitCode = 5
	ShutdownError     ExitCode = 6
	KafkaInitError    ExitCode = 7
	BuildServiceError ExitCode = 8
)

// Exit stops the running process with the given ExitCode
// see os.Exit()
//
// Example:
//
// process.Exit(process.RuntimeError)
func Exit(code ExitCode) {
	os.Exit(int(code)) //nolint:revive // ignore "deep-exit" linter
}
