package haswaitedforrep

import (
	"context"
)

type hasWaitedForReplicasKey struct{}

func ContextWithHasWaitedForReplicas(ctx context.Context) context.Context {
	return context.WithValue(ctx, hasWaitedForReplicasKey{}, struct{}{})
}

func FromContext(ctx context.Context) bool {
	hasWaitedForRepVal := ctx.Value(hasWaitedForReplicasKey{})
	return hasWaitedForRepVal != nil
}
