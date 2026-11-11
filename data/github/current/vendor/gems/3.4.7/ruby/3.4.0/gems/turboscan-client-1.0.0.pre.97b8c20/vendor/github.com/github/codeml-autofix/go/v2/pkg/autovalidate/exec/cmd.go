// Package exec provides utilities for executing commands in various environments.
package exec

import (
	"io"
)

// Command represents a command being prepared or run.
// It mirrors the public methods from os/exec.Cmd.
type Command interface {
	// CombinedOutput runs the command and returns its combined standard
	// output and standard error.
	CombinedOutput() ([]byte, error)

	// Output runs the command and returns its standard output.
	Output() ([]byte, error)

	// Run starts the specified command and waits for it to complete.
	Run() error

	// Start starts the specified command but does not wait for it to complete.
	Start() error

	// Wait waits for the command to exit and waits for any copying to
	// stdin or copying from stdout or stderr to complete.
	Wait() error

	// StdinPipe returns a pipe that will be connected to the command's
	// standard input when the command starts.
	StdinPipe() (io.WriteCloser, error)

	// StdoutPipe returns a pipe that will be connected to the command's
	// standard output when the command starts.
	StdoutPipe() (io.ReadCloser, error)

	// StderrPipe returns a pipe that will be connected to the command's
	// standard error when the command starts.
	StderrPipe() (io.ReadCloser, error)

	// String returns a human-readable description of the command.
	String() string

	// Environ returns a copy of the environment in which the command would be run.
	Environ() []string
}
