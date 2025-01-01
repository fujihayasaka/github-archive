package ctxstash

import (
	"context"

	"github.com/github/go-kvp"
	"github.com/github/go-stats"
)

type stashCtxKey struct{}

// A Stash stores fields and tags in a context for request
// propagation purpose.
type Stash interface {
	Fields() []kvp.Field
	Tags() stats.Tags
	Correlations() Correlations
}

// From returns a Stash from `ctx`.
func From(ctx context.Context) Stash {
	stash, ok := ctx.Value(stashCtxKey{}).(Stash)
	if !ok {
		return singleNopStash
	}
	return stash
}

// WithPopulatedFields scans the provided fields and discards fields with empty values.
// Whichever fields remain are stored in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithPopulatedFields(ctx context.Context, fields ...kvp.Field) context.Context {
	revisedFields := make([]kvp.Field, 0, len(fields))
	for _, field := range fields {
		include := true
		switch field.T {
		// Note that kvp.Err() substitutes "<nil>" for a nil Error.
		// For this reason, we don't attempt to reinterpret fields where field.T == kvp.ErrorType.
		case kvp.StringType:
			include = field.Str != ""
		case kvp.AnyType:
			// For now, don't attempt to detect empty slices, maps, etc.
			// Just let telemetry capture whatever empty container notation is appropriate for the underlying type.
			// (If we decide to change this, the best way is probably to use Sprintf("%T") to inspect the underlying type
			//  followed by len() in case of a container type.)
			include = field.Any != nil
		}
		if include {
			revisedFields = append(revisedFields, field)
		}
	}
	return WithFields(ctx, revisedFields...)
}

// WithFields stores the provided fields in the new returned `ctx`.
// The original context is unchanged, including any fields it stored.
func WithFields(ctx context.Context, fields ...kvp.Field) context.Context {
	// we append the new fields to the old ones, but skip duplicate keys so that
	// new fields override old keys
	ns := copyStash(ctx)
	ns.fields = dedup(ns.fields, fields)
	return context.WithValue(ctx, stashCtxKey{}, ns)
}

func dedup(oldFields, newFields []kvp.Field) []kvp.Field {
	toSkip := make(map[string]struct{}, len(newFields))
	for _, f := range newFields {
		toSkip[f.Key] = struct{}{}
	}
	oldNonDupField := make([]kvp.Field, 0, len(oldFields)+len(newFields))
	for _, oldF := range oldFields {
		if _, ok := toSkip[oldF.Key]; !ok {
			oldNonDupField = append(oldNonDupField, oldF)
		}
	}
	return append(oldNonDupField, newFields...)
}

// WithTags stores the given tags in the new returned `ctx`.
// The original context is unchanged, including any tags it stored.
func WithTags(ctx context.Context, tags stats.Tags) context.Context {
	ns := copyStash(ctx)
	ns.tags = ns.tags.Merge(tags)
	return context.WithValue(ctx, stashCtxKey{}, ns)
}

// WithEmptyStash replaces the existing Stash with a minimal one.
// The original context is unchanged, including its Stash.
func WithEmptyStash(ctx context.Context) context.Context {
	s := From(ctx)
	baseFields := make([]kvp.Field, 0, 8)
	for _, f := range s.Fields() {
		switch f.Key {
		// These should stay in the ctxstash no matter what.
		case "app", "sha", "mu", "host", "launch_service", "launch_env", "release", "deployed_to":
			baseFields = append(baseFields, f)
		}
	}
	return context.WithValue(ctx, stashCtxKey{}, &stash{fields: baseFields})
}

// unexported to avoid people mutating it
type stash struct {
	correlations Correlations
	fields       []kvp.Field
	tags         stats.Tags
}

func (st stash) Fields() []kvp.Field        { return st.fields }
func (st stash) Tags() stats.Tags           { return st.tags }
func (st stash) Correlations() Correlations { return st.correlations }

type nopStash struct{}

var singleNopStash = nopStash{}

func (st nopStash) Fields() []kvp.Field        { return nil }
func (st nopStash) Tags() stats.Tags           { return stats.Tags{} }
func (st nopStash) Correlations() Correlations { return Correlations{} }
