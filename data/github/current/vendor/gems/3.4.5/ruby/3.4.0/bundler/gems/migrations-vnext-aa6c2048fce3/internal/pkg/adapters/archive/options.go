package archive

import (
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/migrations-vnext/internal/pkg/blobstore"
	"github.com/github/migrations-vnext/internal/pkg/dag"
	"github.com/github/migrations-vnext/internal/pkg/resource"
)

// Option defines the function signature for configuring a `LoaderImpl`
// instance.
type Option func(l *Loader)

// WithDefaultUserID sets the default user ID needed to create resources.
func WithDefaultUserID(defaultUserID int64) Option {
	return func(l *Loader) {
		l.defaultUserID = defaultUserID
	}
}

// WithRootPath sets the root path for the Loader.
func WithRootPath(rootPath string) Option {
	return func(l *Loader) {
		l.rootPath = rootPath
	}
}

// WithShuffleResources sets the shuffleNodes flag for the Loader.
func WithShuffleResources(shuffle bool) Option {
	return func(l *Loader) {
		l.shuffleResources = shuffle
	}
}

// WithAllowedOrgs sets the allowed organizations for the Loader.
func WithAllowedOrgs(orgs []string) Option {
	return func(l *Loader) {
		l.allowedOrgs = orgs
	}
}

// WithManager sets the DAG Manager for the Loader.
func WithManager(m dag.Manager) Option {
	return func(l *Loader) {
		l.manager = m
	}
}

// WithMaxIssueEventsPerBatch sets the max issue events per batch for the Loader.
func WithMaxIssueEventsPerBatch(maxPerBatch int) Option {
	return func(l *Loader) {
		l.maxIssueEventsPerBatch = maxPerBatch
	}
}

// WithAllowedResources sets the allowed resources for the Loader.
func WithAllowedResources(resources map[resource.Type]struct{}) Option {
	return func(l *Loader) {
		l.allowedResources = resources
	}
}

// WithLogger sets the logger for the Loader.
func WithLogger(logger log.Logger) Option {
	return func(l *Loader) {
		l.logger = logger.WithFields(kvp.String("component", "archive-loader"))
	}
}

// WithSASGenerator sets the SASGenerator for the Loader.
func WithSASGenerator(s blobstore.SASGenerator) Option {
	return func(l *Loader) {
		l.sasGenerator = s
	}
}

// WithEnterpriseID sets the enterprise ID for the Loader to populate migration context.
func WithEnterpriseID(enterpriseID int64) Option {
	return func(l *Loader) {
		l.enterpriseID = enterpriseID
	}
}
