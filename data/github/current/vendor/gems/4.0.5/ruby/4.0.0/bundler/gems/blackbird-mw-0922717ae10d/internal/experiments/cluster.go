package experiments

import (
	"context"

	"github.com/github/blackbird-mw/internal/types"
)

type ClusterEnv struct {
	EpochID     types.EpochID
	ClusterName string
	CorpusName  string
}

type ctxClusterEnv struct{}

func WithCluster(ctx context.Context, cluster *ClusterEnv) context.Context {
	return context.WithValue(ctx, ctxClusterEnv{}, cluster)
}

func GetCluster(ctx context.Context) *ClusterEnv {
	if val, ok := ctx.Value(ctxClusterEnv{}).(*ClusterEnv); ok {
		return val
	}

	return nil
}
