package exec

import (
	"context"
)

// CommandBuilder provides methods to create configured commands within an environment.
type CommandBuilder interface {
	// NewCommand creates a new command with the specified name and arguments.
	NewCommand(name string, arg ...string) Command

	// GetOutputFile retrieves the content of an output file after command execution.
	// The fileName must match one of the output files specified in the original FileMapping.
	GetOutputFile(fileName string) ([]byte, error)

	// Cleanup removes temporary files and directories created during initialization.
	// Should be called when the CommandBuilder is no longer needed.
	Cleanup() error
}

// CommandEnvironment is the main interface for initializing file mappings and getting a CommandBuilder.
type CommandEnvironment interface {
	// Init materializes files from the file mapping and returns a CommandBuilder interface or error.
	// The codebase files should be included in the file mapping under paths starting with "src/".
	// Additional files (like config files) can be included under other paths.
	Init(ctx context.Context, fm FileMapping) (CommandBuilder, error)
	// SetWorkingDir sets a pre-existing directory to be used as the working directory instead of creating a temp one.
	// Implementations should treat an empty value as "unset".
	SetWorkingDir(dir string)
}
