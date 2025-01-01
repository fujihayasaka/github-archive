package job

import (
	"context"
	"errors"

	"github.com/github/github-telemetry-go/log"

	"github.com/github/notifyd/internal/pkg/tenancy"
)

// Builder is a function that returns a new handler from the given one.
type Builder interface {
	Handle(Handler) HandlerFunc
}

// Chain allows to build stack of handlers that will be called in order to process a job.Request
type Chain struct {
	builders []Builder
}

// NewChain instantiates a chain with the given builders or empty in case none are given.
func NewChain(builders ...Builder) *Chain {
	return &Chain{builders}
}

// Add extends a chain with a new handler
func (c *Chain) Add(builders ...Builder) {
	c.builders = append(c.builders, builders...)
}

// ErrNoHandlerProvided is an error that is returned when no handler is provided to the chain.
var ErrNoHandlerProvided = errors.New("no handler provided")

// Then uses the existing chain to build a handler that stacks all the existing handlers in the
// chain to process a job.Request.
func (c *Chain) Then(h Handler) Handler {
	if h == nil {
		return HandlerFunc(func(context.Context, tenancy.Tenant, log.Logger, Request) error {
			return ErrNoHandlerProvided
		})
	}

	// We traverse the sclice of builders in reverse order so that the innermost are composed first.
	for i := len(c.builders) - 1; i >= 0; i-- {
		h = c.builders[i].Handle(h)
	}

	return h
}
