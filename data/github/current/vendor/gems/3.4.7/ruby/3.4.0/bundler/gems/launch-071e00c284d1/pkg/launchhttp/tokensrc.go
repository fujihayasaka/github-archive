package launchhttp

import (
	"context"
)

// TokenSource is the interface that abstracts the process of
// obtaining an authorization token.
type TokenSource interface {
	Get(ctx context.Context) (string, error)
}
