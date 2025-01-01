// Package autofix provides a way to execute cocofix.js using the options provided by the user.
// It will change once all code is ported to the go codebase.
package autofix

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/spf13/cobra"
)

// Executor represents the executor for autofix
type Executor struct {
	Options *CliOptions
	cmd     *cobra.Command
}

// NewExecutor creates a new Executor
func NewExecutor(options *CliOptions) *Executor {
	return &Executor{ //nolint:exhaustruct
		Options: options,
	}
}

// WithCommand sets the command to use for the executor
func (e *Executor) WithCommand(cmd *cobra.Command) *Executor {
	e.cmd = cmd
	return e
}

// Run executes cocofix.js with the provided options
func (e *Executor) Run() error {
	cocofixPath, overridden := os.LookupEnv("COCOFIX_JS_PATH")
	if !overridden {
		// Check if cocofix.js is available
		var err error
		cocofixPath, err = filepath.Abs(filepath.Join("..", "cocofix", "bin", "cocofix.js"))
		if err != nil {
			return fmt.Errorf("failed to get absolute path for cocofix.js: %w", err)
		}
	}

	if _, err := os.Stat(cocofixPath); err != nil {
		return fmt.Errorf("cocofix.js not found at %s: %w", cocofixPath, err)
	}

	// Convert options to args to pass to cocofix.js
	args := e.Options.ToArgs()

	cmd := exec.Command("node", append([]string{cocofixPath}, args...)...)
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = append(os.Environ(),
		"COCOFIX_INSTALL_TOKEN="+os.Getenv("COCOFIX_INSTALL_TOKEN"),
		"CAPI_DEV_KEY="+os.Getenv("CAPI_DEV_KEY"),
	)

	return cmd.Run()
}
