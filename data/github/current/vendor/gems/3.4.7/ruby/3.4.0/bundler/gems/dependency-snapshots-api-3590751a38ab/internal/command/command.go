package command

import (
	"flag"
	"fmt"
	"io"
	"strings"

	"github.com/pkg/errors"
)

type HandlerFunc func(*Command) error

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

func ListCommands(commands []Command) string {
	var sb strings.Builder
	sb.WriteString("Commands:\n")
	for _, v := range commands {
		sb.WriteString(fmt.Sprintf("\t%s\t%s\n", v.Name, v.Desc))
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

// Returns an error with the provided usage string followed
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

func DispatchCommand(cmdName string, cmds []Command) error {
	for _, v := range cmds {
		if cmdName == v.Name {
			return v.Execute(&v)
		}
	}

	// If we get here we have an unknown command
	return errors.Errorf("unknown command: %s", cmdName)
}
