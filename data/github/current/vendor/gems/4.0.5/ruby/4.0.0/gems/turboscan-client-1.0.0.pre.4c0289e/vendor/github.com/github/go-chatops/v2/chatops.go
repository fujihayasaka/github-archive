// Package chatops provides chatops client and server functionality.
package chatops

import (
	"context"
)

// Chatop represents a Chatop to be executed.
type Chatop interface {
	// Name returns the chatop subcommand name, e.g. 'boom'
	Name() string

	// Help returns the chatop help text, e.g. 'boom <something> - explode something'
	Help() string

	// Regexp returns the js-named-regexp-compatible regular expression for matching input to this command
	// e.g. 'boom (?<thing>\w+)' will match input like 'hubot boom foo' with parameter {"thing": "foo"}
	Regexp() string

	// Handle is the function called when the chatop is executed.
	Handle(context.Context, *CommandRequest) (*CommandResponse, error)
}

var _ Chatop = (*GenericChatop)(nil)

// NewGenericChatop creates a new, generic Chatop that can be used to implement
// a generic Chatop command.
func NewGenericChatop(name, help, regexp string, cmd CommandFunc) *GenericChatop {
	return &GenericChatop{
		name:   name,
		help:   help,
		regexp: regexp,
		cmd:    cmd,
	}
}

// GenericChatop is a generic struct that house the basics of a chatop, minus the Handle method.
type GenericChatop struct {
	name   string
	help   string
	regexp string
	cmd    CommandFunc
}

// Name returns the command name for a Chatop.
func (g *GenericChatop) Name() string {
	return g.name
}

// Help returns the help string outputted for a Chatop.
func (g *GenericChatop) Help() string {
	return g.help
}

// Regexp returns the regular expression that is used to match user input.
func (g *GenericChatop) Regexp() string {
	return g.regexp
}

// Handle is the function called when the chatop is executed. It calls the underlying cmd.
func (g *GenericChatop) Handle(ctx context.Context, req *CommandRequest) (*CommandResponse, error) {
	return g.cmd(ctx, req)
}
