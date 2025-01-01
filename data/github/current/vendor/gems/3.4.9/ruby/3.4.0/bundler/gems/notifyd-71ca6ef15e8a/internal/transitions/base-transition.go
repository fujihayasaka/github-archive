// Package transitions contains database transitions.
package transitions

import (
	"context"
)

// IBaseTransition is a common interface for transitions.
type IBaseTransition interface {
	Run(ctx context.Context, isDryRun bool) error
}
