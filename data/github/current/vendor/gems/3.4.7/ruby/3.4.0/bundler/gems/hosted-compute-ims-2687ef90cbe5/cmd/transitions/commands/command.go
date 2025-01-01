package commands

import (
	"context"
	"fmt"
	"path/filepath"
	"runtime"

	"github.com/github/hosted-compute-ims/internal/config"
	"github.com/github/hosted-compute-ims/internal/store"
)

type Helpers struct {
	Config     *config.Config
	ImageStore *store.ImagesStore
}

type Instance struct {
	// Name will be set automatically when the command is registered
	// to match the file name of the command
	Name string
	// Description is a short description of the command and what it does
	Description string
	// The function to run when the command is executed
	Run func(ctx context.Context, input string, com Instance) error
	// Helpers are useful clients or objects which the command may use
	// They are injected when the command is run
	Helpers Helpers
}

// Lists all available commands.
// Each command will register itself in the Commands map.
var Commands = map[string]Instance{}

func ListCommands() string {
	availableCommands := make([]string, 0, len(Commands))
	for name := range Commands {
		availableCommands = append(availableCommands, name)
	}
	return fmt.Sprintf("Available commands: %s", availableCommands)
}

func RegisterCommand(command Instance) {
	_, file, _, ok := runtime.Caller(1)
	if !ok {
		panic("could not get caller information")
	}

	cmdName := filepath.Base(file)
	command.Name = cmdName

	_, exists := Commands[command.Name]
	if exists {
		panic(fmt.Sprintf("command %s already registered", command.Name))
	}

	Commands[command.Name] = command
}

func Run(ctx context.Context, name string, input string, commandContext Helpers) error {
	if command, exists := Commands[name]; exists {
		command.Helpers = commandContext
		return command.Run(ctx, input, command)
	}

	return fmt.Errorf("command %s not found", name)
}
