package flipper

import (
	"context"
	"fmt"

	"github.com/github/turboscan/ts"
)

// WithFeatureEnabled returns a new context with an override forcing the feature to be globally enabled.
func WithFeatureEnabled(ctx context.Context, feature string) context.Context {
	return withGlobalOverride(ctx, feature, true)
}

// WithFeatureDisabled returns a new context with an override forcing the feature to be globally disabled.
func WithFeatureDisabled(ctx context.Context, feature string) context.Context {
	return withGlobalOverride(ctx, feature, false)
}

// WithFeatureEnabledFor returns a new context with an override forcing the feature to be enabled for the actor.
func WithFeatureEnabledFor(ctx context.Context, feature string, actorID interface{}) context.Context {
	return WithFeatureFlagValue(ctx, actorID, feature, true)
}

// WithFeatureDisabledFor returns a new context with an override forcing the feature to be disabled for the actor.
func WithFeatureDisabledFor(ctx context.Context, feature string, actorID interface{}) context.Context {
	return WithFeatureFlagValue(ctx, actorID, feature, false)
}

// WithFeatureFlagValue returns a new context with an override forcing a value for the feature-actor combination.
func WithFeatureFlagValue(ctx context.Context, actorID interface{}, feature string, value bool) context.Context {
	actor := ""
	if v, ok := actorID.(ts.RepositoryEID); ok {
		actor = fmt.Sprintf("Repository:%d", uint64(v))

	}
	if v, ok := actorID.(ts.UserEID); ok {
		actor = fmt.Sprintf("User:%d", uint64(v))
	}
	if v, ok := actorID.(ts.OwnerEID); ok {
		actor = fmt.Sprintf("Organization:%d", uint64(v))
	}
	if actor == "" {
		return ctx
	}
	return withOverride(ctx, actor, feature, value)
}

func withOverride(ctx context.Context, actor string, feature string, value bool) context.Context {
	overrideKey := getOverrideKey(actor, feature)
	return context.WithValue(ctx, overrideKey, value)
}

func withGlobalOverride(ctx context.Context, feature string, value bool) context.Context {
	overrideKey := getGlobalOverrideKey(feature)
	return context.WithValue(ctx, overrideKey, value)
}

type overrideKeyType string

func getOverrideKey(actor string, feature string) overrideKeyType {
	return overrideKeyType(fmt.Sprintf("ffo-%s:%s", actor, feature))
}

func getGlobalOverrideKey(feature string) overrideKeyType {
	return overrideKeyType(fmt.Sprintf("ffo#%s", feature))
}

// getOverride returns the value of a global or actor specific override if it exists in the context.
func getOverride(ctx context.Context, actor string, feature string) (value bool, ok bool) {
	key := getGlobalOverrideKey(feature)
	if ffOverride, ok := ctx.Value(key).(bool); ok {
		return ffOverride, true
	}

	key = getOverrideKey(actor, feature)
	if ffOverride, ok := ctx.Value(key).(bool); ok {
		return ffOverride, true
	}

	return false, false
}

func noopOverride(ctx context.Context, actor string, feature string) bool {
	if overrideValue, ok := getOverride(ctx, actor, feature); ok {
		return overrideValue
	}
	return false
}
