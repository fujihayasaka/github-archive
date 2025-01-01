package mysql

import "context"

type featureSurfaceNameContextKey struct{}
type queryTableNameContextKey struct{}

func WithFeatureSurfaceName(ctx context.Context, name string) context.Context {
	return context.WithValue(ctx, featureSurfaceNameContextKey{}, name)
}

func WithQueryTableName(ctx context.Context, name string) context.Context {
	return context.WithValue(ctx, queryTableNameContextKey{}, name)
}

func GetFeatureSurfaceName(ctx context.Context) string {
	if name, ok := ctx.Value(featureSurfaceNameContextKey{}).(string); ok {
		return name
	}
	return "unknown"
}

func GetQueryTableName(ctx context.Context) string {
	if name, ok := ctx.Value(queryTableNameContextKey{}).(string); ok {
		return name
	}
	return "unknown"
}
