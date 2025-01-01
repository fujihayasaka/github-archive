package feature

import "context"

type contextKey struct{}

// Enabled returns true if the given feature is enabled for the request.
func Enabled(ctx context.Context, feature string) bool {
	key := contextKey{}
	enabled, ok := ctx.Value(key).(map[string]bool)
	if !ok || enabled == nil {
		return false
	}
	return enabled[feature]
}

func NewContext(ctx context.Context, features map[string]bool) context.Context {
	return context.WithValue(ctx, contextKey{}, features)
}
