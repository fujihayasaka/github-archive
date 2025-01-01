package resource

import (
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/migrations-vnext/internal/pkg/assets"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/client"
	"github.com/github/migrations-vnext/internal/pkg/dag"
)

// Option defines the function signature for configuring  a `LoaderImpl`
// instance.
type Option func(r *LoaderImpl)

// WithEnterpriseID sets the Logger that will be used.
func WithEnterpriseID(e int64) Option {
	return func(r *LoaderImpl) {
		r.enterpriseID = e
	}
}

// WithImportClient sets the Logger that will be used.
func WithImportClient(c client.Importer) Option {
	return func(r *LoaderImpl) {
		r.importClient = c
	}
}

// WithLogger sets the Logger that will be used.
func WithLogger(l log.Logger) Option {
	return func(r *LoaderImpl) {
		r.logger = l
	}
}

// WithStatter sets the `stats.Client` that will be used.
func WithStatter(s stats.Client) Option {
	return func(m *LoaderImpl) {
		m.statter = s
	}
}

// WithKV sets the `KVResolver` that will be used.
func WithKV(kv KVResolver) Option {
	return func(m *LoaderImpl) {
		m.kvResolver = kv
	}
}

// WithDAG sets the `DAG` that will be used.
func WithDAG(d dag.DAG) Option {
	return func(m *LoaderImpl) {
		m.dag = d
	}
}

// WithIntermediateStore sets the `blobstore.Store` that will be used.
func WithIntermediateStore(b *blobstore.Store) Option {
	return func(m *LoaderImpl) {
		m.intermediateStore = b
	}
}

// WithUploader sets the `assets.Uploader` this will be used.
func WithUploader(u assets.Uploader) Option {
	return func(m *LoaderImpl) {
		m.uploader = u
	}
}
