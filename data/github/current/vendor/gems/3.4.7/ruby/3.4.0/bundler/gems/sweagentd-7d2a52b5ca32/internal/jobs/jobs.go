// Package jobs defines the data structures and interfaces for managing
// assignments and jobs in the system. It includes functionality for creating,
// updating, and retrieving assignments and jobs, as well as handling job
// statuses and errors.
package jobs

import (
	"context"
	"fmt"

	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/observability"
)

// FillDisplayLogin fills the DisplayLogin field of the JobActor by resolving
// the user ID to a display login using the GitHub Sweagentd service.
//
// This method is written in such a way that it should *never* error outside of a Proxima environment.
// The behavior of this method outside of a Proxima environment is only to set DisplayLogin to Login.
func (ja *JobActor) FillDisplayLogin(ctx context.Context, obsv observability.Exporters, ffClient featureflags.Client, ghTwirp githubtwirp.ClientInterface, userID uint64) error {
	resolvedLogin, err := githubtwirp.ResolveDisplayLogin(ctx, ghTwirp, obsv, ffClient, userID, ja.Login)
	if err != nil {
		return fmt.Errorf("failed to resolve display login for user: %w", err)
	}

	ja.DisplayLogin = resolvedLogin
	return nil
}
