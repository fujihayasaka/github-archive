package env

import (
	"context"
	"crypto/rsa"
	"net/http"

	"github.com/IBM/sarama"
	freno "github.com/github/go-freno-client"
	"github.com/github/hydro-client-go/v7/pkg/hydro"
	sitesapi "github.com/github/sitesapiclient"
	"github.com/pkg/errors"
	"github.com/twitchtv/twirp"

	"github.com/github/blackbird-mw/internal/auth"
	"github.com/github/blackbird-mw/internal/cache"
	"github.com/github/blackbird-mw/internal/chat"
	"github.com/github/blackbird-mw/internal/copilot"
	"github.com/github/blackbird-mw/internal/db"
	"github.com/github/blackbird-mw/internal/db/mysql"
	"github.com/github/blackbird-mw/internal/env/internal"
	"github.com/github/blackbird-mw/internal/gitaccess"
	"github.com/github/blackbird-mw/internal/github"
	"github.com/github/blackbird-mw/internal/kafka"
	"github.com/github/blackbird-mw/internal/publish/repo"
	"github.com/github/blackbird-mw/internal/quota"
	"github.com/github/blackbird-mw/internal/routing"
	"github.com/github/blackbird-mw/internal/treelights"
	"github.com/github/blackbird-mw/internal/types"
)

// New loads the config from the environment, initializes telemetry, and returns
// an env.Config interface.
//
// NOTE: You should call Config.Close() when your process exits.
func New(ctx context.Context) Config {
	c, err := internal.Load()
	if err != nil {
		panic(errors.Wrap(err, "could not load config"))
	}

	c.InitializeTelemetry(ctx)

	return c
}

// Config is an interface with accessors for config values.
//
// Using an interface rather than a concrete struct ensures that the
// configuration is loaded correctly from the environment.
type Config interface {
	// GetDeployedSHA returns the SHA that was deployed by our infrastructure.
	GetDeployedSHA() string

	// GetDeployedRef returns the SHA that was deployed by our infrastructure.
	GetDeployedRef() string

	// Corpus is the target corpus for this mw deployment.
	Corpus() routing.Corpus

	// Returns a hydro consumer for the target corpus's backfill topic.
	// Callers must call Close on the returned KafkaSource.
	BackfillConsumer(epochID types.EpochID) (*hydro.KafkaSource, error)

	// Returns a hydro consumer for the incremental topics.
	// Callers must call Close on the returned KafkaSource.
	IncrementalConsumer(epochID types.EpochID) *hydro.KafkaSource

	// Returns a fully configured AssignmentsReader.
	AssignmentsReader() kafka.AssignmentsReader

	// RepoPublisher returns a fully-configured repository publisher, capable
	// of publishing repository information to the Kafka onboarding topic.
	// Callers must call Close on the returned publisher.
	RepoPublisher() *repo.Publisher

	// SnapshotProducer returns a Kafka producer for sending messages to the
	// output cluster synchronously when you need to know the offset of the
	// published message (like with snapshots). Callers must call Close on the
	// returned producer.
	SnapshotProducer() sarama.SyncProducer

	// BlackbirdKafkaAdminProvider returns a function that returns a
	// sarama.ClusterAdmin implementation for modifying topics in the output
	// cluster. Callers must call Close on the instance returned by the
	// function.
	//
	// NOTE: This is a workaround for a bug in Sarama and can be simplified
	// if this PR is merged: https://github.com/IBM/sarama/pull/2106
	BlackbirdKafkaAdminProvider() func() sarama.ClusterAdmin
	BlackbirdKafkaAdminClient() *kafka.AdminClient

	SharedKafkaAdminClient() *kafka.AdminClient
	SharedAutoCommittingKafkaClient() sarama.Client
	SharedKafkaClient() sarama.Client

	// TopicConfig returns the Kafka topic configuration (e.g., replication
	// factor, retention, etc.) for creating and truncating per-epoch topics.
	TopicConfig() routing.TopicConfig

	// App returns the application name (for example, "blackbird-ingest").
	App() string

	// SearchClusters holds routing information for the configured search clusters.
	SearchClusters() *routing.SearchClusters

	// CacheClusters holds routing information for the configured cache clusters.
	CacheClusters() *routing.CacheClusters

	// IndexerCluster holds routing information for the crawler's configured
	// corpus. To be used by the ingest.
	IndexerCluster() *routing.IndexerCluster

	// IndexerClusters holds routing information for the all the configured corpora.
	// corpus. To be used by the admin.
	IndexerClusters() *routing.IndexerClusters

	// GetHTTPPort returns the HTTP port for this application.
	GetHTTPPort() int

	// AuthClient wraps calls to internal github authZ APIs.
	AuthClient(db.Store) *auth.Client

	// QuotaRateEstimator wraps calls to Redis to estimate per-actor usage rates.
	QuotaRateEstimator(context.Context) quota.RateEstimator

	PagerCache() cache.Store

	// GitHubClient returns an http client for the internal blackbird specific GitHub API.
	GitHubClient() github.InternalAPIClient

	// GitClient returns a gitaccess.Client. Depending on configuration, it
	// may use the filesystem (only valid in the development environment),
	// or Spokesd.
	GitClient() gitaccess.Client

	// CopilotClient returns an http client for internal copilot-api client.
	CopilotClient() copilot.Client

	// Store returns an implementation of the db.Store interface.
	Store() db.Store

	// Close shuts down anything that got started up when the config was
	// initialized. For example, the stats client.
	Close()

	// Returns the twirp service hooks for query service e.g. hmac hook for
	// authenticating clients.
	QueryServiceHooks() *twirp.ServerHooks

	// Returns the twirp service hooks for the admin service.
	AdminServiceHooks() *twirp.ServerHooks

	// DatabaseMaintence returns an instance of the DB maintaince service.
	DatabaseMaintenance() *mysql.Maint

	// NumIngestionWorkers returns number of ingest workers to run, each worker can
	// process a single repo at a time.
	NumIngestionWorkers() int

	IsChatopsEnabled() bool
	GetChatopsBaseURL() string
	GetChatopsPublicKey() *rsa.PublicKey
	GetChatopsLDAPPassword() string
	ChatClient() chat.Client
	GetTreelightsClient() treelights.Client

	DatabaseThrottler() freno.Throttler

	// Returns an HTTP middleware function that requires the request be signed
	// by the Okta Network Gateway, otherwise responds with Unauthorized.
	OktaAuthHandler() func(next http.Handler) http.Handler

	// Returns an HTTP middleware function that just looks for the ONG username header and adds it to
	// the request context. This is used for stamp admin services that aren't directly behind the ONG,
	// but receive proxied requests.
	OktaUsernameHandler() func(next http.Handler) http.Handler

	// SecurityHandler adds GitHub-standard security headers for the admin UI.
	SecurityHandler() func(next http.Handler) http.Handler

	// SitesAPIClient returns a client for using the Sites API to request
	// information about hosts.
	SitesAPIClient() *sitesapi.Client

	AdminUIEnabled() bool
	GetStamp() routing.Stamp
}
