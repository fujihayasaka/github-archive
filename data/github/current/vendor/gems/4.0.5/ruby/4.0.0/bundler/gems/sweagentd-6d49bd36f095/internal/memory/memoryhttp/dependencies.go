// Package memoryhttp provides HTTP handlers for memory operations
// This package is a "adapter" that connects the core memory service to HTTP requests.
// It also constructs the entire dependency graph for the memory service.
package memoryhttp

import (
	"github.com/github/sweagentd/internal/agenticapp"
	"github.com/github/sweagentd/internal/config"
	cosmosbase "github.com/github/sweagentd/internal/cosmos"
	"github.com/github/sweagentd/internal/experiments/exp"
	"github.com/github/sweagentd/internal/featureflags"
	"github.com/github/sweagentd/internal/github"
	"github.com/github/sweagentd/internal/githubtwirp"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/memory/core"
	"github.com/github/sweagentd/internal/memory/cosmos"
	memorylocal "github.com/github/sweagentd/internal/memory/local"
	secretscanning "github.com/github/sweagentd/internal/memory/secret_scanning"
	"github.com/github/sweagentd/internal/observability"
)

// Dependencies holds all the dependencies required for the memory HTTP handlers.
type Dependencies struct {
	memoryService core.MemoryService
	memoryStore   core.MemoryStore
	HTTPHandler   *MemoryHandler
}

// NewDependencies creates a new Dependencies instance
// It constructs the memory service and all its dependencies based on the configuration
// This allows the HTTP handler to be used in the main application, or to moved to a different package/service if needed.
func NewDependencies(
	cfg *config.Config,
	featureFlagClient featureflags.Client,
	githubClientFactory github.ClientFactoryInterface,
	obsv observability.Exporters,
	appProvider *agenticapp.Provider,
	ghTwirp githubtwirp.ClientInterface,
	expClient exp.ExperimentationClient,
) *Dependencies {
	memoryStore := memorylocal.NewLocalMemoryStore()
	if cfg.IsDevelopment() {
		obsv.Logger.Warn("using in-memory store for agent memory — memory data will not persist across restarts")
	} else {
		// If we are not in development and Cosmos DB is enabled, use the Cosmos memory store
		var err error
		memoryStore, err = cosmos.NewCosmosMemoryStore(&cosmosbase.ContainerOpts{
			DatabaseID:  cfg.AzureCosmosDBDatabase,
			ContainerID: cfg.AzureCosmosDBContainerMemory,
			Opts: cosmosbase.Opts{
				ConnectionString:         cfg.AzureCosmosDBConnectionString,
				Endpoint:                 cfg.AzureCosmosDBEndpoint,
				Obsv:                     obsv,
				AzureCosmosDBSPNTenantID: cfg.AzureCosmosDBSPNTenantID,
				AzureCosmosDBSPNClientID: cfg.AzureCosmosDBSPNClientID,
			},
		})
		if err != nil {
			panic(goerrors.Errorf("failed to create Cosmos memory store: %w", err))
		}
	}
	var secretScanner core.SecretScanner
	if cfg.IsDevelopment() {
		obsv.Logger.Warn("using noop secret scanner for memory — memory content will NOT be scanned for secrets")
		secretScanner = secretscanning.NewNoopSecretScanner()
	} else {
		secretScanner = secretscanning.NewSecretScanner(cfg.TokenScanningURL, cfg.TokenScanningHMACKey)
	}
	billingEntityResolver := newTwirpBillingEntityResolver(ghTwirp)
	memoryService := core.NewMemoryService(memoryStore, featureFlagClient, secretScanner, obsv, ghTwirp, billingEntityResolver)
	memoryHandler := NewMemoryHandler(MemoryHandlerOpts{
		Service:               memoryService,
		GHFactory:             githubClientFactory,
		Obsv:                  obsv,
		AppProvider:           appProvider,
		FeatureFlagClient:     featureFlagClient,
		GHTwirp:               ghTwirp,
		PrivilegedAppChecker:  &github.PrivilegedAppChecker{},
		ExpClient:             expClient,
		IsDevelopment:         cfg.IsDevelopment(),
		BillingEntityResolver: billingEntityResolver,
	})

	return &Dependencies{
		memoryService: memoryService,
		memoryStore:   memoryStore,
		HTTPHandler:   memoryHandler,
	}
}
