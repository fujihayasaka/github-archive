package chatops

import (
	"context"
	"fmt"

	crpc "github.com/github/go-chatops/v2"
)

// unsupportedCommand provides a no-op command. You can use this is a command does not work in a particular environment.
func (app *Application) unsupportedCommand(_ context.Context, r *crpc.CommandRequest) (*crpc.CommandResponse, error) {
	return nil, fmt.Errorf("%q is not supported", r.Method)
}
