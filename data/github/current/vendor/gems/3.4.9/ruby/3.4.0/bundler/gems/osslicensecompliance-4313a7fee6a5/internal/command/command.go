// Package command provides a command executor.
package command

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"strings"
)

// HandlerFunc is the type of func that returns a handler.
type HandlerFunc func(*Command) error

// Command has information about a command.
type Command struct {
	// The name of the command
	Name string
	// A description of the command function
	Desc string
	// The function to execute when the command is parsed
	Execute HandlerFunc
	// The set of subcommands (if any)
	Commands []Command
}

// ListCommands lists commands.
func ListCommands(commands []Command) string {
	var sb strings.Builder
	_, _ = sb.WriteString("Commands:\n")
	for _, v := range commands {
		_, _ = sb.WriteString(fmt.Sprintf("\t%s\t%s\n", v.Name, v.Desc))
	}
	return sb.String()
}

func printUsage(w io.Writer, usage string, f *flag.FlagSet) error {
	_, err := io.WriteString(w, usage)
	if err != nil {
		return err
	}

	// Print flags (if any)
	if f != nil {
		save := f.Output()
		f.SetOutput(w)
		f.PrintDefaults()
		f.SetOutput(save)
	}

	return nil
}

// NewUsageError returns an error with the provided usage string followed
// by a formatted list of the flags from the flag set (if provided)
// The result error is intended to be printed to Stdout or Stderr by the caller.
func NewUsageError(usage string, f *flag.FlagSet) error {
	var sb strings.Builder
	err := printUsage(&sb, usage, f)
	if err != nil {
		return err
	}

	return errors.New(sb.String())
}

// DispatchCommand dispatches a command.
func DispatchCommand(cmdName string, cmds []Command) error {
	for _, v := range cmds {
		if cmdName == v.Name {
			cmd := v
			return cmd.Execute(&cmd)
		}
	}

	// If we get here we have an unknown command
	return fmt.Errorf("unknown command: %s", cmdName)
}
