// Package reqmeta associates log values and stats with Context
package reqmeta

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-stats"
)

type ctxRequestMetadataKey struct{}

// RequestMetadata holds a set of key-value pairs to add to log output and a set of
// Tags to add to metrics.
type RequestMetadata struct {
	logFields *kvp.KVP
	statTags  stats.Tags
}

// NewRequestMetadata initializes a new RequestMetadata.
func NewRequestMetadata() *RequestMetadata {
	return &RequestMetadata{
		logFields: kvp.KVPs(),
		statTags:  stats.Tags{},
	}
}

// WithRequestMetadata decorates the given context with the given RequestMetadata and returns
// the context with that RequestMetadata stored in it.
func WithRequestMetadata(ctx context.Context, rmd *RequestMetadata) context.Context {
	return context.WithValue(ctx, ctxRequestMetadataKey{}, rmd)
}

// GetRequestMetadata returns the RequestMetadata stored in the given context. Returns false if
// that metadata cwas not in the right format.
func GetRequestMetadata(ctx context.Context) (*RequestMetadata, bool) {
	val, ok := ctx.Value(ctxRequestMetadataKey{}).(*RequestMetadata)
	return val, ok
}

// Copy returns a new RequestMetadata with a copy of the log fields and stat
// tags. Necessary before calling TagStatsWith to avoid concurrent writes.
func (m *RequestMetadata) Copy() *RequestMetadata {
	// Clone the tags map.
	statTagsCopy := make(stats.Tags, len(m.statTags))
	for key, value := range m.statTags {
		statTagsCopy[key] = value
	}

	return &RequestMetadata{
		logFields: kvp.KVPs(m.logFields.Fields()...),
		statTags:  statTagsCopy,
	}
}

// LogWith adds the fields to the set of logging kvps and returns a new RequestMetadata object.
// It does not add new fields in-place to avoid errors with concurrent writes.
func LogWith(m *RequestMetadata, fields ...kvp.Field) *RequestMetadata {
	nm := m.Copy()
	newFields := nm.logFields.WithFields(fields...)
	nm.logFields = newFields
	return nm
}

// TagStatsWith adds the tags to the set of metrics tags.
// It does not add new tags in-place to avoid errors with concurrent writes.
func TagStatsWith(m *RequestMetadata, tags stats.Tags) *RequestMetadata {
	nm := m.Copy()
	for k, v := range tags {
		nm.statTags[k] = v
	}
	return nm
}

// LogFields returns the kvp fields for logging.
func (m *RequestMetadata) LogFields() []kvp.Field {
	return m.logFields.Fields()
}

// StatTags returns the metrics tags.
func (m *RequestMetadata) StatTags() stats.Tags {
	return m.statTags
}
