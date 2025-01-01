package payloads

import (
	"context"

	"github.com/github/launch/types"
)

// Store defines the interface for interactions with event payloads
type Store interface {
	Persist(ctx context.Context, workflowBuildID int64, eventPayload []byte, repoID types.GlobalID) (int64, error)
	Get(ctx context.Context, workflowBuildID int64, repoID types.GlobalID) ([]byte, error)
}
